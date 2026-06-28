param(
    [ValidateSet("Preview", "Apply", "Undo")]
    [string]$Mode = "Preview",

    [int]$MaxTotalChars = 60,
    [int]$MaxTitleChars = 30,
    [int]$MaxFileBaseChars = 60,

    [string]$RootPath = "",

    [string]$HistoryFile = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $ScriptRoot = Split-Path -Parent $PSCommandPath
}
else {
    $ScriptRoot = (Get-Item -LiteralPath $RootPath).FullName
}
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

function S {
    param([string]$Base64)
    return [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Base64))
}

function U {
    param([int]$CodePoint)
    return [string][char]$CodePoint
}

$HistoryRoot = Join-Path $ScriptRoot (S "X2xWbseRxpYLTn2Ph2X2TjlZx49/lQRZBnSwi1Vf")

$TargetFolderNames = @(
    (S "iVsJVOJW+l4="),
    (S "VVNNT+JW+l4="),
    (S "JE4pWQBOHFniVvpeIABZbV9s"),
    (S "q4NyXnFc4lb6Xg=="),
    (S "gVvibOJW+l4ATuVlOG4="),
    (S "IH1QZxr/X2xWbpZi85eGU/JTJo33UyB9UGcI/4ZT8lMgfVBnB1kodQn/"),
    (S "IH1QZxr/xomRmAEwlmLzlw=="),
    (S "qXM0bOJW+l4="),
    (S "f4lxXJtc4lb6Xg==")
)

$MetricWords = @(
    (U 0x8D5E),
    ((U 0x70B9) + (U 0x8D5E)),
    (U 0x8BC4),
    ((U 0x8BC4) + (U 0x8BBA)),
    (U 0x85CF),
    ((U 0x6536) + (U 0x85CF)),
    (U 0x6536),
    (U 0x8F6C),
    ((U 0x8F6C) + (U 0x53D1)),
    ((U 0x5206) + (U 0x4EAB))
)

$AuthorWords = @(
    ((U 0x4F5C) + (U 0x8005)),
    ((U 0x535A) + (U 0x4E3B)),
    ((U 0x6635) + (U 0x79F0)),
    ((U 0x8D26) + (U 0x53F7)),
    ((U 0x7528) + (U 0x6237)),
    ((U 0x6765) + (U 0x6E90)),
    ((U 0x8FBE) + (U 0x4EBA)),
    ("UP" + (U 0x4E3B))
)

$FullStop = U 0x3002
$FullColon = U 0xFF1A

function Get-TextElementLength {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return 0
    }

    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    $count = 0
    while ($enumerator.MoveNext()) {
        $count++
    }
    return $count
}

function Limit-TextElements {
    param(
        [AllowNull()][string]$Text,
        [int]$Max
    )

    if ([string]::IsNullOrEmpty($Text) -or $Max -le 0) {
        return ""
    }

    $enumerator = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    $items = New-Object System.Collections.Generic.List[string]
    while ($enumerator.MoveNext() -and $items.Count -lt $Max) {
        [void]$items.Add([string]$enumerator.GetTextElement())
    }
    return -join $items
}

function Clean-NamePart {
    param(
        [AllowNull()][string]$Text,
        [switch]$KeepHash
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }

    $invalid = [Regex]::Escape((-join [System.IO.Path]::GetInvalidFileNameChars()))
    $cleaned = $Text -replace "[$invalid]", ""
    if (-not $KeepHash) {
        $cleaned = $cleaned -replace "#", ""
    }
    $cleaned = $cleaned -replace "[\u00A0\s]+", " "
    $cleaned = $cleaned.Trim(" .`t`r`n")

    return $cleaned
}

