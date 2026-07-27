param(
    [string]$LibraryPath,
    [string]$ImageInboxPath,
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
        [string]$InitialLibrary
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "GPT 作品助手设置"
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(760, 300)
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)

    $intro = New-Object System.Windows.Forms.Label
    $intro.AutoSize = $true
    $intro.Location = New-Object System.Drawing.Point(20, 18)
    $intro.Text = "只需设置一次：图片下载目录负责接收，成品库负责长期保存。"
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

    $status = New-Object System.Windows.Forms.Label
    $status.AutoSize = $true
    $status.Location = New-Object System.Drawing.Point(22, 224)
    $status.ForeColor = [System.Drawing.Color]::FromArgb(72, 105, 92)
    $status.Text = "提示：两个目录可以不同，升级脚本不会覆盖这里的设置。"
    $form.Controls.Add($status)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Location = New-Object System.Drawing.Point(532, 250)
    $saveButton.Size = New-Object System.Drawing.Size(95, 34)
    $saveButton.Text = "保存"
    $saveButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($inboxBox.Text) -or [string]::IsNullOrWhiteSpace($libraryBox.Text)) {
            [System.Windows.Forms.MessageBox]::Show("两个目录都需要填写。", $form.Text) | Out-Null
            return
        }
        $form.Tag = [pscustomobject]@{
            ImageInboxPath = $inboxBox.Text
            LibraryPath = $libraryBox.Text
        }
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($saveButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(642, 250)
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
$currentInbox = [Environment]::ExpandEnvironmentVariables(([string]$config.image_inbox_path).Trim())
if ([string]::IsNullOrWhiteSpace($currentInbox)) {
    $currentInbox = Split-Path -Parent $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($LibraryPath) -and [string]::IsNullOrWhiteSpace($ImageInboxPath)) {
    $settings = Show-WorkPackageSettings -InitialInbox $currentInbox -InitialLibrary $currentLibrary
    if ($null -eq $settings) {
        Write-Output "CANCELLED"
        exit 0
    }
    $LibraryPath = [string]$settings.LibraryPath
    $ImageInboxPath = [string]$settings.ImageInboxPath
} else {
    if ([string]::IsNullOrWhiteSpace($LibraryPath)) {
        $LibraryPath = $currentLibrary
    }
    if ([string]::IsNullOrWhiteSpace($ImageInboxPath)) {
        $ImageInboxPath = $currentInbox
    }
}

$resolvedLibrary = Resolve-ConfiguredDirectory -Path $LibraryPath -Name "LibraryPath" -Create
$resolvedInbox = Resolve-ConfiguredDirectory -Path $ImageInboxPath -Name "ImageInboxPath" -Create

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

$json = $config | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($true)))

Write-Output "ImageInboxPath=$resolvedInbox"
Write-Output "LibraryPath=$resolvedLibrary"
if (-not $NoMessage) {
    Add-Type -AssemblyName PresentationFramework
    $message = "设置已保存。`n`n图片下载目录：$resolvedInbox`n成品库：$resolvedLibrary"
    [System.Windows.MessageBox]::Show($message, "GPT 作品助手", "OK", "Information") | Out-Null
}
