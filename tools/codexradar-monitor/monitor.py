#!/usr/bin/env python3
"""Fetch CodexRadar, rank current models, persist snapshots, and prepare notifications.

The script deliberately uses only Python's standard library so it can run on
GitHub-hosted runners without installing third-party packages.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterable
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

SOURCE_URL = os.environ.get("CODEXRADAR_URL", "https://codexradar.com/")
DATA_DIR = Path(os.environ.get("CODEXRADAR_DATA_DIR", "data/codexradar"))
NOTIFICATION_PATH = Path(
    os.environ.get("CODEXRADAR_NOTIFICATION_PATH", ".codexradar-notification.md")
)
MENTION = os.environ.get("CODEXRADAR_MENTION", "zwmopen").lstrip("@")
SHANGHAI = ZoneInfo("Asia/Shanghai")
MODEL_PATTERN = re.compile(
    r"(?:(?:Sol|Terra|Luna)\s+(?:ultra|max|xhigh|high|medium|low)"
    r"|(?:GPT-)?\d+(?:\.\d+)?[-\s]+(?:ultra|max|xhigh|high|medium|low))",
    re.IGNORECASE,
)


class RadarParseError(RuntimeError):
    """Raised when the page no longer matches the expected public structure."""


class VisibleTextExtractor(HTMLParser):
    """Extract human-visible text while ignoring scripts, styles and SVG noise."""

    SKIPPED = {"script", "style", "noscript", "svg", "template"}

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self._skip_depth = 0
        self.parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        del attrs
        if tag.lower() in self.SKIPPED:
            self._skip_depth += 1

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in self.SKIPPED and self._skip_depth:
            self._skip_depth -= 1

    def handle_data(self, data: str) -> None:
        if self._skip_depth:
            return
        value = re.sub(r"\s+", " ", unescape(data)).strip()
        if value:
            self.parts.append(value)

    def text(self) -> str:
        return "\n".join(self.parts)


@dataclass(frozen=True)
class ModelMetric:
    name: str
    passed: int
    total: int
    iq: float
    cost_usd: float
    duration_hours: float

    @property
    def cost_per_pass(self) -> float:
        return self.cost_usd / max(self.passed, 1)


@dataclass(frozen=True)
class RadarDataset:
    site_updated_label: str
    site_updated_at: str
    observed_at: str
    source_url: str
    models: tuple[ModelMetric, ...]
    strongest: ModelMetric
    value_pick: ModelMetric


def fetch_html(url: str, attempts: int = 3, timeout: int = 30) -> str:
    headers = {
        "User-Agent": (
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "CodexRadarMonitor/1.0 (+https://github.com/zwmopen/scripts)"
        ),
        "Accept": "text/html,application/xhtml+xml",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.7",
        "Accept-Encoding": "identity",
        "Cache-Control": "no-cache",
    }
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        request = Request(url, headers=headers)
        try:
            with urlopen(request, timeout=timeout) as response:
                status = getattr(response, "status", 200)
                if status != 200:
                    raise RadarParseError(f"Unexpected HTTP status: {status}")
                payload = response.read()
                charset = response.headers.get_content_charset() or "utf-8"
                return payload.decode(charset, errors="replace")
        except (HTTPError, URLError, TimeoutError, RadarParseError) as exc:
            last_error = exc
            if attempt < attempts:
                time.sleep(2 ** (attempt - 1))
    raise RadarParseError(f"Unable to fetch {url}: {last_error}")


def visible_text(html: str) -> str:
    parser = VisibleTextExtractor()
    parser.feed(html)
    parser.close()
    return parser.text()


def between(text: str, start: str, end: str) -> str:
    if start not in text or end not in text:
        raise RadarParseError(f"Missing row boundary: {start!r} -> {end!r}")
    return text.split(start, 1)[1].split(end, 1)[0]


def normalize_model_name(value: str) -> str:
    name = re.sub(r"[-\s]+", " ", value).strip()
    if re.match(r"^\d", name):
        name = f"GPT-{name}"
    return name


def parse_update_label(text: str, now: datetime) -> tuple[str, str]:
    matches = re.findall(
        r"降智雷达\s*(\d{1,2})月(\d{1,2})日\s*(\d{1,2}):(\d{2})\s*更新",
        text,
    )
    if not matches:
        raise RadarParseError("Could not find the CodexRadar update timestamp")

    month, day, hour, minute = map(int, matches[-1])
    candidate = datetime(now.year, month, day, hour, minute, tzinfo=SHANGHAI)
    if candidate > now + timedelta(days=7):
        candidate = candidate.replace(year=now.year - 1)
    label = f"{month}月{day}日{hour:02d}:{minute:02d}"
    return label, candidate.isoformat()


def parse_metrics(html: str, now: datetime | None = None) -> tuple[str, str, tuple[ModelMetric, ...]]:
    now = now or datetime.now(SHANGHAI)
    text = visible_text(html)
    label, updated_at = parse_update_label(text, now)

    if "本次多模型指标" not in text:
        raise RadarParseError("Could not locate the current multi-model metrics table")
    section_tail = text.split("本次多模型指标", 1)[1]
    end_positions = [
        section_tail.index(marker)
        for marker in ("固定评测任务集", "共同 10 题参考")
        if marker in section_tail
    ]
    if not end_positions:
        raise RadarParseError("Could not locate the end of the current metrics table")
    section = section_tail[: min(end_positions)]

    header = between(section, "项目", "通过数")
    model_names = [
        normalize_model_name(match.group(0))
        for match in MODEL_PATTERN.finditer(header)
    ]
    if not model_names:
        raise RadarParseError("No models found in the current metrics header")

    pass_values = re.findall(r"(\d+)\s*/\s*(\d+)", between(section, "通过数", "IQ"))
    iq_values = re.findall(r"\d+(?:\.\d+)?", between(section, "IQ", "Agent steps"))
    cost_values = re.findall(r"\$\s*(\d+(?:\.\d+)?)", between(section, "费用", "cache命中率"))
    duration_matches = re.findall(
        r"(\d+(?:\.\d+)?)\s*(h|小时|分钟)",
        between(section, "耗时", "总tokens"),
        re.I,
    )
    duration_values = [
        float(value) / 60 if unit == "分钟" else float(value)
        for value, unit in duration_matches
    ]

    lengths = {
        "models": len(model_names),
        "passes": len(pass_values),
        "iq": len(iq_values),
        "cost": len(cost_values),
        "duration": len(duration_values),
    }
    if len(set(lengths.values())) != 1:
        raise RadarParseError(f"Metric column length mismatch: {lengths}")

    metrics = tuple(
        ModelMetric(
            name=model_names[index],
            passed=int(pass_values[index][0]),
            total=int(pass_values[index][1]),
            iq=float(iq_values[index]),
            cost_usd=float(cost_values[index]),
            duration_hours=float(duration_values[index]),
        )
        for index in range(len(model_names))
    )
    return label, updated_at, metrics


def choose_strongest(models: Iterable[ModelMetric]) -> ModelMetric:
    return sorted(
        models,
        key=lambda item: (
            -item.passed,
            -item.iq,
            item.cost_usd,
            item.duration_hours,
            item.name,
        ),
    )[0]


def choose_value_pick(models: Iterable[ModelMetric]) -> ModelMetric:
    model_list = list(models)
    best_passed = max(item.passed for item in model_list)
    candidates = [
        item
        for item in model_list
        if item.passed >= best_passed - 1 and item.iq >= 90
    ]
    if not candidates:
        candidates = model_list
    return sorted(
        candidates,
        key=lambda item: (
            item.cost_per_pass,
            item.cost_usd,
            item.duration_hours,
            -item.passed,
            -item.iq,
            item.name,
        ),
    )[0]


def build_dataset(html: str, now: datetime | None = None) -> RadarDataset:
    now = now or datetime.now(SHANGHAI)
    label, updated_at, models = parse_metrics(html, now=now)
    return RadarDataset(
        site_updated_label=label,
        site_updated_at=updated_at,
        observed_at=now.isoformat(),
        source_url=SOURCE_URL,
        models=models,
        strongest=choose_strongest(models),
        value_pick=choose_value_pick(models),
    )


def metric_summary(metric: ModelMetric) -> str:
    return (
        f"{metric.name}（{metric.passed}/{metric.total}，IQ {metric.iq:g}，"
        f"${metric.cost_usd:g}，{metric.duration_hours:g}h）"
    )


def recommendation_signature(dataset: RadarDataset) -> str:
    return f"{dataset.strongest.name}|{dataset.value_pick.name}"


def dataset_payload(dataset: RadarDataset) -> dict[str, Any]:
    return {
        "schema_version": "1.0",
        "source": {
            "url": dataset.source_url,
            "site_updated_label": dataset.site_updated_label,
            "site_updated_at": dataset.site_updated_at,
            "observed_at": dataset.observed_at,
        },
        "recommendations": {
            "strongest": asdict(dataset.strongest),
            "value_pick": asdict(dataset.value_pick),
            "signature": recommendation_signature(dataset),
            "value_rule": (
                "Among models within one passed task of the strongest result and IQ >= 90, "
                "choose the lowest cost per passed task; use cost and duration as tie-breakers."
            ),
        },
        "models": [asdict(item) for item in dataset.models],
    }


def load_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise RadarParseError(f"Expected object in {path}")
    return value


def same_dataset(previous: dict[str, Any] | None, current: dict[str, Any]) -> bool:
    if not previous:
        return False
    return (
        previous.get("source", {}).get("site_updated_at")
        == current.get("source", {}).get("site_updated_at")
        and previous.get("models") == current.get("models")
    )


def recommendation_changed(previous: dict[str, Any] | None, current: dict[str, Any]) -> bool:
    if not previous:
        return True
    return (
        previous.get("recommendations", {}).get("signature")
        != current.get("recommendations", {}).get("signature")
    )


def render_table(models: Iterable[ModelMetric]) -> str:
    rows = [
        "| 模型 | 通过 | IQ | 费用 | 耗时 |",
        "|---|---:|---:|---:|---:|",
    ]
    for item in sorted(models, key=lambda model: (-model.passed, model.cost_usd)):
        rows.append(
            f"| {item.name} | {item.passed}/{item.total} | {item.iq:g} | "
            f"${item.cost_usd:g} | {item.duration_hours:g}h |"
        )
    return "\n".join(rows)


def render_latest_markdown(dataset: RadarDataset) -> str:
    return f"""# CodexRadar 最新快照

