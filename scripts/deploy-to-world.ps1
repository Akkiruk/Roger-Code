param(
    [string]$Game,
    [int[]]$ComputerId,
    [string]$SaveName,
    [string]$MinecraftDir,
    [switch]$ResetConfig,
    [switch]$AllInstalled,
    [switch]$ListTargets,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $repoRoot "Games\manifest.json"

function Resolve-MinecraftDir {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path $ExplicitPath)) {
            throw "Minecraft directory not found: $ExplicitPath"
        }
        return (Resolve-Path $ExplicitPath).Path
    }

    $candidates = @()

    if ($env:ROGER_CODE_MINECRAFT_DIR) {
        $candidates += $env:ROGER_CODE_MINECRAFT_DIR
    }

    $defaultPack = Join-Path $env:APPDATA "PrismLauncher\instances\mcparadisepack\minecraft"
    if (Test-Path $defaultPack) {
        $candidates += $defaultPack
    }

    $instancesRoot = Join-Path $env:APPDATA "PrismLauncher\instances"
    if (Test-Path $instancesRoot) {
        $candidates += Get-ChildItem $instancesRoot -Directory | ForEach-Object {
            Join-Path $_.FullName "minecraft"
        }
    }

    $seen = @{}
    foreach ($candidate in $candidates) {
        if (-not $candidate) {
            continue
        }
        if ($seen.ContainsKey($candidate)) {
            continue
        }
        $seen[$candidate] = $true

        if (-not (Test-Path $candidate)) {
            continue
        }

        $saveRoot = Join-Path $candidate "saves"
        if (-not (Test-Path $saveRoot)) {
            continue
        }

        $hasComputers = Get-ChildItem $saveRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
            Test-Path (Join-Path $_.FullName "computercraft\computer")
        } | Select-Object -First 1

        if ($hasComputers) {
            return (Resolve-Path $candidate).Path
        }
    }

    throw "Could not locate a PrismLauncher minecraft directory with ComputerCraft saves. Pass -MinecraftDir explicitly."
}

function Resolve-SaveDir {
    param(
        [string]$MinecraftRoot,
        [string]$RequestedSaveName
    )

    $savesRoot = Join-Path $MinecraftRoot "saves"
    if (-not (Test-Path $savesRoot)) {
        throw "Save directory not found: $savesRoot"
    }

    if ($RequestedSaveName) {
        $requested = Join-Path $savesRoot $RequestedSaveName
        if (-not (Test-Path (Join-Path $requested "computercraft\computer"))) {
            throw "Requested save does not have ComputerCraft computer data: $requested"
        }
        return (Resolve-Path $requested).Path
    }

    $saveCandidates = Get-ChildItem $savesRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
        Test-Path (Join-Path $_.FullName "computercraft\computer")
    } | Sort-Object LastWriteTimeUtc -Descending

    $chosen = $saveCandidates | Select-Object -First 1
    if (-not $chosen) {
        throw "No save with computercraft/computer data found under $savesRoot"
    }

    return $chosen.FullName
}

function Read-LuaInfoFile {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $null
    }

    $raw = Get-Content $Path -Raw
    $info = [ordered]@{}
    foreach ($key in @("program", "game", "version", "lib_version", "content_hash")) {
        $match = [regex]::Match($raw, $key + '\s*=\s*"([^"]*)"')
        if ($match.Success) {
            $info[$key] = $match.Groups[1].Value
        }
    }
    foreach ($key in @("installed_at", "updated_at")) {
        $match = [regex]::Match($raw, $key + '\s*=\s*(\d+)')
        if ($match.Success) {
            $info[$key] = [int64]$match.Groups[1].Value
        }
    }

    if ($info.Count -eq 0) {
        return $null
    }

    return [pscustomobject]$info
}

function Get-ManagedFilesPath {
    param([string]$ComputerDir)
    return (Join-Path $ComputerDir ".roger_deployed_files")
}

