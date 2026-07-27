[CmdletBinding()]
param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
function New-TextFromCodePoints {
    param([int[]]$CodePoints)
    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectsRoot = Split-Path -Parent $repoRoot
$canonicalRoot = Join-Path $projectsRoot 'chatgpt-conversation-tree'
$workPackageSource = Join-Path $canonicalRoot 'src\work-package'
$localFileScriptsName = New-TextFromCodePoints @(0x672C, 0x5730, 0x6587, 0x4EF6, 0x5904, 0x7406, 0x811A, 0x672C)
$workPackageName = (New-TextFromCodePoints @(0x4E00, 0x952E)) + 'GPT' + (New-TextFromCodePoints @(0x4F5C, 0x54C1, 0x5305))
$workPackageLauncher = (New-TextFromCodePoints @(0x4E00, 0x952E, 0x751F, 0x6210, 0x4F5C, 0x54C1, 0x5305)) + '.vbs'
$workPackageSettingsLauncher = (New-TextFromCodePoints @(0x8BBE, 0x7F6E, 0x4F5C, 0x54C1, 0x5305, 0x76EE, 0x5F55)) + '.vbs'
$workPackageFriendlyInstaller = (New-TextFromCodePoints @(0x5B89, 0x88C5)) + 'GPT' + (New-TextFromCodePoints @(0x4F5C, 0x54C1, 0x52A9, 0x624B)) + '.vbs'
$workPackageFriendlyZip = 'GPT' + (New-TextFromCodePoints @(0x4F5C, 0x54C1, 0x52A9, 0x624B)) + '-' + (New-TextFromCodePoints @(0x50BB, 0x74DC, 0x5B89, 0x88C5, 0x5305)) + '.zip'
$workPackageMirror = Join-Path (Join-Path $repoRoot $localFileScriptsName) $workPackageName

$mappings = @(
    @{
        Name = 'ChatGPT userscript'
        Source = Join-Path $canonicalRoot 'src\chatgpt-conversation-tree.user.js'
        Mirror = Join-Path $repoRoot 'chatgpt-conversation-tree.user.js'
    },
    @{
        Name = 'ChatGPT cloud prompts'
        Source = Join-Path $canonicalRoot 'data\chatgpt-cloud-prompts.json'
        Mirror = Join-Path $repoRoot 'chatgpt-cloud-prompts.json'
    },
    @{
        Name = 'Work package installer'
        Source = Join-Path $workPackageSource 'install_work_package_tool.ps1'
        Mirror = Join-Path $workPackageMirror 'install_work_package_tool.ps1'
    },
    @{
        Name = 'Work package friendly installer core'
        Source = Join-Path $workPackageSource 'install_for_user.ps1'
        Mirror = Join-Path $workPackageMirror 'install_for_user.ps1'
    },
    @{
        Name = 'Work package friendly installer launcher'
        Source = Join-Path $workPackageSource $workPackageFriendlyInstaller
        Mirror = Join-Path $workPackageMirror $workPackageFriendlyInstaller
    },
    @{
        Name = 'Work package core'
        Source = Join-Path $workPackageSource 'make_work_package.ps1'
        Mirror = Join-Path $workPackageMirror 'make_work_package.ps1'
    },
    @{
        Name = 'Work package configurator'
        Source = Join-Path $workPackageSource 'configure_work_package.ps1'
        Mirror = Join-Path $workPackageMirror 'configure_work_package.ps1'
    },
    @{
        Name = 'Work package assistant center'
        Source = Join-Path $workPackageSource 'work_package_center.ps1'
        Mirror = Join-Path $workPackageMirror 'work_package_center.ps1'
    },
    @{
        Name = 'Work package launcher'
        Source = Join-Path $workPackageSource $workPackageLauncher
        Mirror = Join-Path $workPackageMirror $workPackageLauncher
    },
    @{
        Name = 'Work package settings launcher'
        Source = Join-Path $workPackageSource $workPackageSettingsLauncher
        Mirror = Join-Path $workPackageMirror $workPackageSettingsLauncher
    },
    @{
        Name = 'Work package README'
        Source = Join-Path $workPackageSource 'README.md'
        Mirror = Join-Path $workPackageMirror 'README.md'
    },
    @{
        Name = 'Work package usage'
        Source = Join-Path $workPackageSource 'usage_zh.md'
        Mirror = Join-Path $workPackageMirror 'usage_zh.md'
    },
    @{
        Name = 'Work package maintenance skill'
        Source = Join-Path $workPackageSource 'SKILL.md'
        Mirror = Join-Path $workPackageMirror 'SKILL.md'
    },
    @{
        Name = 'Work package friendly installer ZIP'
        Source = Join-Path (Join-Path $canonicalRoot 'releases') $workPackageFriendlyZip
        Mirror = Join-Path $repoRoot $workPackageFriendlyZip
    }
)

$hasMismatch = $false
foreach ($mapping in $mappings) {
    if (-not (Test-Path -LiteralPath $mapping.Source -PathType Leaf)) {
        throw "Canonical source is missing: $($mapping.Source)"
    }

    $matches = (Test-Path -LiteralPath $mapping.Mirror -PathType Leaf) -and
        ((Get-FileHash -Algorithm SHA256 -LiteralPath $mapping.Source).Hash -eq
         (Get-FileHash -Algorithm SHA256 -LiteralPath $mapping.Mirror).Hash)

    if ($matches) {
        Write-Host "OK: $($mapping.Name)"
        continue
    }

    $hasMismatch = $true
    if ($Apply) {
        Copy-Item -LiteralPath $mapping.Source -Destination $mapping.Mirror -Force
        Write-Host "SYNCED: $($mapping.Name)"
    }
    else {
        Write-Error "OUT OF SYNC: $($mapping.Name)"
    }
}

if ($hasMismatch -and -not $Apply) {
    exit 1
}

if ($Apply) {
    & $PSCommandPath
    exit $LASTEXITCODE
}

exit 0
