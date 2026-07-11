@echo off
setlocal
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0swap-like-comment-prefix.ps1" -Mode Preview
echo.
echo 上面仅为预览，没有修改文件。
echo 确认后请按 README 使用 Apply 和确认令牌。
pause
