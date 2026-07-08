param(
    [string]$Root = $PSScriptRoot,
    [switch]$Preview
)

$ErrorActionPreference = "Stop"

function Convert-Name {
    param([string]$Name)

    $zan = [string][char]0x8D5E
    $ping = [string][char]0x8BC4
    $match = [regex]::Match($Name, "$zan(\d+)$ping(\d+)")
    if (-not $match.Success) {
        return $Name
    }

    $likes = $match.Groups[1].Value
    $commentDigits = $match.Groups[2].Value
    $prefix = $Name.Substring(0, $match.Index)
    $suffix = $Name.Substring($match.Index + $match.Length)

    # If the comment count is 0 and the title starts with a number,
    # keep a space before that title number.
    if ($commentDigits.Length -gt 1 -and $commentDigits.StartsWith("0")) {
        $comments = "0"
        $titleNumber = $commentDigits.Substring(1)
        return "$prefix$ping$comments$zan$likes $titleNumber$suffix"
    }

    return "$prefix$ping$commentDigits$zan$likes$suffix"
}

$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$logDir = Join-Path $resolvedRoot "rename-logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $logDir "rename_like_comment_$timestamp.csv"

$zan = [string][char]0x8D5E
$ping = [string][char]0x8BC4
$pattern = "$zan\d+$ping\d+"

$items = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match $pattern } |
    Sort-Object { $_.FullName.Length } -Descending

$results = New-Object System.Collections.Generic.List[object]
$renamed = 0
$skipped = 0
$errors = 0

foreach ($item in $items) {
    $newName = Convert-Name -Name $item.Name

    if ($newName -eq $item.Name) {
        $skipped++
        $results.Add([pscustomobject]@{
            Status = "Skipped"
            Reason = "No change"
            Type = if ($item.PSIsContainer) { "Directory" } else { "File" }
            OldPath = $item.FullName
            NewPath = $item.FullName
        })
        continue
    }

    $parentPath = [System.IO.Path]::GetDirectoryName($item.FullName)
    $newPath = Join-Path $parentPath $newName
    if (Test-Path -LiteralPath $newPath) {
        $skipped++
        $results.Add([pscustomobject]@{
            Status = "Skipped"
            Reason = "Target exists"
            Type = if ($item.PSIsContainer) { "Directory" } else { "File" }
            OldPath = $item.FullName
            NewPath = $newPath
        })
        continue
    }

    try {
        if (-not $Preview) {
            Rename-Item -LiteralPath $item.FullName -NewName $newName -ErrorAction Stop
        }
        $renamed++
        $results.Add([pscustomobject]@{
            Status = if ($Preview) { "Preview" } else { "Renamed" }
            Reason = ""
            Type = if ($item.PSIsContainer) { "Directory" } else { "File" }
            OldPath = $item.FullName
            NewPath = $newPath
        })
    }
    catch {
        $errors++
        $results.Add([pscustomobject]@{
            Status = "Error"
            Reason = $_.Exception.Message
            Type = if ($item.PSIsContainer) { "Directory" } else { "File" }
            OldPath = $item.FullName
            NewPath = $newPath
        })
    }
}

$results | Export-Csv -LiteralPath $logPath -NoTypeInformation -Encoding UTF8

$actionLabel = if ($Preview) { "Previewed" } else { "Renamed" }
Write-Host "Root: $resolvedRoot"
Write-Host "Matched: $($items.Count)"
Write-Host "${actionLabel}: $renamed"
Write-Host "Skipped: $skipped"
Write-Host "Errors: $errors"
Write-Host "Log: $logPath"

if ($errors -gt 0) {
    exit 1
}
