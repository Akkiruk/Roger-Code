<#
.SYNOPSIS
  Regenerates Games/manifest.json from the actual file tree.
  Run this after adding or removing game files, then commit the result.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .vscode/generate-manifest.ps1
#>

param(
    [string]$GamesDir = (Join-Path $PSScriptRoot "..\Games")
)

$GamesDir = (Resolve-Path $GamesDir).Path

# ── Game definitions ───────────────────────────────────────────────────────
# Each game maps source_dir to its metadata. Files are auto-discovered.
# Config files are separated so the installer can skip them on updates.

$GameDefs = @{
    blackjack = @{
        name        = "Blackjack"
        description = "Casino Blackjack with betting, stats, achievements"
        source_dir  = "Blackjack"
        config_pattern = "*_config.lua"
    }
    baccarat = @{
        name        = "Baccarat"
        description = "Casino Baccarat with betting"
        source_dir  = "Baccarat"
        config_pattern = "*_config.lua"
    }
    roulette = @{
        name        = "Roulette"
        description = "Casino Roulette with betting"
        source_dir  = "Roulette"
        config_pattern = "*_config.lua"
    }
    slots = @{
        name        = "Slots"
        description = "Casino Slot Machine"
        source_dir  = "Slots"
        config_pattern = "*_config.lua"
    }
}

# Files to always skip
$SkipPatterns = @("*.bak", "*.old", "debug.txt", "*.log")

function Get-GameFiles {
    param([string]$Dir, [string]$ConfigPattern)

    $allFiles = Get-ChildItem $Dir -File | Where-Object {
        $name = $_.Name
        $skip = $false
        foreach ($pat in $SkipPatterns) {
            if ($name -like $pat) { $skip = $true; break }
        }
        -not $skip
    }

    $configFiles = @($allFiles | Where-Object { $_.Name -like $ConfigPattern } | ForEach-Object { $_.Name })
    $luaFiles    = @($allFiles | Where-Object { $_.Extension -eq ".lua" -and $_.Name -notlike $ConfigPattern } | ForEach-Object { $_.Name })
    $assetFiles  = @($allFiles | Where-Object { $_.Extension -ne ".lua" } | ForEach-Object { $_.Name })

    return @{
        files        = $luaFiles
        config_files = $configFiles
        assets       = $assetFiles
    }
}

# ── Build manifest ─────────────────────────────────────────────────────────

$manifest = [ordered]@{
    manifest_version  = 1
    installer_version = "1.0.0"
    games             = [ordered]@{}
    lib               = [ordered]@{
        version = "1.0.0"
        files   = @()
    }
}

# Discover games
foreach ($key in ($GameDefs.Keys | Sort-Object)) {
    $def = $GameDefs[$key]
    $dir = Join-Path $GamesDir $def.source_dir

    if (-not (Test-Path $dir)) {
        Write-Warning "Skipping $key - directory not found: $dir"
        continue
    }

    $discovered = Get-GameFiles -Dir $dir -ConfigPattern $def.config_pattern

    $manifest.games[$key] = [ordered]@{
        name         = $def.name
        version      = "1.0.0"
        description  = $def.description
        source_dir   = $def.source_dir
        files        = $discovered.files
        config_files = $discovered.config_files
        assets       = $discovered.assets
    }

    Write-Host "  $($def.name): $($discovered.files.Count) files, $($discovered.config_files.Count) configs, $($discovered.assets.Count) assets"
}

# Discover lib files
$libDir = Join-Path $GamesDir "lib"
if (Test-Path $libDir) {
    $libFiles = @(Get-ChildItem $libDir -File -Filter "*.lua" | ForEach-Object { $_.Name } | Sort-Object)
    $manifest.lib.files = $libFiles
    Write-Host "  lib: $($libFiles.Count) modules"
}

# ── Write JSON ─────────────────────────────────────────────────────────────

$outPath = Join-Path $GamesDir "manifest.json"
$json = $manifest | ConvertTo-Json -Depth 5
$json | Set-Content $outPath -Encoding UTF8

Write-Host ""
Write-Host "Wrote $outPath" -ForegroundColor Green
Write-Host "Remember to bump version numbers when making releases!"
