param(
    [string]$ClipboardTextOverride,
    [string]$ConversationMetadataJsonOverride,
    [switch]$NoMessage,
    [switch]$Preview,
    [int]$TestFailAfterImageMove = 0
)

$ErrorActionPreference = "Stop"
$workPackageScriptVersion = "1.4.3"
$clipboardTextOverrideSpecified = $PSBoundParameters.ContainsKey("ClipboardTextOverride")
$conversationMetadataOverrideSpecified = $PSBoundParameters.ContainsKey("ConversationMetadataJsonOverride")

function Get-ClipboardText {
    if ($clipboardTextOverrideSpecified) {
        return $ClipboardTextOverride
    }

    try {
        return Get-Clipboard -Raw -Format Text
    } catch {
        return $null
    }
}

function Get-TitleLine {
    param([string]$Text)

    foreach ($line in ($Text -split "\r?\n")) {
        if (-not [string]::IsNullOrWhiteSpace($line)) {
            return $line.Trim()
        }
    }

    return "untitled"
}

function Get-SafeNamePart {
    param(
        [string]$Text,
        [int]$MaxLength = 60
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "untitled"
    }

    $safe = $Text -replace '[<>:"/\\|?*\x00-\x1F]', '_'
    $safe = $safe -replace '\s+', ' '
    $safe = $safe.Trim()
    $safe = $safe.TrimEnd('.', ' ')

    if ([string]::IsNullOrWhiteSpace($safe)) {
        $safe = "untitled"
    }

    if ($MaxLength -gt 0 -and $safe.Length -gt $MaxLength) {
        $safe = $safe.Substring(0, $MaxLength).TrimEnd('.', ' ')
    }

    return $safe
}

function Get-NormalizedGptWindowTitle {
    param([string]$WindowTitle)

    if ([string]::IsNullOrWhiteSpace($WindowTitle)) {
        return ""
    }

    $title = $WindowTitle.Trim()
    $title = $title -replace '\s+-\s+(Microsoft Edge|Google Chrome|Chrome|Chromium|Brave|Mozilla Firefox)$', ''
    $title = $title -replace '\s+—\s+(Microsoft Edge|Google Chrome|Chrome|Chromium|Brave|Mozilla Firefox)$', ''
    $title = $title -replace '^\s*ChatGPT\s*[-–—]\s*', ''
    $title = $title -replace '\s*[-–—]\s*ChatGPT\s*$', ''
    $title = $title.Trim()

    if ([string]::IsNullOrWhiteSpace($title)) {
        return ""
    }

    if ($title -match '^(ChatGPT|OpenAI|新聊天|New chat)$') {
        return ""
    }

    return Get-SafeNamePart -Text $title -MaxLength 80
}

function Get-ForegroundWindowTitle {
    try {
        if (-not ([System.Management.Automation.PSTypeName]"WorkPkgWindowTitle").Type) {
            Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class WorkPkgWindowTitle
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    public static string GetForegroundTitle()
    {
        IntPtr handle = GetForegroundWindow();
        if (handle == IntPtr.Zero) return "";
        StringBuilder buffer = new StringBuilder(1024);
        GetWindowText(handle, buffer, buffer.Capacity);
        return buffer.ToString();
    }
}
'@
        }

        return [WorkPkgWindowTitle]::GetForegroundTitle()
    } catch {
        return ""
    }
}

function ConvertFrom-WorkPkgBase64Utf8 {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    try {
        $bytes = [Convert]::FromBase64String($Value.Trim())
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    } catch {
        return ""
    }
}

function Get-GptConversationTitleFromClipboardHtml {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        if (-not [System.Windows.Forms.Clipboard]::ContainsText([System.Windows.Forms.TextDataFormat]::Html)) {
            return ""
        }

        $html = [System.Windows.Forms.Clipboard]::GetText([System.Windows.Forms.TextDataFormat]::Html)
        if ([string]::IsNullOrWhiteSpace($html)) {
            return ""
        }

        $match = [regex]::Match($html, 'WORKPKG_GPT_TITLE_B64:([A-Za-z0-9+/=]+)')
        if (-not $match.Success) {
            return ""
        }

        $decoded = ConvertFrom-WorkPkgBase64Utf8 -Value $match.Groups[1].Value
        return Get-NormalizedGptWindowTitle -WindowTitle $decoded
    } catch {
        return ""
    }
}

function ConvertFrom-GptConversationMetadataJson {
    param([string]$Json)

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return $null
    }

    try {
        $source = $Json | ConvertFrom-Json
        $accountName = ([string]$source.accountName).Trim()
        $conversationUrl = ([string]$source.conversationUrl).Trim()

        if ($accountName.Length -gt 120) {
            $accountName = $accountName.Substring(0, 120)
        }

        $parsedUri = $null
        $validUrl = [Uri]::TryCreate($conversationUrl, [UriKind]::Absolute, [ref]$parsedUri)
        if (-not $validUrl -or $parsedUri.Scheme -ne "https" -or $parsedUri.Host -notin @("chatgpt.com", "chat.openai.com")) {
            $conversationUrl = ""
        }

        if ([string]::IsNullOrWhiteSpace($accountName) -and [string]::IsNullOrWhiteSpace($conversationUrl)) {
            return $null
        }

        return [pscustomobject][ordered]@{
            accountName = $accountName
            conversationUrl = $conversationUrl
        }
    } catch {
        return $null
    }
}

