param(
    [string]$Root = $PSScriptRoot,
    [ValidateSet("Preview", "Apply", "Undo")]
    [string]$Mode = "Preview",
    [string]$HistoryFile = "",
    [string]$ConfirmApplyToken = "",
    [string]$ConfirmUndoToken = "",
    [int]$TestFailAfterRename = 0
)

$ErrorActionPreference = "Stop"

function Convert-Name {
    param([string]$Name)
    $zan = [string][char]0x8D5E
    $ping = [string][char]0x8BC4
    $match = [regex]::Match($Name, "$zan(\d+)$ping(\d+)")
    if (-not $match.Success) { return $Name }

    $likes = $match.Groups[1].Value
    $commentDigits = $match.Groups[2].Value
    $prefix = $Name.Substring(0, $match.Index)
    $suffix = $Name.Substring($match.Index + $match.Length)

    if ($commentDigits.Length -gt 1 -and $commentDigits.StartsWith("0")) {
        return "$prefix$ping" + "0" + "$zan$likes " + $commentDigits.Substring(1) + $suffix
    }

    return "$prefix$ping$commentDigits$zan$likes$suffix"
}

function Invoke-RenameTransaction {
    param([object[]]$Operations)

    $completed = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($op in $Operations) {
            if (-not (Test-Path -LiteralPath $op.OldPath)) {
                throw "Rename source is missing: $($op.OldPath)"
            }
            if (Test-Path -LiteralPath $op.NewPath) {
                throw "Rename target already exists: $($op.NewPath)"
            }

            Rename-Item -LiteralPath $op.OldPath -NewName ([System.IO.Path]::GetFileName($op.NewPath)) -ErrorAction Stop
            $completed.Add($op) | Out-Null
            if ($TestFailAfterRename -gt 0 -and $completed.Count -ge $TestFailAfterRename) {
                throw "Simulated failure after $($completed.Count) rename(s)."
            }
        }
    }
    catch {
        $rollback = $completed.ToArray()
        [array]::Reverse($rollback)
        foreach ($op in $rollback) {
            if (Test-Path -LiteralPath $op.NewPath) {
                Rename-Item -LiteralPath $op.NewPath -NewName ([System.IO.Path]::GetFileName($op.OldPath)) -ErrorAction SilentlyContinue
            }
        }
        throw
    }
}

function Get-FinalPath {
    param([object]$Operation, [object[]]$AllOperations)

    $path = $Operation.NewPath
    $directoryOperations = @($AllOperations | Where-Object {
        $_.Type -eq "Directory" -and $_.OldPath -ne $Operation.OldPath -and
        $Operation.OldPath.StartsWith($_.OldPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
    } | Sort-Object { $_.OldPath.Length } -Descending)

    foreach ($directoryOp in $directoryOperations) {
        if ($path.StartsWith($directoryOp.OldPath + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
            $path = $directoryOp.NewPath + $path.Substring($directoryOp.OldPath.Length)
        }
    }
    return $path
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$logDir = Join-Path $resolvedRoot "rename-logs"

if ($Mode -eq "Undo") {
    if ($ConfirmUndoToken -ne "UNDO") { throw "Undo requires -ConfirmUndoToken UNDO." }
    if ([string]::IsNullOrWhiteSpace($HistoryFile) -or -not (Test-Path -LiteralPath $HistoryFile -PathType Leaf)) {
        throw "Undo requires a valid -HistoryFile."
    }

    $rows = @(Import-Csv -LiteralPath $HistoryFile | Where-Object { $_.Status -eq "Renamed" })
    [array]::Reverse($rows)
    $ops = New-Object System.Collections.Generic.List[object]
    foreach ($row in $rows) {
        $ops.Add([pscustomobject]@{
            OldPath = $row.NewPath
            NewPath = $row.OldPath
            Type = $row.Type
        }) | Out-Null
    }

    $originalTestValue = $TestFailAfterRename
    $TestFailAfterRename = 0
    Invoke-RenameTransaction -Operations $ops.ToArray()
    $TestFailAfterRename = $originalTestValue
    Write-Host "Undo completed: $HistoryFile"
    return
}

$zan = [string][char]0x8D5E
$ping = [string][char]0x8BC4
$pattern = "$zan\d+$ping\d+"
$items = @(Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction Stop |
    Where-Object { $_.FullName -notlike "$logDir*" -and $_.Name -match $pattern } |
    Sort-Object { $_.FullName.Length } -Descending)

$ops = New-Object System.Collections.Generic.List[object]
$plannedTargets = @{}
foreach ($item in $items) {
    $newName = Convert-Name -Name $item.Name
    if ($newName -eq $item.Name) { continue }

    $newPath = Join-Path ([System.IO.Path]::GetDirectoryName($item.FullName)) $newName
    $targetKey = $newPath.ToLowerInvariant()
    if ($plannedTargets.ContainsKey($targetKey)) { throw "Multiple items would map to: $newPath" }
    $plannedTargets[$targetKey] = $true
    if (Test-Path -LiteralPath $newPath) { throw "Target exists: $newPath" }

    $ops.Add([pscustomobject]@{
        OldPath = $item.FullName
        NewPath = $newPath
        Type = if ($item.PSIsContainer) { "Directory" } else { "File" }
    }) | Out-Null
}

if ($Mode -eq "Preview") {
    foreach ($op in $ops) { Write-Host "PREVIEW: $($op.OldPath) -> $(Get-FinalPath -Operation $op -AllOperations $ops.ToArray())" }
    Write-Host "Matched: $($items.Count)"
    Write-Host "Would rename: $($ops.Count)"
    return
}

if ($ConfirmApplyToken -ne "RENAME") { throw "Apply requires -ConfirmApplyToken RENAME." }
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $logDir "rename_like_comment_$timestamp.csv"
Invoke-RenameTransaction -Operations $ops.ToArray()

$results = foreach ($op in $ops) {
    [pscustomobject]@{
        Status = "Renamed"
        Reason = ""
        Type = $op.Type
        OldPath = $op.OldPath
        NewPath = $op.NewPath
        FinalPath = Get-FinalPath -Operation $op -AllOperations $ops.ToArray()
    }
}
$results | Export-Csv -LiteralPath $logPath -NoTypeInformation -Encoding UTF8
Write-Host "Renamed: $($ops.Count)"
Write-Host "History: $logPath"
