param(
    [string]$SourcePath = "",
    [string]$TargetPath = "",

    [ValidateSet("Preview", "Apply")]
    [string]$Mode = "Preview",

    [ValidateSet("Hardlink", "Copy")]
    [string]$SyncType = "Hardlink",

    [switch]$Replace,
    [switch]$IncludePreviewFolders
)

$ErrorActionPreference = "Stop"

function U {
    param([int]$CodePoint)
    return [string][char]$CodePoint
}

function Test-IsWindows {
    return [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT
}

function Normalize-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd("\")
}

function Read-RequiredPath {
    param(
        [string]$Value,
        [string]$Prompt,
        [switch]$MustExist
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        $Value = Read-Host $Prompt
    }

    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Path is empty."
    }

    $fullPath = Normalize-FullPath $Value
    if ($MustExist -and -not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "Directory does not exist: $fullPath"
    }

    return $fullPath
}

function Test-PathInside {
    param(
        [string]$Parent,
        [string]$Child
    )

    $parentFull = (Normalize-FullPath $Parent) + "\"
    $childFull = Normalize-FullPath $Child
    return $childFull.StartsWith($parentFull, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-RelativePathCompat {
    param(
        [string]$BasePath,
        [string]$FullPath
    )

    $baseUri = New-Object System.Uri ((Normalize-FullPath $BasePath) + "\")
    $pathUri = New-Object System.Uri (Normalize-FullPath $FullPath)
    $relative = $baseUri.MakeRelativeUri($pathUri).ToString()
    return [System.Uri]::UnescapeDataString($relative).Replace("/", "\")
}

function Should-SkipDirectory {
    param([System.IO.DirectoryInfo]$Directory)

    $name = $Directory.Name
    if ($name -in @(".git", ".hg", ".svn", "node_modules", ".sync-history")) {
        return $true
    }

    if (-not $IncludePreviewFolders) {
        $previewWord = (U 0x9884) + (U 0x89C8)
        $hardlinkWord = (U 0x786C) + (U 0x94FE) + (U 0x63A5)
        if (($name.Contains($previewWord) -and $name.Contains($hardlinkWord)) -or
            ($name.ToLowerInvariant().Contains("preview") -and $name.ToLowerInvariant().Contains("hardlink"))) {
            return $true
        }
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
            if (-not (Should-SkipDirectory $dir)) {
                $stack.Push($dir.FullName)
            }
        }

        foreach ($file in Get-ChildItem -LiteralPath $current -File -Force -ErrorAction Stop) {
            Write-Output $file
        }
    }
}

function Add-HardlinkType {
    if ("HardLinkNative" -as [type]) {
        return
    }

    Add-Type @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class HardLinkNative
{
    [DllImport("Kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateHardLink(string lpFileName, string lpExistingFileName, IntPtr lpSecurityAttributes);

    public static void Create(string linkPath, string existingPath)
    {
        if (!CreateHardLink(linkPath, existingPath, IntPtr.Zero))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
"@
}

function New-LinkedOrCopiedFile {
    param(
        [string]$Source,
        [string]$Target,
        [string]$Kind
    )

    if ($Kind -eq "Copy") {
        Copy-Item -LiteralPath $Source -Destination $Target -Force
        return
    }

    [HardLinkNative]::Create($Target, $Source)
}

if (-not (Test-IsWindows)) {
    throw "This script is designed for Windows paths and NTFS hardlinks."
}

$sourceRoot = Read-RequiredPath -Value $SourcePath -Prompt "Source folder" -MustExist
$targetRoot = Read-RequiredPath -Value $TargetPath -Prompt "Target folder"

if ($sourceRoot -eq $targetRoot) {
    throw "Source and target cannot be the same folder."
}

if (Test-PathInside -Parent $sourceRoot -Child $targetRoot) {
    throw "Target folder cannot be inside source folder. Choose a separate working folder."
}

if ($SyncType -eq "Hardlink") {
    $sourceDrive = [System.IO.Path]::GetPathRoot($sourceRoot)
    $targetDrive = [System.IO.Path]::GetPathRoot($targetRoot)
    if (-not $sourceDrive.Equals($targetDrive, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Hardlinks require source and target to be on the same drive. Use -SyncType Copy for cross-drive sync."
    }
    Add-HardlinkType
}

if ($Mode -eq "Apply" -and -not (Test-Path -LiteralPath $targetRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$records = New-Object "System.Collections.Generic.List[object]"
$counts = @{
    Scanned = 0
    Create = 0
    Replace = 0
    Exists = 0
    Failed = 0
}

foreach ($sourceFile in Get-SourceFiles -Root $sourceRoot) {
    $counts.Scanned++
    $relative = Get-RelativePathCompat -BasePath $sourceRoot -FullPath $sourceFile.FullName
    $targetFile = Normalize-FullPath (Join-Path $targetRoot $relative)

    if (-not (Test-PathInside -Parent $targetRoot -Child $targetFile) -and $targetRoot -ne (Split-Path -Parent $targetFile)) {
        throw "Unsafe target path generated: $targetFile"
    }

    $action = "Create"
    $status = "Planned"
    $message = ""

    try {
        $targetExists = Test-Path -LiteralPath $targetFile -PathType Leaf
        $targetDirectoryExists = Test-Path -LiteralPath $targetFile -PathType Container

        if ($targetDirectoryExists) {
            $action = "Fail"
            $status = "Failed"
            $message = "A directory already exists at target file path."
            $counts.Failed++
        }
        elseif ($targetExists -and -not $Replace) {
            $action = "SkipExisting"
            $status = "Skipped"
            $message = "Target file exists. Use -Replace to overwrite it."
            $counts.Exists++
        }
        else {
            if ($targetExists -and $Replace) {
                $action = "Replace"
            }

            if ($Mode -eq "Apply") {
                $targetDir = Split-Path -Parent $targetFile
                if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
                    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
                }

                if ($targetExists -and $Replace) {
                    Remove-Item -LiteralPath $targetFile -Force
                }

                New-LinkedOrCopiedFile -Source $sourceFile.FullName -Target $targetFile -Kind $SyncType
                $status = "Done"
            }

            if ($action -eq "Replace") {
                $counts.Replace++
            }
            else {
                $counts.Create++
            }
        }
    }
    catch {
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
        Message = $message
    }) | Out-Null
}

if ($Mode -eq "Apply") {
    $historyDir = Join-Path $targetRoot ".sync-history"
    if (-not (Test-Path -LiteralPath $historyDir -PathType Container)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }
    $historyFile = Join-Path $historyDir ("sync-history-" + $timestamp + ".csv")
    $records | Export-Csv -LiteralPath $historyFile -NoTypeInformation -Encoding UTF8
}

Write-Host "Material sync finished"
Write-Host "Mode: $Mode"
Write-Host "Type: $SyncType"
Write-Host "Source: $sourceRoot"
Write-Host "Target: $targetRoot"
Write-Host "Scanned files: $($counts.Scanned)"
Write-Host "Will create / created: $($counts.Create)"
Write-Host "Will replace / replaced: $($counts.Replace)"
Write-Host "Skipped existing: $($counts.Exists)"
Write-Host "Failed: $($counts.Failed)"

if ($Mode -eq "Preview") {
    Write-Host "Preview only. Re-run with -Mode Apply to make changes."
}
else {
    Write-Host "History: $historyFile"
}