- 数据更新时间：**{dataset.site_updated_label}（北京时间）**
- 当前能力最强：**{metric_summary(dataset.strongest)}**
- 当前综合性价比：**{metric_summary(dataset.value_pick)}**
- 最后抓取：{dataset.observed_at}
- 来源：{dataset.source_url}

## 本轮完整数据

{render_table(dataset.models)}

## 性价比规则

只在距离本轮最高通过数不超过 1 题、且 IQ 不低于 90 的组合中比较；优先选择每道通过题的成本更低者，再以总费用和耗时作为排序条件。

> 本文件由 GitHub Action 自动更新，请勿手工修改。
"""


def previous_metric(previous: dict[str, Any] | None, key: str) -> str:
    if not previous:
        return "无（首次建立基线）"
    value = previous.get("recommendations", {}).get(key, {})
    name = value.get("name")
    if not name:
        return "未知"
    return str(name)


def render_notification(
    dataset: RadarDataset,
    previous: dict[str, Any] | None,
) -> str:
    return f"""@{MENTION}

## CodexRadar 模型推荐发生变化

- 数据更新时间：**{dataset.site_updated_label}（北京时间）**
- 能力最强：**{previous_metric(previous, 'strongest')} → {dataset.strongest.name}**
- 综合性价比：**{previous_metric(previous, 'value_pick')} → {dataset.value_pick.name}**