function Get-GptConversationMetadata {
    if ($conversationMetadataOverrideSpecified) {
        return ConvertFrom-GptConversationMetadataJson -Json $ConversationMetadataJsonOverride
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        if (-not [System.Windows.Forms.Clipboard]::ContainsText([System.Windows.Forms.TextDataFormat]::Html)) {
            return $null
        }

        $html = [System.Windows.Forms.Clipboard]::GetText([System.Windows.Forms.TextDataFormat]::Html)
        if ([string]::IsNullOrWhiteSpace($html)) {
            return $null
        }

        $match = [regex]::Match($html, 'WORKPKG_GPT_META_B64:([A-Za-z0-9+/=]+)')
        if (-not $match.Success) {
            return $null
        }

        $decoded = ConvertFrom-WorkPkgBase64Utf8 -Value $match.Groups[1].Value
        return ConvertFrom-GptConversationMetadataJson -Json $decoded
    } catch {
        return $null
    }
}

function Get-GptConversationTitle {
    if (-not [string]::IsNullOrWhiteSpace($env:WORKPKG_GPT_TITLE)) {
        $fromEnv = Get-NormalizedGptWindowTitle -WindowTitle $env:WORKPKG_GPT_TITLE
        if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
            return $fromEnv
        }
    }

    $fromClipboardHtml = Get-GptConversationTitleFromClipboardHtml
    if (-not [string]::IsNullOrWhiteSpace($fromClipboardHtml)) {
        return $fromClipboardHtml
    }

    $candidateTitles = New-Object System.Collections.Generic.List[string]
    $foregroundTitle = Get-ForegroundWindowTitle
    if (-not [string]::IsNullOrWhiteSpace($foregroundTitle)) {
        $candidateTitles.Add($foregroundTitle)
    }

    foreach ($processName in @("msedge", "chrome", "brave", "firefox")) {
        try {
            $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_.MainWindowTitle)
            } | Sort-Object StartTime -Descending)

            foreach ($process in $processes) {
                $candidateTitles.Add($process.MainWindowTitle)
            }
        } catch {
        }
    }

    foreach ($candidate in @($candidateTitles | Select-Object -Unique)) {
        if ($candidate -notmatch 'ChatGPT|OpenAI') {
            continue
        }

        $normalized = Get-NormalizedGptWindowTitle -WindowTitle $candidate
        if (-not [string]::IsNullOrWhiteSpace($normalized)) {
            return $normalized
        }
    }

    return ""
}

function Write-ErrorLog {
    param(
        [string]$Directory,
        [string]$Stamp,
        [string]$Message
    )

    $packageWord = "$([char]0x4F5C)$([char]0x54C1)$([char]0x5305)"
    $logPath = Join-Path $Directory "$packageWord`_error_$Stamp.txt"
    [System.IO.File]::WriteAllText($logPath, $Message, (New-Object System.Text.UTF8Encoding($false)))
}

