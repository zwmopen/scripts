param(
    [string]$PackageUrl = "https://raw.githubusercontent.com/zwmopen/scripts/master/GPT%E4%BD%9C%E5%93%81%E5%8A%A9%E6%89%8B-%E5%82%BB%E7%93%9C%E5%AE%89%E8%A3%85%E5%8C%85.zip",
    [string]$WorkingFolder,
    [string]$TargetFolder,
    [string]$DefaultLibraryPath,
    [string]$DefaultPortfolioOutputPath,
    [string]$DefaultInboxPath,
    [switch]$NoUi,
    [switch]$NoShortcut,
    [switch]$SkipProtocol
)

$ErrorActionPreference = "Stop"
$root = if ([string]::IsNullOrWhiteSpace($WorkingFolder)) {
    Join-Path $env:TEMP ("GPTWorkPackageSetup_" + [guid]::NewGuid().ToString("N"))
} else {
    [System.IO.Path]::GetFullPath($WorkingFolder)
}
$zipPath = Join-Path $root "package.zip"
$extractPath = Join-Path $root "package"

try {
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing -Uri $PackageUrl -OutFile $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
    $installer = Get-ChildItem -LiteralPath $extractPath -Filter "install_for_user.ps1" -File -Recurse |
        Select-Object -First 1
    if (-not $installer) {
        throw "The package is missing install_for_user.ps1. Please download it again."
    }

    $arguments = @{}
    if (-not [string]::IsNullOrWhiteSpace($TargetFolder)) { $arguments.TargetFolder = $TargetFolder }
    if (-not [string]::IsNullOrWhiteSpace($DefaultLibraryPath)) { $arguments.DefaultLibraryPath = $DefaultLibraryPath }
    if (-not [string]::IsNullOrWhiteSpace($DefaultPortfolioOutputPath)) { $arguments.DefaultPortfolioOutputPath = $DefaultPortfolioOutputPath }
    if (-not [string]::IsNullOrWhiteSpace($DefaultInboxPath)) { $arguments.DefaultInboxPath = $DefaultInboxPath }
    if ($NoUi) { $arguments.NoUi = $true }
    if ($NoShortcut) { $arguments.NoShortcut = $true }
    if ($SkipProtocol) { $arguments.SkipProtocol = $true }
    & $installer.FullName @arguments
} catch {
    if ($NoUi) { throw }
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        "Installation failed:`n$($_.Exception.Message)`n`nPlease check the network and try again.",
        "GPT Work Package Assistant",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
