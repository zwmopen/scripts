param(
    [ValidateSet("Save", "SavePrompt", "Restore", "Menu", "List")]
    [string]$Mode = "Restore",
    [string]$LayoutName = "素材处理布局",
    [string]$ConfigPath = "",
    [string]$LayoutDir = (Join-Path $PSScriptRoot "layouts"),
    [string]$ShortcutDir = (Join-Path $PSScriptRoot "布局入口"),
    [switch]$NoToast
)

$ErrorActionPreference = "Stop"

function New-TextFromCodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

$nativeAssemblyPath = Join-Path $PSScriptRoot "WindowLayoutNative.v2.dll"
$nativeTypeDefinition = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public class WindowLayoutNative {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32.dll")]
    public static extern bool ShowWindowAsync(IntPtr hWnd, int nCmdShow);
}
'@

if (-not ([System.Management.Automation.PSTypeName]"WindowLayoutNative").Type) {
    if (Test-Path -LiteralPath $nativeAssemblyPath) {
        Add-Type -Path $nativeAssemblyPath
    } else {
        Add-Type -TypeDefinition $nativeTypeDefinition -OutputAssembly $nativeAssemblyPath -OutputType Library
        if (-not ([System.Management.Automation.PSTypeName]"WindowLayoutNative").Type) {
            Add-Type -Path $nativeAssemblyPath
        }
    }
}

function Show-LayoutToast {
    param([string]$Message)

    if ($NoToast) {
        return
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $form = New-Object System.Windows.Forms.Form
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $form.Width = 360
        $form.Height = 86
        $form.TopMost = $true
        $form.BackColor = [System.Drawing.Color]::FromArgb(248, 252, 249)
        $form.ShowInTaskbar = $false

        $bar = New-Object System.Windows.Forms.Panel
        $bar.Width = 7
        $bar.Dock = [System.Windows.Forms.DockStyle]::Left
        $bar.BackColor = [System.Drawing.Color]::FromArgb(32, 140, 89)
        $form.Controls.Add($bar)

        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Message
        $label.AutoSize = $false
        $label.Dock = [System.Windows.Forms.DockStyle]::Fill
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $label.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 11, [System.Drawing.FontStyle]::Regular)
        $label.ForeColor = [System.Drawing.Color]::FromArgb(28, 86, 58)
        $form.Controls.Add($label)

        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1100
        $timer.Add_Tick({
            $timer.Stop()
            $form.Close()
        })

        $form.Add_Shown({ $timer.Start() })
        [System.Windows.Forms.Application]::Run($form)
    } catch {
        Write-Output $Message
    }
}

function ConvertTo-SafeLayoutName {
    param([string]$Name)

    $safe = if ([string]::IsNullOrWhiteSpace($Name)) { "未命名布局" } else { $Name.Trim() }
    $safe = $safe -replace '[\x00-\x1F<>:"/\\|?*]', '_'
    $safe = $safe.Trim(" .")
    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "未命名布局"
    }

    return $safe
}

function Get-LayoutConfigPath {
    param([string]$Name)

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        return $ConfigPath
    }

    if (-not (Test-Path -LiteralPath $LayoutDir)) {
        New-Item -ItemType Directory -Force -Path $LayoutDir | Out-Null
    }

    $safeName = ConvertTo-SafeLayoutName -Name $Name
    return Join-Path $LayoutDir "$safeName.json"
}

