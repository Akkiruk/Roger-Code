param(
    [Parameter(Mandatory = $true)]
    [string]$TargetDir
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$phoneRoot = Join-Path $repoRoot 'Games\PhoneOS'

$filesToCopy = @(
    @{ Source = Join-Path $repoRoot 'Games\runtime_startup.lua'; Destination = Join-Path $TargetDir 'startup.lua' },
    @{ Source = Join-Path $phoneRoot 'startup.lua'; Destination = Join-Path $TargetDir 'phone_os_startup.lua' },
    @{ Source = Join-Path $phoneRoot 'phone_os.lua'; Destination = Join-Path $TargetDir 'phone_os.lua' },
    @{ Source = Join-Path $phoneRoot 'phoneos\blackjack.lua'; Destination = Join-Path $TargetDir 'phoneos\blackjack.lua' },
    @{ Source = Join-Path $phoneRoot 'phoneos\slots.lua'; Destination = Join-Path $TargetDir 'phoneos\slots.lua' },
    @{ Source = Join-Path $phoneRoot 'phoneos\storage.lua'; Destination = Join-Path $TargetDir 'phoneos\storage.lua' },
    @{ Source = Join-Path $phoneRoot 'phoneos\ui.lua'; Destination = Join-Path $TargetDir 'phoneos\ui.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\roger_supervisor.lua'; Destination = Join-Path $TargetDir 'lib\roger_supervisor.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\updater.lua'; Destination = Join-Path $TargetDir 'lib\updater.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\alert.lua'; Destination = Join-Path $TargetDir 'lib\alert.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\cards.lua'; Destination = Join-Path $TargetDir 'lib\cards.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\crash_recovery.lua'; Destination = Join-Path $TargetDir 'lib\crash_recovery.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\currency.lua'; Destination = Join-Path $TargetDir 'lib\currency.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\peripherals.lua'; Destination = Join-Path $TargetDir 'lib\peripherals.lua' },
    @{ Source = Join-Path $repoRoot 'Games\lib\sound.lua'; Destination = Join-Path $TargetDir 'lib\sound.lua' },
    @{ Source = Join-Path $phoneRoot 'blackjack_config.lua'; Destination = Join-Path $TargetDir 'Blackjack\blackjack_config.lua' },
    @{ Source = Join-Path $phoneRoot 'blackjack_config.lua'; Destination = Join-Path $TargetDir 'blackjack_config.lua' },
    @{ Source = Join-Path $phoneRoot 'slots_config.lua'; Destination = Join-Path $TargetDir 'Slots\slots_config.lua' },
    @{ Source = Join-Path $phoneRoot 'slots_config.lua'; Destination = Join-Path $TargetDir 'slots_config.lua' }
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
    schema_version = 2,
  program = "phone_os",
    name = "Pocket Casino OS",
  installed_at = 0,
  updated_at = 0,
  version = "1.0.0",
    boot_mode = "supervisor",
    system_entrypoint = "startup.lua",
    app_entrypoint = "phone_os_startup.lua",
    auto_restart = true,
    update_interval = 300,
}
"@

Set-Content -Path (Join-Path $TargetDir '.installed_program') -Value $installedProgram -NoNewline
Set-Content -Path (Join-Path $TargetDir '.vhcc_unlock') -Value "{`n  source = \"deploy-phoneos\",`n  persistent = true,`n}`n" -NoNewline

Write-Output "Deployed Pocket Casino OS to $TargetDir"
