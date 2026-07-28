param(
    [string]$LibraryPath,
    [string]$PortfolioOutputPath,
    [string]$ImageInboxPath,
    [Nullable[int]]$PortfolioBatchSize,
    [Nullable[bool]]$PortfolioAutoGroup,
    [Nullable[bool]]$PortfolioAutoZip,
    [switch]$NoMessage
)

$ErrorActionPreference = "Stop"
$configPath = Join-Path $PSScriptRoot "workpkg_config.json"

function Resolve-ConfiguredDirectory {
    param(
        [string]$Path,
        [string]$Name,
        [switch]$Create
    )

    $expanded = [Environment]::ExpandEnvironmentVariables(([string]$Path).Trim().Trim([char[]]@(0x22, 0x27)))
    if ([string]::IsNullOrWhiteSpace($expanded)) {
        throw "$Name cannot be empty."
    }
    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        throw "$Name must be an absolute path: $expanded"
    }
    $resolved = [System.IO.Path]::GetFullPath($expanded)
    if ($Create -and -not (Test-Path -LiteralPath $resolved -PathType Container)) {
        New-Item -ItemType Directory -Path $resolved -Force | Out-Null
    }
    return $resolved
}

function Show-WorkPackageSettings {
    param(
        [string]$InitialInbox,
        [string]$InitialLibrary,
        [string]$InitialPortfolioOutput,
        [int]$InitialBatchSize,
        [bool]$InitialAutoGroup,
        [bool]$InitialAutoZip
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "GPT 作品助手设置"
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(760, 500)
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)

    $intro = New-Object System.Windows.Forms.Label
    $intro.AutoSize = $true
    $intro.Location = New-Object System.Drawing.Point(20, 18)
    $intro.Text = "只需设置一次：图片负责接收，成品库放散装作品，作品集目录放整理后的合集。"
    $form.Controls.Add($intro)

    function Add-PathRow {
        param(
            [string]$Label,
            [string]$InitialValue,
            [int]$Top,
            [string]$DialogDescription
        )

        $labelControl = New-Object System.Windows.Forms.Label
        $labelControl.AutoSize = $true
        $labelControl.Location = New-Object System.Drawing.Point(20, $Top)
        $labelControl.Text = $Label
        $form.Controls.Add($labelControl)

        $box = New-Object System.Windows.Forms.TextBox
        $box.Location = New-Object System.Drawing.Point(22, ($Top + 28))
        $box.Size = New-Object System.Drawing.Size(610, 30)
        $box.Text = $InitialValue
        $form.Controls.Add($box)

        $button = New-Object System.Windows.Forms.Button
        $button.Location = New-Object System.Drawing.Point(642, ($Top + 26))
        $button.Size = New-Object System.Drawing.Size(95, 32)
        $button.Text = "浏览选择"
        $button.Add_Click({
            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description = $DialogDescription
            $dialog.ShowNewFolderButton = $true
            if (Test-Path -LiteralPath $box.Text -PathType Container) {
                $dialog.SelectedPath = $box.Text
            }
            if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $box.Text = $dialog.SelectedPath
            }
        }.GetNewClosure())
        $form.Controls.Add($button)
        return $box
    }

    $inboxBox = Add-PathRow `
        -Label "图片下载目录（Edge 实际保存图片的位置）" `
        -InitialValue $InitialInbox `
        -Top 58 `
        -DialogDescription "选择浏览器下载 ChatGPT 图片的目录"

    $libraryBox = Add-PathRow `
        -Label "成品库目录（整理后的作品长期保存在这里）" `
        -InitialValue $InitialLibrary `
        -Top 138 `
        -DialogDescription "选择作品包成品库目录"

    $portfolioBox = Add-PathRow `
        -Label "作品集目录（凑满后把合集放在哪里；不单独设置时跟随成品库）" `
        -InitialValue $InitialPortfolioOutput `
        -Top 218 `
        -DialogDescription "选择整理后的作品集保存目录"

    $groupLabel = New-Object System.Windows.Forms.Label
    $groupLabel.AutoSize = $true
    $groupLabel.Location = New-Object System.Drawing.Point(22, 304)
    $groupLabel.Text = "作品集整理规则"
    $form.Controls.Add($groupLabel)

    $autoGroupBox = New-Object System.Windows.Forms.CheckBox
    $autoGroupBox.AutoSize = $true
    $autoGroupBox.Location = New-Object System.Drawing.Point(22, 338)
    $autoGroupBox.Text = "自动整理作品集"
    $autoGroupBox.Checked = $InitialAutoGroup
    $form.Controls.Add($autoGroupBox)

    $batchLabel = New-Object System.Windows.Forms.Label
    $batchLabel.AutoSize = $true
    $batchLabel.Location = New-Object System.Drawing.Point(190, 340)
    $batchLabel.Text = "每个作品集包含"
    $form.Controls.Add($batchLabel)

    $batchSizeBox = New-Object System.Windows.Forms.NumericUpDown
    $batchSizeBox.Location = New-Object System.Drawing.Point(310, 336)
    $batchSizeBox.Size = New-Object System.Drawing.Size(70, 30)
    $batchSizeBox.Minimum = 1
    $batchSizeBox.Maximum = 500
    $batchSizeBox.Value = [Math]::Max(1, [Math]::Min(500, $InitialBatchSize))
    $form.Controls.Add($batchSizeBox)

    $batchUnit = New-Object System.Windows.Forms.Label
    $batchUnit.AutoSize = $true
    $batchUnit.Location = New-Object System.Drawing.Point(389, 340)
    $batchUnit.Text = "个作品包"
    $form.Controls.Add($batchUnit)

    $autoZipBox = New-Object System.Windows.Forms.CheckBox
    $autoZipBox.AutoSize = $true
    $autoZipBox.Location = New-Object System.Drawing.Point(500, 338)
    $autoZipBox.Text = "同时生成 ZIP"
    $autoZipBox.Checked = $InitialAutoZip
    $form.Controls.Add($autoZipBox)

    $autoGroupBox.Add_CheckedChanged({
        $batchSizeBox.Enabled = $autoGroupBox.Checked
        $autoZipBox.Enabled = $autoGroupBox.Checked
    })
    $batchSizeBox.Enabled = $autoGroupBox.Checked
    $autoZipBox.Enabled = $autoGroupBox.Checked

    $ruleHint = New-Object System.Windows.Forms.Label
    $ruleHint.AutoSize = $true
    $ruleHint.Location = New-Object System.Drawing.Point(22, 376)
    $ruleHint.ForeColor = [System.Drawing.Color]::FromArgb(72, 105, 92)
    $ruleHint.Text = "例如设为 14：每累计 14 个作品包，自动创建下一个连续编号的作品集。"
    $form.Controls.Add($ruleHint)

    $status = New-Object System.Windows.Forms.Label
    $status.AutoSize = $true
    $status.Location = New-Object System.Drawing.Point(22, 414)
    $status.ForeColor = [System.Drawing.Color]::FromArgb(72, 105, 92)
    $status.Text = "设置保存在本地运行数据中，升级脚本不会覆盖。"
    $form.Controls.Add($status)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Location = New-Object System.Drawing.Point(532, 448)
    $saveButton.Size = New-Object System.Drawing.Size(95, 34)
    $saveButton.Text = "保存"
    $saveButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($inboxBox.Text) -or [string]::IsNullOrWhiteSpace($libraryBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("图片下载目录和成品库目录都需要填写。", $form.Text) | Out-Null
            return
        }
        $form.Tag = [pscustomobject]@{
            ImageInboxPath = $inboxBox.Text
            LibraryPath = $libraryBox.Text
            PortfolioOutputPath = $portfolioBox.Text
            PortfolioBatchSize = [int]$batchSizeBox.Value
            PortfolioAutoGroup = [bool]$autoGroupBox.Checked
            PortfolioAutoZip = [bool]$autoZipBox.Checked
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($saveButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(642, 448)
    $cancelButton.Size = New-Object System.Drawing.Size(95, 34)
    $cancelButton.Text = "取消"
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $saveButton
    $form.CancelButton = $cancelButton
    $form.Add_Shown({ $inboxBox.Focus(); $inboxBox.SelectAll() })

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return $form.Tag
    }
    return $null
}

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Configuration file is missing: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$currentLibrary = [Environment]::ExpandEnvironmentVariables(([string]$config.library_path).Trim())
$currentPortfolioOutput = if ($null -ne $config.PSObject.Properties['portfolio_output_path']) {
    [Environment]::ExpandEnvironmentVariables(([string]$config.portfolio_output_path).Trim())
} else {
    ""
}
if ([string]::IsNullOrWhiteSpace($currentPortfolioOutput)) {
    $currentPortfolioOutput = $currentLibrary
}
$currentInbox = [Environment]::ExpandEnvironmentVariables(([string]$config.image_inbox_path).Trim())
$currentBatchSize = if ($null -ne $config.PSObject.Properties['portfolio_batch_size']) {
    [Math]::Max(1, [int]$config.portfolio_batch_size)
} else {
    14
}
$currentAutoGroup = if ($null -ne $config.PSObject.Properties['portfolio_auto_group']) {
    [bool]$config.portfolio_auto_group
} else {
    $true
}
$currentAutoZip = if ($null -ne $config.PSObject.Properties['portfolio_auto_zip']) {
    [bool]$config.portfolio_auto_zip
} else {
    $false
}
if ([string]::IsNullOrWhiteSpace($currentInbox)) {
    $currentInbox = Split-Path -Parent $PSScriptRoot
}