function Get-SavedLayouts {
    if (-not (Test-Path -LiteralPath $LayoutDir)) {
        return @()
    }

    $layouts = @()
    foreach ($file in (Get-ChildItem -LiteralPath $LayoutDir -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try {
            $raw = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
            $config = $raw | ConvertFrom-Json
            $name = if ([string]::IsNullOrWhiteSpace($config.name)) { [System.IO.Path]::GetFileNameWithoutExtension($file.Name) } else { [string]$config.name }
            $count = @($config.items).Count
            $layouts += [pscustomobject]@{
                Name = $name
                Path = $file.FullName
                SavedAt = [string]$config.saved_at
                Count = $count
                Display = "$name  ($count 个窗口)"
            }
        } catch {
        }
    }

    return $layouts
}

function New-LayoutShortcut {
    param(
        [string]$Name,
        [string]$LayoutPath
    )

    if (-not (Test-Path -LiteralPath $ShortcutDir)) {
        New-Item -ItemType Directory -Force -Path $ShortcutDir | Out-Null
    }

    $safeName = ConvertTo-SafeLayoutName -Name $Name
    $shortcutPath = Join-Path $ShortcutDir "打开-$safeName.vbs"
    $layoutPathForVbs = $LayoutPath.Replace('"', '""')

    $vbsTemplate = @'
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptPath = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName)) & "\WindowLayout.ps1"
layoutPath = "__LAYOUT_PATH__"
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & scriptPath & Chr(34) & " -Mode Restore -ConfigPath " & Chr(34) & layoutPath & Chr(34)

shell.Run command, 0, False
'@
    $vbs = $vbsTemplate.Replace("__LAYOUT_PATH__", $layoutPathForVbs)

    [System.IO.File]::WriteAllText($shortcutPath, $vbs, [System.Text.UTF8Encoding]::new($true))
    return $shortcutPath
}

function Show-LayoutNamePrompt {
    param([string]$DefaultName = "新布局")

    try {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $title = "保存窗口布局"
        $message = "给这个窗口布局起个名字："
        $name = [Microsoft.VisualBasic.Interaction]::InputBox($message, $title, $DefaultName)
        if ([string]::IsNullOrWhiteSpace($name)) {
            return $null
        }

        return $name.Trim()
    } catch {
        return $DefaultName
    }
}

function Get-TopLevelWindows {
    $items = New-Object System.Collections.Generic.List[object]

    [WindowLayoutNative]::EnumWindows({
        param([IntPtr]$hWnd, [IntPtr]$lParam)

        if (-not [WindowLayoutNative]::IsWindowVisible($hWnd)) {
            return $true
        }
        $isMinimized = [WindowLayoutNative]::IsIconic($hWnd)

        $length = [WindowLayoutNative]::GetWindowTextLength($hWnd)
        if ($length -le 0) {
            return $true
        }

        $builder = New-Object System.Text.StringBuilder ($length + 1)
        [void][WindowLayoutNative]::GetWindowText($hWnd, $builder, $builder.Capacity)
        $title = $builder.ToString()
        if ([string]::IsNullOrWhiteSpace($title)) {
            return $true
        }

        $rect = New-Object WindowLayoutNative+RECT
        if (-not [WindowLayoutNative]::GetWindowRect($hWnd, [ref]$rect)) {
            return $true
        }

        $width = $rect.Right - $rect.Left
        $height = $rect.Bottom - $rect.Top
        if (-not $isMinimized -and ($width -lt 100 -or $height -lt 80)) {
            return $true
        }

        $pidOut = 0
        [void][WindowLayoutNative]::GetWindowThreadProcessId($hWnd, [ref]$pidOut)
        $process = Get-Process -Id $pidOut -ErrorAction SilentlyContinue
        if ($null -eq $process) {
            return $true
        }

        $items.Add([pscustomobject]@{
            Hwnd = $hWnd.ToInt64()
            Process = $process.ProcessName
            PID = $pidOut
            Title = $title
            X = $rect.Left
            Y = $rect.Top
            W = $width
            H = $height
            ExePath = $process.Path
            IsMinimized = $isMinimized
        })

        return $true
    }, [IntPtr]::Zero) | Out-Null

    return $items
}