function Get-ContentCutIndex {
    param([string]$Text)

    $cutIndexes = New-Object System.Collections.Generic.List[int]

    foreach ($mark in @($FullStop, "`r", "`n")) {
        $index = $Text.IndexOf($mark)
        if ($index -gt 0) {
            [void]$cutIndexes.Add($index)
        }
    }

    $hashIndex = $Text.IndexOf("#")
    if ($hashIndex -gt 0) {
        [void]$cutIndexes.Add($hashIndex)
    }

    $dotSearchFrom = 0
    while ($dotSearchFrom -lt $Text.Length) {
        $dotIndex = $Text.IndexOf(".", $dotSearchFrom)
        if ($dotIndex -lt 0) {
            break
        }

        $prevIsDigit = ($dotIndex -gt 0 -and [char]::IsDigit($Text[$dotIndex - 1]))
        $nextIsDigit = ($dotIndex + 1 -lt $Text.Length -and [char]::IsDigit($Text[$dotIndex + 1]))
        if ($dotIndex -gt 6 -and -not ($prevIsDigit -and $nextIsDigit)) {
            [void]$cutIndexes.Add($dotIndex)
            break
        }

        $dotSearchFrom = $dotIndex + 1
    }

    if ($cutIndexes.Count -eq 0) {
        return -1
    }

    return ($cutIndexes | Measure-Object -Minimum).Minimum
}

function Split-MetaAndTitle {
    param([string]$Text)

    $remaining = $Text.Trim()
    $meta = ""
    $metricPattern = "^(?:(?:" + (($MetricWords | ForEach-Object { [Regex]::Escape($_) }) -join "|") + ")\s*[\d\.A-Za-z" + (U 0x4E07) + (U 0x5343) + (U 0x767E) + "]+\s*)"
    $authorPattern = "^(?:(?:" + (($AuthorWords | ForEach-Object { [Regex]::Escape($_) }) -join "|") + ")(?:\:|" + [Regex]::Escape($FullColon) + ")\s*[^\s#]{1,30}\s*|@[^\s#]{1,30}\s*)"

    while ($true) {
        $metricMatch = [regex]::Match($remaining, $metricPattern)
        if ($metricMatch.Success) {
            $meta += ($metricMatch.Value -replace "\s+", "")
            $remaining = $remaining.Substring($metricMatch.Length).TrimStart()
            continue
        }

        $authorMatch = [regex]::Match($remaining, $authorPattern)
        if ($authorMatch.Success) {
            $meta += ($authorMatch.Value -replace "\s+", "")
            $remaining = $remaining.Substring($authorMatch.Length).TrimStart()
            continue
        }

        break
    }

    return [pscustomobject]@{
        Meta = $meta
        Title = $remaining
    }
}

function Get-ShortNameBase {
    param(
        [string]$Name,
        [int]$MaxTotal,
        [int]$MaxTitle
    )

    $nameForCut = Clean-NamePart -Text $Name -KeepHash
    $cutIndex = Get-ContentCutIndex $nameForCut
    if ($cutIndex -gt 0) {
        $nameForCut = $nameForCut.Substring(0, $cutIndex)
    }

    $cleanName = Clean-NamePart -Text $nameForCut
    $parts = Split-MetaAndTitle $cleanName
    $meta = Clean-NamePart -Text $parts.Meta
    $title = Clean-NamePart -Text $parts.Title

    $metaLength = Get-TextElementLength $meta
    $titleLimit = [Math]::Min($MaxTitle, [Math]::Max(8, $MaxTotal - $metaLength))
    $shortTitle = (Limit-TextElements -Text $title -Max $titleLimit).Trim(" .`t`r`n")
    $result = Clean-NamePart -Text ($meta + $shortTitle)

    if ([string]::IsNullOrWhiteSpace($result)) {
        $result = Limit-TextElements -Text (Clean-NamePart -Text $Name) -Max $MaxTotal
    }

    return Limit-TextElements -Text $result -Max $MaxTotal
}

