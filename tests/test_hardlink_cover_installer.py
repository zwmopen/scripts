from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALLER_PATH = ROOT / "本地文件处理脚本" / "素材处理脚本" / "安装-一键生成硬链接封面.py"

spec = importlib.util.spec_from_file_location("hardlink_installer", INSTALLER_PATH)
installer = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(installer)


class HardlinkInstallerTests(unittest.TestCase):
    def test_install_defaults_to_preview(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp)
            updater, bat = installer.install(target, apply=False)
            self.assertFalse(updater.exists())
            self.assertFalse(bat.exists())

    def test_apply_installs_and_backs_up_existing_files(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp)
            updater = target / installer.UPDATER_NAME
            bat = target / installer.BAT_NAME
            updater.write_text("old updater", encoding="utf-8")
            bat.write_text("old bat", encoding="utf-8")

            installer.install(target, apply=True)

            self.assertIn("transactionally", updater.read_text(encoding="utf-8"))
            backups = list((target / ".hardlink-installer-backups").glob("*/" + installer.UPDATER_NAME))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_text(encoding="utf-8"), "old updater")

    def test_updater_preview_apply_and_failure_rollback(self):
        with tempfile.TemporaryDirectory() as temp:
            target = Path(temp)
            installer.install(target, apply=True)
            updater = target / installer.UPDATER_NAME

            post_a = target / "1.项目A"
            post_b = target / "2.项目B"
            post_a.mkdir()
            post_b.mkdir()
            (post_a / "1.png").write_bytes(b"A")
            (post_b / "1.jpg").write_bytes(b"B")

            preview_dir = target / "0.模板预览（硬链接）"
            preview_dir.mkdir()
            old_file = preview_dir / "old.txt"
            old_file.write_text("keep", encoding="utf-8")

            preview = subprocess.run(
                [sys.executable, str(updater)],
                cwd=target,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertTrue(old_file.exists())

            env = os.environ.copy()
            env["HARDLINK_TEST_FAIL_AFTER"] = "1"
            failed = subprocess.run(
                [sys.executable, str(updater), "--mode", "Apply", "--confirm", "APPLY"],
                cwd=target,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertNotEqual(failed.returncode, 0)
            self.assertTrue(old_file.exists(), "old preview must survive a failed staging build")
            self.assertFalse(any(target.glob(".preview-hardlink-staging-*")))

            applied = subprocess.run(
                [sys.executable, str(updater), "--mode", "Apply", "--confirm", "APPLY"],
                cwd=target,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(applied.returncode, 0, applied.stderr)
            self.assertFalse(old_file.exists())
            links = list(preview_dir.iterdir())
            self.assertEqual(len(links), 2)
            self.assertTrue(all(path.is_file() for path in links))


if __name__ == "__main__":
    unittest.main()