function New-TextFromCodePoints {
    param([int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Get-WorkPackageConfig {
    param([string]$Path)

    $defaults = [pscustomobject]@{
        library_name = New-TextFromCodePoints @(0x56E2, 0x5EFA, 0x6210, 0x54C1, 0x5E93)
        library_path = ""
        portfolio_auto_group = $true
        portfolio_auto_zip = $true
        portfolio_batch_size = 14
        portfolio_prefix = New-TextFromCodePoints @(0x4F5C, 0x54C1, 0x96C6)
        portfolio_log_folder = "_portfolio_move_logs"
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return $defaults
    }

    try {
        $loaded = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $defaults.PSObject.Properties.Name) {
            $value = $loaded.$property
            if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                $defaults.$property = $value
            }
        }
    } catch {
        # 配置损坏时使用内置默认值，不能阻断作品包生成。
    }

    return $defaults
}

function Show-Tip {
    param(
        [string]$Message,
        [int]$Milliseconds = 2000
    )

    if ($NoMessage) {
        Write-Output $Message
        return
    }

    $title = New-TextFromCodePoints @(0x4E00, 0x952E, 0x751F, 0x6210, 0x4F5C, 0x54C1, 0x5305)

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        if (-not ([System.Management.Automation.PSTypeName]"WorkPkgToastForm").Type) {
            Add-Type -Language CSharp -ReferencedAssemblies System.Windows.Forms -TypeDefinition @'
using System;
using System.Windows.Forms;

public class WorkPkgToastForm : Form
{
    protected override bool ShowWithoutActivation { get { return true; } }

    protected override CreateParams CreateParams
    {
        get
        {
            CreateParams cp = base.CreateParams;
            cp.ExStyle |= 0x08000000; // WS_EX_NOACTIVATE
            cp.ExStyle |= 0x00000080; // WS_EX_TOOLWINDOW
            cp.ClassStyle |= 0x00020000; // CS_DROPSHADOW
            return cp;
        }
    }
}
'@
        }

        $form = New-Object WorkPkgToastForm
        $form.ShowInTaskbar = $false
        $form.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $form.TopMost = $true
        $form.BackColor = [System.Drawing.Color]::FromArgb(247, 255, 250)
        $form.Opacity = 0.97
        $form.Width = 380
        $form.Height = 58

        $radius = 18
        $diameter = $radius * 2
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddArc(0, 0, $diameter, $diameter, 180, 90)
        $path.AddArc($form.Width - $diameter - 1, 0, $diameter, $diameter, 270, 90)
        $path.AddArc($form.Width - $diameter - 1, $form.Height - $diameter - 1, $diameter, $diameter, 0, 90)
        $path.AddArc(0, $form.Height - $diameter - 1, $diameter, $diameter, 90, 90)
        $path.CloseFigure()
        $form.Region = New-Object System.Drawing.Region($path)

        $accent = New-Object System.Windows.Forms.Panel
        $accent.Dock = [System.Windows.Forms.DockStyle]::Left
        $accent.Width = 7
        $accent.BackColor = [System.Drawing.Color]::FromArgb(34, 197, 94)
        $form.Controls.Add($accent)

        $label = New-Object System.Windows.Forms.Label
        $label.Dock = [System.Windows.Forms.DockStyle]::Fill
        $label.BackColor = $form.BackColor
        $label.ForeColor = [System.Drawing.Color]::FromArgb(20, 83, 45)
        $label.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 13, [System.Drawing.FontStyle]::Bold)
        $label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $label.Text = $Message
        $label.Padding = New-Object System.Windows.Forms.Padding(14, 0, 18, 1)
        $form.Controls.Add($label)

        $screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $form.Left = [int]($screen.Left + (($screen.Width - $form.Width) / 2))
        $form.Top = [int]($screen.Top + (($screen.Height - $form.Height) / 2))

        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = [Math]::Max(500, $Milliseconds)
        $timer.Add_Tick({
            $timer.Stop()
            $form.Close()
        })

        $timer.Start()
        [System.Windows.Forms.Application]::Run($form)
    } catch {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $shell.Popup($Message, 1, $title, 64) | Out-Null
        } catch {
        }
    }
}

function Get-Sha256Hex {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") })
    } finally {
        $sha.Dispose()
    }
}

function Get-PackagedTextFiles {
    param(
        [string]$Directory,
        [string]$TextPrefix,
        [switch]$Recurse
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        return @()
    }

    if ($Recurse) {
        return @(Get-ChildItem -LiteralPath $Directory -File -Force -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension.ToLowerInvariant() -eq ".txt" -and
            $_.BaseName.StartsWith($TextPrefix) -and
            ($_.FullName -notmatch '\\_portfolio_move_logs\\')
        })
    }

    $files = New-Object System.Collections.Generic.List[object]

    $directFiles = @(Get-ChildItem -LiteralPath $Directory -File -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Extension.ToLowerInvariant() -eq ".txt" -and $_.BaseName.StartsWith($TextPrefix)
    })

    foreach ($file in $directFiles) {
        $files.Add($file)
    }

    $folders = @(Get-ChildItem -LiteralPath $Directory -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^\.?\d{8}_\d{6}_'
    })

    foreach ($folder in $folders) {
        $nestedFiles = @(Get-ChildItem -LiteralPath $folder.FullName -File -Force -ErrorAction SilentlyContinue | Where-Object {
            $_.Extension.ToLowerInvariant() -eq ".txt" -and $_.BaseName.StartsWith($TextPrefix)
        })

        foreach ($file in $nestedFiles) {
            $files.Add($file)
        }
    }

    return $files.ToArray()
}

function Get-LatestPackagedTextHash {
    param(
        [string]$Directory,
        [string]$TextPrefix,
        [switch]$Recurse
    )

    $txtFiles = @(Get-PackagedTextFiles -Directory $Directory -TextPrefix $TextPrefix -Recurse:$Recurse |
        Sort-Object LastWriteTime -Descending)

    foreach ($txt in $txtFiles) {
        try {
            return Get-TextHash -Text ([System.IO.File]::ReadAllText($txt.FullName))
        } catch {
        }
    }

    return $null
}

function Test-PackagedTextHashExists {
    param(
        [string]$Directory,
        [string]$TextPrefix,
        [string]$Hash,
        [switch]$Recurse
    )

    foreach ($txt in @(Get-PackagedTextFiles -Directory $Directory -TextPrefix $TextPrefix -Recurse:$Recurse)) {
        try {
            if ((Get-TextHash -Text ([System.IO.File]::ReadAllText($txt.FullName))) -eq $Hash) {
                return $true
            }
        } catch {
        }
    }

    return $false
}

function Get-TopLevelImages {
    param(
        [string]$Directory,
        [string[]]$ExcludeNames = @()
    )

    $imageExtensions = @(
        ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp",
        ".tif", ".tiff", ".heic", ".heif", ".avif", ".jfif"
    )

    return @(Get-ChildItem -LiteralPath $Directory -File -Force | Where-Object {
        ($imageExtensions -contains $_.Extension.ToLowerInvariant()) -and
        (-not ($ExcludeNames -contains $_.Name))
    } | Sort-Object LastWriteTime, Name)
}

