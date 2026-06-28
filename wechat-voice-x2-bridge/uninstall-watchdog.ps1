$ErrorActionPreference = 'Stop'

$taskName = 'WeChat Voice X2 Bridge Watchdog'
if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Host "Removed scheduled watchdog task:"
    Write-Host $taskName
} else {
    Write-Host "Scheduled watchdog task was not installed."
}
