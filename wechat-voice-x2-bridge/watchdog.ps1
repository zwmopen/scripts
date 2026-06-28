$ErrorActionPreference = 'SilentlyContinue'

$scriptPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.ps1'
$pidPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.pid'
$logPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.log'

function Write-WatchdogLog {
    param([string]$Message)
    Add-Content -LiteralPath $logPath -Value ("{0} watchdog: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message) -Encoding UTF8
}

$running = $false
if (Test-Path -LiteralPath $pidPath) {
    $pidText = (Get-Content -LiteralPath $pidPath -Raw).Trim()
    if ($pidText) {
        $proc = Get-Process -Id ([int]$pidText) -ErrorAction SilentlyContinue
        $running = [bool]$proc
    }
}

if (-not $running) {
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    Start-Process powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',"`"$scriptPath`"" -WindowStyle Hidden | Out-Null
    Write-WatchdogLog 'bridge was not running; started it'
}
