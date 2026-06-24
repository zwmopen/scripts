param(
    [string]$TargetFolder,
    [string]$LibraryName,
    [switch]$NoBackup
)

$ErrorActionPreference = "Stop"

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

$coreSource = Join-Path $PSScriptRoot "make_work_package.ps1"
$usageSource = Join-Path $PSScriptRoot "usage_zh.md"
$coreDest = Join-Path $TargetFolder "make_work_package.ps1"
$entryDest = Join-Path $TargetFolder "$toolName.vbs"
$configDest = Join-Path $TargetFolder "workpkg_config.json"
$usageDest = Join-Path $TargetFolder "$usageName.md"

Backup-IfExists -Path $coreDest
Backup-IfExists -Path $entryDest
Backup-IfExists -Path $configDest
Backup-IfExists -Path $usageDest

Copy-Item -LiteralPath $coreSource -Destination $coreDest -Force

$config = [ordered]@{
    library_name = $LibraryName
    success_message = New-TextFromCodePoints @(0x5DF2, 0x521B, 0x5EFA, 0x4F5C, 0x54C1, 0x5305)
    no_text_message = New-TextFromCodePoints @(0x8BF7, 0x5148, 0x590D, 0x5236, 0x6587, 0x6848)
    no_image_message = New-TextFromCodePoints @(0x8BF7, 0x5148, 0x4E0B, 0x8F7D, 0x4F5C, 0x54C1, 0x56FE)
    duplicate_text_message = New-TextFromCodePoints @(0x8FD8, 0x662F, 0x4E0A, 0x4E00, 0x6761, 0x6587, 0x6848, 0xFF0C, 0x5148, 0x590D, 0x5236, 0x65B0, 0x6587, 0x6848)
    duplicate_existing_message = New-TextFromCodePoints @(0x8BE5, 0x4F5C, 0x54C1, 0x5DF2, 0x521B, 0x5EFA, 0x8FC7, 0xFF0C, 0x5DF2, 0x6E05, 0x7406, 0x672C, 0x6B21, 0x91CD, 0x590D, 0x4E0B, 0x8F7D)
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
}

$json = $config | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($configDest, $json, (New-Object System.Text.UTF8Encoding($true)))

$vbs = @'
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptPath = fso.GetParentFolderName(WScript.ScriptFullName) & "\make_work_package.ps1"
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34)

shell.Run command, 0, False
'@

[System.IO.File]::WriteAllText($entryDest, $vbs, (New-Object System.Text.UTF8Encoding($true)))

if (Test-Path -LiteralPath $usageSource) {
    Copy-Item -LiteralPath $usageSource -Destination $usageDest -Force
}

try {
    $coreItem = Get-Item -LiteralPath $coreDest -Force
    $coreItem.Attributes = $coreItem.Attributes -bor [System.IO.FileAttributes]::Hidden
} catch {
}

Write-Output "Installed=$TargetFolder"
Write-Output "Entry=$entryDest"
Write-Output "LibraryName=$LibraryName"
