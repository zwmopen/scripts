param(
    [ValidateSet("Settings", "Tasks", "Data")]
    [string]$InitialTab = "Settings",
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$configPath = Join-Path $PSScriptRoot "workpkg_config.json"
$corePath = Join-Path $PSScriptRoot "make_work_package.ps1"
$runtimeHistoryPath = Join-Path $PSScriptRoot ".workpkg_history_backup.json"
$taskArchivePath = Join-Path $PSScriptRoot "任务记录"
$backupRoot = Join-Path $PSScriptRoot "备份"

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Set-ObjectProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $Object.$Name = $Value
    }
}

function Resolve-Directory {
    param([string]$Path, [string]$Label)
    $expanded = [Environment]::ExpandEnvironmentVariables(([string]$Path).Trim().Trim('"'))
    if ([string]::IsNullOrWhiteSpace($expanded) -or -not [System.IO.Path]::IsPathRooted($expanded)) {
        throw "$Label 必须填写完整绝对路径。"
    }
    $resolved = [System.IO.Path]::GetFullPath($expanded)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        New-Item -ItemType Directory -Path $resolved -Force | Out-Null
    }
    return $resolved
}

function Write-Config {
    param([object]$Config)
    $json = $Config | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($true)))
}

function Show-Info {
    param([string]$Message, [string]$Title = "GPT 作品助手")
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Show-ErrorMessage {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "GPT 作品助手",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Browse-Directory {
    param([System.Windows.Forms.TextBox]$TextBox, [string]$Description)
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = $Description
    $dialog.ShowNewFolderButton = $true
    if (Test-Path -LiteralPath $TextBox.Text -PathType Container) {
        $dialog.SelectedPath = $TextBox.Text
    }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $TextBox.Text = $dialog.SelectedPath
    }
}

function Get-HistoryPaths {
    param([object]$Config)
    $library = [string]$Config.library_path
    $historyDirectory = Join-Path $library "_作品历史数据"
    return [pscustomobject]@{
        Primary = Join-Path $historyDirectory "作品历史数据库.json"
        Backup = Join-Path $historyDirectory "作品历史数据库.backup.json"
        Runtime = $runtimeHistoryPath
    }
}

function Get-TaskRows {
    param([object]$Config)
    $rows = New-Object System.Collections.Generic.List[object]
    $inbox = [string]$Config.image_inbox_path
    if (Test-Path -LiteralPath $inbox -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $inbox -File -Filter "chatgpt-workpkg-task-*.json" -ErrorAction SilentlyContinue)) {
            $task = Read-JsonFile -Path $file.FullName
            if ($null -eq $task) { continue }
            $rows.Add([pscustomobject]@{
                Status = [string]$task.status
                Title = [string]$task.copyTitle
                Images = "$([int]$task.actualImages)/$([int]$task.expectedImages)"
                Time = $file.LastWriteTime
                BatchId = [string]$task.batchId
                ExpectedImages = [int]$task.expectedImages
                PackagePath = [string]$task.packagePath
                RecordPath = $file.FullName
                Source = "inbox"
            }) | Out-Null
        }
    }
    if (Test-Path -LiteralPath $taskArchivePath -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $taskArchivePath -File -Filter "*.json" -ErrorAction SilentlyContinue)) {
            $task = Read-JsonFile -Path $file.FullName
            if ($null -eq $task) { continue }
            $rows.Add([pscustomobject]@{
                Status = [string]$task.status
                Title = [string]$task.copyTitle
                Images = "$([int]$task.actualImages)/$([int]$task.expectedImages)"
                Time = $file.LastWriteTime
                BatchId = [string]$task.batchId
                ExpectedImages = [int]$task.expectedImages
                PackagePath = [string]$task.packagePath
                RecordPath = $file.FullName
                Source = "archive"
            }) | Out-Null
        }
    }
    $library = [string]$Config.library_path
    if (Test-Path -LiteralPath $library -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $library -File -Recurse -Filter "GPT任务记录.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 80)) {
            $task = Read-JsonFile -Path $file.FullName
            if ($null -eq $task) { continue }
            $rows.Add([pscustomobject]@{
                Status = [string]$task.status
                Title = [string]$task.copyTitle
                Images = "$([int]$task.actualImages)/$([int]$task.expectedImages)"
                Time = $file.LastWriteTime
                BatchId = [string]$task.batchId
                ExpectedImages = [int]$task.expectedImages
                PackagePath = if ([string]::IsNullOrWhiteSpace([string]$task.packagePath)) { $file.DirectoryName } else { [string]$task.packagePath }
                RecordPath = $file.FullName
                Source = "package"
            }) | Out-Null
        }
    }
    return @($rows | Sort-Object Time -Descending)
}

