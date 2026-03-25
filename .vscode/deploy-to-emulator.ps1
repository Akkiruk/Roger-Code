# deploy-to-emulator.ps1
# Legacy wrapper. The active workflow now deploys to the PrismLauncher world runtime.
# Usage: .\deploy-to-emulator.ps1 [-Game Blackjack] [-ComputerId 0]

param(
    [string]$Game = "Blackjack",
    [int[]]$ComputerId,
    [string]$SaveName,
    [string]$MinecraftDir,
    [switch]$ResetConfig,
    [switch]$ListTargets,
    [switch]$DryRun
)

$workspace = Split-Path -Parent $PSScriptRoot
$deployScript = Join-Path $workspace "scripts\deploy-to-world.ps1"

if (-not (Test-Path $deployScript)) {
    throw "World deploy script not found: $deployScript"
}

$argsMap = @{
    Game = $Game
}
if ($ComputerId -and $ComputerId.Count -gt 0) {
    $argsMap.ComputerId = $ComputerId
}
if ($SaveName) {
    $argsMap.SaveName = $SaveName
}
if ($MinecraftDir) {
    $argsMap.MinecraftDir = $MinecraftDir
}
if ($ResetConfig) {
    $argsMap.ResetConfig = $true
}
if ($ListTargets) {
    $argsMap.ListTargets = $true
}
if ($DryRun) {
    $argsMap.DryRun = $true
}

Write-Host "Legacy wrapper: forwarding to PrismLauncher world deployment." -ForegroundColor Yellow
& $deployScript @argsMap
