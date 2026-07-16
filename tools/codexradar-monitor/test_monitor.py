#!/usr/bin/env python3
"""Unit tests for the dependency-free CodexRadar monitor."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

MODULE_PATH = Path(__file__).with_name("monitor.py")
SPEC = importlib.util.spec_from_file_location("codexradar_monitor", MODULE_PATH)
assert SPEC and SPEC.loader
monitor = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(monitor)

SAMPLE_HTML = """
<!doctype html>
<html lang="zh-CN">
<head><title>Codex 雷达</title><style>.hidden{display:none}</style></head>
<body>
  <h2>降智雷达 7月15日17:22更新</h2>
  <p>每天更新两次</p>
  <h3>本次多模型指标</h3>
  <table>
    <thead><tr><th>项目</th><th>Sol max</th><th>Sol low</th><th>Luna max</th><th>Luna high</th></tr></thead>
    <tbody>
      <tr><td>通过数</td><td>6/10</td><td>8/10</td><td>9/10</td><td>5/10</td></tr>
      <tr><td>IQ</td><td>90.0</td><td>120.0</td><td>135.0</td><td>75.0</td></tr>
      <tr><td>Agent steps</td><td>62.1</td><td>24.7</td><td>77.1</td><td>47.7</td></tr>
      <tr><td>费用</td><td>$51.4</td><td>$10.7</td><td>$16.3</td><td>$6.7</td></tr>
      <tr><td>cache命中率</td><td>97.1%</td><td>93.7%</td><td>96.0%</td><td>96.1%</td></tr>
      <tr><td>耗时</td><td>4.2h</td><td>1.0h</td><td>4.0h</td><td>2.2h</td></tr>
      <tr><td>总tokens</td><td>58.8M</td><td>9.9M</td><td>91.0M</td><td>37.4M</td></tr>
    </tbody>
  </table>
  <h3>固定评测任务集</h3>
  <script>document.write('降智雷达 1月1日00:00更新');</script>
</body>
</html>
"""


class MonitorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.now = datetime(2026, 7, 16, 9, 0, tzinfo=ZoneInfo("Asia/Shanghai"))

    def test_parse_metrics(self) -> None:
        label, updated_at, models = monitor.parse_metrics(SAMPLE_HTML, now=self.now)
        self.assertEqual(label, "7月15日17:22")
        self.assertEqual(updated_at, "2026-07-15T17:22:00+08:00")
        self.assertEqual([item.name for item in models], ["Sol max", "Sol low", "Luna max", "Luna high"])
        self.assertEqual(models[2].passed, 9)
        self.assertEqual(models[2].cost_usd, 16.3)

    def test_rankings_match_expected_policy(self) -> None:
        dataset = monitor.build_dataset(SAMPLE_HTML, now=self.now)
        self.assertEqual(dataset.strongest.name, "Luna max")
        self.assertEqual(dataset.value_pick.name, "Sol low")

    def test_persist_only_notifies_on_recommendation_change(self) -> None:
        dataset = monitor.build_dataset(SAMPLE_HTML, now=self.now)
        with tempfile.TemporaryDirectory() as temp_dir:
            original_data_dir = monitor.DATA_DIR
            original_notification = monitor.NOTIFICATION_PATH
            try:
                monitor.DATA_DIR = Path(temp_dir) / "data"
                monitor.NOTIFICATION_PATH = Path(temp_dir) / "notification.md"
                stored, changed = monitor.persist(dataset)
                self.assertTrue(stored)
                self.assertTrue(changed)
                self.assertTrue(monitor.NOTIFICATION_PATH.exists())

                monitor.NOTIFICATION_PATH.unlink()
                stored, changed = monitor.persist(dataset)
                self.assertFalse(stored)
                self.assertFalse(changed)
                self.assertFalse(monitor.NOTIFICATION_PATH.exists())
            finally:
                monitor.DATA_DIR = original_data_dir
                monitor.NOTIFICATION_PATH = original_notification


if __name__ == "__main__":
    unittest.main()
