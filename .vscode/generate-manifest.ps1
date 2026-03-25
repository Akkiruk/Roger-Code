<#
.SYNOPSIS
  Regenerates Games/manifest.json from the actual file tree.
  Auto-discovers ALL programs — any subfolder with .lua files becomes installable.
  Automatically bumps version numbers when file content changes (hash-based).
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
$SkipPatterns = @("*.bak", "*.old", "debug.txt", "*.log", "*.md", "manifest.json", "installer.lua")

# Directories that are not programs (shared support dirs or non-code)
$SkipDirs = @("lib", ".git", ".github", ".vscode", "Do", "node_modules", "emulator")

function Test-SkipFile {
    param([string]$Name)
    foreach ($pat in $SkipPatterns) {
        if ($Name -like $pat) { return $true }
    }
    return $false
}

function Get-RelativeFilePath {
    param(
        [string]$BaseDir,
        [string]$FullPath
    )

    $base = (Resolve-Path $BaseDir).Path.TrimEnd('\', '/')
    $full = (Resolve-Path $FullPath).Path
    return $full.Substring($base.Length + 1).Replace('\', '/')
}

# Discover files in a program directory, sorting into code/config/assets
function Get-ProgramFiles {
    param([string]$Dir)

    $allFiles = Get-ChildItem $Dir -File -Recurse | Where-Object { -not (Test-SkipFile $_.Name) }

    $configFiles = @(
        $allFiles |
            Where-Object { $_.Name -like "*_config.lua" -or $_.Name -like "*_settings.lua" } |
            ForEach-Object { Get-RelativeFilePath -BaseDir $Dir -FullPath $_.FullName } |
            Sort-Object
    )
    $luaFiles = @(
        $allFiles |
            Where-Object { $_.Extension -eq ".lua" -and $_.Name -notlike "*_config.lua" -and $_.Name -notlike "*_settings.lua" } |
            ForEach-Object { Get-RelativeFilePath -BaseDir $Dir -FullPath $_.FullName } |
            Sort-Object
    )
    $assetFiles = @(
        $allFiles |
            Where-Object { $_.Extension -ne ".lua" } |
            ForEach-Object { Get-RelativeFilePath -BaseDir $Dir -FullPath $_.FullName } |
            Sort-Object
    )

    return @{
        files        = $luaFiles
        config_files = $configFiles
        assets       = $assetFiles
    }
}

# Check if a directory uses shared lib (has require("lib.xxx") in any .lua))
function Test-UsesLib {
    param([string]$Dir)
    $luaFiles = Get-ChildItem $Dir -File -Filter "*.lua" -Recurse -ErrorAction SilentlyContinue
    foreach ($f in $luaFiles) {
        $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if ($content -match 'require\s*\(\s*["\x27]lib\.') { return $true }
    }
    return $false
}

# Locate the primary Lua file for a program directory.
function Get-ProgramMainFile {
    param([string]$Dir, [string]$DirName)

    $mainFile = $null
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
    return $mainFile
}

# Read manifest metadata from the first comment block of the main Lua file.
function Get-ProgramMetadata {
    param([string]$Dir, [string]$DirName)

    $meta = @{
        key         = $DirName.ToLower()
        name        = $DirName
        description = ""
    }

    $mainFile = Get-ProgramMainFile -Dir $Dir -DirName $DirName
    if (-not $mainFile) { return $meta }

    $lines = Get-Content $mainFile -TotalCount 10 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '^\s*--\s*manifest-key:\s*(.+)$') {
            $value = $Matches[1].Trim()
            if ($value -ne "") { $meta.key = $value }
            continue
        }
        if ($line -match '^\s*--\s*manifest-name:\s*(.+)$') {
            $value = $Matches[1].Trim()
            if ($value -ne "") { $meta.name = $value }
            continue
        }
        if ($line -match '^\s*--\s*manifest-description:\s*(.+)$') {
            $value = $Matches[1].Trim()
            if ($value -ne "" -and $meta.description -eq "") { $meta.description = $value }
            continue
        }
        if ($line -match '^\s*--\s*(.+)$') {
            $desc = $Matches[1].Trim()
            if (
                $desc -notmatch '^\S+\.lua$' -and
                $desc.Length -gt 10 -and
                $desc -notmatch '^manifest-(key|name|description):'
            ) {
                $meta.description = $desc
                break
            }
        }
    }

    return $meta
}

# ── Hashing & auto-versioning ──────────────────────────────────────────────

