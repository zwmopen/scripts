#!/usr/bin/env python3
"""Unit tests for the rolling CodexRadar recommendation."""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

MODULE_PATH = Path(__file__).with_name("long_term.py")
SPEC = importlib.util.spec_from_file_location("codexradar_long_term", MODULE_PATH)
assert SPEC and SPEC.loader
long_term = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = long_term
SPEC.loader.exec_module(long_term)

TZ = ZoneInfo("Asia/Shanghai")


def entry(at: datetime, scores: dict[str, tuple[int, float, float, float]]) -> dict:
    return {
        "schema_version": "1.0",
        "source": {
            "url": "https://codexradar.com/",
            "site_updated_label": at.strftime("%m月%d日%H:%M"),
            "site_updated_at": at.isoformat(),
            "observed_at": at.isoformat(),
        },
        "recommendations": {
            "strongest": {"name": max(scores, key=lambda name: scores[name][0])},
            "value_pick": {"name": min(scores, key=lambda name: scores[name][2] / scores[name][0])},
        },
        "models": [
            {
                "name": name,
                "passed": values[0],
                "total": 10,
                "iq": values[1],
                "cost_usd": values[2],
                "duration_hours": values[3],
            }
            for name, values in scores.items()
        ],
    }


class LongTermTests(unittest.TestCase):
    def setUp(self) -> None:
        self.now = datetime(2026, 7, 16, 9, 0, tzinfo=TZ)

    def test_collects_before_minimum_rounds(self) -> None:
        latest = entry(self.now, {
            "Sol low": (8, 120, 10, 1),
            "Luna max": (9, 135, 16, 4),
        })
        result = long_term.calculate([], latest, minimum_samples=4)
        self.assertEqual(result.status, "collecting")
        self.assertEqual(result.round_count, 1)
        self.assertIsNone(result.default_name)

    def test_separates_long_term_strength_from_daily_default(self) -> None:
        history = []
        luna_scores = [9, 9, 8, 9, 8, 9]
        sol_scores = [8, 8, 8, 8, 8, 8]
        xhigh_scores = [7, 7, 7, 7, 7, 10]
        for index in range(5):
            at = self.now - timedelta(hours=12 * (5 - index))
            history.append(entry(at, {
                "Luna max": (luna_scores[index], 15 * luna_scores[index], 16, 4),
                "Sol low": (sol_scores[index], 15 * sol_scores[index], 10, 1),
                "Sol xhigh": (xhigh_scores[index], 15 * xhigh_scores[index], 35, 2.8),
            }))
        latest = entry(self.now, {
            "Luna max": (luna_scores[-1], 135, 16, 4),
            "Sol low": (sol_scores[-1], 120, 10, 1),
            "Sol xhigh": (xhigh_scores[-1], 150, 35, 2.8),
        })
        result = long_term.calculate(history, latest, minimum_samples=4)
        self.assertEqual(result.status, "ready")
        self.assertEqual(result.strongest_name, "Luna max")
        self.assertEqual(result.default_name, "Sol low")
        xhigh = long_term.find_model(result, "Sol xhigh")
        self.assertIsNotNone(xhigh)
        self.assertEqual(xhigh.maximum_passed, 10)
        self.assertEqual(xhigh.median_passed, 7)

    def test_deduplicates_same_site_round(self) -> None:
        one = entry(self.now, {"Sol low": (8, 120, 10, 1)})
        two = entry(self.now, {"Sol low": (7, 105, 10, 1)})
        rounds = long_term.unique_rounds([one, two])
        self.assertEqual(len(rounds), 1)
        self.assertEqual(rounds[0]["models"][0]["passed"], 7)

    def test_run_writes_json_and_markdown(self) -> None:
        latest = entry(self.now, {
            "Sol low": (8, 120, 10, 1),
            "Luna max": (9, 135, 16, 4),
        })
        with tempfile.TemporaryDirectory() as temp_dir:
            data_dir = Path(temp_dir)
            (data_dir / "latest.json").write_text(json.dumps(latest), encoding="utf-8")
            (data_dir / "history.jsonl").write_text(json.dumps(latest) + "\n", encoding="utf-8")
            original = long_term.DATA_DIR
            try:
                long_term.DATA_DIR = data_dir
                result = long_term.run()
                self.assertEqual(result.status, "collecting")
                self.assertTrue((data_dir / "rolling-7d.json").exists())
                markdown = (data_dir / "LONG_TERM.md").read_text(encoding="utf-8")
                self.assertIn("长期默认：**尚不下结论**", markdown)
            finally:
                long_term.DATA_DIR = original


if __name__ == "__main__":
    unittest.main()
