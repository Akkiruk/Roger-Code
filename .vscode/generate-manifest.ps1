<#
.SYNOPSIS
  Regenerates Games/manifest.json from the actual file tree.
  Auto-discovers ALL programs — any subfolder with .lua files becomes installable.
  Run this after adding or removing files, then commit the result.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .vscode/generate-manifest.ps1
#>

param(
    [string]$RootDir = (Join-Path $PSScriptRoot "..")
)

$RootDir = (Resolve-Path $RootDir).Path
$GamesDir = Join-Path $RootDir "Games"
$UtilitiesDir = Join-Path $RootDir "Utilities"

# Files to always skip in scans
$SkipPatterns = @("*.bak", "*.old", "debug.txt", "*.log", "*.md", "manifest.json", "installer.lua", "test_*.lua")

# Directories that are not programs (shared support dirs or non-code)
$SkipDirs = @("lib", ".git", ".github", ".vscode", "Do", "node_modules")

function Test-SkipFile {
    param([string]$Name)
    foreach ($pat in $SkipPatterns) {
        if ($Name -like $pat) { return $true }
    }
    return $false
}

# Discover files in a program directory, sorting into code/config/assets
function Get-ProgramFiles {
    param([string]$Dir)

    $allFiles = Get-ChildItem $Dir -File | Where-Object { -not (Test-SkipFile $_.Name) }

    $configFiles = @($allFiles | Where-Object { $_.Name -like "*_config.lua" -or $_.Name -like "*_settings.lua" } | ForEach-Object { $_.Name })
    $luaFiles    = @($allFiles | Where-Object { $_.Extension -eq ".lua" -and $_.Name -notlike "*_config.lua" -and $_.Name -notlike "*_settings.lua" } | ForEach-Object { $_.Name })
    $assetFiles  = @($allFiles | Where-Object { $_.Extension -ne ".lua" } | ForEach-Object { $_.Name })

    return @{
        files        = $luaFiles
        config_files = $configFiles
        assets       = $assetFiles
    }
}

# Check if a directory uses shared lib (has require("lib.xxx") in any .lua))
function Test-UsesLib {
    param([string]$Dir)
    $luaFiles = Get-ChildItem $Dir -File -Filter "*.lua" -ErrorAction SilentlyContinue
    foreach ($f in $luaFiles) {
        $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match 'require\s*\(\s*["\x27]lib\.') { return $true }
    }
    return $false
}

# Read description from first comment block of main lua file
function Get-ProgramDescription {
    param([string]$Dir, [string]$DirName)
    $mainFile = $null
    # Try <dirname>.lua, then startup.lua, then first .lua file
    $candidates = @(
        (Join-Path $Dir "$($DirName.ToLower()).lua"),
        (Join-Path $Dir "startup.lua")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $mainFile = $c; break }
    }
    if (-not $mainFile) {
        $first = Get-ChildItem $Dir -File -Filter "*.lua" | Select-Object -First 1
        if ($first) { $mainFile = $first.FullName }
    }
    if (-not $mainFile) { return "" }

    $lines = Get-Content $mainFile -TotalCount 5 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '^\s*--\s*(.+)$') {
            $desc = $Matches[1].Trim()
            # Skip lines that are just the filename or shebangs
            if ($desc -notmatch '^\S+\.lua$' -and $desc.Length -gt 10) {
                return $desc
            }
        }
    }
    return ""
}

# ── Build manifest ─────────────────────────────────────────────────────────

$manifest = [ordered]@{
    manifest_version  = 1
    installer_version = "1.0.0"
    programs          = [ordered]@{}
    lib               = [ordered]@{
        version = "1.0.0"
        files   = @()
    }
}

Write-Host "Scanning for programs..." -ForegroundColor Cyan

# Auto-discover program directories under Games/
$programDirs = @()
if (Test-Path $GamesDir) {
    $programDirs += Get-ChildItem $GamesDir -Directory | Where-Object { $_.Name -notin $SkipDirs }
}
# Also scan Utilities/
if (Test-Path $UtilitiesDir) {
    $programDirs += Get-ChildItem $UtilitiesDir -Directory | Where-Object { $_.Name -notin $SkipDirs }
}

# Handle standalone .lua files in Utilities/ as single-file programs
$standaloneUtils = @()
if (Test-Path $UtilitiesDir) {
    $standaloneUtils = @(Get-ChildItem $UtilitiesDir -File -Filter "*.lua" | Where-Object { -not (Test-SkipFile $_.Name) })
}

foreach ($dir in ($programDirs | Sort-Object Name)) {
    $key = $dir.Name.ToLower()
    $luaCount = @(Get-ChildItem $dir.FullName -File -Filter "*.lua" -ErrorAction SilentlyContinue).Count
    if ($luaCount -eq 0) {
        Write-Warning "  Skipping $($dir.Name) - no .lua files"
        continue
    }

    $discovered = Get-ProgramFiles -Dir $dir.FullName
    $usesLib = Test-UsesLib -Dir $dir.FullName
    $desc = Get-ProgramDescription -Dir $dir.FullName -DirName $dir.Name

    # Determine source_dir relative to repo root for the installer URL
    $relPath = $dir.FullName.Replace($RootDir, "").TrimStart("\", "/").Replace("\", "/")

    $manifest.programs[$key] = [ordered]@{
        name         = $dir.Name
        version      = "1.0.0"
        description  = $desc
        source_dir   = $relPath
        uses_lib     = $usesLib
        files        = $discovered.files
        config_files = $discovered.config_files
        assets       = $discovered.assets
    }

    $libTag = if ($usesLib) { " [+lib]" } else { "" }
    Write-Host "  $($dir.Name): $($discovered.files.Count) lua, $($discovered.config_files.Count) config, $($discovered.assets.Count) assets$libTag"
}

# Standalone utility scripts (single .lua files, no folder)
foreach ($file in $standaloneUtils) {
    $key = [System.IO.Path]::GetFileNameWithoutExtension($file.Name).ToLower()
    if ($manifest.programs.Contains($key)) { continue }

    $desc = ""
    $lines = Get-Content $file.FullName -TotalCount 3 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '^\s*--\s*(.+)$') {
            $d = $Matches[1].Trim()
            if ($d -notmatch '^\S+\.lua$' -and $d.Length -gt 10) { $desc = $d; break }
        }
    }

    $manifest.programs[$key] = [ordered]@{
        name         = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        version      = "1.0.0"
        description  = $desc
        source_dir   = "Utilities"
        uses_lib     = $false
        files        = @($file.Name)
        config_files = @()
        assets       = @()
    }
    Write-Host "  $($file.Name): standalone utility"
}

# Discover shared lib files
$libDir = Join-Path $GamesDir "lib"
if (Test-Path $libDir) {
    $libFiles = @(Get-ChildItem $libDir -File -Filter "*.lua" | ForEach-Object { $_.Name } | Sort-Object)
    $manifest.lib.files = $libFiles
    Write-Host "  lib/: $($libFiles.Count) shared modules"
}

# ── Write JSON ─────────────────────────────────────────────────────────────

$outPath = Join-Path $GamesDir "manifest.json"
$json = ($manifest | ConvertTo-Json -Depth 5) -replace "`r`n", "`n"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)

Write-Host ""
Write-Host "Wrote $outPath" -ForegroundColor Green
Write-Host "Remember to bump version numbers when making releases!"