function Set-FileTimes {
    param(
        [string]$Path,
        [datetime]$Time
    )

    try {
        $item = Get-Item -LiteralPath $Path -Force
        $item.CreationTime = $Time
        $item.LastWriteTime = $Time
        $item.LastAccessTime = $Time
    } catch {
    }
}

function Remove-DuplicateDownloadImages {
    param(
        [object[]]$Images
    )

    $deleted = 0
    foreach ($image in $Images) {
        if ($clipboardTextOverrideSpecified) {
            Remove-Item -LiteralPath $image.FullName -Force -ErrorAction Stop
        } else {
            Add-Type -AssemblyName Microsoft.VisualBasic
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
                $image.FullName,
                [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
                [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
            )
        }
        $deleted++
    }

    return $deleted
}

function Restore-StagedImages {
    param([object[]]$MovedImages)

    $restoreErrors = New-Object System.Collections.Generic.List[string]
    foreach ($record in @($MovedImages) | Sort-Object Sequence -Descending) {
        try {
            if (-not (Test-Path -LiteralPath $record.StagedPath -PathType Leaf)) {
                continue
            }
            $restorePath = $record.OriginalPath
            if (Test-Path -LiteralPath $restorePath) {
                $restorePath = Get-UniqueFilePath -Path $restorePath
            }
            Move-Item -LiteralPath $record.StagedPath -Destination $restorePath -ErrorAction Stop
        } catch {
            $restoreErrors.Add("$($record.StagedPath): $($_.Exception.Message)") | Out-Null
        }
    }

    return $restoreErrors.ToArray()
}

function Get-PortfolioNumber {
    param(
        [string]$Name,
        [string]$Pattern
    )

    $match = [regex]::Match($Name, $Pattern)
    if (-not $match.Success) {
        return $null
    }

    return [int]$match.Groups[1].Value
}

function New-PortfolioName {
    param(
        [string]$Prefix,
        [int]$Number
    )

    return "{0}_{1:000}" -f $Prefix, $Number
}

function Get-UniqueFilePath {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $Path
    }

    $directory = Split-Path -Parent $Path
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $extension = [System.IO.Path]::GetExtension($Path)
    $index = 2

    do {
        $candidate = Join-Path $directory "$name`_$index$extension"
        $index++
    } while (Test-Path -LiteralPath $candidate)

    return $candidate
}

function New-PortfolioZip {
    param(
        [string]$PortfolioPath,
        [string]$ZipPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $resolvedZipPath = Get-UniqueFilePath -Path $ZipPath
    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $PortfolioPath,
        $resolvedZipPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $false
    )

    return $resolvedZipPath
}

