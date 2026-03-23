param(
    [string]$RootDir = (Join-Path $PSScriptRoot "..")
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path $RootDir).Path
$scriptPath = Join-Path $repoRoot ".vscode\generate-manifest.ps1"

if (-not (Test-Path $scriptPath)) {
    throw "Manifest generator not found: $scriptPath"
}

Write-Host "Regenerating Games/manifest.json..." -ForegroundColor Cyan
& $scriptPath -RootDir $repoRoot

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
