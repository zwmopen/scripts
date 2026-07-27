param(
    [ValidateSet("Settings", "Tasks", "Data")]
    [string]$InitialTab = "Settings",
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
Add-Type @"
using System.Runtime.InteropServices;
public static class WorkPkgDpiAwareness {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
"@
[void][WorkPkgDpiAwareness]::SetProcessDPIAware()
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$configPath = Join-Path $PSScriptRoot "workpkg_config.json"
$corePath = Join-Path $PSScriptRoot "make_work_package.ps1"
$runtimeHistoryPath = Join-Path $PSScriptRoot ".workpkg_history_backup.json"
$taskArchivePath = Join-Path $PSScriptRoot "任务记录"
$backupRoot = Join-Path $PSScriptRoot "备份"
$centerVersion = "1.8.2"

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

function Repair-LegacyConfig {
    param([object]$Config)

    $changed = $false
    $validNamingModes = @("title_conversation", "conversation_title", "title_only", "conversation_only")
    if ([string]$Config.package_naming_mode -notin $validNamingModes) {
        Set-ObjectProperty -Object $Config -Name "package_naming_mode" -Value "title_conversation"
        $changed = $true
    }
    return $changed
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
        # 作品包曾短暂继承临时目录的 Hidden 属性；-Force 可确保旧作品仍能被任务中心读取。
        # 同一作品目录若同时存在新旧记录，优先读取统一记录，避免显示成两条任务。
        $recordFiles = @(Get-ChildItem -LiteralPath $library -File -Recurse -Force -Filter "GPT*记录.json" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @("GPT作品记录.json", "GPT任务记录.json") } |
            Group-Object DirectoryName |
            ForEach-Object {
                $_.Group |
                    Sort-Object @{ Expression = { if ($_.Name -eq "GPT作品记录.json") { 0 } else { 1 } } }, @{ Expression = "LastWriteTime"; Descending = $true } |
                    Select-Object -First 1
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 80)
        foreach ($file in $recordFiles) {
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
$configWasRepaired = Repair-LegacyConfig -Config $config
if ($configWasRepaired -and -not $SelfTest) {
    Write-Config -Config $config
}

if ($SelfTest) {
    $historyPaths = Get-HistoryPaths -Config $config
    $history = Read-JsonFile -Path $historyPaths.Primary
    if ($null -eq $history) { $history = Read-JsonFile -Path $historyPaths.Runtime }
    Write-Output "CENTER_OK"
    Write-Output "Version=$centerVersion"
    Write-Output "ConfigRepaired=$configWasRepaired"
    Write-Output "TaskRows=$(@(Get-TaskRows -Config $config).Count)"
    Write-Output "HistoryEntries=$(if ($null -eq $history) { 0 } else { @($history.entries).Count })"
    exit 0
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "GPT 作品助手中心"
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(860, 650)
$form.Size = New-Object System.Drawing.Size(940, 700)
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10)
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = "Fill"
$form.Controls.Add($tabs)

$settingsTab = New-Object System.Windows.Forms.TabPage
$settingsTab.Text = "① 常用设置"
$settingsTab.AutoScroll = $true
$tasksTab = New-Object System.Windows.Forms.TabPage
$tasksTab.Text = "② 任务中心"
$dataTab = New-Object System.Windows.Forms.TabPage
$dataTab.Text = "③ 数据与恢复"
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

$toolTip = New-Object System.Windows.Forms.ToolTip
$toolTip.AutoPopDelay = 12000
$toolTip.InitialDelay = 350
$toolTip.ReshowDelay = 150

$welcomeLabel = Add-Label -Parent $settingsTab -Text "首次使用只需确认两个目录，再点「保存全部设置」。其余选项保持推荐值即可。" -Left 24 -Top 18 -Width 720
$welcomeLabel.ForeColor = [System.Drawing.Color]::FromArgb(46, 86, 112)
$helpButton = New-Object System.Windows.Forms.Button
$helpButton.Text = "怎么用？"
$helpButton.Location = New-Object System.Drawing.Point(800, 12)
$helpButton.Size = New-Object System.Drawing.Size(90, 32)
$settingsTab.Controls.Add($helpButton)

Add-Label -Parent $settingsTab -Text "图片下载目录（浏览器把图片下载到哪里）" -Left 24 -Top 58 -Width 380 | Out-Null
$inboxBox = New-Object System.Windows.Forms.TextBox
$inboxBox.Location = New-Object System.Drawing.Point(24, 86)
$inboxBox.Size = New-Object System.Drawing.Size(760, 30)
$inboxBox.Text = [string]$config.image_inbox_path
$settingsTab.Controls.Add($inboxBox)
$inboxBrowse = New-Object System.Windows.Forms.Button
$inboxBrowse.Text = "浏览"
$inboxBrowse.Location = New-Object System.Drawing.Point(800, 84)
$inboxBrowse.Size = New-Object System.Drawing.Size(90, 32)
$inboxBrowse.Add_Click({ Browse-Directory -TextBox $inboxBox -Description "选择浏览器下载图片的目录" })
$settingsTab.Controls.Add($inboxBrowse)
$toolTip.SetToolTip($inboxBox, "填写 Edge 或 Chrome 的实际下载位置，例如 D:\Download。支持直接粘贴完整路径。")

Add-Label -Parent $settingsTab -Text "成品库目录（整理完成后的作品长期放在哪里）" -Left 24 -Top 128 -Width 430 | Out-Null
$libraryBox = New-Object System.Windows.Forms.TextBox
$libraryBox.Location = New-Object System.Drawing.Point(24, 156)
$libraryBox.Size = New-Object System.Drawing.Size(760, 30)
$libraryBox.Text = [string]$config.library_path
$settingsTab.Controls.Add($libraryBox)
$libraryBrowse = New-Object System.Windows.Forms.Button
$libraryBrowse.Text = "浏览"
$libraryBrowse.Location = New-Object System.Drawing.Point(800, 154)
$libraryBrowse.Size = New-Object System.Drawing.Size(90, 32)
$libraryBrowse.Add_Click({ Browse-Directory -TextBox $libraryBox -Description "选择作品包成品库" })
$settingsTab.Controls.Add($libraryBrowse)
$toolTip.SetToolTip($libraryBox, "这是最终成品位置，不建议和浏览器下载目录设置成同一个文件夹。")

$groupBox = New-Object System.Windows.Forms.GroupBox
$groupBox.Text = "作品集整理（把若干作品包自动收进一个合集）"
$groupBox.Location = New-Object System.Drawing.Point(24, 206)
$groupBox.Size = New-Object System.Drawing.Size(866, 145)
$settingsTab.Controls.Add($groupBox)
$autoGroup = New-Object System.Windows.Forms.CheckBox
$autoGroup.Text = "凑满后自动整理"
$autoGroup.Location = New-Object System.Drawing.Point(18, 34)
$autoGroup.Size = New-Object System.Drawing.Size(145, 28)
$autoGroup.Checked = [bool]$config.portfolio_auto_group
$groupBox.Controls.Add($autoGroup)
Add-Label -Parent $groupBox -Text "每集包含" -Left 170 -Top 34 -Width 75 | Out-Null
$batchSize = New-Object System.Windows.Forms.NumericUpDown
$batchSize.Location = New-Object System.Drawing.Point(245, 30)
$batchSize.Minimum = 1
$batchSize.Maximum = 500
$batchSize.Value = [Math]::Max(1, [Math]::Min(500, [int]$config.portfolio_batch_size))
$groupBox.Controls.Add($batchSize)
Add-Label -Parent $groupBox -Text "个作品包；合集名称" -Left 300 -Top 34 -Width 145 | Out-Null
$prefixBox = New-Object System.Windows.Forms.TextBox
$prefixBox.Location = New-Object System.Drawing.Point(448, 30)
$prefixBox.Size = New-Object System.Drawing.Size(160, 30)
$prefixBox.Text = [string]$config.portfolio_prefix
$groupBox.Controls.Add($prefixBox)
$autoZip = New-Object System.Windows.Forms.CheckBox
$autoZip.Text = "同时生成 ZIP 压缩包"
$autoZip.Location = New-Object System.Drawing.Point(630, 34)
$autoZip.Size = New-Object System.Drawing.Size(190, 28)
$autoZip.Checked = [bool]$config.portfolio_auto_zip
$groupBox.Controls.Add($autoZip)
$flushButton = New-Object System.Windows.Forms.Button
$flushButton.Text = "现在就整理未满一集的作品"
$flushButton.Location = New-Object System.Drawing.Point(18, 78)
$flushButton.Size = New-Object System.Drawing.Size(220, 34)
$groupBox.Controls.Add($flushButton)
$nextNumberLabel = Add-Label -Parent $groupBox -Text "当前编号：读取中…" -Left 260 -Top 84 -Width 500
$toolTip.SetToolTip($flushButton, "不用等到设定数量凑满，立即把当前散落的作品包整理成一个作品集。")

$nameBox = New-Object System.Windows.Forms.GroupBox
$nameBox.Text = "文件夹命名与完成后动作"
$nameBox.Location = New-Object System.Drawing.Point(24, 367)
$nameBox.Size = New-Object System.Drawing.Size(866, 185)
$settingsTab.Controls.Add($nameBox)
Add-Label -Parent $nameBox -Text "文件夹名称使用" -Left 18 -Top 34 -Width 130 | Out-Null
$namingCombo = New-Object System.Windows.Forms.ComboBox
$namingCombo.DropDownStyle = "DropDownList"
$namingCombo.Location = New-Object System.Drawing.Point(160, 30)
$namingCombo.Size = New-Object System.Drawing.Size(450, 30)
$namingOptions = @(
    [pscustomobject]@{ Label = "文案标题（GPT 对话名）— 推荐，最容易找"; Value = "title_conversation" },
    [pscustomobject]@{ Label = "GPT 对话名（文案标题）— 模板名放前面"; Value = "conversation_title" },
    [pscustomobject]@{ Label = "只用文案标题— 名称最短"; Value = "title_only" },
    [pscustomobject]@{ Label = "只用 GPT 对话名— 同模板作品可能重名"; Value = "conversation_only" }
)
foreach ($option in $namingOptions) {
    [void]$namingCombo.Items.Add([string]$option.Label)
}
$selectedNamingIndex = 0
for ($optionIndex = 0; $optionIndex -lt $namingOptions.Count; $optionIndex++) {
    if ([string]$namingOptions[$optionIndex].Value -eq [string]$config.package_naming_mode) {
        $selectedNamingIndex = $optionIndex
        break
    }
}
$namingCombo.SelectedIndex = $selectedNamingIndex
$nameBox.Controls.Add($namingCombo)
$namingPreview = Add-Label -Parent $nameBox -Text "" -Left 160 -Top 64 -Width 670
$namingPreview.ForeColor = [System.Drawing.Color]::FromArgb(72, 105, 92)
$openFolder = New-Object System.Windows.Forms.CheckBox
$openFolder.Text = "打包完成后，自动打开成品所在位置"
$openFolder.Location = New-Object System.Drawing.Point(18, 104)
$openFolder.Size = New-Object System.Drawing.Size(310, 28)
$openFolder.Checked = [bool]$config.completion_open_folder
$nameBox.Controls.Add($openFolder)
$copyPath = New-Object System.Windows.Forms.CheckBox
$copyPath.Text = "完成后复制文件夹路径"
$copyPath.Location = New-Object System.Drawing.Point(350, 104)
$copyPath.Size = New-Object System.Drawing.Size(220, 28)
$copyPath.Checked = [bool]$config.completion_copy_path
$nameBox.Controls.Add($copyPath)
$copyPathWarning = Add-Label -Parent $nameBox -Text "连续做图时建议关闭：它会覆盖刚复制的下一篇文案。" -Left 350 -Top 135 -Width 430
$copyPathWarning.ForeColor = [System.Drawing.Color]::FromArgb(176, 92, 54)
Add-Label -Parent $nameBox -Text "完成提示停留" -Left 610 -Top 106 -Width 105 | Out-Null
$toastDuration = New-Object System.Windows.Forms.NumericUpDown
$toastDuration.Location = New-Object System.Drawing.Point(718, 102)
$toastDuration.Size = New-Object System.Drawing.Size(72, 30)
$toastDuration.DecimalPlaces = 1
$toastDuration.Minimum = [decimal]0.5
$toastDuration.Maximum = [decimal]10
$toastDuration.Increment = [decimal]0.5
$toastDuration.Value = [decimal]([Math]::Round(([Math]::Max(500, [Math]::Min(10000, [int]$config.notification_duration_ms)) / 1000), 1))
$nameBox.Controls.Add($toastDuration)
Add-Label -Parent $nameBox -Text "秒" -Left 794 -Top 106 -Width 30 | Out-Null

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = "保存全部设置"
$saveButton.Location = New-Object System.Drawing.Point(720, 575)
$saveButton.Size = New-Object System.Drawing.Size(170, 40)
$settingsTab.Controls.Add($saveButton)
$settingsHint = Add-Label -Parent $settingsTab -Text "推荐：连续生产时关闭「打开位置」和「复制路径」；精确图片查重会始终保护你不重复打包。" -Left 24 -Top 584 -Width 670
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
        "本地版本：$centerVersion"
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

function Update-NamingPreview {
    $sampleTitle = "上海团建路线怎么选"
    $sampleConversation = "秋冬年会封面模板"
    $selectedMode = if ($namingCombo.SelectedIndex -ge 0) {
        [string]$namingOptions[$namingCombo.SelectedIndex].Value
    } else {
        "title_conversation"
    }
    $sampleName = switch ($selectedMode) {
        "conversation_title" { "$sampleConversation（$sampleTitle）" }
        "title_only" { $sampleTitle }
        "conversation_only" { $sampleConversation }
        default { "$sampleTitle（$sampleConversation）" }
    }
    $namingPreview.Text = "实际示例：20260727_163006_$sampleName"
}

$namingCombo.Add_SelectedIndexChanged({ Update-NamingPreview })
Update-NamingPreview

$helpButton.Add_Click({
    Show-Info (@(
        "第一次使用，只做 3 步："
        ""
        "1. 图片下载目录：选择 Edge/Chrome 的下载位置。"
        "2. 成品库目录：选择作品最终长期保存的位置。"
        "3. 点击「保存全部设置」。"
        ""
        "日常使用：在 ChatGPT 复制文案，再点图片组旁边的下载打包按钮。"
        ""
        "作品集整理：凑满设定数量后自动归集；「现在就整理」可提前收尾。"
        "命名规则：直接看下方实际示例选择即可。"
        "完成动作：连续做图时建议都关闭，避免弹窗或覆盖下一篇文案。"
    ) -join [Environment]::NewLine)
})

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
        $selectedNamingMode = if ($namingCombo.SelectedIndex -ge 0) {
            [string]$namingOptions[$namingCombo.SelectedIndex].Value
        } else {
            "title_conversation"
        }
        Set-ObjectProperty -Object $config -Name "package_naming_mode" -Value $selectedNamingMode
        Set-ObjectProperty -Object $config -Name "completion_open_folder" -Value ([bool]$openFolder.Checked)
        Set-ObjectProperty -Object $config -Name "completion_copy_path" -Value ([bool]$copyPath.Checked)
        Set-ObjectProperty -Object $config -Name "notification_duration_ms" -Value ([int][Math]::Round(([decimal]$toastDuration.Value * 1000)))
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