function Invoke-PortfolioAutoGroup {
    param(
        [string]$LibraryDir,
        [int]$BatchSize,
        [string]$PortfolioPrefix,
        [string]$LogFolderName,
        [bool]$CreateZip = $true
    )

    $emptyResult = [pscustomobject]@{
        Batches = 0
        Moved = 0
        Failed = 0
        Leftover = 0
        ZipCreated = 0
        ZipFailed = 0
        ZipFiles = @()
        PreviewLog = ""
        ResultLog = ""
    }

    if ($BatchSize -lt 1 -or -not (Test-Path -LiteralPath $LibraryDir)) {
        return $emptyResult
    }

    $portfolioNameCore = $PortfolioPrefix.TrimStart('.')
    $portfolioPattern = "^\.?$([regex]::Escape($portfolioNameCore))_(\d+)$"
    $allDirs = @(Get-ChildItem -LiteralPath $LibraryDir -Directory -Force -ErrorAction SilentlyContinue)

    $existingPortfolios = @($allDirs | Where-Object {
        $_.Name -match $portfolioPattern
    })

    $workFolders = @($allDirs | Where-Object {
        $_.Name -notmatch $portfolioPattern -and
        $_.Name -ne $LogFolderName -and
        $_.Name -match '^\.?\d{8}_\d{6}_'
    } | Sort-Object Name)

    if ($workFolders.Count -lt $BatchSize) {
        $emptyResult.Leftover = $workFolders.Count
        return $emptyResult
    }

    $maxExistingNumber = 0
    foreach ($portfolio in $existingPortfolios) {
        $number = Get-PortfolioNumber -Name $portfolio.Name -Pattern $portfolioPattern
        if ($number -gt $maxExistingNumber) {
            $maxExistingNumber = $number
        }
    }

    $fullBatchCount = [int][math]::Floor($workFolders.Count / $BatchSize)
    $moveCount = $fullBatchCount * $BatchSize
    $leftoverCount = $workFolders.Count - $moveCount
    $selectedFolders = @($workFolders | Select-Object -First $moveCount)
    $plan = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $selectedFolders.Count; $i++) {
        $folder = $selectedFolders[$i]
        $batchIndex = [int][math]::Floor($i / $BatchSize)
        $portfolioNumber = $maxExistingNumber + 1 + $batchIndex
        $portfolioName = New-PortfolioName -Prefix $PortfolioPrefix -Number $portfolioNumber
        $portfolioPath = Join-Path $LibraryDir $portfolioName
        $destinationPath = Join-Path $portfolioPath $folder.Name

        $plan.Add([pscustomobject]@{
            Portfolio = $portfolioName
            PortfolioPath = $portfolioPath
            SourcePath = $folder.FullName
            DestinationPath = $destinationPath
            WorkFolder = $folder.Name
        })
    }

    $logDir = Join-Path $LibraryDir $LogFolderName
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $previewCsv = Join-Path $logDir "portfolio_move_preview_$timestamp.csv"
    $resultCsv = Join-Path $logDir "portfolio_move_result_$timestamp.csv"
    $plan | Export-Csv -LiteralPath $previewCsv -NoTypeInformation -Encoding UTF8

    $collisionPaths = @($plan | Where-Object {
        Test-Path -LiteralPath $_.DestinationPath
    } | Select-Object -ExpandProperty DestinationPath)

    if ($collisionPaths.Count -gt 0) {
        $collisionPaths | ForEach-Object {
            [pscustomobject]@{
                Time = Get-Date
                Portfolio = ""
                SourcePath = ""
                DestinationPath = $_
                Result = "Collision"
                Message = "Destination already exists."
            }
        } | Export-Csv -LiteralPath $resultCsv -NoTypeInformation -Encoding UTF8

        return [pscustomobject]@{
            Batches = $fullBatchCount
            Moved = 0
            Failed = $collisionPaths.Count
            Leftover = $leftoverCount
            ZipCreated = 0
            ZipFailed = 0
            ZipFiles = @()
            PreviewLog = $previewCsv
            ResultLog = $resultCsv
        }
    }

    $results = New-Object System.Collections.Generic.List[object]

    foreach ($item in $plan) {
        try {
            New-Item -ItemType Directory -Path $item.PortfolioPath -Force | Out-Null
            Move-Item -LiteralPath $item.SourcePath -Destination $item.DestinationPath -ErrorAction Stop

            $results.Add([pscustomobject]@{
                Time = Get-Date
                Portfolio = $item.Portfolio
                SourcePath = $item.SourcePath
                DestinationPath = $item.DestinationPath
                Result = "Moved"
                Message = ""
            })
        } catch {
            $results.Add([pscustomobject]@{
                Time = Get-Date
                Portfolio = $item.Portfolio
                SourcePath = $item.SourcePath
                DestinationPath = $item.DestinationPath
                Result = "Failed"
                Message = $_.Exception.Message
            })
        }
    }

    $zipFiles = New-Object System.Collections.Generic.List[string]
    $zipFailedCount = 0

    if ($CreateZip) {
        $portfolioPlans = @($plan |
            Group-Object Portfolio |
            Sort-Object Name)

        foreach ($portfolioPlan in $portfolioPlans) {
            $portfolioName = $portfolioPlan.Name
            $portfolioPath = $portfolioPlan.Group[0].PortfolioPath
            $portfolioMoveFailures = @($results | Where-Object {
                $_.Portfolio -eq $portfolioName -and $_.Result -ne "Moved"
            })

            if ($portfolioMoveFailures.Count -gt 0) {
                continue
            }

            try {
                $zipPath = Join-Path $LibraryDir "$portfolioName.zip"
                $createdZipPath = New-PortfolioZip -PortfolioPath $portfolioPath -ZipPath $zipPath
                $zipFiles.Add($createdZipPath)

                $results.Add([pscustomobject]@{
                    Time = Get-Date
                    Portfolio = $portfolioName
                    SourcePath = $portfolioPath
                    DestinationPath = $createdZipPath
                    Result = "Zipped"
                    Message = ""
                })
            } catch {
                $zipFailedCount++
                $results.Add([pscustomobject]@{
                    Time = Get-Date
                    Portfolio = $portfolioName
                    SourcePath = $portfolioPath
                    DestinationPath = Join-Path $LibraryDir "$portfolioName.zip"
                    Result = "ZipFailed"
                    Message = $_.Exception.Message
                })
            }
        }
    }

    $results | Export-Csv -LiteralPath $resultCsv -NoTypeInformation -Encoding UTF8
    $failedCount = @($results | Where-Object {
        $_.Result -in @("Failed", "Collision", "ZipFailed")
    }).Count

    return [pscustomobject]@{
        Batches = $fullBatchCount
        Moved = @($results | Where-Object { $_.Result -eq "Moved" }).Count
        Failed = $failedCount
        Leftover = $leftoverCount
        ZipCreated = $zipFiles.Count
        ZipFailed = $zipFailedCount
        ZipFiles = $zipFiles.ToArray()
        PreviewLog = $previewCsv
        ResultLog = $resultCsv
    }
}

function Clear-ClipboardAfterSuccess {
    if ($clipboardTextOverrideSpecified) {
        return
    }

    try {
        Set-Clipboard -Value ""
    } catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.Clipboard]::Clear()
        } catch {
        }
    }
}