function Get-UniqueName {
    param(
        [string]$BaseName,
        [System.Collections.Generic.HashSet[string]]$Used,
        [int]$MaxTotal
    )

    $candidate = Limit-TextElements -Text (Clean-NamePart -Text $BaseName) -Max $MaxTotal
    if (-not $Used.Contains($candidate)) {
        [void]$Used.Add($candidate)
        return $candidate
    }

    for ($i = 2; $i -lt 1000; $i++) {
        $suffix = "~$i"
        $baseLimit = $MaxTotal - (Get-TextElementLength $suffix)
        $candidate = (Limit-TextElements -Text $BaseName -Max $baseLimit).Trim(" .`t`r`n") + $suffix
        if (-not $Used.Contains($candidate)) {
            [void]$Used.Add($candidate)
            return $candidate
        }
    }

    throw "Too many duplicate names for: $BaseName"
}

function Get-UniqueFileName {
    param(
        [string]$BaseName,
        [string]$Extension,
        [System.Collections.Generic.HashSet[string]]$Used,
        [int]$MaxBase
    )

    $cleanBase = Limit-TextElements -Text (Clean-NamePart -Text $BaseName) -Max $MaxBase
    $candidate = $cleanBase + $Extension
    if (-not $Used.Contains($candidate)) {
        [void]$Used.Add($candidate)
        return $candidate
    }

    for ($i = 2; $i -lt 1000; $i++) {
        $suffix = "~$i"
        $baseLimit = $MaxBase - (Get-TextElementLength $suffix)
        $candidate = (Limit-TextElements -Text $cleanBase -Max $baseLimit).Trim(" .`t`r`n") + $suffix + $Extension
        if (-not $Used.Contains($candidate)) {
            [void]$Used.Add($candidate)
            return $candidate
        }
    }

    throw "Too many duplicate file names for: $BaseName$Extension"
}