### 当前建议

- 最难任务、最终验收：**{metric_summary(dataset.strongest)}**
- 日常默认、兼顾成本：**{metric_summary(dataset.value_pick)}**

<details>
<summary>展开本轮完整数据</summary>

{render_table(dataset.models)}

</details>

数据来源：{dataset.source_url}

> 自动判定规则：能力最强按通过数、IQ、费用、耗时依次排序；性价比只在距离最高通过数不超过 1 题且 IQ ≥ 90 的组合中比较每道通过题成本。
"""


def persist(dataset: RadarDataset) -> tuple[bool, bool]:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    latest_path = DATA_DIR / "latest.json"
    history_path = DATA_DIR / "history.jsonl"
    markdown_path = DATA_DIR / "README.md"

    previous = load_json(latest_path)
    current = dataset_payload(dataset)
    if same_dataset(previous, current):
        if NOTIFICATION_PATH.exists():
            NOTIFICATION_PATH.unlink()
        print(f"No new CodexRadar dataset; latest remains {dataset.site_updated_label}")
        return False, False

    changed = recommendation_changed(previous, current)

    latest_path.write_text(
        json.dumps(current, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    with history_path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(current, ensure_ascii=False, separators=(",", ":")) + "\n")
    markdown_path.write_text(render_latest_markdown(dataset), encoding="utf-8")

    if changed:
        NOTIFICATION_PATH.write_text(
            render_notification(dataset, previous),
            encoding="utf-8",
        )
    elif NOTIFICATION_PATH.exists():
        NOTIFICATION_PATH.unlink()

    print(
        f"Stored dataset {dataset.site_updated_label}; strongest={dataset.strongest.name}; "
        f"value={dataset.value_pick.name}; recommendation_changed={changed}"
    )
    return True, changed


def run() -> int:
    html = fetch_html(SOURCE_URL)
    dataset = build_dataset(html)
    persist(dataset)
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--html-file",
        type=Path,
        help="Parse a local HTML fixture instead of fetching the live site.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        if args.html_file:
            html = args.html_file.read_text(encoding="utf-8")
            dataset = build_dataset(html)
            persist(dataset)
            return 0
        return run()
    except (OSError, ValueError, RadarParseError, json.JSONDecodeError) as exc:
        print(f"CodexRadar monitor failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
