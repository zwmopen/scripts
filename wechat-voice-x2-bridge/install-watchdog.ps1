$ErrorActionPreference = 'Stop'

$runnerPath = Join-Path $PSScriptRoot 'run-hidden.vbs'
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable

$taskName = 'WeChat Voice X2 Bridge Watchdog'
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + $runnerPath + '" watchdog.ps1')
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'Keeps the mouse X2 WeChat voice typing bridge running.' -Force | Out-Null

$startupTaskName = 'WeChat Voice X2 Bridge Startup'
$startupAction = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + $runnerPath + '" watchdog.ps1 -Restart')
$startupTrigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
Register-ScheduledTask -TaskName $startupTaskName -Action $startupAction -Trigger $startupTrigger -Settings $settings -Description 'Starts the mouse X2 WeChat voice typing bridge when the user logs on.' -Force | Out-Null

$refreshTaskName = 'WeChat Voice X2 Bridge Refresh'
$runnerXml = [Security.SecurityElement]::Escape($runnerPath)
$userId = [Security.SecurityElement]::Escape("$env:USERDOMAIN\$env:USERNAME")
$refreshXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Restarts the mouse X2 WeChat voice typing bridge after unlock or resume.</Description>
  </RegistrationInfo>
  <Triggers>
    <SessionStateChangeTrigger>
      <Enabled>true</Enabled>
      <StateChange>SessionUnlock</StateChange>
      <UserId>$userId</UserId>
    </SessionStateChangeTrigger>
    <EventTrigger>
      <Enabled>true</Enabled>
      <Subscription>&lt;QueryList&gt;&lt;Query Id="0" Path="System"&gt;&lt;Select Path="System"&gt;*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]&lt;/Select&gt;&lt;/Query&gt;&lt;/QueryList&gt;</Subscription>
    </EventTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$userId</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>true</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT5M</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>wscript.exe</Command>
      <Arguments>"$runnerXml" watchdog.ps1 -Restart</Arguments>
    </Exec>
  </Actions>
</Task>
"@
$xmlPath = Join-Path $env:TEMP 'wechat-voice-x2-refresh-task.xml'
Set-Content -LiteralPath $xmlPath -Value $refreshXml -Encoding Unicode
schtasks.exe /Create /TN $refreshTaskName /XML $xmlPath /F | Out-Null
Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue

Write-Host "Installed scheduled watchdog task:"
Write-Host $taskName
Write-Host "Installed scheduled startup task:"
Write-Host $startupTaskName
Write-Host "Installed scheduled refresh task:"
Write-Host $refreshTaskName