function Get-RelativePathFromRoot {
    param(
        [string]$Root,
        [string]$FullPath
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd("\", "/")
    $full = [System.IO.Path]::GetFullPath($FullPath)
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar

    if ($full.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($prefix.Length)
    }

    return ""
}

function Join-RelativePath {
    param(
        [AllowNull()][string]$Parent,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Parent)) {
        return $Name
    }

    return "$Parent\$Name"
}

function Join-FullPath {
    param(
        [string]$Root,
        [AllowNull()][string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $Root
    }

    return Join-Path $Root $RelativePath
}

function Get-PathDepth {
    param([AllowNull()][string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return 0
    }

    return @($RelativePath -split "[\\/]+" | Where-Object { $_ -ne "" }).Count
}

function Get-TargetRoots {
    $roots = New-Object System.Collections.Generic.List[object]

    foreach ($name in $TargetFolderNames) {
        $path = Join-Path $ScriptRoot $name
        if (Test-Path -LiteralPath $path -PathType Container) {
            $roots.Add([pscustomobject]@{
                RootName = $name
                RootPath = (Get-Item -LiteralPath $path).FullName
            })
        } else {
            Write-Warning "Target folder was not found and has been skipped: $path"
        }
    }

    return $roots
}

function New-RenamePlan {
    param(
        [int]$MaxTotal,
        [int]$MaxTitle,
        [int]$MaxFileBase
    )

    $nodes = New-Object System.Collections.Generic.List[object]
    foreach ($root in Get-TargetRoots) {
        $folders = Get-ChildItem -LiteralPath $root.RootPath -Directory -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($folder in $folders) {
            $relativePath = Get-RelativePathFromRoot -Root $root.RootPath -FullPath $folder.FullName
            $parentRelative = Split-Path $relativePath -Parent
            if ($parentRelative -eq ".") {
                $parentRelative = ""
            }

            $nodes.Add([pscustomobject]@{
                RootName = $root.RootName
                RootPath = $root.RootPath
                OriginalRelativePath = $relativePath
                OriginalParentRelative = $parentRelative
                OriginalName = $folder.Name
                Depth = Get-PathDepth $relativePath
                NewName = $folder.Name
                NewRelativePath = ""
                NewParentRelative = ""
                LeafChanged = $false
            })
        }
    }

    $groups = $nodes | Group-Object RootPath, OriginalParentRelative
    foreach ($group in $groups) {
        $used = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($node in ($group.Group | Sort-Object OriginalName)) {
            $cleanForCut = Clean-NamePart -Text $node.OriginalName -KeepHash
            $shortBase = Get-ShortNameBase -Name $node.OriginalName -MaxTotal $MaxTotal -MaxTitle $MaxTitle
            $shouldShorten = (
                (Get-TextElementLength $node.OriginalName) -gt $MaxTotal -or
                (Get-ContentCutIndex $cleanForCut) -gt 0 -or
                $node.OriginalName.Contains("#")
            )

            if ($shouldShorten) {
                $node.NewName = Get-UniqueName -BaseName $shortBase -Used $used -MaxTotal $MaxTotal
            } else {
                $node.NewName = Get-UniqueName -BaseName $node.OriginalName -Used $used -MaxTotal $MaxTotal
            }

            $node.LeafChanged = ($node.OriginalName -cne $node.NewName)
        }
    }

    $nodeByRootAndRelative = @{}
    foreach ($node in $nodes) {
        $key = "$($node.RootPath)|$($node.OriginalRelativePath)"
        $nodeByRootAndRelative[$key] = $node
    }

    foreach ($node in ($nodes | Sort-Object Depth, OriginalRelativePath)) {
        if ([string]::IsNullOrWhiteSpace($node.OriginalParentRelative)) {
            $node.NewParentRelative = ""
            $node.NewRelativePath = $node.NewName
        } else {
            $parentKey = "$($node.RootPath)|$($node.OriginalParentRelative)"
            $parentNode = $nodeByRootAndRelative[$parentKey]
            $node.NewParentRelative = $parentNode.NewRelativePath
            $node.NewRelativePath = Join-RelativePath -Parent $node.NewParentRelative -Name $node.NewName
        }
    }

    $folderRows = @($nodes | Select-Object `
        @{Name = "ItemType"; Expression = { "Directory" }},
        RootName,
        RootPath,
        OriginalRelativePath,
        NewRelativePath,
        OriginalParentRelative,
        NewParentRelative,
        OriginalName,
        NewName,
        Depth,
        LeafChanged,
        @{Name = "OriginalNameChars"; Expression = { Get-TextElementLength $_.OriginalName }},
        @{Name = "NewNameChars"; Expression = { Get-TextElementLength $_.NewName }},
        @{Name = "OriginalFullPathChars"; Expression = { (Join-FullPath -Root $_.RootPath -RelativePath $_.OriginalRelativePath).Length }},
        @{Name = "NewFullPathChars"; Expression = { (Join-FullPath -Root $_.RootPath -RelativePath $_.NewRelativePath).Length }})

    $folderMap = @{}
    foreach ($node in $nodes) {
        $folderMap["$($node.RootPath)|$($node.OriginalRelativePath)"] = $node
    }

    $fileRows = New-Object System.Collections.Generic.List[object]
    foreach ($root in Get-TargetRoots) {
        $files = Get-ChildItem -LiteralPath $root.RootPath -File -Recurse -Force -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            $relativePath = Get-RelativePathFromRoot -Root $root.RootPath -FullPath $file.FullName
            $parentRelative = Split-Path $relativePath -Parent
            if ($parentRelative -eq ".") {
                $parentRelative = ""
            }

            $newParentRelative = ""
            if (-not [string]::IsNullOrWhiteSpace($parentRelative)) {
                $parentKey = "$($root.RootPath)|$parentRelative"
                if ($folderMap.ContainsKey($parentKey)) {
                    $newParentRelative = $folderMap[$parentKey].NewRelativePath
                } else {
                    $newParentRelative = $parentRelative
                }
            }

            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            $extension = [System.IO.Path]::GetExtension($file.Name)
            $cleanForCut = Clean-NamePart -Text $baseName -KeepHash
            $shortBase = Get-ShortNameBase -Name $baseName -MaxTotal $MaxFileBase -MaxTitle $MaxTitle
            $shouldShorten = (
                (Get-TextElementLength $baseName) -gt $MaxFileBase -or
                (Get-ContentCutIndex $cleanForCut) -gt 0 -or
                $baseName.Contains("#") -or
                $file.FullName.Length -gt 240
            )

            $newName = $file.Name
            if ($shouldShorten) {
                $newName = (Clean-NamePart -Text $shortBase) + $extension
            }

            $newRelativePath = Join-RelativePath -Parent $newParentRelative -Name $newName
            $fileRows.Add([pscustomobject]@{
                ItemType = "File"
                RootName = $root.RootName
                RootPath = $root.RootPath
                OriginalRelativePath = $relativePath
                NewRelativePath = $newRelativePath
                OriginalParentRelative = $parentRelative
                NewParentRelative = $newParentRelative
                OriginalName = $file.Name
                NewName = $newName
                Depth = Get-PathDepth $relativePath
                LeafChanged = ($file.Name -cne $newName)
                OriginalNameChars = Get-TextElementLength $file.Name
                NewNameChars = Get-TextElementLength $newName
                OriginalFullPathChars = $file.FullName.Length
                NewFullPathChars = (Join-FullPath -Root $root.RootPath -RelativePath $newRelativePath).Length
            })
        }
    }

    $fileGroups = $fileRows | Group-Object RootPath, NewParentRelative
    foreach ($group in $fileGroups) {
        $used = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($row in ($group.Group | Sort-Object OriginalName)) {
            if ($row.LeafChanged) {
                $extension = [System.IO.Path]::GetExtension($row.NewName)
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($row.NewName)
                $row.NewName = Get-UniqueFileName -BaseName $baseName -Extension $extension -Used $used -MaxBase $MaxFileBase
                $row.NewRelativePath = Join-RelativePath -Parent $row.NewParentRelative -Name $row.NewName
                $row.NewNameChars = Get-TextElementLength $row.NewName
                $row.NewFullPathChars = (Join-FullPath -Root $row.RootPath -RelativePath $row.NewRelativePath).Length
                $row.LeafChanged = ($row.OriginalName -cne $row.NewName)
            } else {
                [void]$used.Add($row.OriginalName)
            }
        }
    }

    return @($folderRows) + @($fileRows.ToArray())
}

function Save-Plan {
    param(
        [object[]]$Plan,
        [string]$Kind
    )

    if (-not (Test-Path -LiteralPath $HistoryRoot)) {
        New-Item -ItemType Directory -Path $HistoryRoot | Out-Null
    }

    $path = Join-Path $HistoryRoot "$Kind-$Timestamp.csv"
    $Plan | Export-Csv -LiteralPath $path -NoTypeInformation -Encoding UTF8
    return $path
}

function Invoke-ApplyPlan {
    param([object[]]$Rows)

    $changedRows = @($Rows | Where-Object { "$($_.LeafChanged)" -eq "True" })
    if ($changedRows.Count -eq 0) {
        Write-Host "No folder needs renaming."
        return
    }

    $directoryRows = @($changedRows | Where-Object { [string]::IsNullOrWhiteSpace($_.ItemType) -or $_.ItemType -eq "Directory" })
    $fileRows = @($changedRows | Where-Object { $_.ItemType -eq "File" })

    $tempPrefix = "__jh_rename_$Timestamp`_"
    $depths = $directoryRows | ForEach-Object { [int]$_.Depth } | Sort-Object -Descending -Unique

    foreach ($depth in $depths) {
        $batch = @($directoryRows | Where-Object { [int]$_.Depth -eq $depth })
        $tempRows = New-Object System.Collections.Generic.List[object]

        foreach ($row in $batch) {
            $fromPath = Join-FullPath -Root $row.RootPath -RelativePath $row.OriginalRelativePath
            if (-not (Test-Path -LiteralPath $fromPath -PathType Container)) {
                Write-Warning "Folder not found, skipped: $fromPath"
                continue
            }

            $tempName = $tempPrefix + ([guid]::NewGuid().ToString("N"))
            Rename-Item -LiteralPath $fromPath -NewName $tempName
            $tempRows.Add([pscustomobject]@{
                RootPath = $row.RootPath
                ParentRelative = $row.OriginalParentRelative
                TempName = $tempName
                FinalName = $row.NewName
            })
        }

        foreach ($tempRow in $tempRows) {
            $tempRelative = Join-RelativePath -Parent $tempRow.ParentRelative -Name $tempRow.TempName
            $tempPath = Join-FullPath -Root $tempRow.RootPath -RelativePath $tempRelative
            Rename-Item -LiteralPath $tempPath -NewName $tempRow.FinalName
        }
    }

    $fileGroups = $fileRows | Group-Object RootPath, NewParentRelative
    foreach ($group in $fileGroups) {
        $tempRows = New-Object System.Collections.Generic.List[object]

        foreach ($row in $group.Group) {
            $currentRelative = Join-RelativePath -Parent $row.NewParentRelative -Name $row.OriginalName
            $fromPath = Join-FullPath -Root $row.RootPath -RelativePath $currentRelative
            if (-not (Test-Path -LiteralPath $fromPath -PathType Leaf)) {
                Write-Warning "File not found, skipped: $fromPath"
                continue
            }

            $tempName = $tempPrefix + ([guid]::NewGuid().ToString("N")) + ([System.IO.Path]::GetExtension($row.OriginalName))
            Rename-Item -LiteralPath $fromPath -NewName $tempName
            $tempRows.Add([pscustomobject]@{
                RootPath = $row.RootPath
                ParentRelative = $row.NewParentRelative
                TempName = $tempName
                FinalName = $row.NewName
            })
        }

        foreach ($tempRow in $tempRows) {
            $tempRelative = Join-RelativePath -Parent $tempRow.ParentRelative -Name $tempRow.TempName
            $tempPath = Join-FullPath -Root $tempRow.RootPath -RelativePath $tempRelative
            Rename-Item -LiteralPath $tempPath -NewName $tempRow.FinalName
        }
    }
}

function Get-LatestHistoryFile {
    if (-not (Test-Path -LiteralPath $HistoryRoot)) {
        return ""
    }

    $latest = Get-ChildItem -LiteralPath $HistoryRoot -Filter "rename-history-*.csv" -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $latest) {
        return ""
    }

    return $latest.FullName
}

function Invoke-UndoPlan {
    param([object[]]$Rows)

    $changedRows = @($Rows | Where-Object { "$($_.LeafChanged)" -eq "True" })
    if ($changedRows.Count -eq 0) {
        Write-Host "No renamed folder exists in this history file."
        return
    }

    $tempPrefix = "__jh_undo_$Timestamp`_"
    $fileRows = @($changedRows | Where-Object { $_.ItemType -eq "File" })
    $fileGroups = $fileRows | Group-Object RootPath, NewParentRelative
    foreach ($group in $fileGroups) {
        $tempRows = New-Object System.Collections.Generic.List[object]

        foreach ($row in $group.Group) {
            $fromPath = Join-FullPath -Root $row.RootPath -RelativePath $row.NewRelativePath
            if (-not (Test-Path -LiteralPath $fromPath -PathType Leaf)) {
                Write-Warning "File not found while undoing, skipped: $fromPath"
                continue
            }

            $tempName = $tempPrefix + ([guid]::NewGuid().ToString("N")) + ([System.IO.Path]::GetExtension($row.NewName))
            Rename-Item -LiteralPath $fromPath -NewName $tempName
            $tempRows.Add([pscustomobject]@{
                RootPath = $row.RootPath
                ParentRelative = $row.NewParentRelative
                TempName = $tempName
                FinalName = $row.OriginalName
            })
        }

        foreach ($tempRow in $tempRows) {
            $tempRelative = Join-RelativePath -Parent $tempRow.ParentRelative -Name $tempRow.TempName
            $tempPath = Join-FullPath -Root $tempRow.RootPath -RelativePath $tempRelative
            Rename-Item -LiteralPath $tempPath -NewName $tempRow.FinalName
        }
    }

    $directoryRows = @($changedRows | Where-Object { [string]::IsNullOrWhiteSpace($_.ItemType) -or $_.ItemType -eq "Directory" })
    $depths = $directoryRows | ForEach-Object { [int]$_.Depth } | Sort-Object -Descending -Unique

    foreach ($depth in $depths) {
        $batch = @($directoryRows | Where-Object { [int]$_.Depth -eq $depth })
        $tempRows = New-Object System.Collections.Generic.List[object]

        foreach ($row in $batch) {
            $fromPath = Join-FullPath -Root $row.RootPath -RelativePath $row.NewRelativePath
            if (-not (Test-Path -LiteralPath $fromPath -PathType Container)) {
                Write-Warning "Folder not found while undoing, skipped: $fromPath"
                continue
            }

            $tempName = $tempPrefix + ([guid]::NewGuid().ToString("N"))
            Rename-Item -LiteralPath $fromPath -NewName $tempName
            $tempRows.Add([pscustomobject]@{
                RootPath = $row.RootPath
                ParentRelative = $row.NewParentRelative
                TempName = $tempName
                FinalName = $row.OriginalName
            })
        }

        foreach ($tempRow in $tempRows) {
            $tempRelative = Join-RelativePath -Parent $tempRow.ParentRelative -Name $tempRow.TempName
            $tempPath = Join-FullPath -Root $tempRow.RootPath -RelativePath $tempRelative
            Rename-Item -LiteralPath $tempPath -NewName $tempRow.FinalName
        }
    }
}

if ($Mode -eq "Undo") {
    if ([string]::IsNullOrWhiteSpace($HistoryFile)) {
        $HistoryFile = Get-LatestHistoryFile
    }

    if ([string]::IsNullOrWhiteSpace($HistoryFile) -or -not (Test-Path -LiteralPath $HistoryFile -PathType Leaf)) {
        throw "No undo history file was found."
    }

    $rows = @(Import-Csv -LiteralPath $HistoryFile)
    Invoke-UndoPlan -Rows $rows
    $undoRecord = Save-Plan -Plan $rows -Kind "undo-used-history"
    Write-Host "Undo completed from history: $HistoryFile"
    Write-Host "Undo record: $undoRecord"
    exit 0
}

$plan = @(New-RenamePlan -MaxTotal $MaxTotalChars -MaxTitle $MaxTitleChars -MaxFileBase $MaxFileBaseChars)
$changed = @($plan | Where-Object { $_.LeafChanged })
$previewPath = Save-Plan -Plan $plan -Kind "preview"

Write-Host ""
Write-Host "Jianghu collected-folder long-name fixer"
Write-Host "Mode: $Mode"
Write-Host "Scanned items: $($plan.Count)"
Write-Host "Will rename: $($changed.Count)"
Write-Host "Preview record: $previewPath"
Write-Host ""

if ($changed.Count -gt 0 -and $changed.Count -le 100) {
    $changed |
        Select-Object RootName, OriginalName, NewName, OriginalNameChars, NewNameChars, OriginalFullPathChars, NewFullPathChars |
        Format-Table -AutoSize -Wrap
} elseif ($changed.Count -gt 100) {
    Write-Host "Changed item list is long, so the detailed table was written only to the CSV record."
}

if ($Mode -eq "Preview") {
    Write-Host ""
    Write-Host "Preview only. No folder was renamed."
    exit 0
}

$historyPath = Save-Plan -Plan $plan -Kind "rename-history"
Invoke-ApplyPlan -Rows $plan

Write-Host ""
Write-Host "Done."
Write-Host "History file: $historyPath"
Write-Host "Undo command: powershell -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode Undo -HistoryFile `"$historyPath`""
