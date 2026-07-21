[CmdletBinding()]
param(
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$projectsRoot = Split-Path -Parent $repoRoot
$canonicalRoot = Join-Path $projectsRoot 'chatgpt-conversation-tree'

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
