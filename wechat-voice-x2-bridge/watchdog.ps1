param([switch]$Restart)

$ErrorActionPreference = 'SilentlyContinue'

$watchdogLockTaken = $false
$watchdogMutex = [System.Threading.Mutex]::new($false, 'Local\WeChatVoiceX2BridgeWatchdog')
try {
    $watchdogLockTaken = $watchdogMutex.WaitOne(0)
} catch [System.Threading.AbandonedMutexException] {
    $watchdogLockTaken = $true
}
if (-not $watchdogLockTaken) { exit 0 }

$scriptPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.ps1'
$pidPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.pid'
$logPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.log'
$heartbeatPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.heartbeat'

function Write-WatchdogLog {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value ("{0} watchdog: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message) -Encoding UTF8
}

$running = $false
$pidText = ''
$proc = $null
if (Test-Path -LiteralPath $pidPath) {
    $pidText = (Get-Content -LiteralPath $pidPath -Raw).Trim()
    if ($pidText) {
        $proc = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
        $pidStamp = (Get-Item -LiteralPath $pidPath).LastWriteTime
        $heartbeatFresh = (Test-Path -LiteralPath $heartbeatPath) -and (((Get-Date) - (Get-Item -LiteralPath $heartbeatPath).LastWriteTime).TotalSeconds -lt 45)
        $running = [bool]$proc -and ([Math]::Abs(($proc.StartTime - $pidStamp).TotalSeconds) -lt 10) -and $heartbeatFresh
    }
}

if (($Restart -or -not $running) -and $proc) {
    Stop-Process -Id ([int]$pidText) -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
    $running = $false
    Write-WatchdogLog 'stopped stale or restart-requested bridge'
}

if (-not $running) {
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $heartbeatPath -Force -ErrorAction SilentlyContinue
    Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$scriptPath`"" -WindowStyle Hidden | Out-Null
    Write-WatchdogLog 'bridge was not running; started it'
}

if ($watchdogLockTaken) {
    try { $watchdogMutex.ReleaseMutex() } catch { }
}
$watchdogMutex.Dispose()
