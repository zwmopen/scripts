@echo off
set "PIDFILE=%~dp0wechat-voice-x2-bridge.pid"
if not exist "%PIDFILE%" (
  echo WeChat Voice X2 Bridge is not running.
  pause
  exit /b 0
)
set /p BRIDGEPID=<"%PIDFILE%"
taskkill /PID %BRIDGEPID% /F
del "%PIDFILE%" >nul 2>nul
echo WeChat Voice X2 Bridge stopped.
pause