# Compute a content hash for a list of files (sorted by name for determinism)
function Get-ContentHash {
    param([string[]]$FilePaths)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $sorted = $FilePaths | Sort-Object
    foreach ($fp in $sorted) {
        if (Test-Path $fp) {
            $bytes = [System.IO.File]::ReadAllBytes($fp)
            [void]$sha.TransformBlock($bytes, 0, $bytes.Length, $bytes, 0)
        }
    }
    [void]$sha.TransformFinalBlock(@(), 0, 0)
    $hashStr = [BitConverter]::ToString($sha.Hash).Replace("-", "").ToLower()
    $sha.Dispose()
    return $hashStr.Substring(0, 16)  # 16-char hex prefix is plenty
}

# Bump the patch component of a semver string
function Bump-PatchVersion {
    param([string]$Version)
    $parts = $Version -split '\.'
    if ($parts.Count -ne 3) { return "1.0.1" }
    $parts[2] = [string]([int]$parts[2] + 1)
    return $parts -join '.'
}

# Read the existing manifest to preserve versions and compare hashes
$outPath = Join-Path $GamesDir "manifest.json"
$oldManifest = $null
if (Test-Path $outPath) {
    try {
        $oldManifest = Get-Content $outPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warning "Could not parse existing manifest, starting fresh"
    }
}

# Helper: get old version + hash for a program or lib
function Get-OldEntry {
    param([string]$Key, [switch]$IsLib)
    if (-not $oldManifest) { return @{ version = "1.0.0"; content_hash = "" } }
    if ($IsLib) {
        $v = if ($oldManifest.lib.version) { $oldManifest.lib.version } else { "1.0.0" }
        $h = if ($oldManifest.lib.content_hash) { $oldManifest.lib.content_hash } else { "" }
        return @{ version = $v; content_hash = $h }
    }
    $prog = $null
    if ($oldManifest.programs.PSObject.Properties.Name -contains $Key) {
        $prog = $oldManifest.programs.$Key
    }
    if ($prog) {
        $v = if ($prog.version) { $prog.version } else { "1.0.0" }
        $h = if ($prog.content_hash) { $prog.content_hash } else { "" }
        return @{ version = $v; content_hash = $h }
    }
    return @{ version = "1.0.0"; content_hash = "" }
}

# Resolve version: bump patch if hash changed, keep if same, start at 1.0.0 if new
function Resolve-Version {
    param([string]$Key, [string]$NewHash, [switch]$IsLib)
    $old = Get-OldEntry -Key $Key -IsLib:$IsLib
    if ($old.content_hash -eq "") {
        # New entry or no hash stored — keep existing version, store hash
        return $old.version
    }
    if ($old.content_hash -eq $NewHash) {
        return $old.version
    }
    # Hash changed — auto-bump
    $bumped = Bump-PatchVersion $old.version
    return $bumped
}

# ── Build manifest ─────────────────────────────────────────────────────────

# Read installer version and compute its content hash
$installerFile = Join-Path $GamesDir "installer.lua"
$installerVersion = "1.0.0"
$installerHash = ""
if (Test-Path $installerFile) {
    $match = Select-String -Path $installerFile -Pattern 'INSTALLER_VERSION\s*=\s*"([^"]+)"' | Select-Object -First 1
    if ($match) {
        $installerVersion = $match.Matches[0].Groups[1].Value
    }
    $installerHash = Get-ContentHash -FilePaths @($installerFile)

    # Auto-bump installer version when content changes
    $oldInstallerHash = ""
    $oldInstallerVersion = $installerVersion
    if ($oldManifest -and $oldManifest.installer_hash) {
        $oldInstallerHash = $oldManifest.installer_hash
    }
    if ($oldManifest -and $oldManifest.installer_version) {
        $oldInstallerVersion = $oldManifest.installer_version
    }
    if ($oldInstallerHash -ne "" -and $oldInstallerHash -ne $installerHash) {
        $installerVersion = Bump-PatchVersion $oldInstallerVersion
        # Write bumped version back into installer.lua
        $installerContent = [System.IO.File]::ReadAllText($installerFile)
        $installerContent = $installerContent -replace '(local INSTALLER_VERSION\s*=\s*")[^"]+"', "`${1}$installerVersion`""
        $utf8NoBomTemp = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($installerFile, $installerContent, $utf8NoBomTemp)
        # Recompute hash after writing new version
        $installerHash = Get-ContentHash -FilePaths @($installerFile)
        Write-Host "  installer.lua: v$oldInstallerVersion -> v$installerVersion (auto-bumped)" -ForegroundColor Yellow
    } else {
        Write-Host "  installer.lua: v$installerVersion" -ForegroundColor DarkGray
    }
}

