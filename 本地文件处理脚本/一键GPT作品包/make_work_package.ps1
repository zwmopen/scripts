param(
    [string]$ClipboardTextOverride,
    [string]$ConversationMetadataJsonOverride,
    [string]$BatchId,
    [int]$ExpectedImageCount = 0,
    [switch]$NoMessage,
    [switch]$Preview,
    [switch]$Diagnose,
    [switch]$RebuildHistory,
    [switch]$CleanExistingDuplicates,
    [int]$TestFailAfterImageMove = 0
)

$ErrorActionPreference = "Stop"
$workPackageScriptVersion = "1.7.1"
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
        image_inbox_path = ""
        portfolio_auto_group = $true
        portfolio_auto_zip = $true
        portfolio_batch_size = 14
        portfolio_prefix = New-TextFromCodePoints @(0x4F5C, 0x54C1, 0x96C6)
        portfolio_log_folder = "_portfolio_move_logs"
        visual_similarity_enabled = $true
        visual_similarity_max_distance = 6
        visual_similarity_max_average = 3
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

function Get-WorkPackageInboxImages {
    param(
        [string]$Directory,
        [string[]]$ExcludeNames = @(),
        [string]$RequestedBatchId = "",
        [int]$RequestedExpectedCount = 0
    )

    $allImages = @(Get-TopLevelImages -Directory $Directory -ExcludeNames $ExcludeNames)
    if ($allImages.Count -eq 0) {
        return [pscustomobject]@{
            Images = @()
            BatchId = $RequestedBatchId
            ExpectedCount = [Math]::Max(0, $RequestedExpectedCount)
            IsComplete = [string]::IsNullOrWhiteSpace($RequestedBatchId)
            BatchFound = [string]::IsNullOrWhiteSpace($RequestedBatchId)
        }
    }

    $batchPattern = '^chatgpt-workpkg-(?<batch>\d{8}-\d{6}-[a-z0-9]{4})-(?<index>\d+)-of-(?<total>\d+)\.[^.]+$'
    $batchRows = @($allImages | ForEach-Object {
        $match = [regex]::Match($_.Name, $batchPattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            [pscustomobject]@{
                File = $_
                BatchId = $match.Groups['batch'].Value
                Index = [int]$match.Groups['index'].Value
                Total = [int]$match.Groups['total'].Value
            }
        }
    })

    if ($batchRows.Count -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($RequestedBatchId)) {
            return [pscustomobject]@{
                Images = @()
                BatchId = $RequestedBatchId
                ExpectedCount = [Math]::Max(0, $RequestedExpectedCount)
                IsComplete = $false
                BatchFound = $false
            }
        }
        return [pscustomobject]@{
            Images = $allImages
            BatchId = ""
            ExpectedCount = $allImages.Count
            IsComplete = $true
            BatchFound = $true
        }
    }

    $groupedBatches = @($batchRows | Group-Object BatchId | ForEach-Object {
        [pscustomobject]@{
            BatchId = $_.Name
            Rows = @($_.Group)
            LastWriteTime = (@($_.Group.File | Sort-Object LastWriteTime -Descending)[0]).LastWriteTime
        }
    } | Sort-Object LastWriteTime -Descending)
    $latestBatch = if ([string]::IsNullOrWhiteSpace($RequestedBatchId)) {
        @($groupedBatches)[0]
    } else {
        @($groupedBatches | Where-Object { $_.BatchId -eq $RequestedBatchId } | Select-Object -First 1)
    }
    if (@($latestBatch).Count -eq 0) {
        return [pscustomobject]@{
            Images = @()
            BatchId = $RequestedBatchId
            ExpectedCount = [Math]::Max(0, $RequestedExpectedCount)
            IsComplete = $false
            BatchFound = $false
        }
    }
    $latestBatch = @($latestBatch)[0]

    $rows = @($latestBatch.Rows | Sort-Object Index)
    $declaredCount = [int](@($rows.Total | Sort-Object -Descending)[0])
    $expectedCount = [Math]::Max(1, [Math]::Max($declaredCount, $RequestedExpectedCount))
    $uniqueIndexes = @($rows.Index | Sort-Object -Unique)

    return [pscustomobject]@{
        Images = @($rows.File)
        BatchId = [string]$latestBatch.BatchId
        ExpectedCount = $expectedCount
        IsComplete = ($rows.Count -eq $expectedCount -and $uniqueIndexes.Count -eq $expectedCount)
        BatchFound = $true
    }
}

function Set-WorkPackageTaskProperty {
    param(
        [object]$Task,
        [string]$Name,
        [object]$Value
    )

    if ($null -eq $Task.PSObject.Properties[$Name]) {
        $Task | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $Task.$Name = $Value
    }
}

