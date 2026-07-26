$ErrorActionPreference = 'Stop'

$watchdogPath = Join-Path $PSScriptRoot 'watchdog.ps1'
$pidPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.pid'
$heartbeatPath = Join-Path $PSScriptRoot 'wechat-voice-x2-bridge.heartbeat'

try {
    & $watchdogPath -Restart
    Start-Sleep -Seconds 3

    $pidText = (Get-Content -LiteralPath $pidPath -Raw -ErrorAction Stop).Trim()
    $process = Get-Process -Id ([int]$pidText) -ErrorAction Stop
    $heartbeatAge = ((Get-Date) - (Get-Item -LiteralPath $heartbeatPath -ErrorAction Stop).LastWriteTime).TotalSeconds
    if ($heartbeatAge -ge 45) {
        throw '监听心跳没有更新。'
    }
    $message = "鼠标语音输入已启动并通过健康检查。`n`n进程：$($process.Id)`n现在可以按 X2 开始语音输入。"
    $title = '鼠标语音输入'
    $icon = 'Information'
    $exitCode = 0
}
catch {
    $message = "启动或修复失败：`n$($_.Exception.Message)`n`n请把这个提示交给 Codex 检查。"
    $title = '鼠标语音输入需要检查'
    $icon = 'Error'
    $exitCode = 1
}

Add-Type -AssemblyName PresentationFramework
[System.Windows.MessageBox]::Show($message, $title, 'OK', $icon) | Out-Null
exit $exitCode