function Read-ManagedFiles {
    param([string]$ComputerDir)

    $path = Get-ManagedFilesPath -ComputerDir $ComputerDir
    if (-not (Test-Path $path)) {
        return @()
    }

    return @(Get-Content $path | Where-Object { $_ -and $_.Trim() -ne "" } | ForEach-Object {
        $_.Trim().Replace('\', '/')
    })
}

function Write-ManagedFiles {
    param(
        [string]$ComputerDir,
        [string[]]$Paths
    )

    $path = Get-ManagedFilesPath -ComputerDir $ComputerDir
    $content = ($Paths | Sort-Object -Unique) -join "`n"
    if ($content.Length -gt 0) {
        $content += "`n"
    }
    [System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
}

function Write-InstalledProgramInfo {
    param(
        [string]$ComputerDir,
        [string]$ProgramKey,
        [pscustomobject]$ProgramEntry,
        [pscustomobject]$Manifest,
        [int64]$InstalledAt
    )

    $lines = @(
        "{",
        "  updated_at = $([int64](Get-Date -UFormat %s) * 1000),",
        "  program = `"$ProgramKey`",",
        "  installed_at = $InstalledAt,",
        "  version = `"$($ProgramEntry.version)`","
    )

    if ($ProgramEntry.uses_lib -and $Manifest.lib -and $Manifest.lib.version) {
        $lines += "  lib_version = `"$($Manifest.lib.version)`","
    }

    $lines += @(
        "  content_hash = `"$($ProgramEntry.content_hash)`",",
        "}"
    )

    $path = Join-Path $ComputerDir ".installed_program"
    [System.IO.File]::WriteAllText($path, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}

function Ensure-ParentDirectory {
    param([string]$TargetPath)
    $parent = Split-Path -Parent $TargetPath
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
}

function Get-ProgramEntry {
    param(
        [pscustomobject]$Manifest,
        [string]$ProgramKey
    )

    $normalized = $ProgramKey.ToLower()
    foreach ($property in $Manifest.programs.PSObject.Properties) {
        if ($property.Name.ToLower() -eq $normalized) {
            return [pscustomobject]@{
                Key = $property.Name
                Entry = $property.Value
            }
        }
    }

    throw "Program '$ProgramKey' was not found in Games/manifest.json"
}

function Get-DesiredDeployment {
    param(
        [string]$RepoRoot,
        [pscustomobject]$Manifest,
        [pscustomobject]$ProgramEntry
    )

    $desired = @()
    $sourceBase = Join-Path $RepoRoot $ProgramEntry.source_dir

    foreach ($file in @($ProgramEntry.files)) {
        $desired += [pscustomobject]@{
            RelativePath = $file.Replace('\', '/')
            SourcePath = Join-Path $sourceBase $file
            Kind = "code"
        }
    }

    foreach ($file in @($ProgramEntry.assets)) {
        $desired += [pscustomobject]@{
            RelativePath = $file.Replace('\', '/')
            SourcePath = Join-Path $sourceBase $file
            Kind = "asset"
        }
    }

    foreach ($file in @($ProgramEntry.config_files)) {
        $desired += [pscustomobject]@{
            RelativePath = $file.Replace('\', '/')
            SourcePath = Join-Path $sourceBase $file
            Kind = "config"
        }
    }

    if ($ProgramEntry.uses_lib -and $Manifest.lib -and $Manifest.lib.files) {
        foreach ($file in @($Manifest.lib.files)) {
            $desired += [pscustomobject]@{
                RelativePath = ("lib/" + $file.Replace('\', '/'))
                SourcePath = Join-Path $RepoRoot ("Games\lib\" + $file.Replace('/', '\'))
                Kind = "lib"
            }
        }
    }

    return $desired
}

function Get-ComputerTargets {
    param(
        [string]$ComputerRoot,
        [string]$ProgramKey,
        [int[]]$Ids,
        [switch]$AllInstalled
    )

    $directories = @(Get-ChildItem $ComputerRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)

    if ($Ids -and $Ids.Count -gt 0) {
        $targets = @()
        foreach ($id in $Ids) {
            $targetDir = Join-Path $ComputerRoot $id
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }

            $info = Read-LuaInfoFile -Path (Join-Path $targetDir ".installed_program")
            $targets += [pscustomobject]@{
                Id = [string]$id
                Dir = $targetDir
                Info = $info
            }
        }
        return $targets
    }

    $targets = @()
    foreach ($dir in $directories) {
        $info = Read-LuaInfoFile -Path (Join-Path $dir.FullName ".installed_program")
        if (-not $info) {
            continue
        }

        $installedKey = ($info.program, $info.game | Where-Object { $_ } | Select-Object -First 1)
        if ($AllInstalled -or ($ProgramKey -and $installedKey -and $installedKey.ToLower() -eq $ProgramKey.ToLower())) {
            $targets += [pscustomobject]@{
                Id = $dir.Name
                Dir = $dir.FullName
                Info = $info
            }
        }
    }

    return $targets
}

if (-not (Test-Path $manifestPath)) {
    throw "Manifest not found: $manifestPath"
}

$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$minecraftRoot = Resolve-MinecraftDir -ExplicitPath $MinecraftDir
$saveDir = Resolve-SaveDir -MinecraftRoot $minecraftRoot -RequestedSaveName $SaveName
$computerRoot = Join-Path $saveDir "computercraft\computer"

if (-not (Test-Path $computerRoot)) {
    throw "Computer directory not found: $computerRoot"
}

if ($ListTargets) {
    Write-Host "Minecraft: $minecraftRoot" -ForegroundColor Cyan
    Write-Host "Save:      $saveDir" -ForegroundColor Cyan
    Write-Host ""

    $targets = Get-ComputerTargets -ComputerRoot $computerRoot -AllInstalled
    if (-not $targets -or $targets.Count -eq 0) {
        Write-Host "No installed ComputerCraft programs were found." -ForegroundColor Yellow
        return
    }

    foreach ($target in $targets) {
        $installedKey = ($target.Info.program, $target.Info.game | Where-Object { $_ } | Select-Object -First 1)
        $version = if ($target.Info.version) { $target.Info.version } else { "?" }
        Write-Host ("[{0}] {1} v{2}" -f $target.Id, $installedKey, $version) -ForegroundColor Gray
    }
    return
}

if (-not $Game) {
    throw "Pass -Game <Name> or use -ListTargets."
}

$resolvedProgram = Get-ProgramEntry -Manifest $manifest -ProgramKey $Game
$programKey = $resolvedProgram.Key
$programEntry = $resolvedProgram.Entry
$desiredFiles = Get-DesiredDeployment -RepoRoot $repoRoot -Manifest $manifest -ProgramEntry $programEntry
$desiredRelativePaths = @($desiredFiles | ForEach-Object { $_.RelativePath })

$targets = Get-ComputerTargets -ComputerRoot $computerRoot -ProgramKey $programKey -Ids $ComputerId -AllInstalled:$AllInstalled

if (-not $targets -or $targets.Count -eq 0) {
    throw "No target computers found for '$programKey' in $saveDir. Pass -ComputerId to target a specific computer."
}

Write-Host "Deploying $programKey to PrismLauncher runtime..." -ForegroundColor Cyan
Write-Host "  Minecraft: $minecraftRoot"
Write-Host "  Save:      $saveDir"
Write-Host "  Targets:   $($targets.Id -join ', ')"

foreach ($target in $targets) {
    $targetDir = $target.Dir
    $previouslyManaged = Read-ManagedFiles -ComputerDir $targetDir

    Write-Host ""
    Write-Host "Computer $($target.Id)" -ForegroundColor Yellow

    foreach ($relativePath in $previouslyManaged) {
        if ($desiredRelativePaths -contains $relativePath) {
            continue
        }

        $fullPath = Join-Path $targetDir ($relativePath.Replace('/', '\'))
        if (Test-Path $fullPath) {
            if ($DryRun) {
                Write-Host "  [dry-run] Remove $relativePath" -ForegroundColor DarkYellow
            } else {
                Remove-Item $fullPath -Force -Recurse -ErrorAction SilentlyContinue
                Write-Host "  Removed $relativePath" -ForegroundColor DarkGray
            }
        }
    }

    $copied = 0
    foreach ($item in $desiredFiles) {
        $relativePath = $item.RelativePath
        $targetPath = Join-Path $targetDir ($relativePath.Replace('/', '\'))

        if ($item.Kind -eq "config" -and -not $ResetConfig -and (Test-Path $targetPath)) {
            Write-Host "  Keeping config $relativePath" -ForegroundColor DarkGray
            continue
        }

        if (-not (Test-Path $item.SourcePath)) {
            throw "Missing source file for deployment: $($item.SourcePath)"
        }

        if ($DryRun) {
            Write-Host "  [dry-run] Copy $relativePath" -ForegroundColor DarkYellow
            $copied++
            continue
        }

        Ensure-ParentDirectory -TargetPath $targetPath
        Copy-Item $item.SourcePath -Destination $targetPath -Force
        $copied++
    }

    $existingInstalledAt = if ($target.Info -and $target.Info.installed_at) { [int64]$target.Info.installed_at } else { [int64](Get-Date -UFormat %s) * 1000 }

    if ($DryRun) {
        Write-Host "  [dry-run] Update .installed_program" -ForegroundColor DarkYellow
        Write-Host "  [dry-run] Update .roger_deployed_files" -ForegroundColor DarkYellow
    } else {
        Write-InstalledProgramInfo -ComputerDir $targetDir -ProgramKey $programKey -ProgramEntry $programEntry -Manifest $manifest -InstalledAt $existingInstalledAt
        Write-ManagedFiles -ComputerDir $targetDir -Paths $desiredRelativePaths
    }

    Write-Host "  Synced $copied files" -ForegroundColor Green
}

Write-Host ""
Write-Host "Deployment complete." -ForegroundColor Green
