$ErrorActionPreference = 'Stop'

$taskNames = @('WeChat Voice X2 Bridge Watchdog', 'WeChat Voice X2 Bridge Refresh')
foreach ($taskName in $taskNames) {
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Removed scheduled task:"
        Write-Host $taskName
    } else {
        Write-Host "Scheduled task was not installed:"
        Write-Host $taskName
    }
}
