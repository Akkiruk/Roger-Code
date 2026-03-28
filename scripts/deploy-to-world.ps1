param(
    [string]$Game,
    [int[]]$ComputerId,
    [string]$SaveName,
    [string]$MinecraftDir,
    [switch]$ResetConfig,
    [switch]$AllInstalled,
    [switch]$ListTargets,
    [switch]$DryRun,
    [switch]$SkipDeployIndex,
    [switch]$SkipManifest
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot "build-deploy-index.ps1"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("roger-deploy-" + [guid]::NewGuid().ToString("N"))
$indexDir = Join-Path $tempRoot "deploy-index"

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
        if (-not $candidate -or $seen.ContainsKey($candidate)) {
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
    foreach ($key in @("program", "game", "name", "version", "source_commit", "package_hash", "content_hash", "spec_path")) {
        $match = [regex]::Match($raw, $key + '\s*=\s*"([^"]*)"')
        if ($match.Success) {
            $info[$key] = $match.Groups[1].Value
        }
    }
    foreach ($key in @("schema_version", "installed_at", "updated_at")) {
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
        [pscustomobject]$Spec,
        [string]$SpecPath,
        [int64]$InstalledAt
    )

    $lines = @(
        "{",
        "  schema_version = 1,",
        "  program = `"$($Spec.program.key)`",",
        "  name = `"$($Spec.program.name)`",",
        "  version = `"$($Spec.program.version)`",",
        "  source_commit = `"$($Spec.build.commit)`",",
        "  package_hash = `"$($Spec.build.package_hash)`",",
        "  content_hash = `"$($Spec.build.package_hash)`",",
        "  spec_path = `"$SpecPath`",",
        "  installed_at = $InstalledAt,",
        "  updated_at = $([int64](Get-Date -UFormat %s) * 1000),",
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

function Remove-StaleFiles {
    param(
        [string]$ComputerDir,
        [string[]]$PreviousPaths,
        [string[]]$DesiredPaths,
        [switch]$DryRunMode
    )

    $wanted = @{}
    foreach ($path in $DesiredPaths) {
        $wanted[$path] = $true
    }

    foreach ($relativePath in $PreviousPaths) {
        if ($wanted.ContainsKey($relativePath)) {
            continue
        }

        $fullPath = Join-Path $ComputerDir ($relativePath.Replace('/', '\'))
        if (-not (Test-Path $fullPath)) {
            continue
        }

        if ($DryRunMode) {
            Write-Host "  [dry-run] Remove $relativePath" -ForegroundColor DarkYellow
        } else {
            Remove-Item $fullPath -Force -Recurse -ErrorAction SilentlyContinue
            Write-Host "  Removed $relativePath" -ForegroundColor DarkGray
        }
    }
}

function Get-ComputerTargets {
    param(
        [string]$ComputerRoot,
        [string]$ProgramKey,
        [int[]]$Ids,
        [switch]$AllInstalledMode
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
        if ($AllInstalledMode -or ($ProgramKey -and $installedKey -and $installedKey.ToLower() -eq $ProgramKey.ToLower())) {
            $targets += [pscustomobject]@{
                Id = $dir.Name
                Dir = $dir.FullName
                Info = $info
            }
        }
    }

    return $targets
}

function Get-DeployIndex {
    param()

    if ($SkipDeployIndex -or $SkipManifest) {
        throw "Skipping deploy-index generation is no longer supported for the primary deployment flow."
    }

    & $buildScript -RepoRoot $repoRoot -OutputDir $indexDir
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build deploy index"
    }

    $latestPath = Join-Path $indexDir "latest.json"
    if (-not (Test-Path $latestPath)) {
        throw "Generated deploy index is missing latest.json"
    }

    return (Get-Content $latestPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-ProgramSpec {
    param(
        [pscustomobject]$Latest,
        [string]$ProgramKey
    )

    $normalized = $ProgramKey.ToLower()
    $programEntry = $null
    foreach ($property in $Latest.programs.PSObject.Properties) {
        if ($property.Name.ToLower() -eq $normalized) {
            $programEntry = $property.Value
            break
        }
    }

    if (-not $programEntry) {
        throw "Program '$ProgramKey' was not found in the generated deploy index"
    }

    $specPath = Join-Path $indexDir $programEntry.spec_path
    if (-not (Test-Path $specPath)) {
        throw "Program spec not found: $specPath"
    }

    return [pscustomobject]@{
        Key = $normalized
        SpecPath = $programEntry.spec_path
        Spec = (Get-Content $specPath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
}

try {
    $latest = Get-DeployIndex
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

        $targets = Get-ComputerTargets -ComputerRoot $computerRoot -AllInstalledMode
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

    $resolvedProgram = Get-ProgramSpec -Latest $latest -ProgramKey $Game
    $spec = $resolvedProgram.Spec
    $desiredFiles = @($spec.install.files)
    $desiredRelativePaths = @($desiredFiles | ForEach-Object { $_.install_path })
    $targets = Get-ComputerTargets -ComputerRoot $computerRoot -ProgramKey $resolvedProgram.Key -Ids $ComputerId -AllInstalledMode:$AllInstalled

    if (-not $targets -or $targets.Count -eq 0) {
        throw "No target computers found for '$($resolvedProgram.Key)' in $saveDir. Pass -ComputerId to target a specific computer."
    }

    Write-Host "Deploying $($resolvedProgram.Key) to PrismLauncher runtime..." -ForegroundColor Cyan
    Write-Host "  Minecraft: $minecraftRoot"
    Write-Host "  Save:      $saveDir"
    Write-Host "  Targets:   $($targets.Id -join ', ')"

    foreach ($target in $targets) {
        $targetDir = $target.Dir
        $previouslyManaged = Read-ManagedFiles -ComputerDir $targetDir

        Write-Host ""
        Write-Host "Computer $($target.Id)" -ForegroundColor Yellow

        Remove-StaleFiles -ComputerDir $targetDir -PreviousPaths $previouslyManaged -DesiredPaths $desiredRelativePaths -DryRunMode:$DryRun

        $copied = 0
        foreach ($item in $desiredFiles) {
            $relativePath = $item.install_path
            $targetPath = Join-Path $targetDir ($relativePath.Replace('/', '\'))
            $sourcePath = Join-Path $repoRoot ($item.repo_path.Replace('/', '\'))

            if ($item.preserve_existing -and -not $ResetConfig -and (Test-Path $targetPath)) {
                Write-Host "  Keeping config $relativePath" -ForegroundColor DarkGray
                continue
            }

            if (-not (Test-Path $sourcePath)) {
                throw "Missing source file for deployment: $sourcePath"
            }

            if ($DryRun) {
                Write-Host "  [dry-run] Copy $relativePath" -ForegroundColor DarkYellow
                $copied++
                continue
            }

            Ensure-ParentDirectory -TargetPath $targetPath
            Copy-Item $sourcePath -Destination $targetPath -Force
            $copied++
        }

        $existingInstalledAt = if ($target.Info -and $target.Info.installed_at) {
            [int64]$target.Info.installed_at
        } else {
            [int64](Get-Date -UFormat %s) * 1000
        }

        if ($DryRun) {
            Write-Host "  [dry-run] Update .installed_program" -ForegroundColor DarkYellow
            Write-Host "  [dry-run] Update .roger_deployed_files" -ForegroundColor DarkYellow
        } else {
            Write-InstalledProgramInfo -ComputerDir $targetDir -Spec $spec -SpecPath $resolvedProgram.SpecPath -InstalledAt $existingInstalledAt
            Write-ManagedFiles -ComputerDir $targetDir -Paths $desiredRelativePaths
        }

        Write-Host "  Synced $copied files" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Deployment complete." -ForegroundColor Green
} finally {
    if (Test-Path $tempRoot) {
        Remove-Item $tempRoot -Force -Recurse -ErrorAction SilentlyContinue
    }
}