function Get-ExplorerWindows {
    param(
        $TopWindows = $null,
        [switch]$IncludeMinimized
    )

    $result = @()
    try {
        if ($null -eq $TopWindows) {
            $TopWindows = Get-TopLevelWindows
        }

        $visibleExplorerHwnds = @(
            $TopWindows |
                Where-Object { $_.Process -ieq "explorer" -and $_.Title -ne "Program Manager" -and ($IncludeMinimized -or -not $_.IsMinimized) } |
                ForEach-Object { [int64]$_.Hwnd }
        )
        $shell = New-Object -ComObject Shell.Application
        foreach ($window in @($shell.Windows())) {
            try {
                $fileName = [System.IO.Path]::GetFileName($window.FullName)
                if (-not [string]::Equals($fileName, "explorer.exe", [System.StringComparison]::OrdinalIgnoreCase)) {
                    continue
                }

                $path = $window.Document.Folder.Self.Path
                if ([string]::IsNullOrWhiteSpace($path)) {
                    continue
                }

                $hWnd = [IntPtr]([int64]$window.HWND)
                if ($visibleExplorerHwnds -notcontains $hWnd.ToInt64()) {
                    continue
                }

                $rect = New-Object WindowLayoutNative+RECT
                if (-not [WindowLayoutNative]::GetWindowRect($hWnd, [ref]$rect)) {
                    continue
                }

                $result += [pscustomobject]@{
                    Hwnd = $hWnd.ToInt64()
                    Path = $path
                    X = $rect.Left
                    Y = $rect.Top
                    W = $rect.Right - $rect.Left
                    H = $rect.Bottom - $rect.Top
                }
            } catch {
            }
        }
    } catch {
    }

    return $result
}

function Move-WindowToRect {
    param(
        [IntPtr]$Hwnd,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H
    )

    if ($Hwnd -eq [IntPtr]::Zero -or $W -le 0 -or $H -le 0) {
        return $false
    }

    $wasMinimized = [WindowLayoutNative]::IsIconic($Hwnd)
    [void][WindowLayoutNative]::ShowWindowAsync($Hwnd, 9)
    if ($wasMinimized) {
        Start-Sleep -Milliseconds 60
    }
    return [WindowLayoutNative]::MoveWindow($Hwnd, $X, $Y, $W, $H, $true)
}

function Wait-ForResult {
    param(
        [scriptblock]$ScriptBlock,
        [int]$TimeoutMs = 3500,
        [int]$PollMs = 100
    )

    $start = Get-Date
    do {
        $value = & $ScriptBlock
        if ($null -ne $value) {
            return $value
        }
        Start-Sleep -Milliseconds $PollMs
    } while (((Get-Date) - $start).TotalMilliseconds -lt $TimeoutMs)

    return $null
}

