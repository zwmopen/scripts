param(
    [string]$SourcePath = "",
    [string]$TargetPath = "",

    [ValidateSet("Preview", "Apply", "Undo")]
    [string]$Mode = "Preview",

    [ValidateSet("Hardlink", "Copy")]
    [string]$SyncType = "Hardlink",

    [switch]$Replace,
    [switch]$IncludePreviewFolders,
    [string]$HistoryFile = "",
    [string]$ConfirmReplaceToken = "",
    [string]$ConfirmUndoToken = "",
    [switch]$TestFailAfterBackup
)

$ErrorActionPreference = "Stop"

function U { param([int]$CodePoint) return [string][char]$CodePoint }
function Test-IsWindows { return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT }
function Normalize-FullPath { param([string]$Path) return [System.IO.Path]::GetFullPath($Path).TrimEnd("\", "/") }

function Read-RequiredPath {
    param([string]$Value, [string]$Prompt, [switch]$MustExist)
    if ([string]::IsNullOrWhiteSpace($Value)) { $Value = Read-Host $Prompt }
    if ([string]::IsNullOrWhiteSpace($Value)) { throw "Path is empty." }
    $fullPath = Normalize-FullPath $Value
    if ($MustExist -and -not (Test-Path -LiteralPath $fullPath -PathType Container)) { throw "Directory does not exist: $fullPath" }
    return $fullPath
}

function Test-PathInside {
    param([string]$Parent, [string]$Child)
    $parentFull = Normalize-FullPath $Parent
    $childFull = Normalize-FullPath $Child
    if ($parentFull.Equals($childFull, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    $relative = [System.IO.Path]::GetRelativePath($parentFull, $childFull)
    return (-not [System.IO.Path]::IsPathRooted($relative)) -and $relative -ne ".." -and -not $relative.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)")
}

function Get-RelativePathCompat {
    param([string]$BasePath, [string]$FullPath)
    return [System.IO.Path]::GetRelativePath((Normalize-FullPath $BasePath), (Normalize-FullPath $FullPath))
}

function Should-SkipDirectory {
    param([System.IO.DirectoryInfo]$Directory)
    $name = $Directory.Name
    if ($name -in @(".git", ".hg", ".svn", "node_modules", ".sync-history")) { return $true }
    if (-not $IncludePreviewFolders) {
        $previewWord = (U 0x9884) + (U 0x89C8)
        $hardlinkWord = (U 0x786C) + (U 0x94FE) + (U 0x63A5)
        if (($name.Contains($previewWord) -and $name.Contains($hardlinkWord)) -or
            ($name.ToLowerInvariant().Contains("preview") -and $name.ToLowerInvariant().Contains("hardlink"))) { return $true }
    }
    return $false
}

function Get-SourceFiles {
    param([string]$Root)
    $stack = New-Object "System.Collections.Generic.Stack[string]"
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        foreach ($dir in Get-ChildItem -LiteralPath $current -Directory -Force -ErrorAction Stop) {
            if (-not (Should-SkipDirectory $dir)) { $stack.Push($dir.FullName) }
        }
        foreach ($file in Get-ChildItem -LiteralPath $current -File -Force -ErrorAction Stop) { Write-Output $file }
    }
}

function Add-HardlinkType {
    if ("HardLinkNative" -as [type]) { return }
    Add-Type @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class HardLinkNative {
    [DllImport("Kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateHardLink(string linkPath, string existingPath, IntPtr attrs);
    public static void Create(string linkPath, string existingPath) {
        if (!CreateHardLink(linkPath, existingPath, IntPtr.Zero)) throw new Win32Exception(Marshal.GetLastWin32Error());
    }
}
"@
}

function New-LinkedOrCopiedFile {
    param([string]$Source, [string]$Target, [string]$Kind)
    if ($Kind -eq "Copy") {
        Copy-Item -LiteralPath $Source -Destination $Target -ErrorAction Stop
        return
    }
    [HardLinkNative]::Create($Target, $Source)
}

function Get-HistoryRoot { param([string]$TargetRoot) return Join-Path $TargetRoot ".sync-history" }
function Get-UniqueTempPath { param([string]$Target) return "$Target.sync-new-$([guid]::NewGuid().ToString('N'))" }

function Invoke-Undo {
    param([string]$CsvPath)
    if ($ConfirmUndoToken -ne "UNDO") { throw "Undo requires -ConfirmUndoToken UNDO." }
    if (-not (Test-Path -LiteralPath $CsvPath -PathType Leaf)) { throw "History file does not exist: $CsvPath" }
    $records = @(Import-Csv -LiteralPath $CsvPath)
    $errors = New-Object System.Collections.Generic.List[string]

    $undoRecords = @($records | Where-Object { $_.Status -eq "Done" })
    [array]::Reverse($undoRecords)
    foreach ($record in $undoRecords) {
        try {
            if ($record.Action -eq "Create") {
                if (Test-Path -LiteralPath $record.Target -PathType Leaf) {
                    Remove-Item -LiteralPath $record.Target -Force -ErrorAction Stop
                }
            }
            elseif ($record.Action -eq "Replace") {
                if ([string]::IsNullOrWhiteSpace($record.Backup) -or -not (Test-Path -LiteralPath $record.Backup -PathType Leaf)) {
                    throw "Replacement backup is missing."
                }
                if (Test-Path -LiteralPath $record.Target -PathType Leaf) {
                    Remove-Item -LiteralPath $record.Target -Force -ErrorAction Stop
                }
                $parent = Split-Path -Parent $record.Target
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }
                Move-Item -LiteralPath $record.Backup -Destination $record.Target -ErrorAction Stop
            }
        }
        catch {
            $errors.Add("$($record.Target): $($_.Exception.Message)") | Out-Null
        }
    }

    if ($errors.Count -gt 0) { throw "Undo incomplete:`n$($errors -join "`n")" }
    Write-Host "Undo completed: $CsvPath"
}

if (-not (Test-IsWindows)) { throw "This script is designed for Windows paths and NTFS hardlinks." }

if ($Mode -eq "Undo") {
    if ([string]::IsNullOrWhiteSpace($HistoryFile)) { throw "Undo requires -HistoryFile." }
    Invoke-Undo -CsvPath (Normalize-FullPath $HistoryFile)
    return
}

$sourceRoot = Read-RequiredPath -Value $SourcePath -Prompt "Source folder" -MustExist
$targetRoot = Read-RequiredPath -Value $TargetPath -Prompt "Target folder"
if ($sourceRoot -eq $targetRoot) { throw "Source and target cannot be the same folder." }
if ((Test-PathInside -Parent $sourceRoot -Child $targetRoot) -or (Test-PathInside -Parent $targetRoot -Child $sourceRoot)) {
    throw "Source and target must be separate, non-nested folders."
}
if ($Mode -eq "Apply" -and $Replace -and $ConfirmReplaceToken -ne "REPLACE") {
    throw "Replacing files requires -ConfirmReplaceToken REPLACE."
}

if ($SyncType -eq "Hardlink") {
    $sourceDrive = [System.IO.Path]::GetPathRoot($sourceRoot)
    $targetDrive = [System.IO.Path]::GetPathRoot($targetRoot)
    if (-not $sourceDrive.Equals($targetDrive, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Hardlinks require source and target on the same drive. Use Copy for cross-drive sync."
    }
    Add-HardlinkType
}

if ($Mode -eq "Apply" -and -not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$historyRoot = Get-HistoryRoot -TargetRoot $targetRoot
$backupRoot = Join-Path $historyRoot "replaced-$timestamp"
$records = New-Object "System.Collections.Generic.List[object]"
$counts = @{ Scanned = 0; Create = 0; Replace = 0; Exists = 0; Failed = 0 }

foreach ($sourceFile in Get-SourceFiles -Root $sourceRoot) {
    $counts.Scanned++
    $relative = Get-RelativePathCompat -BasePath $sourceRoot -FullPath $sourceFile.FullName
    $targetFile = Normalize-FullPath (Join-Path $targetRoot $relative)
    if (-not (Test-PathInside -Parent $targetRoot -Child $targetFile)) { throw "Unsafe target path generated: $targetFile" }

    $action = "Create"
    $status = "Planned"
    $message = ""
    $backupPath = ""
    $tempPath = ""

    try {
        $targetExists = Test-Path -LiteralPath $targetFile -PathType Leaf
        if (Test-Path -LiteralPath $targetFile -PathType Container) { throw "A directory already exists at target file path." }

        if ($targetExists -and -not $Replace) {
            $action = "SkipExisting"
            $status = "Skipped"
            $message = "Target exists. Use -Replace."
            $counts.Exists++
        }
        else {
            if ($targetExists) { $action = "Replace" }

            if ($Mode -eq "Apply") {
                $targetDir = Split-Path -Parent $targetFile
                if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }

                $tempPath = Get-UniqueTempPath -Target $targetFile
                New-LinkedOrCopiedFile -Source $sourceFile.FullName -Target $tempPath -Kind $SyncType

                if ($targetExists) {
                    $backupPath = Join-Path $backupRoot $relative
                    $backupDir = Split-Path -Parent $backupPath
                    if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) {
                        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
                    }
                    Move-Item -LiteralPath $targetFile -Destination $backupPath -ErrorAction Stop
                    if ($TestFailAfterBackup) {
                        throw "Simulated failure after backing up the existing target."
                    }
                }

                try {
                    Move-Item -LiteralPath $tempPath -Destination $targetFile -ErrorAction Stop
                    $tempPath = ""
                    $status = "Done"
                }
                catch {
                    if ($backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf) -and -not (Test-Path -LiteralPath $targetFile)) {
                        Move-Item -LiteralPath $backupPath -Destination $targetFile -ErrorAction SilentlyContinue
                    }
                    throw
                }
            }

            if ($action -eq "Replace") { $counts.Replace++ } else { $counts.Create++ }
        }
    }
    catch {
        if ($tempPath -and (Test-Path -LiteralPath $tempPath -PathType Leaf)) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
        if ($backupPath -and (Test-Path -LiteralPath $backupPath -PathType Leaf) -and -not (Test-Path -LiteralPath $targetFile)) {
            Move-Item -LiteralPath $backupPath -Destination $targetFile -ErrorAction SilentlyContinue
        }
        $action = "Fail"
        $status = "Failed"
        $message = $_.Exception.Message
        $counts.Failed++
    }

    $records.Add([pscustomobject]@{
        Action = $action
        Status = $status
        Type = $SyncType
        Source = $sourceFile.FullName
        Target = $targetFile
        Backup = $backupPath
        Message = $message
    }) | Out-Null
}

$historyFile = ""
if ($Mode -eq "Apply") {
    if (-not (Test-Path -LiteralPath $historyRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $historyRoot -Force | Out-Null
    }
    $historyFile = Join-Path $historyRoot "sync-history-$timestamp.csv"
    $records | Export-Csv -LiteralPath $historyFile -NoTypeInformation -Encoding UTF8
}

Write-Host "Material sync finished"
Write-Host "Mode: $Mode"
Write-Host "Type: $SyncType"
Write-Host "Scanned: $($counts.Scanned)"
Write-Host "Create: $($counts.Create)"
Write-Host "Replace: $($counts.Replace)"
Write-Host "Skipped: $($counts.Exists)"
Write-Host "Failed: $($counts.Failed)"
if ($Mode -eq "Preview") { Write-Host "Preview only. Use -Mode Apply to make changes." } else { Write-Host "History: $historyFile" }
if ($counts.Failed -gt 0) { throw "Material sync completed with $($counts.Failed) failed file(s). History: $historyFile" }