function Save-LastTextHash {
    param(
        [string]$Path,
        [string]$Hash
    )

    if (Test-Path -LiteralPath $Path) {
        try {
            $existing = Get-Item -LiteralPath $Path -Force
            $existing.Attributes = $existing.Attributes -band (-bnot [System.IO.FileAttributes]::Hidden)
        } catch {
        }
    }

    [System.IO.File]::WriteAllText($Path, $Hash, (New-Object System.Text.UTF8Encoding($false)))

    try {
        $hashItem = Get-Item -LiteralPath $Path -Force
        $hashItem.Attributes = $hashItem.Attributes -bor [System.IO.FileAttributes]::Hidden
    } catch {
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$packageTime = Get-Date
$stamp = $packageTime.ToString("yyyyMMdd_HHmmss")
$textPrefix = "$([char]0x6587)$([char]0x6848)"
$configPath = Join-Path $scriptDir "workpkg_config.json"
$config = Get-WorkPackageConfig -Path $configPath
$libraryName = [string]$config.library_name
$configuredLibraryPath = [Environment]::ExpandEnvironmentVariables(([string]$config.library_path).Trim())
if ([string]::IsNullOrWhiteSpace($configuredLibraryPath)) {
    $libraryDir = Join-Path $scriptDir $libraryName
} else {
    if (-not [System.IO.Path]::IsPathRooted($configuredLibraryPath)) {
        throw "workpkg_config.json library_path must be an absolute path: $configuredLibraryPath"
    }
    $libraryDir = [System.IO.Path]::GetFullPath($configuredLibraryPath)
}

function Normalize-TextForDuplicateHash {
    param([string]$Text)

    if ($null -eq $Text) {
        return ""
    }

    $normalized = $Text.Replace(([string][char]0xFEFF), "")
    $normalized = $normalized -replace "`r`n?", "`n"
    $normalized = $normalized -replace '[\t ]+(?=\n|$)', ''
    $normalized = $normalized.Trim([char[]]@(0x20, 0x09, 0x0A))
    return $normalized.Normalize([System.Text.NormalizationForm]::FormC)
}

function Get-TextHash {
    param([string]$Text)
    return Get-Sha256Hex -Text (Normalize-TextForDuplicateHash -Text $Text)
}

function Get-LegacyTextHash {
    param([string]$Text)
    return Get-Sha256Hex -Text $Text
}
$successMessage = New-TextFromCodePoints @(0x5DF2, 0x521B, 0x5EFA, 0x4F5C, 0x54C1, 0x5305)
$noImageMessage = New-TextFromCodePoints @(0x8BF7, 0x5148, 0x4E0B, 0x8F7D, 0x4F5C, 0x54C1, 0x56FE)
$duplicateExistingMessage = New-TextFromCodePoints @(0x672C, 0x6B21, 0x4E3A, 0x91CD, 0x590D, 0x4E0B, 0x8F7D, 0xFF0C, 0x5DF2, 0x5220, 0x9664, 0x672C, 0x5730, 0x56FE, 0x7247, 0x548C, 0x6587, 0x6848, 0x3002)
$portfolioGroupedMessage = New-TextFromCodePoints @(0x5DF2, 0x521B, 0x5EFA, 0x4F5C, 0x54C1, 0x5305, 0xFF0C, 0x5DF2, 0x6574, 0x7406, 0x4F5C, 0x54C1, 0x96C6)
$portfolioZippedMessage = New-TextFromCodePoints @(0x5DF2, 0x521B, 0x5EFA, 0x4F5C, 0x54C1, 0x5305, 0xFF0C, 0x5DF2, 0x6574, 0x7406, 0x5E76, 0x538B, 0x7F29, 0x4F5C, 0x54C1, 0x96C6)
$portfolioGroupDoneMessage = New-TextFromCodePoints @(0x5DF2, 0x6574, 0x7406, 0x4F5C, 0x54C1, 0x96C6)
$portfolioZipDoneMessage = New-TextFromCodePoints @(0x5DF2, 0x751F, 0x6210, 0x005A, 0x0049, 0x0050, 0x538B, 0x7F29, 0x5305)
$portfolioZipFailedMessage = New-TextFromCodePoints @(0x4F5C, 0x54C1, 0x96C6, 0x538B, 0x7F29, 0x5931, 0x8D25)
$imageExcludeNames = @("$(New-TextFromCodePoints @(0x5206, 0x9694, 0x56FE)).png")
$portfolioAutoGroup = [bool]$config.portfolio_auto_group
$portfolioAutoZip = [bool]$config.portfolio_auto_zip
$portfolioBatchSize = [Math]::Max(1, [int]$config.portfolio_batch_size)
$portfolioPrefix = ([string]$config.portfolio_prefix).TrimStart('.')
$portfolioLogFolder = [string]$config.portfolio_log_folder
$lockStream = $null
$lockPath = Join-Path $scriptDir ".workpkg.lock"
$lastHashPath = Join-Path $scriptDir ".workpkg_last_text.sha256"
$stagingDir = $null
$movedImages = New-Object System.Collections.Generic.List[object]
$packageCommitted = $false

try {
    if (Test-Path -LiteralPath $lockPath) {
        try {
            $lockItem = Get-Item -LiteralPath $lockPath -Force
            if (((Get-Date) - $lockItem.LastWriteTime).TotalSeconds -gt 30) {
                Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
            }
        } catch {
        }
    }

    try {
        $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    } catch {
        return
    }

    $text = Get-ClipboardText
    if ($null -eq $text -or [string]::IsNullOrWhiteSpace($text)) {
        Show-Tip -Message (New-TextFromCodePoints @(0x8BF7, 0x5148, 0x590D, 0x5236, 0x6587, 0x6848))
        return
    }

    $images = Get-TopLevelImages -Directory $scriptDir -ExcludeNames $imageExcludeNames
    if ($images.Count -eq 0) {
        Show-Tip -Message $noImageMessage
        return
    }

    $currentHash = Get-TextHash -Text $text
    $legacyCurrentHash = Get-LegacyTextHash -Text $text
    $duplicateExists = Test-PackagedTextHashExists -Directory $libraryDir -TextPrefix $textPrefix -Hash $currentHash -Recurse
    if (-not $duplicateExists) {
        $duplicateExists = Test-PackagedTextHashExists -Directory $scriptDir -TextPrefix $textPrefix -Hash $currentHash
    }

    $lastHash = $null

    if (Test-Path -LiteralPath $lastHashPath) {
        try {
            $lastHash = ([System.IO.File]::ReadAllText($lastHashPath)).Trim()
        } catch {
            $lastHash = $null
        }
    }

    if (-not $duplicateExists -and [string]::IsNullOrWhiteSpace($lastHash)) {
        $lastHash = Get-LatestPackagedTextHash -Directory $libraryDir -TextPrefix $textPrefix -Recurse
        if ([string]::IsNullOrWhiteSpace($lastHash)) {
            $lastHash = Get-LatestPackagedTextHash -Directory $scriptDir -TextPrefix $textPrefix
        }
    }

    if ($duplicateExists -or $lastHash -eq $currentHash -or $lastHash -eq $legacyCurrentHash) {
        if ($Preview) {
            Write-Output "PREVIEW_DUPLICATE"
            Write-Output "Version=$workPackageScriptVersion"
            Write-Output "WouldDeleteImages=$($images.Count)"
            return
        }
        $removedImages = Remove-DuplicateDownloadImages -Images $images
        Clear-ClipboardAfterSuccess
        Show-Tip -Message $duplicateExistingMessage
        if ($NoMessage) {
            Write-Output "DUPLICATE"
            Write-Output "Version=$workPackageScriptVersion"
            Write-Output "DeletedImages=$removedImages"
        }
        return
    }

    if (-not $Preview -and -not (Test-Path -LiteralPath $libraryDir)) {
        New-Item -ItemType Directory -Path $libraryDir | Out-Null
    }

    $title = Get-SafeNamePart -Text (Get-TitleLine -Text $text)
    $gptConversationTitle = Get-GptConversationTitle
    $gptConversationMetadata = Get-GptConversationMetadata
    $folderTitle = $title
    if (-not [string]::IsNullOrWhiteSpace($gptConversationTitle) -and $gptConversationTitle -ne $title) {
        $folderTitle = Get-SafeNamePart -Text "$title（$gptConversationTitle）" -MaxLength 130
    }

    $targetDir = Join-Path $libraryDir "$stamp`_$folderTitle"
    $packageId = $stamp

    $index = 2
    while (Test-Path -LiteralPath $targetDir) {
        $targetDir = Join-Path $libraryDir "$stamp`_$folderTitle`_$index"
        $packageId = "$stamp`_$index"
        $index++
    }

    if ($Preview) {
        Write-Output "PREVIEW"
        Write-Output "Version=$workPackageScriptVersion"
        Write-Output "Folder=$targetDir"
        Write-Output "Images=$($images.Count)"
        Write-Output "WouldMoveSourceImages=$($images.Count)"
        return
    }

    $stagingDir = Join-Path $libraryDir ".workpkg_staging_$packageId"
    $stagingIndex = 2
    while (Test-Path -LiteralPath $stagingDir) {
        $stagingDir = Join-Path $libraryDir ".workpkg_staging_$packageId`_$stagingIndex"
        $stagingIndex++
    }
    New-Item -ItemType Directory -Path $stagingDir | Out-Null
    try {
        $stagingItem = Get-Item -LiteralPath $stagingDir -Force
        $stagingItem.Attributes = $stagingItem.Attributes -bor [System.IO.FileAttributes]::Hidden
    } catch {
    }

    $mediaPrefix = "$title`_$packageId"

    $txtPath = Join-Path $stagingDir "$textPrefix`_$stamp.txt"
    [System.IO.File]::WriteAllText($txtPath, $text, (New-Object System.Text.UTF8Encoding($false)))
    Set-FileTimes -Path $txtPath -Time $packageTime

    if ($null -ne $gptConversationMetadata) {
        $provenanceFileName = "GPT" + (New-TextFromCodePoints @(0x4F1A, 0x8BDD, 0x6EAF, 0x6E90)) + ".json"
        $provenancePath = Join-Path $stagingDir $provenanceFileName
        $provenance = [ordered]@{
            accountName = [string]$gptConversationMetadata.accountName
            conversationUrl = [string]$gptConversationMetadata.conversationUrl
        }
        $provenanceJson = $provenance | ConvertTo-Json
        [System.IO.File]::WriteAllText($provenancePath, $provenanceJson, (New-Object System.Text.UTF8Encoding($false)))
        Set-FileTimes -Path $provenancePath -Time $packageTime
    }

    $numberFormat = "D$([Math]::Max(2, $images.Count.ToString().Length))"

    for ($i = 0; $i -lt $images.Count; $i++) {
        $image = $images[$i]
        $sequence = ($i + 1).ToString($numberFormat)
        $newName = "$mediaPrefix`_$sequence$($image.Extension.ToLowerInvariant())"
        $newPath = Join-Path $stagingDir $newName
        $originalPath = $image.FullName
        Move-Item -LiteralPath $originalPath -Destination $newPath -ErrorAction Stop
        $movedImages.Add([pscustomobject]@{
            Sequence = $i
            OriginalPath = $originalPath
            StagedPath = $newPath
        }) | Out-Null
        Set-FileTimes -Path $newPath -Time ($packageTime.AddSeconds($i + 1))
        if ($TestFailAfterImageMove -gt 0 -and $movedImages.Count -ge $TestFailAfterImageMove) {
            throw "Simulated failure after moving $($movedImages.Count) image(s)."
        }
    }

    Move-Item -LiteralPath $stagingDir -Destination $targetDir -ErrorAction Stop
    $packageCommitted = $true
    $stagingDir = $null
    $txtPath = Join-Path $targetDir "$textPrefix`_$stamp.txt"

    Save-LastTextHash -Path $lastHashPath -Hash $currentHash

    $portfolioResult = $null
    if ($portfolioAutoGroup) {
        $portfolioResult = Invoke-PortfolioAutoGroup -LibraryDir $libraryDir -BatchSize $portfolioBatchSize -PortfolioPrefix $portfolioPrefix -LogFolderName $portfolioLogFolder -CreateZip:$portfolioAutoZip
    }

    $finalTargetDir = $targetDir
    if ($null -ne $portfolioResult -and $portfolioResult.Moved -gt 0 -and -not (Test-Path -LiteralPath $finalTargetDir)) {
        $targetLeaf = Split-Path -Leaf $targetDir
        $movedTarget = @(Get-ChildItem -LiteralPath $libraryDir -Directory -Force -Recurse -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -eq $targetLeaf
        } | Select-Object -First 1)

        if ($movedTarget.Count -gt 0) {
            $finalTargetDir = $movedTarget[0].FullName
        }
    }

    Clear-ClipboardAfterSuccess
    $stageMessages = New-Object System.Collections.Generic.List[string]
    $stageMessages.Add($successMessage)

    if ($null -ne $portfolioResult -and $portfolioResult.Moved -gt 0) {
        $stageMessages.Add($portfolioGroupDoneMessage)

        if ($portfolioResult.ZipCreated -gt 0) {
            $stageMessages.Add($portfolioZipDoneMessage)
        } elseif ($portfolioResult.ZipFailed -gt 0) {
            $stageMessages.Add($portfolioZipFailedMessage)
        }
    }

    foreach ($stageMessage in $stageMessages) {
        Show-Tip -Message $stageMessage -Milliseconds 850
    }

    if ($NoMessage) {
        Write-Output "OK"
        Write-Output "Version=$workPackageScriptVersion"
        Write-Output "Folder=$finalTargetDir"
        Write-Output "GptConversationTitle=$gptConversationTitle"
        Write-Output "Images=$($images.Count)"
        Write-Output "Txt=$([System.IO.Path]::GetFileName($txtPath))"
        if ($null -ne $portfolioResult) {
            Write-Output "PortfolioMoved=$($portfolioResult.Moved)"
            Write-Output "PortfolioFailed=$($portfolioResult.Failed)"
            Write-Output "PortfolioLeftover=$($portfolioResult.Leftover)"
            Write-Output "PortfolioZipCreated=$($portfolioResult.ZipCreated)"
            Write-Output "PortfolioZipFailed=$($portfolioResult.ZipFailed)"
            foreach ($zipFile in @($portfolioResult.ZipFiles)) {
                Write-Output "PortfolioZip=$zipFile"
            }
            if (-not [string]::IsNullOrWhiteSpace($portfolioResult.ResultLog)) {
                Write-Output "PortfolioLog=$($portfolioResult.ResultLog)"
            }
        }
    }
} catch {
    $originalError = $_
    if (-not $packageCommitted) {
        $restoreErrors = Restore-StagedImages -MovedImages $movedImages.ToArray()
        if (-not [string]::IsNullOrWhiteSpace($stagingDir) -and (Test-Path -LiteralPath $stagingDir)) {
            try {
                Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction Stop
            } catch {
                $restoreErrors += "Staging cleanup: $($_.Exception.Message)"
            }
        }
        if (@($restoreErrors).Count -gt 0) {
            try {
                Write-ErrorLog -Directory $scriptDir -Stamp $stamp -Message ("Rollback incomplete:`r`n" + (@($restoreErrors) -join "`r`n"))
            } catch {
            }
        }
    }
    try {
        Write-ErrorLog -Directory $scriptDir -Stamp $stamp -Message ("Make work package failed:`r`n" + $_.Exception.Message)
    } catch {
    }

    throw $originalError
} finally {
    if ($null -ne $lockStream) {
        $lockStream.Close()
    }

    if ($null -ne $lockStream -and (Test-Path -LiteralPath $lockPath)) {
        Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
    }
}

