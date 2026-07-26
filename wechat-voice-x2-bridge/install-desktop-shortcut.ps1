$ErrorActionPreference = 'Stop'

$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop '鼠标语音输入-启动修复.lnk'
$repairPath = Join-Path $PSScriptRoot 'repair-and-status.ps1'
$powershellPath = Join-Path $PSHOME 'powershell.exe'

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershellPath
$shortcut.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $repairPath + '"'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.Description = '启动、修复并检查鼠标 X2 微信语音输入'
$shortcut.IconLocation = "$env:SystemRoot\System32\imageres.dll,68"
$shortcut.Save()

Write-Output $shortcutPath
