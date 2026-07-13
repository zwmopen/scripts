$ErrorActionPreference = "Stop"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) { throw "ASSERTION FAILED: $Message. Expected=[$Expected] Actual=[$Actual]" }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("scripts-safety-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    # Work package: preview does nothing; simulated failure restores all source images.
    $workSource = Join-Path $repoRoot "本地文件处理脚本/一键GPT作品包/make_work_package.ps1"
    $workDir = Join-Path $tempRoot "work-package"
    New-Item -ItemType Directory -Path $workDir | Out-Null
    $workScript = Join-Path $workDir "make_work_package.ps1"
    Copy-Item -LiteralPath $workSource -Destination $workScript
    Assert-True (Test-Path -LiteralPath $workScript -PathType Leaf) "copied work package script is missing"
    $workScript = (Get-Item -LiteralPath $workScript).FullName

    [System.IO.File]::WriteAllBytes((Join-Path $workDir "one.png"), [byte[]](1,2,3))
    [System.IO.File]::WriteAllBytes((Join-Path $workDir "two.jpg"), [byte[]](4,5,6))
    $text = "测试标题`r`n测试正文"

    $previewOutput = @(& $workScript -ClipboardTextOverride $text -NoMessage -Preview)
    Assert-True ($previewOutput -contains "PREVIEW") "work package preview marker is missing"
    Assert-Equal 2 (@(Get-ChildItem -LiteralPath $workDir -File | Where-Object { $_.Extension -in @('.png','.jpg') }).Count) "preview must not move images"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $workDir "团建成品库"))) "preview must not create the library"

    $failedAsExpected = $false
    try {
        & $workScript -ClipboardTextOverride $text -NoMessage -TestFailAfterImageMove 1 -ErrorAction Stop | Out-Null
    } catch {
        $failedAsExpected = $_.Exception.Message -match "Simulated failure"
    }
    Assert-True $failedAsExpected "simulated work package failure was not observed"
    Assert-Equal 2 (@(Get-ChildItem -LiteralPath $workDir -File | Where-Object { $_.Extension -in @('.png','.jpg') }).Count) "failed package must restore all original images"
    Assert-Equal 0 (@(Get-ChildItem -LiteralPath (Join-Path $workDir "团建成品库") -Directory -Force -ErrorAction SilentlyContinue | Where-Object Name -like '.workpkg_staging_*').Count) "failed package must remove staging directories"

    $successOutput = @(& $workScript -ClipboardTextOverride $text -NoMessage)
    Assert-True ($successOutput -contains "OK") "work package success marker is missing"
    Assert-Equal 0 (@(Get-ChildItem -LiteralPath $workDir -File | Where-Object { $_.Extension -in @('.png','.jpg') }).Count) "successful package should move source images into the package"

    [System.IO.File]::WriteAllBytes((Join-Path $workDir "duplicate.png"), [byte[]](7,8,9))
    $duplicateOutput = @(& $workScript -ClipboardTextOverride $text -NoMessage)
    Assert-True ($duplicateOutput -contains "DUPLICATE") "duplicate package marker is missing"
    Assert-Equal 0 (@(Get-ChildItem -LiteralPath $workDir -File | Where-Object Extension -eq '.png').Count) "duplicate image must leave the source folder"
    $quarantine = @(Get-ChildItem -LiteralPath $workDir -Directory -Force | Where-Object Name -like '.workpkg_duplicate_downloads_*')
    Assert-Equal 1 $quarantine.Count "duplicate images must be quarantined instead of deleted"
    Assert-Equal 1 (@(Get-ChildItem -LiteralPath $quarantine[0].FullName -File).Count) "quarantine should contain the duplicate image"

    # Sync: preview, replacement token, rollback after backup, successful replacement, undo.
    $syncScript = Join-Path $repoRoot "本地文件处理脚本/素材处理脚本/同步-硬链接素材工作副本.ps1"
    $syncSource = Join-Path $tempRoot "sync-source"
    $syncTarget = Join-Path $tempRoot "sync-target"
    New-Item -ItemType Directory -Path $syncSource | Out-Null
    Set-Content -LiteralPath (Join-Path $syncSource "item.txt") -Value "version-one" -NoNewline

    & $syncScript -SourcePath $syncSource -TargetPath $syncTarget -Mode Preview -SyncType Copy | Out-Null
    Assert-True (-not (Test-Path -LiteralPath $syncTarget)) "sync preview must not create target directory"

    & $syncScript -SourcePath $syncSource -TargetPath $syncTarget -Mode Apply -SyncType Copy | Out-Null
    $targetFile = Join-Path $syncTarget "item.txt"
    Assert-Equal "version-one" (Get-Content -LiteralPath $targetFile -Raw) "initial sync content mismatch"

    Set-Content -LiteralPath (Join-Path $syncSource "item.txt") -Value "version-two" -NoNewline
    $missingTokenFailed = $false
    try {
        & $syncScript -SourcePath $syncSource -TargetPath $syncTarget -Mode Apply -SyncType Copy -Replace -ErrorAction Stop | Out-Null
    } catch { $missingTokenFailed = $_.Exception.Message -match "ConfirmReplaceToken" }
    Assert-True $missingTokenFailed "replace without confirmation token must fail"
    Assert-Equal "version-one" (Get-Content -LiteralPath $targetFile -Raw) "failed confirmation must not alter target"

    $rollbackFailed = $false
    try {
        & $syncScript -SourcePath $syncSource -TargetPath $syncTarget -Mode Apply -SyncType Copy -Replace -ConfirmReplaceToken REPLACE -TestFailAfterBackup -ErrorAction Stop | Out-Null
    } catch { $rollbackFailed = $true }
    Assert-True $rollbackFailed "simulated sync replacement failure was not observed"
    Assert-Equal "version-one" (Get-Content -LiteralPath $targetFile -Raw) "failed replacement must restore old target"
    Assert-Equal 0 (@(Get-ChildItem -LiteralPath $syncTarget -File -Recurse -Force | Where-Object Name -like '*.sync-new-*').Count) "failed replacement must remove temp files"

    & $syncScript -SourcePath $syncSource -TargetPath $syncTarget -Mode Apply -SyncType Copy -Replace -ConfirmReplaceToken REPLACE | Out-Null
    Assert-Equal "version-two" (Get-Content -LiteralPath $targetFile -Raw) "successful replacement content mismatch"
    $replaceHistory = @(Get-ChildItem -LiteralPath (Join-Path $syncTarget ".sync-history") -Filter 'sync-history-*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    Assert-Equal 1 $replaceHistory.Count "replacement history file is missing"

    & $syncScript -Mode Undo -HistoryFile $replaceHistory[0].FullName -ConfirmUndoToken UNDO | Out-Null
    Assert-Equal "version-one" (Get-Content -LiteralPath $targetFile -Raw) "sync undo must restore old target"

    # Rename: default preview, token requirement, rollback, apply and undo with nested items.
    $renameScript = Join-Path $repoRoot "本地文件处理脚本/素材处理脚本/评论在前改名工具/swap-like-comment-prefix.ps1"
    $renameRoot = Join-Path $tempRoot "rename"
    New-Item -ItemType Directory -Path $renameRoot | Out-Null
    $oldParent = Join-Path $renameRoot "项目赞10评2"
    New-Item -ItemType Directory -Path $oldParent | Out-Null
    $oldChild = Join-Path $oldParent "图片赞5评1.txt"
    Set-Content -LiteralPath $oldChild -Value "x" -NoNewline

    & $renameScript -Root $renameRoot | Out-Null
    Assert-True (Test-Path -LiteralPath $oldParent) "rename default mode must be Preview"
    Assert-True (Test-Path -LiteralPath $oldChild) "rename preview must not alter child file"

    $renameTokenFailed = $false
    try { & $renameScript -Root $renameRoot -Mode Apply -ErrorAction Stop | Out-Null } catch { $renameTokenFailed = $_.Exception.Message -match "ConfirmApplyToken" }
    Assert-True $renameTokenFailed "rename apply without token must fail"

    $renameRollbackFailed = $false
    try {
        & $renameScript -Root $renameRoot -Mode Apply -ConfirmApplyToken RENAME -TestFailAfterRename 1 -ErrorAction Stop | Out-Null
    } catch { $renameRollbackFailed = $true }
    Assert-True $renameRollbackFailed "simulated rename failure was not observed"
    Assert-True (Test-Path -LiteralPath $oldParent) "rename rollback must restore parent"
    Assert-True (Test-Path -LiteralPath $oldChild) "rename rollback must restore child"

    & $renameScript -Root $renameRoot -Mode Apply -ConfirmApplyToken RENAME | Out-Null
    $newParent = Join-Path $renameRoot "项目评2赞10"
    $newChild = Join-Path $newParent "图片评1赞5.txt"
    Assert-True (Test-Path -LiteralPath $newParent) "renamed parent is missing"
    Assert-True (Test-Path -LiteralPath $newChild) "renamed child is missing"
    $renameHistory = @(Get-ChildItem -LiteralPath (Join-Path $renameRoot "rename-logs") -Filter 'rename_like_comment_*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
    Assert-Equal 1 $renameHistory.Count "rename history is missing"

    & $renameScript -Root $renameRoot -Mode Undo -HistoryFile $renameHistory[0].FullName -ConfirmUndoToken UNDO | Out-Null
    Assert-True (Test-Path -LiteralPath $oldParent) "rename undo must restore parent"
    Assert-True (Test-Path -LiteralPath $oldChild) "rename undo must restore child"

    Write-Host "All script safety behavior tests passed."
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
