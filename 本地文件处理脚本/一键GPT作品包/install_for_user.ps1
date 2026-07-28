param(
    [string]$TargetFolder,
    [string]$DefaultLibraryPath,
    [string]$DefaultPortfolioOutputPath,
    [string]$DefaultInboxPath,
    [switch]$NoUi,
    [switch]$NoShortcut,
    [switch]$SkipProtocol
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms

$targetFolder = if ([string]::IsNullOrWhiteSpace($TargetFolder)) {
    Join-Path $env:LOCALAPPDATA "GPTWorkPackageAssistant"
} else {
    [System.IO.Path]::GetFullPath($TargetFolder)
}
$configPath = Join-Path $targetFolder "workpkg_config.json"
$installerPath = Join-Path $PSScriptRoot "install_work_package_tool.ps1"
$settingsLauncherName = "设置作品包目录.vbs"
$settingsLauncherPath = Join-Path $targetFolder $settingsLauncherName
$userscriptUrl = "https://raw.githubusercontent.com/zwmopen/scripts/master/chatgpt-conversation-tree.user.js"

function Get-DownloadsFolder {
    try {
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
        $valueName = "{374DE290-123F-4565-9164-39C4925E467B}"
        $value = (Get-ItemProperty -LiteralPath $key -Name $valueName -ErrorAction Stop).$valueName
        $expanded = [Environment]::ExpandEnvironmentVariables([string]$value)
        if ([System.IO.Path]::IsPathRooted($expanded)) {
            return [System.IO.Path]::GetFullPath($expanded)
        }
    } catch {
    }
    return (Join-Path $env:USERPROFILE "Downloads")
}

try {
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw "安装文件不完整，请重新下载整个「一键GPT作品包」文件夹后再双击安装。"
    }

    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        if ($SkipProtocol) {
            & $installerPath -TargetFolder $targetFolder | Out-Null
        } else {
            & $installerPath -TargetFolder $targetFolder -RegisterProtocol | Out-Null
        }
    } else {
        $defaultLibrary = if ([string]::IsNullOrWhiteSpace($DefaultLibraryPath)) {
            Join-Path ([Environment]::GetFolderPath("MyDocuments")) "GPT作品库"
        } else {
            [System.IO.Path]::GetFullPath($DefaultLibraryPath)
        }
        $defaultInbox = if ([string]::IsNullOrWhiteSpace($DefaultInboxPath)) {
            Get-DownloadsFolder
        } else {
            [System.IO.Path]::GetFullPath($DefaultInboxPath)
        }
        $installArguments = @{
            TargetFolder = $targetFolder
            LibraryName = "GPT作品库"
            LibraryPath = $defaultLibrary
            ImageInboxPath = $defaultInbox
        }
        if (-not [string]::IsNullOrWhiteSpace($DefaultPortfolioOutputPath)) {
            $installArguments.PortfolioOutputPath = [System.IO.Path]::GetFullPath($DefaultPortfolioOutputPath)
        }
        if (-not $SkipProtocol) {
            $installArguments.RegisterProtocol = $true
        }
        & $installerPath @installArguments | Out-Null
    }

    $desktop = [Environment]::GetFolderPath("Desktop")
    if (-not $NoShortcut -and -not [string]::IsNullOrWhiteSpace($desktop)) {
        $shortcutPath = Join-Path $desktop "GPT作品助手中心.lnk"
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "$env:WINDIR\System32\wscript.exe"
        $shortcut.Arguments = "`"$settingsLauncherPath`""
        $shortcut.WorkingDirectory = $targetFolder
        $shortcut.Description = "设置目录、查看任务、备份和恢复 GPT 作品助手"
        $shortcut.Save()
    }

    if ($NoUi) {
        Write-Output "FRIENDLY_INSTALL_OK"
        Write-Output "Target=$targetFolder"
    } else {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "本地作品助手已安装。`n`n接下来会打开设置中心，请确认图片下载、成品库和作品集目录后保存。作品集目录不单独设置时默认使用成品库。`n`n是否同时打开 ChatGPT 网页脚本安装页？",
            "GPT 作品助手安装完成",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )

        Start-Process -FilePath "wscript.exe" -ArgumentList @("`"$settingsLauncherPath`"")
        if ($answer -eq [System.Windows.Forms.DialogResult]::Yes) {
            Start-Process $userscriptUrl
        }
    }
} catch {
    if ($NoUi) {
        throw
    }
    [System.Windows.Forms.MessageBox]::Show(
        "安装失败：`n$($_.Exception.Message)",
        "GPT 作品助手",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}
