param(
    [string]$Game,
    [int]$ComputerId = 0,
    [switch]$NoMocks,
    [switch]$CleanEmulator,
    [switch]$SkipManifest,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestScript = Join-Path $PSScriptRoot "regenerate-manifest.ps1"
$deployScript = Join-Path $repoRoot ".vscode\deploy-to-emulator.ps1"

if (-not $SkipManifest) {
    if ($DryRun) {
        Write-Host "[dry-run] Would regenerate Games/manifest.json" -ForegroundColor Yellow
    } else {
        & $manifestScript
    }
}

if ($Game -or $CleanEmulator) {
    if (-not (Test-Path $deployScript)) {
        throw "Emulator deploy script not found: $deployScript"
    }

    $deployArgs = @{}
    if ($Game) {
        $deployArgs.Game = $Game
    }
    if ($ComputerId -ne 0) {
        $deployArgs.ComputerId = $ComputerId
    }
    if ($NoMocks) {
        $deployArgs.NoMocks = $true
    }
    if ($CleanEmulator) {
        $deployArgs.Clean = $true
    }

    if ($DryRun) {
        $argText = if ($deployArgs.Count -gt 0) {
            ($deployArgs.GetEnumerator() | Sort-Object Name | ForEach-Object {
                if ($_.Value -is [bool]) {
                    "-$($_.Key)"
                } else {
                    "-$($_.Key) $($_.Value)"
                }
            }) -join " "
        } else {
            "<none>"
        }
        Write-Host "[dry-run] Would run deploy-to-emulator.ps1 $argText" -ForegroundColor Yellow
    } else {
        & $deployScript @deployArgs
        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }
} elseif ($DryRun) {
    Write-Host "[dry-run] No emulator action requested. Pass -Game <Name> to deploy a program." -ForegroundColor DarkYellow
} else {
    Write-Host "Manifest sync complete. Pass -Game <Name> to deploy to the CraftOS-PC emulator." -ForegroundColor Green
}
