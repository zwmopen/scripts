param(
    [string]$LibraryPath,
    [switch]$NoMessage
)

$ErrorActionPreference = "Stop"
$configPath = Join-Path $PSScriptRoot "workpkg_config.json"

function New-TextFromCodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Configuration file is missing: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($LibraryPath)) {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = New-TextFromCodePoints @(0x9009, 0x62E9, 0x4F5C, 0x54C1, 0x5305, 0x4FDD, 0x5B58, 0x76EE, 0x5F55)
    $dialog.ShowNewFolderButton = $true
    $currentPath = [Environment]::ExpandEnvironmentVariables(([string]$config.library_path).Trim())
    if (-not [string]::IsNullOrWhiteSpace($currentPath) -and (Test-Path -LiteralPath $currentPath -PathType Container)) {
        $dialog.SelectedPath = $currentPath
    }
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Output "CANCELLED"
        exit 0
    }
    $LibraryPath = $dialog.SelectedPath
}

$expandedPath = [Environment]::ExpandEnvironmentVariables($LibraryPath.Trim())
if (-not [System.IO.Path]::IsPathRooted($expandedPath)) {
    throw "LibraryPath must be an absolute path: $expandedPath"
}
$resolvedPath = [System.IO.Path]::GetFullPath($expandedPath)
if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedPath -Force | Out-Null
}

if ($null -eq $config.PSObject.Properties['library_path']) {
    $config | Add-Member -NotePropertyName library_path -NotePropertyValue $resolvedPath
} else {
    $config.library_path = $resolvedPath
}

$json = $config | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($true)))

Write-Output "LibraryPath=$resolvedPath"
if (-not $NoMessage) {
    Add-Type -AssemblyName PresentationFramework
    $message = (New-TextFromCodePoints @(0x4F5C, 0x54C1, 0x5305, 0x5C06, 0x4FDD, 0x5B58, 0x5230, 0xFF1A)) + "`n$resolvedPath"
    $title = New-TextFromCodePoints @(0x8BBE, 0x7F6E, 0x5DF2, 0x4FDD, 0x5B58)
    [System.Windows.MessageBox]::Show($message, $title, "OK", "Information") | Out-Null
}
