#!/usr/bin/env python3
"""Build a seven-day stable Codex model recommendation from saved radar rounds."""

from __future__ import annotations

import json
import os
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta
from pathlib import Path
from statistics import mean, median, pstdev
from typing import Any, Iterable
from zoneinfo import ZoneInfo

DATA_DIR = Path(os.environ.get("CODEXRADAR_DATA_DIR", "data/codexradar"))
ROLLING_DAYS = int(os.environ.get("CODEXRADAR_ROLLING_DAYS", "7"))
MIN_SAMPLES = int(os.environ.get("CODEXRADAR_MIN_LONG_TERM_SAMPLES", "4"))
STABLE_SAMPLES = int(os.environ.get("CODEXRADAR_STABLE_LONG_TERM_SAMPLES", "8"))
MIN_COVERAGE = float(os.environ.get("CODEXRADAR_MIN_MODEL_COVERAGE", "0.6"))
SHANGHAI = ZoneInfo("Asia/Shanghai")


class LongTermDataError(RuntimeError):
    """Raised when stored radar data is incomplete or malformed."""


@dataclass(frozen=True)
class ModelSummary:
    name: str
    sample_count: int
    coverage: float
    average_passed: float
    median_passed: float
    minimum_passed: int
    maximum_passed: int
    passed_stdev: float
    average_iq: float
    average_cost_usd: float
    average_duration_hours: float
    average_cost_per_pass: float
    top_rate: float


@dataclass(frozen=True)
class RollingSummary:
    schema_version: str
    window_days: int
    round_count: int
    minimum_samples: int
    stable_samples: int
    status: str
    confidence: str
    strongest_name: str | None
    default_name: str | None
    generated_at: str
    latest_site_updated_at: str
    models: tuple[ModelSummary, ...]