function Save-WorkPackageTaskJson {
    param(
        [object]$Task,
        [string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $json = $Task | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Wait-WorkPackageTask {
    param(
        [string]$Directory,
        [string]$RequestedBatchId,
        [int]$WaitSeconds = 20
    )

    if ([string]::IsNullOrWhiteSpace($RequestedBatchId)) {
        return $null
    }
    if ($RequestedBatchId -notmatch '^[A-Za-z0-9-]{8,80}$') {
        throw "Invalid work package batch id: $RequestedBatchId"
    }

    $taskPath = Join-Path $Directory "chatgpt-workpkg-task-$RequestedBatchId.json"
    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $WaitSeconds))
    do {
        if (Test-Path -LiteralPath $taskPath -PathType Leaf) {
            try {
                $task = Get-Content -LiteralPath $taskPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([string]$task.batchId -eq $RequestedBatchId) {
                    return [pscustomobject]@{
                        Path = $taskPath
                        Data = $task
                    }
                }
            } catch {
                # The browser may still be finishing the small JSON download.
            }
        }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)

    return $null
}

function Get-FileSha256Hex {
    param([string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        return -join ($sha.ComputeHash($stream) | ForEach-Object { $_.ToString("x2") })
    } finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        $sha.Dispose()
    }
}

function Get-ImageDHash {
    param([string]$Path)

    $sourceImage = $null
    $smallBitmap = $null
    $graphics = $null
    try {
        Add-Type -AssemblyName System.Drawing
        $sourceImage = [System.Drawing.Image]::FromFile($Path)
        $smallBitmap = New-Object System.Drawing.Bitmap 9, 8
        $graphics = [System.Drawing.Graphics]::FromImage($smallBitmap)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
        $graphics.DrawImage($sourceImage, 0, 0, 9, 8)

        $hashBytes = New-Object byte[] 8
        for ($y = 0; $y -lt 8; $y++) {
            for ($x = 0; $x -lt 8; $x++) {
                $left = $smallBitmap.GetPixel($x, $y)
                $right = $smallBitmap.GetPixel($x + 1, $y)
                $leftLuma = (299 * $left.R) + (587 * $left.G) + (114 * $left.B)
                $rightLuma = (299 * $right.R) + (587 * $right.G) + (114 * $right.B)
                if ($leftLuma -gt $rightLuma) {
                    $bitIndex = ($y * 8) + $x
                    $byteIndex = [Math]::Floor($bitIndex / 8)
                    $bitInByte = 7 - ($bitIndex % 8)
                    $hashBytes[$byteIndex] = $hashBytes[$byteIndex] -bor (1 -shl $bitInByte)
                }
            }
        }

        return -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
    } catch {
        return ""
    } finally {
        if ($null -ne $graphics) {
            $graphics.Dispose()
        }
        if ($null -ne $smallBitmap) {
            $smallBitmap.Dispose()
        }
        if ($null -ne $sourceImage) {
            $sourceImage.Dispose()
        }
    }
}

function Get-HammingDistanceHex {
    param(
        [string]$First,
        [string]$Second
    )

    if ($First.Length -ne 16 -or $Second.Length -ne 16) {
        return 64
    }

    $distance = 0
    for ($i = 0; $i -lt 16; $i += 2) {
        $value = [Convert]::ToByte($First.Substring($i, 2), 16) -bxor [Convert]::ToByte($Second.Substring($i, 2), 16)
        while ($value -ne 0) {
            $distance += ($value -band 1)
            $value = $value -shr 1
        }
    }
    return $distance
}

function Get-ImageHashInfo {
    param([object[]]$Images)

    $hashes = @($Images | ForEach-Object { Get-FileSha256Hex -Path $_.FullName } | Sort-Object)
    $perceptualHashes = @($Images | ForEach-Object { Get-ImageDHash -Path $_.FullName })
    $payload = "$($hashes.Count)`n$($hashes -join "`n")"

    return [pscustomobject]@{
        Count = $hashes.Count
        Hashes = $hashes
        PerceptualHashes = $perceptualHashes
        SetHash = Get-Sha256Hex -Text $payload
    }
}

function Get-VisualSimilarityMatch {
    param(
        [object]$Database,
        [object]$ImageHashInfo,
        [int]$MaxDistance = 6,
        [double]$MaxAverageDistance = 3
    )

    $currentHashes = @($ImageHashInfo.PerceptualHashes)
    if ($currentHashes.Count -eq 0 -or @($currentHashes | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        return $null
    }

    $bestMatch = $null
    foreach ($entry in @($Database.entries)) {
        $property = $entry.PSObject.Properties["imagePerceptualHash"]
        if ($null -eq $property) {
            continue
        }

        $historyHashes = @($entry.imagePerceptualHash)
        if ($historyHashes.Count -ne $currentHashes.Count -or @($historyHashes | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            continue
        }

        $pairs = New-Object System.Collections.Generic.List[object]
        for ($currentIndex = 0; $currentIndex -lt $currentHashes.Count; $currentIndex++) {
            for ($historyIndex = 0; $historyIndex -lt $historyHashes.Count; $historyIndex++) {
                $distance = Get-HammingDistanceHex -First $currentHashes[$currentIndex] -Second $historyHashes[$historyIndex]
                if ($distance -le $MaxDistance) {
                    $pairs.Add([pscustomobject]@{
                        Current = $currentIndex
                        History = $historyIndex
                        Distance = $distance
                    }) | Out-Null
                }
            }
        }

        $usedCurrent = @{}
        $usedHistory = @{}
        $matchedDistances = New-Object System.Collections.Generic.List[int]
        foreach ($pair in @($pairs | Sort-Object Distance, Current, History)) {
            if (-not $usedCurrent.ContainsKey($pair.Current) -and -not $usedHistory.ContainsKey($pair.History)) {
                $usedCurrent[$pair.Current] = $true
                $usedHistory[$pair.History] = $true
                $matchedDistances.Add([int]$pair.Distance) | Out-Null
            }
        }

        if ($matchedDistances.Count -ne $currentHashes.Count) {
            continue
        }

        $averageDistance = ($matchedDistances | Measure-Object -Average).Average
        if ($averageDistance -gt $MaxAverageDistance) {
            continue
        }

        if ($null -eq $bestMatch -or $averageDistance -lt $bestMatch.AverageDistance) {
            $bestMatch = [pscustomobject]@{
                Entry = $entry
                AverageDistance = [Math]::Round($averageDistance, 2)
                MaximumDistance = ($matchedDistances | Measure-Object -Maximum).Maximum
            }
        }
    }

    return $bestMatch
}

function New-WorkHistoryDatabase {
    $now = [DateTime]::UtcNow.ToString("o")
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        createdAt = $now
        updatedAt = $now
        portfolioLastIssued = 0
        entries = @()
    }
}

function Test-WorkHistoryDatabase {
    param([object]$Database)

    return (
        $null -ne $Database -and
        $null -ne $Database.PSObject.Properties["schemaVersion"] -and
        [int]$Database.schemaVersion -eq 1 -and
        $null -ne $Database.PSObject.Properties["entries"]
    )
}

function Read-WorkHistoryDatabaseFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    try {
        $database = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (Test-WorkHistoryDatabase -Database $database) {
            if ($null -eq $database.PSObject.Properties["portfolioLastIssued"]) {
                $database | Add-Member -MemberType NoteProperty -Name "portfolioLastIssued" -Value 0
            }
            return $database
        }
    } catch {
    }

    return $null
}

function Write-JsonFileAtomic {
    param(
        [string]$Path,
        [string]$Json
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $temporaryPath = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $Json, (New-Object System.Text.UTF8Encoding($false)))
        $validated = Get-Content -LiteralPath $temporaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not (Test-WorkHistoryDatabase -Database $validated)) {
            throw "History database validation failed."
        }
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Save-WorkHistoryDatabase {
    param(
        [object]$Database,
        [string]$PrimaryPath,
        [string]$BackupPath,
        [string]$RuntimeMirrorPath
    )

    $Database.updatedAt = [DateTime]::UtcNow.ToString("o")
    $json = $Database | ConvertTo-Json -Depth 8

    if (Test-Path -LiteralPath $PrimaryPath -PathType Leaf) {
        $existingDatabase = Read-WorkHistoryDatabaseFile -Path $PrimaryPath
        if ($null -ne $existingDatabase) {
            $existingJson = $existingDatabase | ConvertTo-Json -Depth 8
            Write-JsonFileAtomic -Path $BackupPath -Json $existingJson
        }
    }

    Write-JsonFileAtomic -Path $PrimaryPath -Json $json
    if ($null -eq (Read-WorkHistoryDatabaseFile -Path $BackupPath)) {
        Write-JsonFileAtomic -Path $BackupPath -Json $json
    }
    Write-JsonFileAtomic -Path $RuntimeMirrorPath -Json $json

    try {
        $mirrorItem = Get-Item -LiteralPath $RuntimeMirrorPath -Force
        $mirrorItem.Attributes = $mirrorItem.Attributes -bor [System.IO.FileAttributes]::Hidden
    } catch {
    }
}

function Get-WorkHistoryDatabase {
    param(
        [string]$PrimaryPath,
        [string]$BackupPath,
        [string]$RuntimeMirrorPath
    )

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($candidate in @(
        [pscustomobject]@{ Path = $PrimaryPath; Priority = 3 },
        [pscustomobject]@{ Path = $RuntimeMirrorPath; Priority = 2 },
        [pscustomobject]@{ Path = $BackupPath; Priority = 1 }
    )) {
        $database = Read-WorkHistoryDatabaseFile -Path $candidate.Path
        if ($null -ne $database) {
            $updatedAt = [datetime]::MinValue
            try {
                $updatedAt = [datetime]::Parse([string]$database.updatedAt).ToUniversalTime()
            } catch {
            }
            $candidates.Add([pscustomobject]@{
                Path = $candidate.Path
                Priority = $candidate.Priority
                UpdatedAt = $updatedAt
                Database = $database
            }) | Out-Null
        }
    }

    $selected = @($candidates | Sort-Object UpdatedAt, Priority -Descending | Select-Object -First 1)
    if ($selected.Count -gt 0) {
        return [pscustomobject]@{
            Database = $selected[0].Database
            SourcePath = $selected[0].Path
            IsNew = $false
        }
    }

    return [pscustomobject]@{
        Database = New-WorkHistoryDatabase
        SourcePath = ""
        IsNew = $true
    }
}

function Add-WorkHistoryEntry {
    param(
        [object]$Database,
        [string]$TextHash,
        [object]$ImageHashInfo,
        [string]$Title,
        [string]$PackageFolder,
        [string]$PackagePath = "",
        [string]$Source = "created",
        [datetime]$RecordedAt = (Get-Date)
    )

    if (@($Database.entries | Where-Object { $_.imageSetSha256 -eq $ImageHashInfo.SetHash }).Count -gt 0) {
        return $false
    }

    $entry = [pscustomobject][ordered]@{
        id = [guid]::NewGuid().ToString("N")
        recordedAt = $RecordedAt.ToUniversalTime().ToString("o")
        textSha256 = $TextHash
        imageSetSha256 = $ImageHashInfo.SetHash
        imageCount = $ImageHashInfo.Count
        imageSha256 = @($ImageHashInfo.Hashes)
        imagePerceptualHash = @($ImageHashInfo.PerceptualHashes)
        title = $Title
        packageFolder = $PackageFolder
        packagePath = $PackagePath
        source = $Source
    }
    $Database.entries = @($Database.entries) + @($entry)
    return $true
}

function Test-ImageSetHashExists {
    param(
        [object]$Database,
        [string]$ImageSetHash
    )

    return @($Database.entries | Where-Object { $_.imageSetSha256 -eq $ImageSetHash }).Count -gt 0
}

function Import-ExistingPackagesIntoHistory {
    param(
        [object]$Database,
        [string]$LibraryDirectory,
        [string]$TextPrefix
    )

    $imported = 0
    $duplicateFolders = New-Object System.Collections.Generic.List[string]
    foreach ($textFile in @(Get-PackagedTextFiles -Directory $LibraryDirectory -TextPrefix $TextPrefix -Recurse | Sort-Object LastWriteTime, FullName)) {
        try {
            $packageImages = Get-TopLevelImages -Directory $textFile.DirectoryName
            if ($packageImages.Count -eq 0) {
                continue
            }

            $text = [System.IO.File]::ReadAllText($textFile.FullName)
            $imageHashInfo = Get-ImageHashInfo -Images $packageImages
            $title = Get-TitleLine -Text $text
            if (Add-WorkHistoryEntry `
                -Database $Database `
                -TextHash (Get-TextHash -Text $text) `
                -ImageHashInfo $imageHashInfo `
                -Title $title `
                -PackageFolder $textFile.Directory.Name `
                -PackagePath $textFile.DirectoryName `
                -Source "migration" `
                -RecordedAt $textFile.LastWriteTime) {
                $imported++
            } elseif (-not $duplicateFolders.Contains($textFile.DirectoryName)) {
                $duplicateFolders.Add($textFile.DirectoryName) | Out-Null
            }
        } catch {
        }
    }

    return [pscustomobject]@{
        Imported = $imported
        DuplicateFolders = $duplicateFolders.ToArray()
    }
}

function Remove-DirectoryToRecycleBin {
    param(
        [string]$Path,
        [string]$AllowedRoot
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedRoot = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\') + '\'
    if (-not $resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a folder outside the configured library: $resolvedPath"
    }

    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
        $resolvedPath,
        [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
        [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
    )
    return -not (Test-Path -LiteralPath $resolvedPath)
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

function Get-PortfolioHistoryMaxNumber {
    param(
        [object]$Database,
        [string]$LibraryDir,
        [string]$PortfolioPrefix,
        [string]$LogFolderName
    )

    $maxNumber = 0
    if ($null -ne $Database -and $null -ne $Database.PSObject.Properties["portfolioLastIssued"]) {
        $maxNumber = [Math]::Max($maxNumber, [int]$Database.portfolioLastIssued)
    }

    $portfolioNameCore = $PortfolioPrefix.TrimStart('.')
    $portfolioPattern = "(?i)\.?$([regex]::Escape($portfolioNameCore))_(\d+)"
    $candidateTexts = New-Object System.Collections.Generic.List[string]

    if ($null -ne $Database) {
        foreach ($entry in @($Database.entries)) {
            $candidateTexts.Add([string]$entry.packageFolder) | Out-Null
            $candidateTexts.Add([string]$entry.packagePath) | Out-Null
        }
    }

    if (Test-Path -LiteralPath $LibraryDir -PathType Container) {
        foreach ($item in @(Get-ChildItem -LiteralPath $LibraryDir -Force -ErrorAction SilentlyContinue)) {
            $candidateTexts.Add([string]$item.Name) | Out-Null
            $candidateTexts.Add([string]$item.FullName) | Out-Null
        }

        $logDirectory = Join-Path $LibraryDir $LogFolderName
        if (Test-Path -LiteralPath $logDirectory -PathType Container) {
            foreach ($logFile in @(Get-ChildItem -LiteralPath $logDirectory -File -Force -ErrorAction SilentlyContinue)) {
                $candidateTexts.Add([string]$logFile.Name) | Out-Null
                try {
                    foreach ($match in [regex]::Matches(
                        [System.IO.File]::ReadAllText($logFile.FullName),
                        $portfolioPattern
                    )) {
                        $number = [int]$match.Groups[1].Value
                        if ($number -gt $maxNumber) {
                            $maxNumber = $number
                        }
                    }
                } catch {
                }
            }
        }
    }

    foreach ($textValue in $candidateTexts) {
        foreach ($match in [regex]::Matches([string]$textValue, $portfolioPattern)) {
            $number = [int]$match.Groups[1].Value
            if ($number -gt $maxNumber) {
                $maxNumber = $number
            }
        }
    }

    return $maxNumber
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
        [int]$MinimumExistingNumber = 0,
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
        HighestIssuedNumber = [Math]::Max(0, $MinimumExistingNumber)
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

    $maxExistingNumber = [Math]::Max(0, $MinimumExistingNumber)
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
            HighestIssuedNumber = $maxExistingNumber
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
        HighestIssuedNumber = if (@($results | Where-Object { $_.Result -eq "Moved" }).Count -gt 0) {
            $maxExistingNumber + $fullBatchCount
        } else {
            $maxExistingNumber
        }
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

function Resolve-HistoryPackagePath {
    param(
        [object]$Entry,
        [string]$LibraryDirectory
    )

    $storedPath = [string]$Entry.packagePath
    if (-not [string]::IsNullOrWhiteSpace($storedPath) -and (Test-Path -LiteralPath $storedPath -PathType Container)) {
        return $storedPath
    }

    $folderName = [string]$Entry.packageFolder
    if (-not [string]::IsNullOrWhiteSpace($folderName) -and (Test-Path -LiteralPath $LibraryDirectory -PathType Container)) {
        $found = @(Get-ChildItem -LiteralPath $LibraryDirectory -Directory -Force -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $folderName } |
            Select-Object -First 1)
        if ($found.Count -gt 0) {
            return $found[0].FullName
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($storedPath)) {
        return $storedPath
    }
    return $folderName
}

function Copy-PathToClipboard {
    param([string]$Path)

    if ($clipboardTextOverrideSpecified -or [string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    try {
        Set-Clipboard -Value $Path
    } catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [System.Windows.Forms.Clipboard]::SetText($Path)
        } catch {
        }
    }
}

function Save-VisualSimilarityOverride {
    param(
        [string]$Path,
        [string]$ImageSetHash
    )

    $state = [ordered]@{
        imageSetSha256 = $ImageSetHash
        createdAt = [DateTime]::UtcNow.ToString("o")
    }
    [System.IO.File]::WriteAllText($Path, ($state | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
    try {
        $item = Get-Item -LiteralPath $Path -Force
        $item.Attributes = $item.Attributes -bor [System.IO.FileAttributes]::Hidden
    } catch {
    }
}

function Test-AndConsumeVisualSimilarityOverride {
    param(
        [string]$Path,
        [string]$ImageSetHash,
        [int]$ValidMinutes = 30
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    $isValid = $false
    try {
        $state = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        $createdAt = [datetime]::Parse([string]$state.createdAt).ToUniversalTime()
        $isValid = (
            [string]$state.imageSetSha256 -eq $ImageSetHash -and
            ([DateTime]::UtcNow - $createdAt).TotalMinutes -le $ValidMinutes
        )
    } catch {
    }

    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    return $isValid
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
$configuredInboxPath = [Environment]::ExpandEnvironmentVariables(([string]$config.image_inbox_path).Trim())
if ([string]::IsNullOrWhiteSpace($configuredInboxPath)) {
    $imageInboxDir = $scriptDir
} else {
    if (-not [System.IO.Path]::IsPathRooted($configuredInboxPath)) {
        throw "workpkg_config.json image_inbox_path must be an absolute path: $configuredInboxPath"
    }
    $imageInboxDir = [System.IO.Path]::GetFullPath($configuredInboxPath)
}
$configuredLibraryPath = [Environment]::ExpandEnvironmentVariables(([string]$config.library_path).Trim())
if ([string]::IsNullOrWhiteSpace($configuredLibraryPath)) {
    $libraryDir = Join-Path $scriptDir $libraryName
} else {
    if (-not [System.IO.Path]::IsPathRooted($configuredLibraryPath)) {
        throw "workpkg_config.json library_path must be an absolute path: $configuredLibraryPath"
    }
    $libraryDir = [System.IO.Path]::GetFullPath($configuredLibraryPath)
}
$historyDirectory = Join-Path $libraryDir "_作品历史数据"
$historyPath = Join-Path $historyDirectory "作品历史数据库.json"
$historyBackupPath = Join-Path $historyDirectory "作品历史数据库.backup.json"
$historyRuntimeMirrorPath = Join-Path $scriptDir ".workpkg_history_backup.json"

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
$similarTextMessage = "本组有历史相似文案，但图片不同，已继续创建作品包。"
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
$visualSimilarityEnabled = [bool]$config.visual_similarity_enabled
$visualSimilarityMaxDistance = [Math]::Max(0, [Math]::Min(64, [int]$config.visual_similarity_max_distance))
$visualSimilarityMaxAverage = [Math]::Max(0, [double]$config.visual_similarity_max_average)
$lockStream = $null
$lockPath = Join-Path $scriptDir ".workpkg.lock"
$lastHashPath = Join-Path $scriptDir ".workpkg_last_text.sha256"
$visualOverridePath = Join-Path $scriptDir ".workpkg_visual_similarity_override.json"
$stagingDir = $null
$movedImages = New-Object System.Collections.Generic.List[object]
$packageCommitted = $false
$taskData = $null
$taskPath = ""

try {
    if ($Diagnose) {
        $inboxExists = Test-Path -LiteralPath $imageInboxDir -PathType Container
        $libraryExists = Test-Path -LiteralPath $libraryDir -PathType Container
        $inboxImageCount = if ($inboxExists) {
            @(Get-TopLevelImages -Directory $imageInboxDir -ExcludeNames $imageExcludeNames).Count
        } else {
            0
        }
        $diagnosticMessage = @(
            "GPT 作品包环境检查"
            ""
            "图片下载目录：$imageInboxDir"
            "目录状态：$(if ($inboxExists) { '正常' } else { '不存在' })"
            "当前图片：$inboxImageCount 张"
            ""
            "成品库：$libraryDir"
            "目录状态：$(if ($libraryExists) { '正常' } else { '尚未创建，将在首次打包时创建' })"
            ""
            "本地打包器：$workPackageScriptVersion"
        ) -join "`r`n"
        if (-not $NoMessage) {
            Add-Type -AssemblyName PresentationFramework
            [System.Windows.MessageBox]::Show($diagnosticMessage, "GPT 作品包自检", "OK", "Information") | Out-Null
        }
        Write-Output "DIAGNOSTIC"
        Write-Output "Version=$workPackageScriptVersion"
        Write-Output "ImageInbox=$imageInboxDir"
        Write-Output "InboxExists=$inboxExists"
        Write-Output "InboxImages=$inboxImageCount"
        Write-Output "Library=$libraryDir"
        Write-Output "LibraryExists=$libraryExists"
        return
    }

    if (Test-Path -LiteralPath $lockPath) {
        try {
            $lockItem = Get-Item -LiteralPath $lockPath -Force
            if (((Get-Date) - $lockItem.LastWriteTime).TotalSeconds -gt 30) {
                Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
            }
        } catch {
        }
    }

    $queueDeadline = (Get-Date).AddMinutes(5)
    do {
        try {
            $lockStream = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch {
            $lockStream = $null
            Start-Sleep -Milliseconds 250
        }
    } while ($null -eq $lockStream -and (Get-Date) -lt $queueDeadline)
    if ($null -eq $lockStream) {
        Show-Tip -Message "本地打包队列等待超时，请稍后再试。"
        if ($NoMessage) {
            Write-Output "QUEUE_TIMEOUT"
            Write-Output "Version=$workPackageScriptVersion"
            Write-Output "BatchId=$BatchId"
        }
        return
    }

    if ($RebuildHistory) {
        if (-not (Test-Path -LiteralPath $libraryDir -PathType Container)) {
            throw "Configured library does not exist: $libraryDir"
        }

        $rebuiltDatabase = New-WorkHistoryDatabase
        $migrationResult = Import-ExistingPackagesIntoHistory `
            -Database $rebuiltDatabase `
            -LibraryDirectory $libraryDir `
            -TextPrefix $textPrefix
        $rebuiltDatabase.portfolioLastIssued = Get-PortfolioHistoryMaxNumber `
            -Database $rebuiltDatabase `
            -LibraryDir $libraryDir `
            -PortfolioPrefix $portfolioPrefix `
            -LogFolderName $portfolioLogFolder

        if ($Preview) {
            Write-Output "PREVIEW_HISTORY_REBUILD"
            Write-Output "Version=$workPackageScriptVersion"
            Write-Output "UniqueImageSets=$($migrationResult.Imported)"
            Write-Output "DuplicateFolders=$(@($migrationResult.DuplicateFolders).Count)"
            foreach ($duplicateFolder in @($migrationResult.DuplicateFolders)) {
                Write-Output "DuplicateFolder=$duplicateFolder"
            }
            return
        }

        Save-WorkHistoryDatabase `
            -Database $rebuiltDatabase `
            -PrimaryPath $historyPath `
            -BackupPath $historyBackupPath `
            -RuntimeMirrorPath $historyRuntimeMirrorPath

        $removedDuplicateFolders = 0
        $failedDuplicateFolders = 0
        if ($CleanExistingDuplicates) {
            foreach ($duplicateFolder in @($migrationResult.DuplicateFolders)) {
                try {
                    if (Remove-DirectoryToRecycleBin -Path $duplicateFolder -AllowedRoot $libraryDir) {
                        $removedDuplicateFolders++
                    } else {
                        $failedDuplicateFolders++
                    }
                } catch {
                    $failedDuplicateFolders++
                }
            }
        }

        Write-Output "HISTORY_REBUILT"
        Write-Output "Version=$workPackageScriptVersion"
        Write-Output "HistoryDatabase=$historyPath"
        Write-Output "UniqueImageSets=$($migrationResult.Imported)"
        Write-Output "DuplicateFolders=$(@($migrationResult.DuplicateFolders).Count)"
        Write-Output "RemovedDuplicateFolders=$removedDuplicateFolders"
        Write-Output "FailedDuplicateFolders=$failedDuplicateFolders"
        return
    }

    $taskState = Wait-WorkPackageTask -Directory $imageInboxDir -RequestedBatchId $BatchId -WaitSeconds 20
    $taskData = if ($null -ne $taskState) { $taskState.Data } else { $null }
    $taskPath = if ($null -ne $taskState) { [string]$taskState.Path } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($BatchId) -and $null -eq $taskData) {
        Show-Tip -Message "没有收到本次任务清单，请检查浏览器下载目录。"
        if ($NoMessage) {
            Write-Output "TASK_MISSING"
            Write-Output "Version=$workPackageScriptVersion"
            Write-Output "BatchId=$BatchId"
        }
        return
    }

    if ($null -ne $taskData) {
        Set-WorkPackageTaskProperty -Task $taskData -Name "status" -Value "processing"
        Set-WorkPackageTaskProperty -Task $taskData -Name "processingAt" -Value ((Get-Date).ToString("o"))
        Save-WorkPackageTaskJson -Task $taskData -Path $taskPath
        $text = [string]$taskData.copyText
        $metadataOverride = [ordered]@{
            accountName = [string]$taskData.accountName
            conversationUrl = [string]$taskData.conversationUrl
        } | ConvertTo-Json -Compress
        $ConversationMetadataJsonOverride = $metadataOverride
        $conversationMetadataOverrideSpecified = $true
    } else {
        $text = Get-ClipboardText
    }
    if ($null -eq $text -or [string]::IsNullOrWhiteSpace($text)) {
        Show-Tip -Message (New-TextFromCodePoints @(0x8BF7, 0x5148, 0x590D, 0x5236, 0x6587, 0x6848))
        return
    }

    $inboxSelection = Get-WorkPackageInboxImages `
        -Directory $imageInboxDir `
        -ExcludeNames $imageExcludeNames `
        -RequestedBatchId $BatchId `
        -RequestedExpectedCount $ExpectedImageCount
    $images = @($inboxSelection.Images)
    if ($images.Count -eq 0) {
        if ($null -ne $taskData) {
            Set-WorkPackageTaskProperty -Task $taskData -Name "status" -Value "waiting_images"
            Set-WorkPackageTaskProperty -Task $taskData -Name "actualImages" -Value 0
            Save-WorkPackageTaskJson -Task $taskData -Path $taskPath
        }
        $missingBatchMessage = if ([string]::IsNullOrWhiteSpace($BatchId)) {
            $noImageMessage
        } else {
            "没有找到本次批次图片，请检查浏览器下载是否完成。"
        }
        Show-Tip -Message $missingBatchMessage
        return
    }
    if (-not $inboxSelection.IsComplete) {
        if ($null -ne $taskData) {
            Set-WorkPackageTaskProperty -Task $taskData -Name "status" -Value "incomplete_images"
            Set-WorkPackageTaskProperty -Task $taskData -Name "actualImages" -Value $images.Count
            Save-WorkPackageTaskJson -Task $taskData -Path $taskPath
        }
        $incompleteMessage = "本组图片尚未下载完整：$($images.Count)/$($inboxSelection.ExpectedCount)，请稍后再打包。"
        Show-Tip -Message $incompleteMessage
        if ($NoMessage) {
            Write-Output "INCOMPLETE_BATCH"
            Write-Output "Version=$workPackageScriptVersion"
            Write-Output "BatchId=$($inboxSelection.BatchId)"
            Write-Output "DownloadedImages=$($images.Count)"
            Write-Output "ExpectedImages=$($inboxSelection.ExpectedCount)"
        }
        return
    }

    if (-not $Preview -and -not (Test-Path -LiteralPath $libraryDir)) {
        New-Item -ItemType Directory -Path $libraryDir | Out-Null
    }

    $currentHash = Get-TextHash -Text $text
    $imageHashInfo = Get-ImageHashInfo -Images $images
    $historyState = Get-WorkHistoryDatabase `
        -PrimaryPath $historyPath `
        -BackupPath $historyBackupPath `
        -RuntimeMirrorPath $historyRuntimeMirrorPath
    $historyDatabase = $historyState.Database
    $historyMigrated = 0
    $storedPortfolioLastIssued = [int]$historyDatabase.portfolioLastIssued
    $inferredPortfolioLastIssued = Get-PortfolioHistoryMaxNumber `
        -Database $historyDatabase `
        -LibraryDir $libraryDir `
        -PortfolioPrefix $portfolioPrefix `
        -LogFolderName $portfolioLogFolder
    if ($inferredPortfolioLastIssued -gt $storedPortfolioLastIssued) {
        $historyDatabase.portfolioLastIssued = $inferredPortfolioLastIssued
    }

    if ($historyState.IsNew) {
        $migrationResult = Import-ExistingPackagesIntoHistory `
            -Database $historyDatabase `
            -LibraryDirectory $libraryDir `
            -TextPrefix $textPrefix
        $historyMigrated = $migrationResult.Imported
    }

    if (-not $Preview -and (
        $historyState.IsNew -or
        $historyState.SourcePath -ne $historyPath -or
        $inferredPortfolioLastIssued -gt $storedPortfolioLastIssued
    )) {
        Save-WorkHistoryDatabase `
            -Database $historyDatabase `
            -PrimaryPath $historyPath `
            -BackupPath $historyBackupPath `
            -RuntimeMirrorPath $historyRuntimeMirrorPath
    }

    $duplicateExists = Test-ImageSetHashExists -Database $historyDatabase -ImageSetHash $imageHashInfo.SetHash
    $similarTextExists = @($historyDatabase.entries | Where-Object { $_.textSha256 -eq $currentHash }).Count -gt 0

    if ($duplicateExists) {
        if ($Preview) {
            Write-Output "PREVIEW_DUPLICATE"
            Write-Output "Version=$workPackageScriptVersion"
            Write-Output "WouldDeleteImages=$($images.Count)"
            Write-Output "DuplicateReason=ExactImageSet"
            return
        }
        $removedImages = Remove-DuplicateDownloadImages -Images $images
        if ($null -ne $taskData) {
            Set-WorkPackageTaskProperty -Task $taskData -Name "status" -Value "duplicate"
            Set-WorkPackageTaskProperty -Task $taskData -Name "completedAt" -Value ((Get-Date).ToString("o"))
            Set-WorkPackageTaskProperty -Task $taskData -Name "actualImages" -Value $images.Count
            Set-WorkPackageTaskProperty -Task $taskData -Name "duplicateReason" -Value "ExactImageSet"
            $taskLogPath = Join-Path (Join-Path $scriptDir "任务记录") "chatgpt-workpkg-task-$BatchId.json"
            Save-WorkPackageTaskJson -Task $taskData -Path $taskLogPath
            if (-not [string]::IsNullOrWhiteSpace($taskPath) -and (Test-Path -LiteralPath $taskPath -PathType Leaf)) {
                Remove-Item -LiteralPath $taskPath -Force -ErrorAction SilentlyContinue
            }
        } else {
            Clear-ClipboardAfterSuccess
        }
        Show-Tip -Message $duplicateExistingMessage
        if ($NoMessage) {
            Write-Output "DUPLICATE"
            Write-Output "Version=$workPackageScriptVersion"
            Write-Output "DeletedImages=$removedImages"
            Write-Output "DuplicateReason=ExactImageSet"
            Write-Output "HistoryEntries=$(@($historyDatabase.entries).Count)"
        }
        return
    }

    $visualSimilarityBypassed = Test-AndConsumeVisualSimilarityOverride `
        -Path $visualOverridePath `
        -ImageSetHash $imageHashInfo.SetHash
    if ($visualSimilarityEnabled -and -not $visualSimilarityBypassed) {
        $visualMatch = Get-VisualSimilarityMatch `
            -Database $historyDatabase `
            -ImageHashInfo $imageHashInfo `
            -MaxDistance $visualSimilarityMaxDistance `
            -MaxAverageDistance $visualSimilarityMaxAverage
        if ($null -ne $visualMatch) {
            $similarPackagePath = Resolve-HistoryPackagePath -Entry $visualMatch.Entry -LibraryDirectory $libraryDir
            Save-VisualSimilarityOverride -Path $visualOverridePath -ImageSetHash $imageHashInfo.SetHash
            Copy-PathToClipboard -Path $similarPackagePath
            if ($null -ne $taskData) {
                Set-WorkPackageTaskProperty -Task $taskData -Name "status" -Value "visual_similar"
                Set-WorkPackageTaskProperty -Task $taskData -Name "similarPackagePath" -Value $similarPackagePath
                Set-WorkPackageTaskProperty -Task $taskData -Name "visualAverageDistance" -Value $visualMatch.AverageDistance
                Set-WorkPackageTaskProperty -Task $taskData -Name "visualMaximumDistance" -Value $visualMatch.MaximumDistance
                Save-WorkPackageTaskJson -Task $taskData -Path $taskPath
            }
            Show-Tip -Message "检测到图片视觉近似历史作品，已停止打包；相似包路径已复制。"
            if ($NoMessage) {
                Write-Output "VISUAL_SIMILAR"
                Write-Output "Version=$workPackageScriptVersion"
                Write-Output "SimilarPackage=$similarPackagePath"
                Write-Output "AverageDistance=$($visualMatch.AverageDistance)"
                Write-Output "MaximumDistance=$($visualMatch.MaximumDistance)"
                Write-Output "ImagesPreserved=$($images.Count)"
            }
            return
        }
    }

    $title = Get-SafeNamePart -Text (Get-TitleLine -Text $text)
    $gptConversationTitle = if ($null -ne $taskData -and -not [string]::IsNullOrWhiteSpace([string]$taskData.conversationTitle)) {
        Get-NormalizedGptWindowTitle -WindowTitle ([string]$taskData.conversationTitle)
    } else {
        Get-GptConversationTitle
    }
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

    $taskRecordFileName = "GPT任务记录.json"
    if ($null -ne $taskData) {
        Set-WorkPackageTaskProperty -Task $taskData -Name "status" -Value "completed"
        Set-WorkPackageTaskProperty -Task $taskData -Name "completedAt" -Value ((Get-Date).ToString("o"))
        Set-WorkPackageTaskProperty -Task $taskData -Name "actualImages" -Value $images.Count
        Set-WorkPackageTaskProperty -Task $taskData -Name "textSha256" -Value $currentHash
        Set-WorkPackageTaskProperty -Task $taskData -Name "imageSetSha256" -Value $imageHashInfo.SetHash
        Set-WorkPackageTaskProperty -Task $taskData -Name "packageFolder" -Value (Split-Path -Leaf $targetDir)
        Save-WorkPackageTaskJson -Task $taskData -Path (Join-Path $stagingDir $taskRecordFileName)
        Set-FileTimes -Path (Join-Path $stagingDir $taskRecordFileName) -Time $packageTime
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
        $portfolioResult = Invoke-PortfolioAutoGroup `
            -LibraryDir $libraryDir `
            -BatchSize $portfolioBatchSize `
            -PortfolioPrefix $portfolioPrefix `
            -LogFolderName $portfolioLogFolder `
            -MinimumExistingNumber ([int]$historyDatabase.portfolioLastIssued) `
            -CreateZip:$portfolioAutoZip
        if ($null -ne $portfolioResult -and $portfolioResult.HighestIssuedNumber -gt [int]$historyDatabase.portfolioLastIssued) {
            $historyDatabase.portfolioLastIssued = [int]$portfolioResult.HighestIssuedNumber
        }
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

    if ($null -ne $taskData) {
        Set-WorkPackageTaskProperty -Task $taskData -Name "packagePath" -Value $finalTargetDir
        Save-WorkPackageTaskJson -Task $taskData -Path (Join-Path $finalTargetDir $taskRecordFileName)
        if (-not [string]::IsNullOrWhiteSpace($taskPath) -and (Test-Path -LiteralPath $taskPath -PathType Leaf)) {
            Remove-Item -LiteralPath $taskPath -Force -ErrorAction SilentlyContinue
        }
    }

    [void](Add-WorkHistoryEntry `
        -Database $historyDatabase `
        -TextHash $currentHash `
        -ImageHashInfo $imageHashInfo `
        -Title $title `
        -PackageFolder (Split-Path -Leaf $finalTargetDir) `
        -PackagePath $finalTargetDir `
        -Source "created" `
        -RecordedAt $packageTime)
    Save-WorkHistoryDatabase `
        -Database $historyDatabase `
        -PrimaryPath $historyPath `
        -BackupPath $historyBackupPath `
        -RuntimeMirrorPath $historyRuntimeMirrorPath

    if ($null -eq $taskData) {
        Clear-ClipboardAfterSuccess
    }
    $stageMessages = New-Object System.Collections.Generic.List[string]
    $stageMessages.Add($successMessage)
    if ($similarTextExists) {
        $stageMessages.Add($similarTextMessage)
    }

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
        Write-Output "SimilarText=$similarTextExists"
        Write-Output "HistoryEntries=$(@($historyDatabase.entries).Count)"
        Write-Output "HistoryMigrated=$historyMigrated"
        Write-Output "HistoryDatabase=$historyPath"
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
    if ($null -ne $taskData -and -not [string]::IsNullOrWhiteSpace($taskPath)) {
        try {
            Set-WorkPackageTaskProperty -Task $taskData -Name "status" -Value "failed"
            Set-WorkPackageTaskProperty -Task $taskData -Name "failedAt" -Value ((Get-Date).ToString("o"))
            Set-WorkPackageTaskProperty -Task $taskData -Name "error" -Value $originalError.Exception.Message
            Save-WorkPackageTaskJson -Task $taskData -Path $taskPath
        } catch {
        }
    }
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

