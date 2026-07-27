param(
    [string]$TargetFolder,
    [string]$LibraryName,
    [string]$LibraryPath,
    [string]$ImageInboxPath,
    [switch]$RegisterProtocol,
    [switch]$NoBackup
)

$ErrorActionPreference = "Stop"
$libraryNameSpecified = $PSBoundParameters.ContainsKey("LibraryName") -and -not [string]::IsNullOrWhiteSpace($LibraryName)
$libraryPathSpecified = $PSBoundParameters.ContainsKey("LibraryPath")
$imageInboxPathSpecified = $PSBoundParameters.ContainsKey("ImageInboxPath")

function New-TextFromCodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Backup-IfExists {
    param([string]$Path)

    if ($NoBackup -or -not (Test-Path -LiteralPath $Path)) {
        return
    }

    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Copy-Item -LiteralPath $Path -Destination "$Path.bak_$stamp" -Force
}

if ([string]::IsNullOrWhiteSpace($TargetFolder)) {
    $TargetFolder = (Get-Location).Path
}

if ([string]::IsNullOrWhiteSpace($LibraryName)) {
    $LibraryName = New-TextFromCodePoints @(0x6210, 0x54C1, 0x5E93)
}

if (-not (Test-Path -LiteralPath $TargetFolder)) {
    New-Item -ItemType Directory -Path $TargetFolder | Out-Null
}

$toolName = New-TextFromCodePoints @(0x4E00, 0x952E, 0x751F, 0x6210, 0x4F5C, 0x54C1, 0x5305)
$usageName = New-TextFromCodePoints @(0x4F7F, 0x7528, 0x8BF4, 0x660E, 0x2D, 0x4E00, 0x952E, 0x4F5C, 0x54C1, 0x5305)
$settingsName = New-TextFromCodePoints @(0x8BBE, 0x7F6E, 0x4F5C, 0x54C1, 0x5305, 0x76EE, 0x5F55)

$coreSource = Join-Path $PSScriptRoot "make_work_package.ps1"
$entrySource = Join-Path $PSScriptRoot "${toolName}.vbs"
$usageSource = Join-Path $PSScriptRoot "usage_zh.md"
$configureSource = Join-Path $PSScriptRoot "configure_work_package.ps1"
$centerSource = Join-Path $PSScriptRoot "work_package_center.ps1"
$settingsSource = Join-Path $PSScriptRoot "${settingsName}.vbs"
$coreDest = Join-Path $TargetFolder "make_work_package.ps1"
$entryDest = Join-Path $TargetFolder "${toolName}.vbs"
$configDest = Join-Path $TargetFolder "workpkg_config.json"
$usageDest = Join-Path $TargetFolder "$usageName.md"
$configureDest = Join-Path $TargetFolder "configure_work_package.ps1"
$centerDest = Join-Path $TargetFolder "work_package_center.ps1"
$settingsDest = Join-Path $TargetFolder "${settingsName}.vbs"

Backup-IfExists -Path $coreDest
Backup-IfExists -Path $entryDest
Backup-IfExists -Path $configDest
Backup-IfExists -Path $usageDest
Backup-IfExists -Path $configureDest
Backup-IfExists -Path $centerDest
Backup-IfExists -Path $settingsDest

Copy-Item -LiteralPath $coreSource -Destination $coreDest -Force
Copy-Item -LiteralPath $configureSource -Destination $configureDest -Force
Copy-Item -LiteralPath $centerSource -Destination $centerDest -Force

$config = [ordered]@{
    library_name = $LibraryName
    library_path = ""
    image_inbox_path = ""
    success_message = New-TextFromCodePoints @(0x5DF2, 0x521B, 0x5EFA, 0x4F5C, 0x54C1, 0x5305)
    no_text_message = New-TextFromCodePoints @(0x8BF7, 0x5148, 0x590D, 0x5236, 0x6587, 0x6848)
    no_image_message = New-TextFromCodePoints @(0x8BF7, 0x5148, 0x4E0B, 0x8F7D, 0x4F5C, 0x54C1, 0x56FE)
    duplicate_text_message = New-TextFromCodePoints @(0x8FD8, 0x662F, 0x4E0A, 0x4E00, 0x6761, 0x6587, 0x6848, 0xFF0C, 0x5148, 0x590D, 0x5236, 0x65B0, 0x6587, 0x6848)
    duplicate_existing_message = New-TextFromCodePoints @(0x672C, 0x6B21, 0x4E3A, 0x91CD, 0x590D, 0x4E0B, 0x8F7D, 0xFF0C, 0x5DF2, 0x5220, 0x9664, 0x672C, 0x5730, 0x56FE, 0x7247, 0x548C, 0x6587, 0x6848, 0x3002)
    portfolio_grouped_message = New-TextFromCodePoints @(0x5DF2, 0x521B, 0x5EFA, 0x4F5C, 0x54C1, 0x5305, 0xFF0C, 0x5DF2, 0x6574, 0x7406, 0x4F5C, 0x54C1, 0x96C6)
    portfolio_zipped_message = New-TextFromCodePoints @(0x5DF2, 0x521B, 0x5EFA, 0x4F5C, 0x54C1, 0x5305, 0xFF0C, 0x5DF2, 0x6574, 0x7406, 0x5E76, 0x538B, 0x7F29, 0x4F5C, 0x54C1, 0x96C6)
    portfolio_group_done_message = New-TextFromCodePoints @(0x5DF2, 0x6574, 0x7406, 0x4F5C, 0x54C1, 0x96C6)
    portfolio_zip_done_message = New-TextFromCodePoints @(0x5DF2, 0x751F, 0x6210, 0x005A, 0x0049, 0x0050, 0x538B, 0x7F29, 0x5305)
    portfolio_zip_failed_message = New-TextFromCodePoints @(0x4F5C, 0x54C1, 0x96C6, 0x538B, 0x7F29, 0x5931, 0x8D25)
    portfolio_auto_group = $true
    portfolio_auto_zip = $true
    portfolio_batch_size = 14
    portfolio_prefix = New-TextFromCodePoints @(0x4F5C, 0x54C1, 0x96C6)
    portfolio_log_folder = "_portfolio_move_logs"
    package_naming_mode = "title_conversation"
    completion_open_folder = $false
    completion_copy_path = $false
    notification_duration_ms = 850
    visual_similarity_enabled = $true
    visual_similarity_max_distance = 6
    visual_similarity_max_average = 3
}

