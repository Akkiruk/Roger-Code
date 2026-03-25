param(
    [string]$Game,
    [int[]]$ComputerId,
    [string]$SaveName,
    [string]$MinecraftDir,
    [switch]$ResetConfig,
    [switch]$AllInstalled,
    [switch]$ListTargets,
    [switch]$SkipManifest,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestScript = Join-Path $PSScriptRoot "regenerate-manifest.ps1"
$deployScript = Join-Path $PSScriptRoot "deploy-to-world.ps1"

if (-not $SkipManifest) {
    if ($DryRun) {
        Write-Host "[dry-run] Would regenerate Games/manifest.json" -ForegroundColor Yellow
    } else {
        & $manifestScript
    }
}

if (-not (Test-Path $deployScript)) {
    throw "World deploy script not found: $deployScript"
}

$deployArgs = @{}
if ($Game) {
    $deployArgs.Game = $Game
}
if ($ComputerId -and $ComputerId.Count -gt 0) {
    $deployArgs.ComputerId = $ComputerId
}
if ($SaveName) {
    $deployArgs.SaveName = $SaveName
}
if ($MinecraftDir) {
    $deployArgs.MinecraftDir = $MinecraftDir
}
if ($ResetConfig) {
    $deployArgs.ResetConfig = $true
}
if ($AllInstalled) {
    $deployArgs.AllInstalled = $true
}
if ($ListTargets) {
    $deployArgs.ListTargets = $true
}
if ($DryRun) {
    $deployArgs.DryRun = $true
}

if ($DryRun) {
    $argText = if ($deployArgs.Count -gt 0) {
        ($deployArgs.GetEnumerator() | Sort-Object Name | ForEach-Object {
            if ($_.Value -is [System.Array]) {
                "-$($_.Key) $($_.Value -join ',')"
            } elseif ($_.Value -is [bool]) {
                "-$($_.Key)"
            } else {
                "-$($_.Key) $($_.Value)"
            }
        }) -join " "
    } else {
        "<none>"
    }
    Write-Host "[dry-run] Would run deploy-to-world.ps1 $argText" -ForegroundColor Yellow
    return
}

& $deployScript @deployArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