function Get-StatusLabel {
    param([string]$Status)
    switch ($Status) {
        "queued" { "等待处理" }
        "processing" { "正在处理" }
        "waiting_images" { "等待图片" }
        "incomplete_images" { "图片未完整" }
        "completed" { "已完成" }
        "duplicate" { "重复已删除" }
        "visual_similar" { "视觉近似" }
        "failed" { "失败" }
        default { if ([string]::IsNullOrWhiteSpace($Status)) { "未知" } else { $Status } }
    }
}

function New-Backup {
    param([object]$Config)
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    }
    $folder = Join-Path $backupRoot (Get-Date -Format "yyyyMMdd_HHmmss")
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    Copy-Item -LiteralPath $configPath -Destination (Join-Path $folder "workpkg_config.json") -Force
    $historyPaths = Get-HistoryPaths -Config $Config
    foreach ($item in @(
        [pscustomobject]@{ Source = $historyPaths.Primary; Name = "history-primary.json" },
        [pscustomobject]@{ Source = $historyPaths.Backup; Name = "history-backup.json" },
        [pscustomobject]@{ Source = $historyPaths.Runtime; Name = "history-runtime.json" }
    )) {
        if (Test-Path -LiteralPath $item.Source -PathType Leaf) {
            Copy-Item -LiteralPath $item.Source -Destination (Join-Path $folder $item.Name) -Force
        }
    }
    if (Test-Path -LiteralPath $taskArchivePath -PathType Container) {
        Copy-Item -LiteralPath $taskArchivePath -Destination (Join-Path $folder "任务记录") -Recurse -Force
    }
    return $folder
}

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    Show-ErrorMessage "本地配置文件不存在，请重新安装作品助手。"
    exit 1
}

$config = Read-JsonFile -Path $configPath
if ($null -eq $config) {
    Show-ErrorMessage "本地配置文件损坏，请从备份恢复或重新安装。"
    exit 1
}