if (Test-Path -LiteralPath $configDest -PathType Leaf) {
    try {
        $existingConfig = Get-Content -LiteralPath $configDest -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($key in @($config.Keys)) {
            $property = $existingConfig.PSObject.Properties[$key]
            if ($null -ne $property -and $null -ne $property.Value) {
                $config[$key] = $property.Value
            }
        }
    } catch {
        # A damaged config is backed up and replaced with safe defaults.
    }
}

if ($libraryNameSpecified) {
    $config.library_name = $LibraryName
}
if ($libraryPathSpecified) {
    $expandedLibraryPath = [Environment]::ExpandEnvironmentVariables(([string]$LibraryPath).Trim())
    if (-not [string]::IsNullOrWhiteSpace($expandedLibraryPath) -and -not [System.IO.Path]::IsPathRooted($expandedLibraryPath)) {
        throw "LibraryPath must be an absolute path: $expandedLibraryPath"
    }
    $config.library_path = $expandedLibraryPath
}
if ($imageInboxPathSpecified) {
    $expandedInboxPath = [Environment]::ExpandEnvironmentVariables(([string]$ImageInboxPath).Trim())
    if (-not [string]::IsNullOrWhiteSpace($expandedInboxPath) -and -not [System.IO.Path]::IsPathRooted($expandedInboxPath)) {
        throw "ImageInboxPath must be an absolute path: $expandedInboxPath"
    }
    $config.image_inbox_path = $expandedInboxPath
}

$json = $config | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($configDest, $json, (New-Object System.Text.UTF8Encoding($true)))

if (-not (Test-Path -LiteralPath $entrySource -PathType Leaf)) {
    throw "VBS launcher template is missing: $entrySource"
}

# Copy the no-BOM VBS template without rewriting its encoding.
Copy-Item -LiteralPath $entrySource -Destination $entryDest -Force
Copy-Item -LiteralPath $settingsSource -Destination $settingsDest -Force

if (Test-Path -LiteralPath $usageSource) {
    Copy-Item -LiteralPath $usageSource -Destination $usageDest -Force
}

if ($RegisterProtocol) {
    $protocolRoot = "HKCU:\Software\Classes\cgpt-workpkg"
    $commandKey = Join-Path $protocolRoot "shell\open\command"
    New-Item -Path $commandKey -Force | Out-Null
    Set-Item -Path $protocolRoot -Value "URL:ChatGPT Work Package Launcher"
    New-ItemProperty -Path $protocolRoot -Name "URL Protocol" -Value "" -PropertyType String -Force | Out-Null
    Set-Item -Path $commandKey -Value ('wscript.exe "' + $entryDest + '" "%1"')
}

try {
    $coreItem = Get-Item -LiteralPath $coreDest -Force
    $coreItem.Attributes = $coreItem.Attributes -bor [System.IO.FileAttributes]::Hidden
    $configureItem = Get-Item -LiteralPath $configureDest -Force
    $configureItem.Attributes = $configureItem.Attributes -bor [System.IO.FileAttributes]::Hidden
    $centerItem = Get-Item -LiteralPath $centerDest -Force
    $centerItem.Attributes = $centerItem.Attributes -bor [System.IO.FileAttributes]::Hidden
} catch {
}

Write-Output "Installed=$TargetFolder"
Write-Output "Entry=$entryDest"
Write-Output "LibraryName=$($config.library_name)"
Write-Output "LibraryPath=$($config.library_path)"
Write-Output "ImageInboxPath=$($config.image_inbox_path)"
Write-Output "ProtocolRegistered=$([bool]$RegisterProtocol)"