function Find-ExplorerInWindows {
    param(
        $Windows,
        [string]$Path
    )

    $target = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    return $Windows |
        Where-Object { [System.IO.Path]::GetFullPath($_.Path).TrimEnd('\') -ieq $target } |
        Select-Object -First 1
}

function Find-ExplorerByPath {
    param([string]$Path)

    return Find-ExplorerInWindows -Windows (Get-ExplorerWindows -IncludeMinimized) -Path $Path
}

function Start-OrFindExplorer {
    param(
        [string]$Path,
        $ExistingWindows = @()
    )

    $existing = Find-ExplorerInWindows -Windows $ExistingWindows -Path $Path
    if ($null -ne $existing) {
        return $existing.Hwnd
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    Start-Process explorer.exe -ArgumentList @($Path) | Out-Null
    $created = Wait-ForResult -TimeoutMs 3500 -PollMs 100 -ScriptBlock {
        Find-ExplorerByPath -Path $Path
    }

    if ($null -eq $created) {
        return $null
    }

    return $created.Hwnd
}

function Find-BrowserWindow {
    param(
        $Windows = $null,
        [string]$ProcessName,
        [string]$TitleKeyword,
        [int64[]]$ExcludeHwnd = @()
    )

    if ($null -eq $Windows) {
        $Windows = Get-TopLevelWindows
    }

    $windows = $Windows |
        Where-Object { $_.Process -ieq $ProcessName -and ($ExcludeHwnd -notcontains [int64]$_.Hwnd) }

    if (-not [string]::IsNullOrWhiteSpace($TitleKeyword)) {
        $match = $windows |
            Where-Object { $_.Title -like "*$TitleKeyword*" } |
            Sort-Object X, Y |
            Select-Object -First 1
        if ($null -ne $match) {
            return $match
        }
    }

    return $windows | Sort-Object X, Y | Select-Object -First 1
}

function Start-OrFindBrowser {
    param(
        [string]$Browser,
        [string]$ExePath,
        [string]$Url,
        [string]$TitleKeyword,
        $ExistingWindows = @(),
        [int64[]]$ExcludeHwnd = @()
    )

    $processName = if ($Browser -ieq "edge") { "msedge" } elseif ($Browser -ieq "chrome") { "chrome" } else { $Browser }
    $existing = Find-BrowserWindow -Windows $ExistingWindows -ProcessName $processName -TitleKeyword $TitleKeyword -ExcludeHwnd $ExcludeHwnd
    if ($null -ne $existing) {
        return $existing.Hwnd
    }

    $before = @($ExistingWindows | Where-Object { $_.Process -ieq $processName } | ForEach-Object { [int64]$_.Hwnd })

    $launchPath = $ExePath
    if ([string]::IsNullOrWhiteSpace($launchPath) -or -not (Test-Path -LiteralPath $launchPath)) {
        $launchPath = if ($processName -ieq "msedge") { "msedge.exe" } else { "chrome.exe" }
    }

    $targetUrl = if ([string]::IsNullOrWhiteSpace($Url)) { "https://chatgpt.com/" } else { $Url }
    Start-Process -FilePath $launchPath -ArgumentList @("--new-window", $targetUrl) | Out-Null

    $created = Wait-ForResult -TimeoutMs 4500 -PollMs 100 -ScriptBlock {
        $latestWindows = Get-TopLevelWindows
        $newWindow = $latestWindows |
            Where-Object { $_.Process -ieq $processName -and ($before -notcontains [int64]$_.Hwnd) } |
            Sort-Object X, Y |
            Select-Object -First 1
        if ($null -ne $newWindow) {
            return $newWindow
        }

        return Find-BrowserWindow -Windows $latestWindows -ProcessName $processName -TitleKeyword $TitleKeyword -ExcludeHwnd $ExcludeHwnd
    }

    if ($null -eq $created) {
        return $null
    }

    return $created.Hwnd
}

function Save-CurrentLayout {
    param([string]$Name = $LayoutName)

    $items = @()

    foreach ($window in (Get-ExplorerWindows | Sort-Object X, Y)) {
        $items += [ordered]@{
            kind = "explorer"
            path = $window.Path
            x = $window.X
            y = $window.Y
            w = $window.W
            h = $window.H
        }
    }

    $browserWindows = Get-TopLevelWindows |
        Where-Object {
            ($_.Process -ieq "msedge" -or $_.Process -ieq "chrome") -and
            ($_.Title -like "*ChatGPT*") -and
            (-not $_.IsMinimized)
        } |
        Sort-Object X, Y

    foreach ($window in $browserWindows) {
        $browser = if ($window.Process -ieq "msedge") { "edge" } else { "chrome" }
        $items += [ordered]@{
            kind = "browser"
            browser = $browser
            exe_path = $window.ExePath
            url = "https://chatgpt.com/"
            title_keyword = "ChatGPT"
            x = $window.X
            y = $window.Y
            w = $window.W
            h = $window.H
        }
    }

    $displayName = ConvertTo-SafeLayoutName -Name $Name
    $targetConfigPath = Get-LayoutConfigPath -Name $displayName

    $config = [ordered]@{
        name = $displayName
        saved_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        items = $items
    }

    $json = $config | ConvertTo-Json -Depth 6
    [System.IO.File]::WriteAllText($targetConfigPath, $json, [System.Text.UTF8Encoding]::new($true))
    $shortcutPath = New-LayoutShortcut -Name $displayName -LayoutPath $targetConfigPath

    $message = if ($items.Count -gt 0) {
        (New-TextFromCodePoints @(0x5DF2, 0x4FDD, 0x5B58, 0x7A97, 0x53E3, 0x5E03, 0x5C40)) + " $displayName ($($items.Count))"
    } else {
        New-TextFromCodePoints @(0x672A, 0x627E, 0x5230, 0x53EF, 0x4FDD, 0x5B58, 0x7684, 0x7A97, 0x53E3)
    }
    Show-LayoutToast -Message $message
    $config["shortcut"] = $shortcutPath
    return $config
}

function Restore-Layout {
    param([string]$Name = $LayoutName)

    $targetConfigPath = Get-LayoutConfigPath -Name $Name

    if (-not (Test-Path -LiteralPath $targetConfigPath)) {
        Show-LayoutToast -Message (New-TextFromCodePoints @(0x8BF7, 0x5148, 0x4FDD, 0x5B58, 0x7A97, 0x53E3, 0x5E03, 0x5C40))
        return
    }

    $raw = [System.IO.File]::ReadAllText($targetConfigPath, [System.Text.Encoding]::UTF8)
    $config = $raw | ConvertFrom-Json
    $ok = 0
    $failed = 0
    $topWindows = Get-TopLevelWindows
    $explorerWindows = Get-ExplorerWindows -TopWindows $topWindows -IncludeMinimized
    $usedHwnd = @()

    foreach ($item in @($config.items)) {
        $hwnd = $null
        if ($item.kind -eq "explorer") {
            $hwnd = Start-OrFindExplorer -Path ([string]$item.path) -ExistingWindows $explorerWindows
        } elseif ($item.kind -eq "browser") {
            $hwnd = Start-OrFindBrowser -Browser ([string]$item.browser) -ExePath ([string]$item.exe_path) -Url ([string]$item.url) -TitleKeyword ([string]$item.title_keyword) -ExistingWindows $topWindows -ExcludeHwnd $usedHwnd
        }

        if ($null -eq $hwnd) {
            $failed++
            continue
        }

        $moved = Move-WindowToRect -Hwnd ([IntPtr]([int64]$hwnd)) -X ([int]$item.x) -Y ([int]$item.y) -W ([int]$item.w) -H ([int]$item.h)
        if ($moved) {
            $ok++
            $usedHwnd += [int64]$hwnd
        } else {
            $failed++
        }
    }

    $message = if ($failed -gt 0) {
        (New-TextFromCodePoints @(0x5DF2, 0x6062, 0x590D, 0x7A97, 0x53E3)) + " $ok, " + (New-TextFromCodePoints @(0x5931, 0x8D25)) + " $failed"
    } else {
        (New-TextFromCodePoints @(0x5DF2, 0x6062, 0x590D, 0x7A97, 0x53E3, 0x5E03, 0x5C40)) + " $ok"
    }

    Show-LayoutToast -Message $message
}

function Update-LayoutListBox {
    param($ListBox)

    $ListBox.Items.Clear()
    foreach ($layout in (Get-SavedLayouts)) {
        [void]$ListBox.Items.Add($layout)
    }

    if ($ListBox.Items.Count -gt 0) {
        $ListBox.SelectedIndex = 0
    }
}

function Show-LayoutMenu {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $form = New-Object System.Windows.Forms.Form
        $form.Text = "窗口布局中心"
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
        $form.Width = 520
        $form.Height = 420
        $form.MinimumSize = New-Object System.Drawing.Size(480, 360)
        $form.BackColor = [System.Drawing.Color]::FromArgb(248, 252, 249)
        $form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

        $title = New-Object System.Windows.Forms.Label
        $title.Text = "选择一个工作布局"
        $title.Left = 22
        $title.Top = 18
        $title.Width = 440
        $title.Height = 28
        $title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 13, [System.Drawing.FontStyle]::Bold)
        $title.ForeColor = [System.Drawing.Color]::FromArgb(24, 82, 57)
        $form.Controls.Add($title)

        $hint = New-Object System.Windows.Forms.Label
        $hint.Text = "保存不同工作流的位置和大小，下次一键恢复。"
        $hint.Left = 24
        $hint.Top = 48
        $hint.Width = 440
        $hint.Height = 24
        $hint.ForeColor = [System.Drawing.Color]::FromArgb(86, 110, 96)
        $form.Controls.Add($hint)

        $list = New-Object System.Windows.Forms.ListBox
        $list.Left = 24
        $list.Top = 86
        $list.Width = 300
        $list.Height = 240
        $list.DisplayMember = "Display"
        $list.BackColor = [System.Drawing.Color]::White
        $list.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        $form.Controls.Add($list)

        $openButton = New-Object System.Windows.Forms.Button
        $openButton.Text = "打开布局"
        $openButton.Left = 348
        $openButton.Top = 88
        $openButton.Width = 130
        $openButton.Height = 36
        $form.Controls.Add($openButton)

        $saveNewButton = New-Object System.Windows.Forms.Button
        $saveNewButton.Text = "保存为新布局"
        $saveNewButton.Left = 348
        $saveNewButton.Top = 136
        $saveNewButton.Width = 130
        $saveNewButton.Height = 36
        $form.Controls.Add($saveNewButton)

        $overwriteButton = New-Object System.Windows.Forms.Button
        $overwriteButton.Text = "覆盖所选布局"
        $overwriteButton.Left = 348
        $overwriteButton.Top = 184
        $overwriteButton.Width = 130
        $overwriteButton.Height = 36
        $form.Controls.Add($overwriteButton)

        $folderButton = New-Object System.Windows.Forms.Button
        $folderButton.Text = "打开入口文件夹"
        $folderButton.Left = 348
        $folderButton.Top = 232
        $folderButton.Width = 130
        $folderButton.Height = 36
        $form.Controls.Add($folderButton)

        $refreshButton = New-Object System.Windows.Forms.Button
        $refreshButton.Text = "刷新"
        $refreshButton.Left = 348
        $refreshButton.Top = 280
        $refreshButton.Width = 130
        $refreshButton.Height = 36
        $form.Controls.Add($refreshButton)

        $status = New-Object System.Windows.Forms.Label
        $status.Left = 24
        $status.Top = 338
        $status.Width = 454
        $status.Height = 24
        $status.ForeColor = [System.Drawing.Color]::FromArgb(86, 110, 96)
        $form.Controls.Add($status)

        $refresh = {
            Update-LayoutListBox -ListBox $list
            if ($list.Items.Count -gt 0) {
                $status.Text = "已加载 $($list.Items.Count) 个布局。"
            } else {
                $status.Text = "还没有保存布局。先摆好窗口，再点保存为新布局。"
            }
        }

        $openButton.Add_Click({
            if ($null -eq $list.SelectedItem) {
                $status.Text = "先选一个布局。"
                return
            }
            $selected = $list.SelectedItem
            $form.Hide()
            Restore-Layout -Name $selected.Name
            $form.Close()
        })

        $list.Add_DoubleClick({
            if ($null -ne $list.SelectedItem) {
                $selected = $list.SelectedItem
                $form.Hide()
                Restore-Layout -Name $selected.Name
                $form.Close()
            }
        })

        $saveNewButton.Add_Click({
            $name = Show-LayoutNamePrompt -DefaultName "新布局"
            if ($null -eq $name) {
                $status.Text = "已取消。"
                return
            }
            Save-CurrentLayout -Name $name | Out-Null
            & $refresh
            $status.Text = "已保存：$name。"
        })

        $overwriteButton.Add_Click({
            if ($null -eq $list.SelectedItem) {
                $status.Text = "先选一个要覆盖的布局。"
                return
            }
            $selected = $list.SelectedItem
            Save-CurrentLayout -Name $selected.Name | Out-Null
            & $refresh
            $status.Text = "已覆盖：$($selected.Name)。"
        })

        $folderButton.Add_Click({
            if (-not (Test-Path -LiteralPath $ShortcutDir)) {
                New-Item -ItemType Directory -Force -Path $ShortcutDir | Out-Null
            }
            Start-Process explorer.exe -ArgumentList @($ShortcutDir) | Out-Null
        })

        $refreshButton.Add_Click({
            & $refresh
        })

        $form.Add_Shown({
            & $refresh
        })

        [System.Windows.Forms.Application]::Run($form)
    } catch {
        Show-LayoutToast -Message "布局中心打开失败"
        throw
    }
}

if ($Mode -eq "Save") {
    Save-CurrentLayout -Name $LayoutName | Out-Null
} elseif ($Mode -eq "SavePrompt") {
    $name = Show-LayoutNamePrompt -DefaultName $LayoutName
    if ($null -ne $name) {
        Save-CurrentLayout -Name $name | Out-Null
    }
} elseif ($Mode -eq "Restore") {
    Restore-Layout -Name $LayoutName
} elseif ($Mode -eq "Menu") {
    Show-LayoutMenu
} else {
    Get-TopLevelWindows | Sort-Object X, Y, Process | Format-Table -AutoSize
}