if ($SelfTest) {
    $historyPaths = Get-HistoryPaths -Config $config
    $history = Read-JsonFile -Path $historyPaths.Primary
    if ($null -eq $history) { $history = Read-JsonFile -Path $historyPaths.Runtime }
    Write-Output "CENTER_OK"
    Write-Output "Version=1.8.0"
    Write-Output "TaskRows=$(@(Get-TaskRows -Config $config).Count)"
    Write-Output "HistoryEntries=$(if ($null -eq $history) { 0 } else { @($history.entries).Count })"
    exit 0
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "GPT 作品助手中心"
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(920, 650)
$form.Size = New-Object System.Drawing.Size(960, 700)
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = "Fill"
$form.Controls.Add($tabs)

$settingsTab = New-Object System.Windows.Forms.TabPage
$settingsTab.Text = "常用设置"
$tasksTab = New-Object System.Windows.Forms.TabPage
$tasksTab.Text = "任务中心"
$dataTab = New-Object System.Windows.Forms.TabPage
$dataTab.Text = "数据与恢复"
$tabs.TabPages.AddRange(@($settingsTab, $tasksTab, $dataTab))

function Add-Label {
    param([System.Windows.Forms.Control]$Parent, [string]$Text, [int]$Left, [int]$Top, [int]$Width = 220)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($Left, $Top)
    $label.Size = New-Object System.Drawing.Size($Width, 26)
    $Parent.Controls.Add($label)
    return $label
}

Add-Label -Parent $settingsTab -Text "图片下载目录" -Left 24 -Top 24 | Out-Null
$inboxBox = New-Object System.Windows.Forms.TextBox
$inboxBox.Location = New-Object System.Drawing.Point(24, 52)
$inboxBox.Size = New-Object System.Drawing.Size(760, 30)
$inboxBox.Text = [string]$config.image_inbox_path
$settingsTab.Controls.Add($inboxBox)
$inboxBrowse = New-Object System.Windows.Forms.Button
$inboxBrowse.Text = "浏览"
$inboxBrowse.Location = New-Object System.Drawing.Point(800, 50)
$inboxBrowse.Size = New-Object System.Drawing.Size(90, 32)
$inboxBrowse.Add_Click({ Browse-Directory -TextBox $inboxBox -Description "选择浏览器下载图片的目录" })
$settingsTab.Controls.Add($inboxBrowse)

Add-Label -Parent $settingsTab -Text "成品库目录" -Left 24 -Top 94 | Out-Null
$libraryBox = New-Object System.Windows.Forms.TextBox
$libraryBox.Location = New-Object System.Drawing.Point(24, 122)
$libraryBox.Size = New-Object System.Drawing.Size(760, 30)
$libraryBox.Text = [string]$config.library_path
$settingsTab.Controls.Add($libraryBox)
$libraryBrowse = New-Object System.Windows.Forms.Button
$libraryBrowse.Text = "浏览"
$libraryBrowse.Location = New-Object System.Drawing.Point(800, 120)
$libraryBrowse.Size = New-Object System.Drawing.Size(90, 32)
$libraryBrowse.Add_Click({ Browse-Directory -TextBox $libraryBox -Description "选择作品包成品库" })
$settingsTab.Controls.Add($libraryBrowse)

$groupBox = New-Object System.Windows.Forms.GroupBox
$groupBox.Text = "作品集整理"
$groupBox.Location = New-Object System.Drawing.Point(24, 172)
$groupBox.Size = New-Object System.Drawing.Size(866, 132)
$settingsTab.Controls.Add($groupBox)
$autoGroup = New-Object System.Windows.Forms.CheckBox
$autoGroup.Text = "自动整理"
$autoGroup.Location = New-Object System.Drawing.Point(18, 34)
$autoGroup.Checked = [bool]$config.portfolio_auto_group
$groupBox.Controls.Add($autoGroup)
Add-Label -Parent $groupBox -Text "每集数量" -Left 140 -Top 34 -Width 75 | Out-Null
$batchSize = New-Object System.Windows.Forms.NumericUpDown
$batchSize.Location = New-Object System.Drawing.Point(220, 30)
$batchSize.Minimum = 1
$batchSize.Maximum = 500
$batchSize.Value = [Math]::Max(1, [Math]::Min(500, [int]$config.portfolio_batch_size))
$groupBox.Controls.Add($batchSize)
Add-Label -Parent $groupBox -Text "名称前缀" -Left 330 -Top 34 -Width 75 | Out-Null
$prefixBox = New-Object System.Windows.Forms.TextBox
$prefixBox.Location = New-Object System.Drawing.Point(410, 30)
$prefixBox.Size = New-Object System.Drawing.Size(160, 30)
$prefixBox.Text = [string]$config.portfolio_prefix
$groupBox.Controls.Add($prefixBox)
$autoZip = New-Object System.Windows.Forms.CheckBox
$autoZip.Text = "生成 ZIP"
$autoZip.Location = New-Object System.Drawing.Point(610, 34)
$autoZip.Checked = [bool]$config.portfolio_auto_zip
$groupBox.Controls.Add($autoZip)
$flushButton = New-Object System.Windows.Forms.Button
$flushButton.Text = "立即整理剩余作品"
$flushButton.Location = New-Object System.Drawing.Point(18, 78)
$flushButton.Size = New-Object System.Drawing.Size(170, 34)
$groupBox.Controls.Add($flushButton)
$nextNumberLabel = Add-Label -Parent $groupBox -Text "当前编号：读取中…" -Left 215 -Top 84 -Width 420

$nameBox = New-Object System.Windows.Forms.GroupBox
$nameBox.Text = "命名与完成动作"
$nameBox.Location = New-Object System.Drawing.Point(24, 320)
$nameBox.Size = New-Object System.Drawing.Size(866, 150)
$settingsTab.Controls.Add($nameBox)
Add-Label -Parent $nameBox -Text "作品包文件夹格式" -Left 18 -Top 34 -Width 135 | Out-Null
$namingCombo = New-Object System.Windows.Forms.ComboBox
$namingCombo.DropDownStyle = "DropDownList"
$namingCombo.Location = New-Object System.Drawing.Point(160, 30)
$namingCombo.Size = New-Object System.Drawing.Size(410, 30)
$namingOptions = @(
    [pscustomobject]@{ Label = "文案标题（GPT 窗口名）— 推荐"; Value = "title_conversation" },
    [pscustomobject]@{ Label = "GPT 窗口名（文案标题）"; Value = "conversation_title" },
    [pscustomobject]@{ Label = "仅文案标题"; Value = "title_only" },
    [pscustomobject]@{ Label = "仅 GPT 窗口名"; Value = "conversation_only" }
)
$namingCombo.DisplayMember = "Label"
$namingCombo.ValueMember = "Value"
$namingCombo.DataSource = $namingOptions
$selectedNaming = @($namingOptions | Where-Object Value -eq ([string]$config.package_naming_mode) | Select-Object -First 1)
if ($selectedNaming.Count -gt 0) { $namingCombo.SelectedValue = $selectedNaming[0].Value }
$nameBox.Controls.Add($namingCombo)
$openFolder = New-Object System.Windows.Forms.CheckBox
$openFolder.Text = "完成后打开作品包"
$openFolder.Location = New-Object System.Drawing.Point(18, 82)
$openFolder.Checked = [bool]$config.completion_open_folder
$nameBox.Controls.Add($openFolder)
$copyPath = New-Object System.Windows.Forms.CheckBox
$copyPath.Text = "完成后复制路径（会覆盖剪贴板）"
$copyPath.Location = New-Object System.Drawing.Point(220, 82)
$copyPath.Size = New-Object System.Drawing.Size(260, 28)
$copyPath.Checked = [bool]$config.completion_copy_path
$nameBox.Controls.Add($copyPath)
Add-Label -Parent $nameBox -Text "提示时长（毫秒）" -Left 510 -Top 84 -Width 125 | Out-Null
$toastDuration = New-Object System.Windows.Forms.NumericUpDown
$toastDuration.Location = New-Object System.Drawing.Point(640, 80)
$toastDuration.Minimum = 500
$toastDuration.Maximum = 10000
$toastDuration.Increment = 250
$toastDuration.Value = [Math]::Max(500, [Math]::Min(10000, [int]$config.notification_duration_ms))
$nameBox.Controls.Add($toastDuration)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = "保存全部设置"
$saveButton.Location = New-Object System.Drawing.Point(720, 500)
$saveButton.Size = New-Object System.Drawing.Size(170, 40)
$settingsTab.Controls.Add($saveButton)
$settingsHint = Add-Label -Parent $settingsTab -Text "精确图片查重保持固定开启，避免生成真正重复的作品包。" -Left 24 -Top 510 -Width 640
$settingsHint.ForeColor = [System.Drawing.Color]::FromArgb(72, 105, 92)

$taskList = New-Object System.Windows.Forms.ListView
$taskList.View = "Details"
$taskList.FullRowSelect = $true
$taskList.GridLines = $true
$taskList.HideSelection = $false
$taskList.Location = New-Object System.Drawing.Point(18, 18)
$taskList.Size = New-Object System.Drawing.Size(872, 490)
[void]$taskList.Columns.Add("状态", 105)
[void]$taskList.Columns.Add("文案/任务", 390)
[void]$taskList.Columns.Add("图片", 85)
[void]$taskList.Columns.Add("时间", 160)
[void]$taskList.Columns.Add("来源", 90)
$tasksTab.Controls.Add($taskList)

$taskRefresh = New-Object System.Windows.Forms.Button
$taskRefresh.Text = "刷新"
$taskRefresh.Location = New-Object System.Drawing.Point(18, 526)
$taskRefresh.Size = New-Object System.Drawing.Size(90, 34)
$tasksTab.Controls.Add($taskRefresh)
$taskRetry = New-Object System.Windows.Forms.Button
$taskRetry.Text = "重试"
$taskRetry.Location = New-Object System.Drawing.Point(122, 526)
$taskRetry.Size = New-Object System.Drawing.Size(90, 34)
$tasksTab.Controls.Add($taskRetry)
$taskOpen = New-Object System.Windows.Forms.Button
$taskOpen.Text = "打开作品包"
$taskOpen.Location = New-Object System.Drawing.Point(226, 526)
$taskOpen.Size = New-Object System.Drawing.Size(120, 34)
$tasksTab.Controls.Add($taskOpen)
$taskCopy = New-Object System.Windows.Forms.Button
$taskCopy.Text = "复制路径"
$taskCopy.Location = New-Object System.Drawing.Point(360, 526)
$taskCopy.Size = New-Object System.Drawing.Size(100, 34)
$tasksTab.Controls.Add($taskCopy)
$taskRemove = New-Object System.Windows.Forms.Button
$taskRemove.Text = "移除记录"
$taskRemove.Location = New-Object System.Drawing.Point(474, 526)
$taskRemove.Size = New-Object System.Drawing.Size(100, 34)
$tasksTab.Controls.Add($taskRemove)
$taskHint = Add-Label -Parent $tasksTab -Text "移除记录不会删除图片或作品包；已完成作品包内的溯源记录不可在这里删除。" -Left 18 -Top 576 -Width 760
$taskHint.ForeColor = [System.Drawing.Color]::FromArgb(72, 105, 92)

$dataSummary = Add-Label -Parent $dataTab -Text "正在读取数据…" -Left 24 -Top 28 -Width 820
$dataSummary.Height = 150
$dataSummary.BorderStyle = "FixedSingle"
$dataSummary.Padding = New-Object System.Windows.Forms.Padding(14)
$backupButton = New-Object System.Windows.Forms.Button
$backupButton.Text = "立即完整备份"
$backupButton.Location = New-Object System.Drawing.Point(24, 210)
$backupButton.Size = New-Object System.Drawing.Size(160, 40)
$dataTab.Controls.Add($backupButton)
$restoreButton = New-Object System.Windows.Forms.Button
$restoreButton.Text = "恢复最近备份"
$restoreButton.Location = New-Object System.Drawing.Point(200, 210)
$restoreButton.Size = New-Object System.Drawing.Size(160, 40)
$dataTab.Controls.Add($restoreButton)
$openBackupButton = New-Object System.Windows.Forms.Button
$openBackupButton.Text = "打开备份目录"
$openBackupButton.Location = New-Object System.Drawing.Point(376, 210)
$openBackupButton.Size = New-Object System.Drawing.Size(160, 40)
$dataTab.Controls.Add($openBackupButton)
$dataHint = Add-Label -Parent $dataTab -Text "备份包含本地设置、查重历史主库/备份/运行镜像和任务记录，不复制大型作品图片。" -Left 24 -Top 276 -Width 820
$dataHint.ForeColor = [System.Drawing.Color]::FromArgb(72, 105, 92)

function Refresh-DataSummary {
    $historyPaths = Get-HistoryPaths -Config $config
    $history = Read-JsonFile -Path $historyPaths.Primary
    if ($null -eq $history) { $history = Read-JsonFile -Path $historyPaths.Runtime }
    $entryCount = if ($null -eq $history) { 0 } else { @($history.entries).Count }
    $lastNumber = if ($null -eq $history) { 0 } else { [int]$history.portfolioLastIssued }
    $historySize = if (Test-Path -LiteralPath $historyPaths.Primary) {
        [Math]::Round((Get-Item -LiteralPath $historyPaths.Primary).Length / 1KB, 1)
    } else { 0 }
    $pending = @(Get-TaskRows -Config $config | Where-Object Source -eq "inbox").Count
    $dataSummary.Text = @(
        "成品库：$([string]$config.library_path)"
        "查重历史：$entryCount 条，约 $historySize KB"
        "作品集最后编号：$lastNumber；下一个编号：$($lastNumber + 1)"
        "当前待处理任务：$pending"
        "本地版本：1.8.0"
    ) -join [Environment]::NewLine
    $nextNumberLabel.Text = "最后编号：$lastNumber；下一个：$($lastNumber + 1)"
}

function Refresh-TaskList {
    $taskList.Items.Clear()
    foreach ($row in @(Get-TaskRows -Config $config)) {
        $item = New-Object System.Windows.Forms.ListViewItem((Get-StatusLabel -Status $row.Status))
        [void]$item.SubItems.Add($(if ([string]::IsNullOrWhiteSpace($row.Title)) { $row.BatchId } else { $row.Title }))
        [void]$item.SubItems.Add($row.Images)
        [void]$item.SubItems.Add($row.Time.ToString("yyyy-MM-dd HH:mm:ss"))
        [void]$item.SubItems.Add($row.Source)
        $item.Tag = $row
        [void]$taskList.Items.Add($item)
    }
}

$saveButton.Add_Click({
    try {
        $resolvedInbox = Resolve-Directory -Path $inboxBox.Text -Label "图片下载目录"
        $resolvedLibrary = Resolve-Directory -Path $libraryBox.Text -Label "成品库目录"
        $resolvedPrefix = ([string]$prefixBox.Text).Trim().TrimStart('.')
        if ([string]::IsNullOrWhiteSpace($resolvedPrefix)) {
            throw "作品集名称前缀不能为空。"
        }
        Set-ObjectProperty -Object $config -Name "image_inbox_path" -Value $resolvedInbox
        Set-ObjectProperty -Object $config -Name "library_path" -Value $resolvedLibrary
        Set-ObjectProperty -Object $config -Name "portfolio_auto_group" -Value ([bool]$autoGroup.Checked)
        Set-ObjectProperty -Object $config -Name "portfolio_auto_zip" -Value ([bool]$autoZip.Checked)
        Set-ObjectProperty -Object $config -Name "portfolio_batch_size" -Value ([int]$batchSize.Value)
        Set-ObjectProperty -Object $config -Name "portfolio_prefix" -Value $resolvedPrefix
        Set-ObjectProperty -Object $config -Name "package_naming_mode" -Value ([string]$namingCombo.SelectedValue)
        Set-ObjectProperty -Object $config -Name "completion_open_folder" -Value ([bool]$openFolder.Checked)
        Set-ObjectProperty -Object $config -Name "completion_copy_path" -Value ([bool]$copyPath.Checked)
        Set-ObjectProperty -Object $config -Name "notification_duration_ms" -Value ([int]$toastDuration.Value)
        Write-Config -Config $config
        Refresh-DataSummary
        Show-Info "设置已保存。"
    } catch {
        Show-ErrorMessage $_.Exception.Message
    }
})

$flushButton.Add_Click({
    try {
        $result = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $corePath -FlushPortfolio -NoMessage
        Refresh-DataSummary
        $movedLine = @($result | Where-Object { $_ -like "Moved=*" } | Select-Object -First 1)
        $moved = if ($movedLine.Count) { $movedLine[0].Split('=')[1] } else { "0" }
        Show-Info "立即整理完成，共移动 $moved 个作品包。"
    } catch {
        Show-ErrorMessage $_.Exception.Message
    }
})

$taskRefresh.Add_Click({ Refresh-TaskList })
$taskRetry.Add_Click({
    if ($taskList.SelectedItems.Count -eq 0) { return }
    $row = $taskList.SelectedItems[0].Tag
    if ($row.Source -ne "inbox" -or [string]::IsNullOrWhiteSpace($row.BatchId)) {
        Show-Info "只有仍在下载目录里的等待、失败或图片不完整任务可以重试。"
        return
    }
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $corePath -BatchId $row.BatchId -ExpectedImageCount $row.ExpectedImages -NoMessage | Out-Null
        Refresh-TaskList
        Refresh-DataSummary
    } catch {
        Show-ErrorMessage $_.Exception.Message
    }
})
$taskOpen.Add_Click({
    if ($taskList.SelectedItems.Count -eq 0) { return }
    $path = [string]$taskList.SelectedItems[0].Tag.PackagePath
    if (Test-Path -LiteralPath $path) {
        Start-Process -FilePath "explorer.exe" -ArgumentList @("/select,`"$path`"")
    } else {
        Show-Info "这条任务还没有可打开的作品包。"
    }
})
$taskCopy.Add_Click({
    if ($taskList.SelectedItems.Count -eq 0) { return }
    $path = [string]$taskList.SelectedItems[0].Tag.PackagePath
    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = [string]$taskList.SelectedItems[0].Tag.RecordPath
    }
    Set-Clipboard -Value $path
    Show-Info "路径已复制。"
})
$taskRemove.Add_Click({
    if ($taskList.SelectedItems.Count -eq 0) { return }
    $row = $taskList.SelectedItems[0].Tag
    if ($row.Source -eq "package") {
        Show-Info "作品包内的任务溯源记录需要保留，不能在这里删除。"
        return
    }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "只移除这条任务记录，不删除图片或作品包。确定继续吗？",
        "GPT 作品助手",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($answer -eq [System.Windows.Forms.DialogResult]::Yes -and (Test-Path -LiteralPath $row.RecordPath)) {
        Remove-Item -LiteralPath $row.RecordPath -Force
        Refresh-TaskList
        Refresh-DataSummary
    }
})

$backupButton.Add_Click({
    try {
        $folder = New-Backup -Config $config
        Refresh-DataSummary
        Show-Info "备份已完成：`n$folder"
    } catch {
        Show-ErrorMessage $_.Exception.Message
    }
})
$openBackupButton.Add_Click({
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    }
    Start-Process -FilePath "explorer.exe" -ArgumentList @("`"$backupRoot`"")
})
$restoreButton.Add_Click({
    $latest = @(Get-ChildItem -LiteralPath $backupRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1)
    if ($latest.Count -eq 0) {
        Show-Info "还没有可恢复的备份。"
        return
    }
    $answer = [System.Windows.Forms.MessageBox]::Show(
        "将恢复最近备份：$($latest[0].Name)`n当前设置和历史库会先自动再备份一次。是否继续？",
        "GPT 作品助手",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    try {
        [void](New-Backup -Config $config)
        $restoreFolder = $latest[0].FullName
        $savedConfig = Join-Path $restoreFolder "workpkg_config.json"
        if (Test-Path -LiteralPath $savedConfig) {
            Copy-Item -LiteralPath $savedConfig -Destination $configPath -Force
        }
        $restoredConfig = Read-JsonFile -Path $configPath
        $historyPaths = Get-HistoryPaths -Config $restoredConfig
        foreach ($item in @(
            [pscustomobject]@{ Source = Join-Path $restoreFolder "history-primary.json"; Destination = $historyPaths.Primary },
            [pscustomobject]@{ Source = Join-Path $restoreFolder "history-backup.json"; Destination = $historyPaths.Backup },
            [pscustomobject]@{ Source = Join-Path $restoreFolder "history-runtime.json"; Destination = $historyPaths.Runtime }
        )) {
            if (Test-Path -LiteralPath $item.Source) {
                $parent = Split-Path -Parent $item.Destination
                if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }
                try {
                    Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Force
                } catch {
                    $destinationItem = Get-Item -LiteralPath $item.Destination -Force -ErrorAction SilentlyContinue
                    if ($null -ne $destinationItem) {
                        $destinationItem.Attributes = $destinationItem.Attributes -band (-bnot [System.IO.FileAttributes]::Hidden)
                    }
                    Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Force
                }
                if ($item.Destination -eq $historyPaths.Runtime) {
                    $runtimeItem = Get-Item -LiteralPath $item.Destination -Force
                    $runtimeItem.Attributes = $runtimeItem.Attributes -bor [System.IO.FileAttributes]::Hidden
                }
            }
        }
        Show-Info "最近备份已恢复。请重新打开助手中心查看最新设置。"
    } catch {
        Show-ErrorMessage $_.Exception.Message
    }
})

$tabs.SelectedTab = switch ($InitialTab) {
    "Tasks" { $tasksTab }
    "Data" { $dataTab }
    default { $settingsTab }
}
$tabs.Add_SelectedIndexChanged({
    if ($tabs.SelectedTab -eq $tasksTab) { Refresh-TaskList }
    if ($tabs.SelectedTab -eq $dataTab) { Refresh-DataSummary }
})

Refresh-TaskList
Refresh-DataSummary
[void]$form.ShowDialog()
