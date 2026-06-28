from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


UPDATER_NAME = "更新预览硬链接.py"
BAT_NAME = "双击更新预览硬链接.bat"


UPDATER_SCRIPT = r'''from __future__ import annotations

import os
import re
from pathlib import Path


IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}
SKIP_KEYWORDS = ("预览", "硬链接")
MAX_PAGES = 3


def safe_name(name: str, max_len: int = 120) -> str:
    name = re.sub(r'[<>:"/\\|?*\r\n\t]', "_", name).strip()
    name = re.sub(r"\s+", " ", name)
    name = name.rstrip(". ")
    return (name or "未命名")[:max_len]


def natural_key(text: str):
    parts = re.split(r"(\d+)", text.lower())
    return [int(p) if p.isdigit() else p for p in parts]


def numeric_page_name(path: Path) -> int | None:
    m = re.fullmatch(r"0*(\d+)", path.stem.strip())
    if not m:
        return None
    return int(m.group(1))


def is_pure_numeric_sequence(files: list[Path]) -> bool:
    return bool(files) and all(numeric_page_name(path) is not None for path in files)


def page_hint_key(path: Path):
    stem = path.stem.strip().lower()
    m = re.fullmatch(r"p\s*0*(\d+)", stem)
    if m:
        return (0, int(m.group(1)))
    if stem in {"图片", "image", "img"}:
        return (0, 1)
    m = re.fullmatch(r"(?:图片|image|img)[\s_（(]*0*(\d+)[）)]?", stem)
    if m:
        return (0, int(m.group(1)) + 1)
    return (1, natural_key(path.name))


def image_sort_key(path: Path):
    return (-int(path.stat().st_mtime), page_hint_key(path))


def should_skip_dir(path: Path) -> bool:
    name = path.name
    return name.startswith("0") or any(keyword in name for keyword in SKIP_KEYWORDS)


def find_preview_dir(source: Path) -> Path:
    dirs = [p for p in source.iterdir() if p.is_dir()]
    candidates = [p for p in dirs if "预览" in p.name and "硬链接" in p.name]
    candidates.sort(key=lambda p: (0 if p.name.startswith("0") else 1, natural_key(p.name)))
    if candidates:
        return candidates[0]
    return source / "0.模板预览（硬链接）"


def clear_preview_files(preview_dir: Path):
    preview_dir.mkdir(parents=True, exist_ok=True)
    for item in preview_dir.iterdir():
        if item.is_file():
            item.unlink()


def collect_images(post_dir: Path):
    files = [p for p in post_dir.iterdir() if p.is_file() and p.suffix.lower() in IMAGE_EXTS]
    if is_pure_numeric_sequence(files):
        sorted_files = sorted(files, key=lambda path: numeric_page_name(path) or 0)
    else:
        sorted_files = sorted(files, key=image_sort_key)
    return sorted_files[:MAX_PAGES]


def hardlink(src: Path, dst: Path):
    if dst.exists():
        dst.unlink()
    os.link(src, dst)


def process_post(post_dir: Path, preview_dir: Path):
    base = safe_name(post_dir.name)
    stats = {"images": 0, "created": 0, "failed": 0}

    for idx, src in enumerate(collect_images(post_dir), 1):
        dst = preview_dir / f"{base}-P{idx:02d}{src.suffix.lower()}"
        try:
            hardlink(src, dst)
            stats["created"] += 1
        except Exception as exc:
            stats["failed"] += 1
            print(f"失败: {src} -> {dst}: {exc}")
        stats["images"] += 1

    return stats


def main():
    source = Path(__file__).resolve().parent
    preview_dir = find_preview_dir(source)
    clear_preview_files(preview_dir)

    post_dirs = [p for p in source.iterdir() if p.is_dir() and not should_skip_dir(p)]
    post_dirs.sort(key=lambda p: natural_key(p.name))

    totals = {"posts": 0, "images": 0, "created": 0, "failed": 0, "no_images": 0}
    for post_dir in post_dirs:
        stats = process_post(post_dir, preview_dir)
        totals["posts"] += 1
        totals["images"] += stats["images"]
        totals["created"] += stats["created"]
        totals["failed"] += stats["failed"]
        if stats["images"] == 0:
            totals["no_images"] += 1

    print("预览硬链接刷新完成")
    print(f"源目录: {source}")
    print(f"预览目录: {preview_dir}")
    print(f"帖子文件夹: {totals['posts']}")
    print(f"图片: {totals['images']}（每个文件夹最多 {MAX_PAGES} 张）")
    print(f"创建硬链接: {totals['created']}")
    print(f"失败: {totals['failed']}")
    print(f"无图片文件夹: {totals['no_images']}")


if __name__ == "__main__":
    main()
'''


BAT_SCRIPT = r'''@echo off
chcp 65001 >nul
cd /d "%~dp0"
set PYTHONIOENCODING=utf-8
python "%~dp0更新预览硬链接.py"
echo.
echo 已完成。按任意键关闭窗口。
pause >nul
'''


def install(target: Path, overwrite: bool = True) -> tuple[Path, Path]:
    target = target.resolve()
    if not target.exists() or not target.is_dir():
        raise NotADirectoryError(str(target))

    updater = target / UPDATER_NAME
    bat = target / BAT_NAME
    if not overwrite:
        for path in (updater, bat):
            if path.exists():
                raise FileExistsError(str(path))

    updater.write_text(UPDATER_SCRIPT, encoding="utf-8")
    bat.write_text(BAT_SCRIPT, encoding="utf-8")
    return updater, bat


def main():
    parser = argparse.ArgumentParser(description="Install a double-click preview hardlink updater into a folder.")
    parser.add_argument("target", nargs="?", default=".", help="Target folder. Defaults to current working directory.")
    parser.add_argument("--no-overwrite", action="store_true", help="Do not overwrite existing updater files.")
    parser.add_argument("--run", action="store_true", help="Run the installed updater immediately.")
    args = parser.parse_args()

    target = Path(args.target)
    updater, bat = install(target, overwrite=not args.no_overwrite)
    print(f"已安装: {updater}")
    print(f"已安装: {bat}")

    if args.run:
        print("开始刷新预览硬链接...")
        result = subprocess.run([sys.executable, str(updater)], cwd=str(target))
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
