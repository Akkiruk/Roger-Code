param(
    [Parameter(Mandatory = $true)]
    [string]$TargetDir
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$phoneRoot = $PSScriptRoot

$filesToCopy = @(
    @{ Source = Join-Path $phoneRoot 'startup.lua'; Destination = Join-Path $TargetDir 'startup.lua' },
    @{ Source = Join-Path $phoneRoot 'phone_os.lua'; Destination = Join-Path $TargetDir 'phone_os.lua' },
    @{ Source = Join-Path $phoneRoot 'phoneos\blackjack.lua'; Destination = Join-Path $TargetDir 'phoneos\blackjack.lua' },
    @{ Source = Join-Path $phoneRoot 'phoneos\slots.lua'; Destination = Join-Path $TargetDir 'phoneos\slots.lua' },
    @{ Source = Join-Path $phoneRoot 'phoneos\storage.lua'; Destination = Join-Path $TargetDir 'phoneos\storage.lua' },
    @{ Source = Join-Path $phoneRoot 'phoneos\ui.lua'; Destination = Join-Path $TargetDir 'phoneos\ui.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\alert.lua'; Destination = Join-Path $TargetDir 'lib\alert.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\cards.lua'; Destination = Join-Path $TargetDir 'lib\cards.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\crash_recovery.lua'; Destination = Join-Path $TargetDir 'lib\crash_recovery.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\currency.lua'; Destination = Join-Path $TargetDir 'lib\currency.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\peripherals.lua'; Destination = Join-Path $TargetDir 'lib\peripherals.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\sound.lua'; Destination = Join-Path $TargetDir 'lib\sound.lua' },
    @{ Source = Join-Path $repoRoot 'Games\Blackjack\blackjack_config.lua'; Destination = Join-Path $TargetDir 'Blackjack\blackjack_config.lua' },
    @{ Source = Join-Path $repoRoot 'Games\Slots\slots_config.lua'; Destination = Join-Path $TargetDir 'Slots\slots_config.lua' }
)

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null

foreach ($entry in $filesToCopy) {
    if (-not (Test-Path $entry.Source)) {
        throw "Missing source file: $($entry.Source)"
    }

    $destParent = Split-Path -Parent $entry.Destination
    if ($destParent) {
        New-Item -ItemType Directory -Force -Path $destParent | Out-Null
    }

    Copy-Item -Force -Path $entry.Source -Destination $entry.Destination
}

$installedProgram = @"
{
  program = "phone_os",
  installed_at = 0,
  updated_at = 0,
  version = "1.0.0",
}
"@

Set-Content -Path (Join-Path $TargetDir '.installed_program') -Value $installedProgram -NoNewline

Write-Output "Deployed Pocket Casino OS to $TargetDir"
