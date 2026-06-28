$ErrorActionPreference = 'Stop'

$shortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'WeChat Voice X2 Bridge.lnk'
if (Test-Path -LiteralPath $shortcutPath) {
    Remove-Item -LiteralPath $shortcutPath -Force
    Write-Host "Removed startup shortcut:"
    Write-Host $shortcutPath
} else {
    Write-Host "Startup shortcut was not installed."
}

