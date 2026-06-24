---
name: xhs-gpt-work-package
description: Use when helping the user distribute, install, explain, customize, or repair a generic Windows one-click GPT work-package tool for colleagues or other users. Trigger on requests about sharing the GPT文案+图片 workflow, creating a reusable skill/script package, installing 一键生成作品包.vbs into a download-image folder, packaging clipboard copy into TXT, renaming images to 01/02/03, or producing a 成品库 / 团建成品库 folder workflow.
---

# GPT Work Package Tool

This skill turns a repeatable human workflow into a portable local tool:

1. Download the images for one note into a working folder.
2. Copy the GPT-written note copy.
3. Double-click a generated `一键生成作品包.vbs`.
4. Receive one finished package folder containing `文案_*.txt` and renamed images.
5. When enough loose package folders accumulate, automatically group them into numbered portfolio folders such as `作品集_001`.

The skill is not only for the current user's machine. Treat it as a distributable workplace helper: documentation plus scripts plus an installer.

## Bundle Contents

Use the files in `scripts/`:

- `install_work_package_tool.ps1`: installer/generator for another user's target folder.
- `make_work_package.ps1`: portable core script copied by the installer.
- `一键生成作品包.vbs`: simple visible launcher template.
- `usage_zh.md`: Chinese usage guide copied into the target folder.

## Install Workflow

When the user wants to give this to someone else or install it into a new folder:

1. Ask for or infer the folder where images are downloaded.
2. Run the installer with that folder as `TargetFolder`.
3. Choose a library name. Default is `成品库`; use `团建成品库` for the team-building workflow.
4. Tell the user which file to double-click and the human workflow.

Example:

```powershell
& "C:\Users\z\.codex\skills\xhs-gpt-work-package\scripts\install_work_package_tool.ps1" `
  -TargetFolder "D:\Download\素材下载" `
  -LibraryName "团建成品库"
```

The installer creates or updates these files in the target folder:

```text
一键生成作品包.vbs
make_work_package.ps1
workpkg_config.json
使用说明-一键作品包.md
```

It hides `make_work_package.ps1` after installation.

## User-Facing Usage

Explain it like this:

```text
1. 先把这一篇笔记的图片下载到这个文件夹。
2. 再复制 GPT 生成好的文案。
3. 双击“一键生成作品包.vbs”。
4. 成品会自动进入“成品库”（或你设置的成品库名字）。
```

Important: one copied text block corresponds to one note. If the user forgets to copy text or repeats the previous text, the tool must refuse to package images.

## Required Behavior

Preserve these rules when modifying the template:

