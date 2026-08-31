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
- `configure_work_package.ps1`: folder picker and config updater.
- `一键生成作品包.vbs`: simple visible launcher template.
- `设置作品包目录.vbs`: manual output-folder setup entry.
- `usage_zh.md`: Chinese usage guide copied into the target folder.

## Install Workflow

When the user wants to give this to someone else or install it into a new folder:

1. Ask for or infer the folder where images are downloaded.
2. Run the installer with that folder as `TargetFolder`.
3. Choose either a child-folder `LibraryName` or an absolute `LibraryPath`.
4. Use `RegisterProtocol` when the ChatGPT userscript should invoke the local packager.
5. Tell the user which file to double-click and the human workflow.

Example:

```powershell
& "D:\AICode\工具开发\projects\chatgpt-conversation-tree\src\work-package\install_work_package_tool.ps1" `
  -TargetFolder "D:\Download" `
  -LibraryName "团建成品库" `
  -LibraryPath "D:\Projects\MyProject\团建成品库" `
  -RegisterProtocol
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

Important: one copied text block corresponds to one note. Exact duplicate image sets are the primary duplicate key; equal normalized copy with newly generated image bytes is allowed and receives a similar-copy notice.

## Required Behavior

Preserve these rules when modifying the template:

- Only process files in the script's own folder level. Do not enter child folders.
- If the clipboard has no text, show a short toast saying `请先复制文案` and do not create any library/package folder.
- If clipboard text exists but there are no same-level user images, show `请先下载作品图`, do not create any library/package folder, do not clear the clipboard, and leave the folder untouched.
- Compute SHA-256 for every image and a stable order-independent image-set hash. If the complete image set already exists in history, do not create a package even when the copy changed. Send current same-level images to the Recycle Bin, clear the clipboard, and show `本次为重复下载，已删除本地图片和文案。`.
- Store durable history in `<library>\_作品历史数据\作品历史数据库.json`, keep the previous valid primary as `.backup.json`, and maintain a hidden runtime mirror `.workpkg_history_backup.json`. Never rely on archived work folders remaining present.
- If normalized copy matches history but the exact image set differs, create the package and show `本组有历史相似文案，但图片不同，已继续创建作品包。`.
- Store a 64-bit dHash for supported images. When every image can be matched one-to-one to a historical package within the configured Hamming thresholds, stop without deleting downloads, report and copy the historical folder path, and allow one second-run bypass for that exact image set.
- Only after fresh clipboard text exists, create or use the configured library folder.
- Create each note/post package folder as `yyyyMMdd_HHmmss_<first non-empty line of copy>` with no leading dot. Keep legacy `.yyyyMMdd_HHmmss_` folders compatible for duplicate scanning and portfolio grouping, but never add the dot to newly created folders.
- Save clipboard text as `文案_yyyyMMdd_HHmmss.txt` inside that package folder.
- Save successful task and provenance metadata together in `GPT作品记录.json`; do not generate separate task/provenance files. Preserve compatibility when reading legacy `GPT任务记录.json`. Never mix account or URL metadata into the clipboard copy text, and missing metadata must not block packaging.
- Do not create, copy, or insert any blank separator image. Packages should contain only the text file and the user-downloaded images.
- Name package media with the copy title first and a package timestamp before the sequence: `<title>_yyyyMMdd_HHmmss_01.ext`, `<title>_yyyyMMdd_HHmmss_02.ext`, etc. This keeps every image name unique across packages and makes name sorting useful on phones.
- Set package file times in order: text at package time, then user images at package time + 1 second, + 2 seconds, etc. This keeps time sorting grouped more predictably.
- Move same-level images into the package folder and order them by modification time before renaming.
- Never treat legacy `分隔图.png` as a user-downloaded image when moving or cleaning duplicates.
- On first migration or explicit `-RebuildHistory`, scan archived packages recursively to build the durable history database. Normal duplicate checks must read the database instead of rescanning every archived text and image.
- If `portfolio_auto_group` is enabled, after a new package is created, group top-level loose package folders into visible `作品集_001`, `作品集_002`, etc. using `portfolio_batch_size` folders per portfolio. Accept both current `yyyyMMdd_HHmmss_` and legacy `.yyyyMMdd_HHmmss_` note folders.
- Write completed portfolio folders, optional ZIP files, and move logs under `portfolio_output_path`. If that setting is missing or blank, use `library_path` for backward compatibility.
- Default `portfolio_auto_zip` to `false`. If the user enables it, create a same-level ZIP archive for each newly created portfolio folder, for example `作品集_005.zip`. The archive should contain the 14 package folders directly.
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
  "library_path": "",
  "portfolio_output_path": "",
  "success_message": "已创建作品包",
  "no_text_message": "请先复制文案",
  "no_image_message": "请先下载作品图",
  "duplicate_text_message": "还是上一条文案，先复制新文案",
  "duplicate_existing_message": "本次为重复下载，已删除本地图片和文案。",
  "portfolio_grouped_message": "已创建作品包，已整理作品集",
  "portfolio_zipped_message": "已创建作品包，已整理并压缩作品集",
  "portfolio_group_done_message": "已整理作品集",
  "portfolio_zip_done_message": "已生成ZIP压缩包",
  "portfolio_zip_failed_message": "作品集压缩失败",
  "portfolio_auto_group": true,
  "portfolio_auto_zip": false,
  "portfolio_batch_size": 14,
  "portfolio_prefix": "作品集",
  "portfolio_log_folder": "_portfolio_move_logs"
}
```

If the user asks for a different output folder name, update `library_name`. If the output belongs in a separate project or disk, set an absolute `library_path`; it takes precedence over `library_name`.

## Validation

Always test installs/upgrades in a temporary folder before touching a real material folder.

Minimum tests:

- Fresh copy plus two fake images: creates the configured library, creates one package folder under it, writes one `文案_*.txt`, creates no blank separator image, and moves images as `<title>_yyyyMMdd_HHmmss_01`, `<title>_yyyyMMdd_HHmmss_02`, etc.
- Empty clipboard text: does not create the library, does not create a package folder, and leaves images in place.
- Text but no same-level images: shows `请先下载作品图`, creates no package, leaves clipboard/text state alone, and leaves folders untouched.
- Duplicate exact image set: does not create a new package and cleans the newly downloaded same-level images, even if copy differs.
- Same normalized copy with different image bytes: creates a new package and reports similar copy.
- Visual-near but byte-different image set: stops before packaging, preserves downloads, reports the historical folder, and permits one explicit second-run bypass.
- History rebuild preview: finds duplicated existing package folders without requiring clipboard text or downloaded images.
- Portfolio grouping: with 13 existing loose package folders and one new package, creates the next `作品集_###`, moves 14 folders into it, creates `作品集_###.zip`, logs the move/zip, and still detects duplicate text inside that portfolio afterward.
- Syntax check passes for the installed `make_work_package.ps1`.
- Absolute-library install: images are read from the runtime/download folder, the package is created under `library_path`, and no shadow library is created beside the runtime scripts.
- Upgrade install: existing config values remain intact unless the corresponding installer parameter is explicitly supplied.

Use the script's test-only parameters:

```powershell
.\make_work_package.ps1 -ClipboardTextOverride "标题`r`n正文" -NoMessage
.\make_work_package.ps1 -ClipboardTextOverride "" -NoMessage
```

`-NoMessage` emits text signals instead of showing toasts.