$hasDirectSettings = (
    $PSBoundParameters.ContainsKey('LibraryPath') -or
    $PSBoundParameters.ContainsKey('PortfolioOutputPath') -or
    $PSBoundParameters.ContainsKey('ImageInboxPath') -or
    $PSBoundParameters.ContainsKey('PortfolioBatchSize') -or
    $PSBoundParameters.ContainsKey('PortfolioAutoGroup') -or
    $PSBoundParameters.ContainsKey('PortfolioAutoZip')
)

if (-not $hasDirectSettings) {
    $settings = Show-WorkPackageSettings `
        -InitialInbox $currentInbox `
        -InitialLibrary $currentLibrary `
        -InitialPortfolioOutput $currentPortfolioOutput `
        -InitialBatchSize $currentBatchSize `
        -InitialAutoGroup $currentAutoGroup `
        -InitialAutoZip $currentAutoZip
    if ($null -eq $settings) {
        Write-Output "CANCELLED"
        exit 0
    }
    $LibraryPath = [string]$settings.LibraryPath
    $PortfolioOutputPath = [string]$settings.PortfolioOutputPath
    $ImageInboxPath = [string]$settings.ImageInboxPath
    $PortfolioBatchSize = [int]$settings.PortfolioBatchSize
    $PortfolioAutoGroup = [bool]$settings.PortfolioAutoGroup
    $PortfolioAutoZip = [bool]$settings.PortfolioAutoZip
} else {
    if ([string]::IsNullOrWhiteSpace($LibraryPath)) {
        $LibraryPath = $currentLibrary
    }
    if ([string]::IsNullOrWhiteSpace($ImageInboxPath)) {
        $ImageInboxPath = $currentInbox
    }
    if ([string]::IsNullOrWhiteSpace($PortfolioOutputPath)) {
        $PortfolioOutputPath = $currentPortfolioOutput
    }
    if (-not $PSBoundParameters.ContainsKey('PortfolioBatchSize')) {
        $PortfolioBatchSize = $currentBatchSize
    }
    if (-not $PSBoundParameters.ContainsKey('PortfolioAutoGroup')) {
        $PortfolioAutoGroup = $currentAutoGroup
    }
    if (-not $PSBoundParameters.ContainsKey('PortfolioAutoZip')) {
        $PortfolioAutoZip = $currentAutoZip
    }
}

