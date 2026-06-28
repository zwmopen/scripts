$ErrorActionPreference = 'Stop'

$taskName = 'WeChat Voice X2 Bridge Watchdog'
$watchdogPath = Join-Path $PSScriptRoot 'watchdog.ps1'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $watchdogPath + '"')
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'Keeps the mouse X2 WeChat voice typing bridge running.' -Force | Out-Null
Write-Host "Installed scheduled watchdog task:"
Write-Host $taskName