def load_object(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise LongTermDataError(f"Missing required file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise LongTermDataError(f"Invalid JSON in {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise LongTermDataError(f"Expected JSON object in {path}")
    return value


def load_history(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    entries: list[dict[str, Any]] = []
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line:
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            raise LongTermDataError(f"Invalid JSON in {path}:{line_number}: {exc}") from exc
        if not isinstance(value, dict):
            raise LongTermDataError(f"Expected JSON object in {path}:{line_number}")
        entries.append(value)
    return entries


def entry_time(entry: dict[str, Any]) -> datetime | None:
    value = entry.get("source", {}).get("site_updated_at")
    if not isinstance(value, str):
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=SHANGHAI)
    return parsed.astimezone(SHANGHAI)


def unique_rounds(entries: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    by_timestamp: dict[str, dict[str, Any]] = {}
    for entry in entries:
        timestamp = entry.get("source", {}).get("site_updated_at")
        models = entry.get("models")
        if isinstance(timestamp, str) and isinstance(models, list):
            by_timestamp[timestamp] = entry
    return sorted(
        by_timestamp.values(),
        key=lambda item: entry_time(item) or datetime.min.replace(tzinfo=SHANGHAI),
    )


def calculate(
    history: Iterable[dict[str, Any]],
    latest: dict[str, Any],
    *,
    window_days: int = ROLLING_DAYS,
    minimum_samples: int = MIN_SAMPLES,
    stable_samples: int = STABLE_SAMPLES,
) -> RollingSummary:
    latest_time = entry_time(latest)
    if latest_time is None:
        raise LongTermDataError("latest.json has no valid source.site_updated_at")
    current_names = {
        item.get("name")
        for item in latest.get("models", [])
        if isinstance(item, dict) and isinstance(item.get("name"), str)
    }
    if not current_names:
        raise LongTermDataError("latest.json contains no current model names")

    cutoff = latest_time - timedelta(days=window_days)
    rounds = [
        item
        for item in unique_rounds([*history, latest])
        if (timestamp := entry_time(item)) is not None and cutoff <= timestamp <= latest_time
    ]
    round_count = len(rounds)
    per_model: dict[str, list[dict[str, Any]]] = {name: [] for name in current_names}
    top_counts = {name: 0 for name in current_names}

    for radar_round in rounds:
        row = {
            item.get("name"): item
            for item in radar_round.get("models", [])
            if isinstance(item, dict) and item.get("name") in current_names
        }
        valid = {
            name: item
            for name, item in row.items()
            if all(
                isinstance(item.get(field), (int, float))
                for field in ("passed", "iq", "cost_usd", "duration_hours")
            )
        }
        if valid:
            best_passed = max(int(item["passed"]) for item in valid.values())
            for name, item in valid.items():
                if int(item["passed"]) == best_passed:
                    top_counts[name] += 1
                per_model[name].append(item)

    summaries: list[ModelSummary] = []
    for name in sorted(current_names):
        samples = per_model[name]
        if not samples:
            continue
        passes = [int(item["passed"]) for item in samples]
        iq_values = [float(item["iq"]) for item in samples]
        costs = [float(item["cost_usd"]) for item in samples]
        durations = [float(item["duration_hours"]) for item in samples]
        avg_passed = mean(passes)
        summaries.append(
            ModelSummary(
                name=name,
                sample_count=len(samples),
                coverage=len(samples) / max(round_count, 1),
                average_passed=avg_passed,
                median_passed=float(median(passes)),
                minimum_passed=min(passes),
                maximum_passed=max(passes),
                passed_stdev=float(pstdev(passes)) if len(passes) > 1 else 0.0,
                average_iq=mean(iq_values),
                average_cost_usd=mean(costs),
                average_duration_hours=mean(durations),
                average_cost_per_pass=mean(costs) / max(avg_passed, 0.001),
                top_rate=top_counts[name] / max(round_count, 1),
            )
        )

    candidates = [
        item
        for item in summaries
        if item.sample_count >= minimum_samples and item.coverage >= MIN_COVERAGE
    ]
    if round_count < minimum_samples or not candidates:
        return RollingSummary(
            schema_version="1.0",
            window_days=window_days,
            round_count=round_count,
            minimum_samples=minimum_samples,
            stable_samples=stable_samples,
            status="collecting",
            confidence="insufficient",
            strongest_name=None,
            default_name=None,
            generated_at=datetime.now(SHANGHAI).isoformat(),
            latest_site_updated_at=latest_time.isoformat(),
            models=tuple(summaries),
        )

    strongest = sorted(
        candidates,
        key=lambda item: (
            -item.median_passed,
            -item.average_passed,
            item.passed_stdev,
            -item.minimum_passed,
            -item.average_iq,
            item.average_cost_usd,
            item.name,
        ),
    )[0]
    best_average = max(item.average_passed for item in candidates)
    default_candidates = [
        item
        for item in candidates
        if item.average_passed >= best_average - 1 and item.average_iq >= 90
    ] or candidates
    default = sorted(
        default_candidates,
        key=lambda item: (
            item.average_cost_per_pass,
            item.passed_stdev,
            item.average_cost_usd,
            item.average_duration_hours,
            -item.median_passed,
            -item.average_passed,
            item.name,
        ),
    )[0]
    selected_samples = min(strongest.sample_count, default.sample_count)
    confidence = (
        "stable"
        if selected_samples >= stable_samples
        and strongest.coverage >= 0.8
        and default.coverage >= 0.8
        else "provisional"
    )
    return RollingSummary(
        schema_version="1.0",
        window_days=window_days,
        round_count=round_count,
        minimum_samples=minimum_samples,
        stable_samples=stable_samples,
        status="ready",
        confidence=confidence,
        strongest_name=strongest.name,
        default_name=default.name,
        generated_at=datetime.now(SHANGHAI).isoformat(),
        latest_site_updated_at=latest_time.isoformat(),
        models=tuple(summaries),
    )


def find_model(summary: RollingSummary, name: str | None) -> ModelSummary | None:
    return next((item for item in summary.models if item.name == name), None)


def table(summary: RollingSummary) -> str:
    rows = [
        "| 模型 | 样本 | 平均通过 | 中位数 | 最差 | 波动σ | 平均IQ | 平均费用 | 每通过题成本 | 榜首率 |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for item in sorted(
        summary.models,
        key=lambda model: (-model.median_passed, -model.average_passed, model.average_cost_usd),
    ):
        rows.append(
            f"| {item.name} | {item.sample_count} | {item.average_passed:.2f}/10 | "
            f"{item.median_passed:g} | {item.minimum_passed}/10 | {item.passed_stdev:.2f} | "
            f"{item.average_iq:.1f} | ${item.average_cost_usd:.2f} | "
            f"${item.average_cost_per_pass:.2f} | {item.top_rate:.0%} |"
        )
    return "\n".join(rows)


def model_sentence(item: ModelSummary) -> str:
    return (
        f"{item.name}（{item.sample_count} 轮，平均 {item.average_passed:.2f}/10，"
        f"中位数 {item.median_passed:g}，最差 {item.minimum_passed}/10，"
        f"波动 σ={item.passed_stdev:.2f}，平均 ${item.average_cost_usd:.2f}）"
    )


def render_markdown(summary: RollingSummary, latest: dict[str, Any]) -> str:
    current_value = latest.get("recommendations", {}).get("value_pick", {}).get("name", "未知")
    current_strongest = latest.get("recommendations", {}).get("strongest", {}).get("name", "未知")
    if summary.status != "ready":
        conclusion = f"""## 结论

当前只累计 **{summary.round_count} 轮**，至少需要 **{summary.minimum_samples} 轮**才形成暂定长期结论，达到约 **{summary.stable_samples} 轮**后才标记为稳定。

- 当前轮能力最强：**{current_strongest}**
- 当前轮性价比：**{current_value}**
- 长期默认：**尚不下结论**

样本不足期间可以临时使用当前轮性价比，但不要因为某一轮 10/10 就永久切换默认模型。
"""
    else:
        strongest = find_model(summary, summary.strongest_name)
        default = find_model(summary, summary.default_name)
        assert strongest and default
        confidence = "稳定" if summary.confidence == "stable" else "暂定"
        conclusion = f"""## 结论

- 置信度：**{confidence}**
- 长期能力最强：**{model_sentence(strongest)}**
- 长期日常默认：**{model_sentence(default)}**
- 当前轮能力最强：**{current_strongest}**
- 当前轮性价比：**{current_value}**

长期默认不追单轮榜首。先看中位数和平均通过数，再看最差轮次与波动；只有能力接近时，才用平均每道通过题成本决定日常默认。
"""
    return f"""# CodexRadar 长期稳定建议

- 统计窗口：最近 **{summary.window_days} 天**
- 有效轮次：**{summary.round_count}**
- 最新榜单时间：{summary.latest_site_updated_at}
- 生成时间：{summary.generated_at}

{conclusion}

## 滚动统计表

{table(summary) if summary.models else '尚无数据。'}

## 使用规则

1. **日常默认看本页长期建议**，不要每天追单轮榜首。
2. 当前轮结果只用于临时切换、故障排查和重要任务升级。
3. 长期能力最强适合疑难任务与最终验收；长期日常默认适合普通开发和持续执行。
4. 某模型样本覆盖不足 60% 时，不参与长期冠军判断。
5. 模型代际或名称变化后，新模型必须重新累计样本，不能继承上一代结论。

> 本文件由 GitHub Action 根据 `history.jsonl` 自动生成，请勿手工修改。
"""


def run() -> RollingSummary:
    latest_path = DATA_DIR / "latest.json"
    history_path = DATA_DIR / "history.jsonl"
    output_json = DATA_DIR / "rolling-7d.json"
    output_markdown = DATA_DIR / "LONG_TERM.md"

    latest = load_object(latest_path)
    history = load_history(history_path)
    summary = calculate(history, latest)
    output_json.write_text(
        json.dumps(asdict(summary), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    output_markdown.write_text(render_markdown(summary, latest), encoding="utf-8")
    print(
        f"Long-term summary: rounds={summary.round_count}; status={summary.status}; "
        f"strongest={summary.strongest_name}; default={summary.default_name}"
    )
    return summary


def main() -> int:
    try:
        run()
        return 0
    except (OSError, ValueError, LongTermDataError) as exc:
        print(f"CodexRadar long-term analysis failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
