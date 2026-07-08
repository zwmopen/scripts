@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0swap-like-comment-prefix.ps1"
echo.
pause
