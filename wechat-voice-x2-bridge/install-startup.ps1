$ErrorActionPreference = 'Stop'

$startupDir = [Environment]::GetFolderPath('Startup')
$shortcutPath = Join-Path $startupDir 'WeChat Voice X2 Bridge.lnk'
$scriptPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.ps1'

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = 'powershell.exe'
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $scriptPath + '"'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.WindowStyle = 7
$shortcut.Description = 'Mouse X2 side-button bridge for WeChat Input voice typing'
$shortcut.Save()

Write-Host "Installed startup shortcut:"
Write-Host $shortcutPath