$resolvedLibrary = Resolve-ConfiguredDirectory -Path $LibraryPath -Name "LibraryPath" -Create
$resolvedInbox = Resolve-ConfiguredDirectory -Path $ImageInboxPath -Name "ImageInboxPath" -Create
$resolvedPortfolioOutput = Resolve-ConfiguredDirectory -Path $PortfolioOutputPath -Name "PortfolioOutputPath" -Create

if ($null -eq $config.PSObject.Properties['library_path']) {
    $config | Add-Member -NotePropertyName library_path -NotePropertyValue $resolvedLibrary
} else {
    $config.library_path = $resolvedLibrary
}
if ($null -eq $config.PSObject.Properties['image_inbox_path']) {
    $config | Add-Member -NotePropertyName image_inbox_path -NotePropertyValue $resolvedInbox
} else {
    $config.image_inbox_path = $resolvedInbox
}
if ($null -eq $config.PSObject.Properties['portfolio_output_path']) {
    $config | Add-Member -NotePropertyName portfolio_output_path -NotePropertyValue $resolvedPortfolioOutput
} else {
    $config.portfolio_output_path = $resolvedPortfolioOutput
}
$resolvedBatchSize = [Math]::Max(1, [Math]::Min(500, [int]$PortfolioBatchSize))
foreach ($setting in @(
    [pscustomobject]@{ Name = 'portfolio_batch_size'; Value = $resolvedBatchSize },
    [pscustomobject]@{ Name = 'portfolio_auto_group'; Value = [bool]$PortfolioAutoGroup },
    [pscustomobject]@{ Name = 'portfolio_auto_zip'; Value = [bool]$PortfolioAutoZip }
)) {
    if ($null -eq $config.PSObject.Properties[$setting.Name]) {
        $config | Add-Member -NotePropertyName $setting.Name -NotePropertyValue $setting.Value
    } else {
        $config.($setting.Name) = $setting.Value
    }
}

$json = $config | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($true)))

Write-Output "ImageInboxPath=$resolvedInbox"
Write-Output "LibraryPath=$resolvedLibrary"
Write-Output "PortfolioOutputPath=$resolvedPortfolioOutput"
Write-Output "PortfolioBatchSize=$resolvedBatchSize"
Write-Output "PortfolioAutoGroup=$([bool]$PortfolioAutoGroup)"
Write-Output "PortfolioAutoZip=$([bool]$PortfolioAutoZip)"
if (-not $NoMessage) {
    Add-Type -AssemblyName PresentationFramework
    $groupSummary = if ([bool]$PortfolioAutoGroup) {
        "每 $resolvedBatchSize 个作品包自动整理一个作品集；ZIP：$(if ([bool]$PortfolioAutoZip) { '开启' } else { '关闭' })"
    } else {
        "自动整理作品集：关闭"
    }
    $message = "设置已保存。`n`n图片下载目录：$resolvedInbox`n成品库：$resolvedLibrary`n作品集目录：$resolvedPortfolioOutput`n$groupSummary"
    [System.Windows.MessageBox]::Show($message, "GPT 作品助手", "OK", "Information") | Out-Null
}
