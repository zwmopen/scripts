param(
    [string]$LibraryPath,
    [switch]$NoMessage
)

$ErrorActionPreference = "Stop"
$configPath = Join-Path $PSScriptRoot "workpkg_config.json"

function New-TextFromCodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Show-LibraryPathEditor {
    param([string]$InitialPath)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = New-TextFromCodePoints @(0x8BBE, 0x7F6E, 0x4F5C, 0x54C1, 0x5305, 0x76EE, 0x5F55)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.ClientSize = New-Object System.Drawing.Size(680, 150)
    $form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)

    $label = New-Object System.Windows.Forms.Label
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(18, 18)
    $label.Text = New-TextFromCodePoints @(0x7C98, 0x8D34, 0x6216, 0x8F93, 0x5165, 0x5B8C, 0x6574, 0x6587, 0x4EF6, 0x5939, 0x5730, 0x5740)
    $form.Controls.Add($label)

    $pathBox = New-Object System.Windows.Forms.TextBox
    $pathBox.Location = New-Object System.Drawing.Point(20, 48)
    $pathBox.Size = New-Object System.Drawing.Size(535, 30)
    $pathBox.Text = $InitialPath
    $form.Controls.Add($pathBox)

    $browseButton = New-Object System.Windows.Forms.Button
    $browseButton.Location = New-Object System.Drawing.Point(565, 46)
    $browseButton.Size = New-Object System.Drawing.Size(95, 32)
    $browseButton.Text = New-TextFromCodePoints @(0x6D4F, 0x89C8, 0x9009, 0x62E9)
    $browseButton.Add_Click({
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = New-TextFromCodePoints @(0x9009, 0x62E9, 0x4F5C, 0x54C1, 0x5305, 0x4FDD, 0x5B58, 0x76EE, 0x5F55)
        $dialog.ShowNewFolderButton = $true
        if (Test-Path -LiteralPath $pathBox.Text -PathType Container) {
            $dialog.SelectedPath = $pathBox.Text
        }
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $pathBox.Text = $dialog.SelectedPath
        }
    })
    $form.Controls.Add($browseButton)

    $saveButton = New-Object System.Windows.Forms.Button
    $saveButton.Location = New-Object System.Drawing.Point(460, 98)
    $saveButton.Size = New-Object System.Drawing.Size(95, 34)
    $saveButton.Text = New-TextFromCodePoints @(0x4FDD, 0x5B58)
    $saveButton.Add_Click({
        if ([string]::IsNullOrWhiteSpace($pathBox.Text)) {
            $message = New-TextFromCodePoints @(0x8BF7, 0x7C98, 0x8D34, 0x6216, 0x8F93, 0x5165, 0x6587, 0x4EF6, 0x5939, 0x5730, 0x5740)
            [System.Windows.Forms.MessageBox]::Show($message, $form.Text) | Out-Null
            return
        }
        $form.Tag = $pathBox.Text.Trim().Trim([char[]]@(0x22, 0x27))
        $form.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $form.Close()
    })
    $form.Controls.Add($saveButton)

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Location = New-Object System.Drawing.Point(565, 98)
    $cancelButton.Size = New-Object System.Drawing.Size(95, 34)
    $cancelButton.Text = New-TextFromCodePoints @(0x53D6, 0x6D88)
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $form.Controls.Add($cancelButton)

    $form.AcceptButton = $saveButton
    $form.CancelButton = $cancelButton
    $form.Add_Shown({ $pathBox.Focus(); $pathBox.SelectAll() })

    if ($form.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        return [string]$form.Tag
    }
    return $null
}

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Configuration file is missing: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($LibraryPath)) {
    $currentPath = [Environment]::ExpandEnvironmentVariables(([string]$config.library_path).Trim())
    $LibraryPath = Show-LibraryPathEditor -InitialPath $currentPath
    if ([string]::IsNullOrWhiteSpace($LibraryPath)) {
        Write-Output "CANCELLED"
        exit 0
    }
}

$expandedPath = [Environment]::ExpandEnvironmentVariables($LibraryPath.Trim())
if (-not [System.IO.Path]::IsPathRooted($expandedPath)) {
    throw "LibraryPath must be an absolute path: $expandedPath"
}
$resolvedPath = [System.IO.Path]::GetFullPath($expandedPath)
if (-not (Test-Path -LiteralPath $resolvedPath -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedPath -Force | Out-Null
}

if ($null -eq $config.PSObject.Properties['library_path']) {
    $config | Add-Member -NotePropertyName library_path -NotePropertyValue $resolvedPath
} else {
    $config.library_path = $resolvedPath
}

$json = $config | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($configPath, $json, (New-Object System.Text.UTF8Encoding($true)))

Write-Output "LibraryPath=$resolvedPath"
if (-not $NoMessage) {
    Add-Type -AssemblyName PresentationFramework
    $message = (New-TextFromCodePoints @(0x4F5C, 0x54C1, 0x5305, 0x5C06, 0x4FDD, 0x5B58, 0x5230, 0xFF1A)) + "`n$resolvedPath"
    $title = New-TextFromCodePoints @(0x8BBE, 0x7F6E, 0x5DF2, 0x4FDD, 0x5B58)
    [System.Windows.MessageBox]::Show($message, $title, "OK", "Information") | Out-Null
}