- Only process files in the script's own folder level. Do not enter child folders.
- If the clipboard has no text, show a short toast saying `请先复制文案` and do not create any library/package folder.
- If clipboard text exists but there are no same-level user images, show `请先下载作品图`, do not create any library/package folder, do not clear the clipboard, and leave the folder untouched.
- If the clipboard text exactly matches an existing archived `文案_*.txt`, treat it as already packaged, clean the current same-level downloaded images, and show `该作品已创建过，已清理本次重复下载`.
- If the clipboard still contains the previous note copy, treat it as duplicate rather than creating another package.
- Only after fresh clipboard text exists, create or use the configured library folder.
- Create a package folder named `yyyyMMdd_HHmmss_<first non-empty line of copy>`.
- Save clipboard text as `文案_yyyyMMdd_HHmmss.txt` inside that package folder.
- Do not create, copy, or insert any blank separator image. Packages should contain only the text file and the user-downloaded images.
- Name package media with the copy title first and a package timestamp before the sequence: `<title>_yyyyMMdd_HHmmss_01.ext`, `<title>_yyyyMMdd_HHmmss_02.ext`, etc. This keeps every image name unique across packages and makes name sorting useful on phones.
- Set package file times in order: text at package time, then user images at package time + 1 second, + 2 seconds, etc. This keeps time sorting grouped more predictably.
- Move same-level images into the package folder and order them by modification time before renaming.
- Never treat legacy `分隔图.png` as a user-downloaded image when moving or cleaning duplicates.
- For duplicate checks, search archived `文案_*.txt` recursively inside the library so packages inside `作品集_001`, `作品集_002`, etc. are still detected.
- If `portfolio_auto_group` is enabled, after a new package is created, group top-level loose package folders into `作品集_001`, `作品集_002`, etc. using `portfolio_batch_size` folders per portfolio. Only folders whose names start with `yyyyMMdd_HHmmss_` should be grouped.
- If `portfolio_auto_zip` is enabled, create a same-level ZIP archive for each newly created portfolio folder, for example `作品集_005.zip`. The archive should contain the 14 package folders directly.
- Skip existing portfolio folders, `_portfolio_move_logs`, files, archives, and child folders. If the loose package count is below the batch size, leave them in place.
- Write portfolio preview/result CSV logs under `_portfolio_move_logs`; do not use blocking popups for the integrated one-click flow.
- On success, show short stage toasts in sequence so the user can see progress nodes: `已创建作品包`; if grouping happened, `已整理作品集`; if ZIP succeeded, `已生成ZIP压缩包`; if ZIP failed, `作品集压缩失败`.
- Duplicate cleanup should send files to the Recycle Bin where possible; test mode may remove temporary fake files directly.
- Clear the clipboard after a successful package.
- Toasts should appear near the center of the screen and auto-close quickly. Prefer a refined white-green rounded card: soft near-white background, green accent strip, dark green text, light shadow, and modest font size. Do not use blocking message boxes and do not open the new folder on success.
- Keep the visible double-click file Chinese and friendly; keep the invoked PowerShell implementation ASCII-named to avoid Windows double-click encoding issues.

## Customization

The installed tool reads `workpkg_config.json`. For another user, prefer changing config instead of editing code:

```json
{
  "library_name": "成品库",
  "success_message": "已创建作品包",
  "no_text_message": "请先复制文案",
  "no_image_message": "请先下载作品图",
  "duplicate_text_message": "还是上一条文案，先复制新文案",
  "duplicate_existing_message": "该作品已创建过，已清理本次重复下载",
  "portfolio_grouped_message": "已创建作品包，已整理作品集",
  "portfolio_zipped_message": "已创建作品包，已整理并压缩作品集",
  "portfolio_group_done_message": "已整理作品集",
  "portfolio_zip_done_message": "已生成ZIP压缩包",
  "portfolio_zip_failed_message": "作品集压缩失败",
  "portfolio_auto_group": true,
  "portfolio_auto_zip": true,
  "portfolio_batch_size": 14,
  "portfolio_prefix": "作品集",
  "portfolio_log_folder": "_portfolio_move_logs"
}
```

If the user asks for a different output folder name, update `library_name`.

## Validation

Always test installs/upgrades in a temporary folder before touching a real material folder.

Minimum tests:

- Fresh copy plus two fake images: creates the configured library, creates one package folder under it, writes one `文案_*.txt`, creates no blank separator image, and moves images as `<title>_yyyyMMdd_HHmmss_01`, `<title>_yyyyMMdd_HHmmss_02`, etc.
- Empty clipboard text: does not create the library, does not create a package folder, and leaves images in place.
- Text but no same-level images: shows `请先下载作品图`, creates no package, leaves clipboard/text state alone, and leaves folders untouched.
- Duplicate existing copy: does not create a new package and cleans the newly downloaded same-level images.
- Portfolio grouping: with 13 existing loose package folders and one new package, creates the next `作品集_###`, moves 14 folders into it, creates `作品集_###.zip`, logs the move/zip, and still detects duplicate text inside that portfolio afterward.
- Syntax check passes for the installed `make_work_package.ps1`.

Use the script's test-only parameters:

```powershell
.\make_work_package.ps1 -ClipboardTextOverride "标题`r`n正文" -NoMessage
.\make_work_package.ps1 -ClipboardTextOverride "" -NoMessage
```

`-NoMessage` emits text signals instead of showing toasts.