$manifest = [ordered]@{
    manifest_version  = 1
    installer_version = $installerVersion
    installer_hash    = $installerHash
    programs          = [ordered]@{}
    lib               = [ordered]@{
        version      = "1.0.0"
        content_hash = ""
        files        = @()
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
    $meta = Get-ProgramMetadata -Dir $dir.FullName -DirName $dir.Name
    $key = $meta.key
    $luaCount = @(Get-ChildItem $dir.FullName -File -Filter "*.lua" -ErrorAction SilentlyContinue).Count
    if ($luaCount -eq 0) {
        Write-Warning "  Skipping $($dir.Name) - no .lua files"
        continue
    }

    $discovered = Get-ProgramFiles -Dir $dir.FullName
    $usesLib = Test-UsesLib -Dir $dir.FullName
    $desc = $meta.description

    # Determine source_dir relative to repo root for the installer URL
    $relPath = $dir.FullName.Replace($RootDir, "").TrimStart("\", "/").Replace("\", "/")

    # Compute content hash from all code + config files (not assets — those rarely change and are large)
    $hashFiles = @()
    foreach ($f in ($discovered.files + $discovered.config_files)) {
        $hashFiles += Join-Path $dir.FullName $f
    }
    $contentHash = Get-ContentHash -FilePaths $hashFiles
    $version = Resolve-Version -Key $key -NewHash $contentHash

    $manifest.programs[$key] = [ordered]@{
        name         = $meta.name
        version      = $version
        content_hash = $contentHash
        description  = $desc
        source_dir   = $relPath
        uses_lib     = $usesLib
        files        = $discovered.files
        config_files = $discovered.config_files
        assets       = $discovered.assets
    }

    # Show version bump info
    $old = Get-OldEntry -Key $key
    $versionTag = "v$version"
    if ($old.content_hash -ne "" -and $old.content_hash -ne $contentHash) {
        $versionTag = "v$($old.version) -> v$version (auto-bumped)"
    } elseif ($old.content_hash -eq "") {
        $versionTag = "v$version (new hash)"
    }

    $libTag = if ($usesLib) { " [+lib]" } else { "" }
    Write-Host "  $($dir.Name): $($discovered.files.Count) lua, $($discovered.config_files.Count) config, $($discovered.assets.Count) assets$libTag  $versionTag"
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

    $contentHash = Get-ContentHash -FilePaths @($file.FullName)
    $version = Resolve-Version -Key $key -NewHash $contentHash

    $manifest.programs[$key] = [ordered]@{
        name         = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        version      = $version
        content_hash = $contentHash
        description  = $desc
        source_dir   = "Utilities"
        uses_lib     = $false
        files        = @($file.Name)
        config_files = @()
        assets       = @()
    }
    Write-Host "  $($file.Name): standalone utility  v$version"
}

# Discover shared lib files
$libDir = Join-Path $GamesDir "lib"
if (Test-Path $libDir) {
    $libItems = @(Get-ChildItem $libDir -File -Filter "*.lua" -Recurse | Sort-Object FullName)
    $libFiles = @($libItems | ForEach-Object { Get-RelativeFilePath -BaseDir $libDir -FullPath $_.FullName })
    $libPaths = @($libItems | ForEach-Object { $_.FullName })
    $libHash = Get-ContentHash -FilePaths $libPaths
    $libVersion = Resolve-Version -Key "lib" -NewHash $libHash -IsLib

    $manifest.lib.version = $libVersion
    $manifest.lib.content_hash = $libHash
    $manifest.lib.files = $libFiles

    $oldLib = Get-OldEntry -Key "lib" -IsLib
    $libTag = "v$libVersion"
    if ($oldLib.content_hash -ne "" -and $oldLib.content_hash -ne $libHash) {
        $libTag = "v$($oldLib.version) -> v$libVersion (auto-bumped)"
    } elseif ($oldLib.content_hash -eq "") {
        $libTag = "v$libVersion (new hash)"
    }
    Write-Host "  lib/: $($libFiles.Count) shared modules  $libTag"
}

# ── Write JSON ─────────────────────────────────────────────────────────────

$outPath = Join-Path $GamesDir "manifest.json"
$json = ($manifest | ConvertTo-Json -Depth 5) -replace "`r`n", "`n"
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText($outPath, $json, $utf8NoBom)

Write-Host ""
Write-Host "Wrote $outPath" -ForegroundColor Green
Write-Host "Versions are auto-bumped when file content changes." -ForegroundColor Gray
