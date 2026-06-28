$ErrorActionPreference = 'Stop'

$taskName = 'WeChat Voice X2 Bridge Watchdog'
$runnerPath = Join-Path $PSScriptRoot 'run-hidden.vbs'
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + $runnerPath + '" watchdog.ps1')
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'Keeps the mouse X2 WeChat voice typing bridge running.' -Force | Out-Null
Write-Host "Installed scheduled watchdog task:"
Write-Host $taskName
