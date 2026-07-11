from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

UPDATER_NAME = "更新预览硬链接.py"
BAT_NAME = "双击更新预览硬链接.bat"

UPDATER_SCRIPT = r'''from __future__ import annotations

import argparse
import os
import re
import shutil
import time
from pathlib import Path

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
SKIP_KEYWORDS = ("预览", "硬链接")
MAX_PAGES = 3


def safe_name(name: str, max_len: int = 120) -> str:
    name = re.sub(r'[<>:"/\\|?*\r\n\t]', "_", name).strip()
    name = re.sub(r"\s+", " ", name).rstrip(". ")
    return (name or "未命名")[:max_len]


def natural_key(text: str):
    return [int(part) if part.isdigit() else part for part in re.split(r"(\d+)", text.lower())]


def numeric_page_name(path: Path) -> int | None:
    match = re.fullmatch(r"0*(\d+)", path.stem.strip())
    return int(match.group(1)) if match else None


def collect_images(post_dir: Path):
    files = [path for path in post_dir.iterdir() if path.is_file() and path.suffix.lower() in IMAGE_EXTS]
    if files and all(numeric_page_name(path) is not None for path in files):
        files.sort(key=lambda path: numeric_page_name(path) or 0)
    else:
        files.sort(key=lambda path: (-int(path.stat().st_mtime), natural_key(path.name)))
    return files[:MAX_PAGES]


def should_skip_dir(path: Path) -> bool:
    return path.name.startswith("0") or any(keyword in path.name for keyword in SKIP_KEYWORDS)


def find_preview_dir(source: Path) -> Path:
    candidates = [path for path in source.iterdir() if path.is_dir() and "预览" in path.name and "硬链接" in path.name]
    candidates.sort(key=lambda path: (0 if path.name.startswith("0") else 1, natural_key(path.name)))
    return candidates[0] if candidates else source / "0.模板预览（硬链接）"


def build_plan(source: Path, preview_dir: Path):
    plan = []
    post_dirs = sorted(
        (path for path in source.iterdir() if path.is_dir() and not should_skip_dir(path)),
        key=lambda path: natural_key(path.name),
    )
    for post_dir in post_dirs:
        base = safe_name(post_dir.name)
        for index, source_image in enumerate(collect_images(post_dir), 1):
            plan.append((source_image, preview_dir / f"{base}-P{index:02d}{source_image.suffix.lower()}"))
    return post_dirs, plan


def apply_plan(source: Path, preview_dir: Path, plan):
    stamp = time.strftime("%Y%m%d-%H%M%S")
    staging = source / f".preview-hardlink-staging-{stamp}-{os.getpid()}"
    backup = source / f".preview-hardlink-backup-{stamp}-{os.getpid()}"
    fail_after = int(os.environ.get("HARDLINK_TEST_FAIL_AFTER", "0") or "0")
    staging.mkdir(parents=False, exist_ok=False)
    old_moved = False
    committed = False

    try:
        for index, (source_image, destination) in enumerate(plan, 1):
            os.link(source_image, staging / destination.name)
            if fail_after and index >= fail_after:
                raise RuntimeError(f"simulated failure after {index} link(s)")

        if preview_dir.exists():
            preview_dir.rename(backup)
            old_moved = True

        staging.rename(preview_dir)
        committed = True
        if backup.exists():
            shutil.rmtree(backup)
    except Exception:
        if staging.exists():
            shutil.rmtree(staging, ignore_errors=True)
        if old_moved and backup.exists() and not preview_dir.exists():
            backup.rename(preview_dir)
        raise
    finally:
        if committed and backup.exists():
            shutil.rmtree(backup, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description="Refresh preview hardlinks transactionally.")
    parser.add_argument("--mode", choices=("Preview", "Apply"), default="Preview")
    parser.add_argument("--confirm", default="")
    args = parser.parse_args()

    source = Path(__file__).resolve().parent
    preview_dir = find_preview_dir(source)
    post_dirs, plan = build_plan(source, preview_dir)

    print(f"模式: {args.mode}")
    print(f"源目录: {source}")
    print(f"预览目录: {preview_dir}")
    print(f"帖子文件夹: {len(post_dirs)}")
    print(f"计划硬链接: {len(plan)}")

    if args.mode == "Preview":
        print("仅预览。使用 --mode Apply --confirm APPLY 执行。")
        return

    if args.confirm != "APPLY":
        raise SystemExit("Apply requires --confirm APPLY")

    apply_plan(source, preview_dir, plan)
    print("预览硬链接刷新完成")


if __name__ == "__main__":
    main()
'''

BAT_SCRIPT = r'''@echo off
chcp 65001 >nul
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
python "%~dp0更新预览硬链接.py" --mode Apply --confirm APPLY
echo.
echo 已完成。按任意键关闭窗口。
pause >nul
'''


def install(target: Path, apply: bool = False, overwrite: bool = True) -> tuple[Path, Path]:
    target = target.resolve()
    if not target.is_dir():
        raise NotADirectoryError(str(target))

    updater = target / UPDATER_NAME
    bat = target / BAT_NAME

    if not apply:
        print(f"PREVIEW install: {updater}")
        print(f"PREVIEW install: {bat}")
        return updater, bat

    if not overwrite and (updater.exists() or bat.exists()):
        raise FileExistsError("Updater files already exist.")

    backup_dir = target / ".hardlink-installer-backups" / time.strftime("%Y%m%d-%H%M%S")
    originals: dict[Path, Path] = {}
    temp_files: list[tuple[Path, Path]] = []

    try:
        for path, content in ((updater, UPDATER_SCRIPT), (bat, BAT_SCRIPT)):
            if path.exists():
                backup_dir.mkdir(parents=True, exist_ok=True)
                backup_path = backup_dir / path.name
                shutil.copy2(path, backup_path)
                originals[path] = backup_path

            file_descriptor, temp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=target)
            os.close(file_descriptor)
            temporary = Path(temp_name)
            temporary.write_text(content, encoding="utf-8")
            temp_files.append((temporary, path))

        for temporary, path in temp_files:
            os.replace(temporary, path)

        return updater, bat
    except Exception:
        for temporary, _ in temp_files:
            temporary.unlink(missing_ok=True)
        for path, backup_path in originals.items():
            if backup_path.exists():
                shutil.copy2(backup_path, path)
        raise


def main():
    parser = argparse.ArgumentParser(description="Install a transactional preview hardlink updater.")
    parser.add_argument("target", nargs="?", default=".")
    parser.add_argument("--apply", action="store_true", help="Write installer files. Default is preview only.")
    parser.add_argument("--no-overwrite", action="store_true")
    parser.add_argument("--run", action="store_true")
    args = parser.parse_args()

    target = Path(args.target)
    updater, bat = install(target, apply=args.apply, overwrite=not args.no_overwrite)

    if not args.apply:
        print("Preview only. Re-run with --apply to install.")
        return

    print(f"已安装: {updater}")
    print(f"已安装: {bat}")

    if args.run:
        result = subprocess.run(
            [sys.executable, str(updater), "--mode", "Apply", "--confirm", "APPLY"],
            cwd=str(target.resolve()),
            check=False,
        )
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
