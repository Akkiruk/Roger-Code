param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot ".."),
    [string]$OutputDir,
    [string]$PreviousIndexDir
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path $RepoRoot).Path
$GamesDir = Join-Path $RepoRoot "Games"
$UtilitiesDir = Join-Path $RepoRoot "Utilities"

if (-not $OutputDir) {
    $OutputDir = Join-Path $RepoRoot ".generated\deploy-index"
}

$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
if ($PreviousIndexDir) {
    $PreviousIndexDir = [System.IO.Path]::GetFullPath($PreviousIndexDir)
}

& (Join-Path $PSScriptRoot "check-lua-forward-declarations.ps1") -RepoRoot $RepoRoot
if (-not $?) {
    throw "Lua forward-declaration check failed"
}

$RepoName = Split-Path $RepoRoot -Leaf
$RepoOwner = "Akkiruk"
$PrimaryBranch = "main"
$SchemaVersion = 1
$InstallerPath = "Games/installer.lua"

$SkipPatterns = @("*.bak", "*.old", "*.log", "*.md", "manifest.json")
$SkipDirs = @("lib", ".git", ".github", ".vscode", "Do", "node_modules", "emulator")
$HiddenStandalonePrograms = @(
    "peripheral_info_collector",
    "test_ccvault",
    "test_ccvault_full"
)

function Test-SkipFile {
    param([string]$Name)

    foreach ($pattern in $SkipPatterns) {
        if ($Name -like $pattern) {
            return $true
        }
    }

    return $false
}

function Get-RelativeFilePath {
    param(
        [string]$BaseDir,
        [string]$FullPath
    )

    $base = ([System.IO.Path]::GetFullPath($BaseDir)).TrimEnd('\', '/')
    $full = [System.IO.Path]::GetFullPath($FullPath)
    return $full.Substring($base.Length + 1).Replace('\', '/')
}

function Get-Utf8Content {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Write-Utf8NoBomFile {
    param(
        [string]$Path,
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function ConvertTo-StableJson {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,
        [int]$Depth = 8
    )

    return (($InputObject | ConvertTo-Json -Depth $Depth) -replace "`r`n", "`n")
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256 {
    param([string]$Value)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }

    return ([BitConverter]::ToString($hash).Replace("-", "").ToLowerInvariant())
}

function Get-ProgramMainFile {
    param(
        [string]$Dir,
        [string]$DirName
    )

    $candidates = @(
        (Join-Path $Dir "$($DirName.ToLowerInvariant()).lua"),
        (Join-Path $Dir "$DirName.lua"),
        (Join-Path $Dir "startup.lua")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $first = Get-ChildItem $Dir -File -Filter "*.lua" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
    if ($first) {
        return $first.FullName
    }

    return $null
}

function Get-ProgramMetadata {
    param(
        [string]$Dir,
        [string]$DirName,
        [string]$SourceRoot,
        [string]$DefaultCategory
    )

    $meta = [ordered]@{
        key         = $DirName.ToLowerInvariant()
        name        = $DirName
        description = ""
        category    = $DefaultCategory
        entrypoint  = ""
        source_root = $SourceRoot
    }

    $mainFile = Get-ProgramMainFile -Dir $Dir -DirName $DirName
    if ($mainFile) {
        $meta.entrypoint = Get-RelativeFilePath -BaseDir $Dir -FullPath $mainFile
    }

    if (-not $mainFile) {
        return $meta
    }

    $lines = Get-Content $mainFile -TotalCount 12 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '^\s*--\s*manifest-key:\s*(.+)$') {
            $value = $Matches[1].Trim()
            if ($value) {
                $meta.key = $value
            }
            continue
        }
        if ($line -match '^\s*--\s*manifest-name:\s*(.+)$') {
            $value = $Matches[1].Trim()
            if ($value) {
                $meta.name = $value
            }
            continue
        }
        if ($line -match '^\s*--\s*manifest-description:\s*(.+)$') {
            $value = $Matches[1].Trim()
            if ($value -and -not $meta.description) {
                $meta.description = $value
            }
            continue
        }
        if ($line -match '^\s*--\s*manifest-category:\s*(.+)$') {
            $value = $Matches[1].Trim()
            if ($value) {
                $meta.category = $value
            }
            continue
        }
        if ($line -match '^\s*--\s*(.+)$') {
            $desc = $Matches[1].Trim()
            if (
                $desc.Length -gt 10 -and
                $desc -notmatch '^manifest-(key|name|description|category):' -and
                $desc -notmatch '^\S+\.lua$' -and
                $desc -notmatch '^[-=]{4,}$'
            ) {
                $meta.description = $desc
                break
            }
        }
    }

    return $meta
}

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
            Where-Object {
                $_.Extension -eq ".lua" -and
                $_.Name -notlike "*_config.lua" -and
                $_.Name -notlike "*_settings.lua"
            } |
            ForEach-Object { Get-RelativeFilePath -BaseDir $Dir -FullPath $_.FullName } |
            Sort-Object
    )

    $assetFiles = @(
        $allFiles |
            Where-Object { $_.Extension -ne ".lua" } |
            ForEach-Object { Get-RelativeFilePath -BaseDir $Dir -FullPath $_.FullName } |
            Sort-Object
    )

    return [ordered]@{
        files        = $luaFiles
        config_files = $configFiles
        assets       = $assetFiles
        lua_files    = @($luaFiles + $configFiles | Sort-Object -Unique)
    }
}

function Get-RequireLiterals {
    param([string]$Path)

    $content = Get-Utf8Content -Path $Path
    $matches = [regex]::Matches($content, 'require\s*\(\s*["'']([^"'']+)["'']\s*\)')
    $modules = New-Object System.Collections.Generic.List[string]

    foreach ($match in $matches) {
        $moduleName = $match.Groups[1].Value
        if ($moduleName) {
            $modules.Add($moduleName)
        }
    }

    return @($modules | Sort-Object -Unique)
}

function Resolve-LibModulePath {
    param(
        [string]$RepoRootPath,
        [string]$ModuleName
    )

    $relative = $ModuleName.Substring(4).Replace('.', '/')
    $candidate = Join-Path $RepoRootPath ("Games\lib\" + $relative + ".lua")
    if (Test-Path $candidate) {
        return $candidate
    }

    $candidate = Join-Path $RepoRootPath ("Games\lib\" + $relative + "\init.lua")
    if (Test-Path $candidate) {
        return $candidate
    }

    return $null
}

function Get-LibDependencyClosure {
    param(
        [string]$RepoRootPath,
        [string]$PackageRoot,
        [string[]]$LuaRelativePaths
    )

    $queue = New-Object System.Collections.Generic.Queue[string]
    $seenModules = New-Object "System.Collections.Generic.HashSet[string]" ([System.StringComparer]::OrdinalIgnoreCase)
    $resolved = New-Object System.Collections.Generic.List[string]

    foreach ($relativePath in $LuaRelativePaths) {
        $fullPath = Join-Path $PackageRoot ($relativePath.Replace('/', '\'))
        if (-not (Test-Path $fullPath)) {
            continue
        }

        foreach ($moduleName in Get-RequireLiterals -Path $fullPath) {
            if ($moduleName -like "lib.*" -and $seenModules.Add($moduleName)) {
                $queue.Enqueue($moduleName)
            }
        }
    }

    while ($queue.Count -gt 0) {
        $moduleName = $queue.Dequeue()
        $modulePath = Resolve-LibModulePath -RepoRootPath $RepoRootPath -ModuleName $moduleName
        if (-not $modulePath) {
            throw "Could not resolve required module '$moduleName'"
        }

        $relativeLibPath = Get-RelativeFilePath -BaseDir (Join-Path $RepoRootPath "Games\lib") -FullPath $modulePath
        if ($resolved -notcontains $relativeLibPath) {
            $resolved.Add($relativeLibPath)
        }

        foreach ($childModule in Get-RequireLiterals -Path $modulePath) {
            if ($childModule -like "lib.*" -and $seenModules.Add($childModule)) {
                $queue.Enqueue($childModule)
            }
        }
    }

    return @($resolved | Sort-Object)
}

function Get-VersionSeedData {
    param(
        [string]$Key,
        [hashtable]$PreviousPrograms
    )

    if ($PreviousPrograms.ContainsKey($Key)) {
        return $PreviousPrograms[$Key]
    }

    return @{
        version = "1.0.0"
        package_hash = ""
    }
}

function Bump-PatchVersion {
    param([string]$Version)

    $parts = $Version -split '\.'
    if ($parts.Count -ne 3) {
        return "1.0.1"
    }

    $parts[2] = [string]([int]$parts[2] + 1)
    return ($parts -join '.')
}

function Resolve-DisplayVersion {
    param(
        [string]$Key,
        [string]$PackageHash,
        [hashtable]$PreviousPrograms
    )

    $seed = Get-VersionSeedData -Key $Key -PreviousPrograms $PreviousPrograms
    if (-not $seed.package_hash) {
        return $seed.version
    }

    if ($seed.package_hash -eq $PackageHash) {
        return $seed.version
    }

    return (Bump-PatchVersion -Version $seed.version)
}

$previousPrograms = @{}
if ($PreviousIndexDir) {
    $previousLatestPath = Join-Path $PreviousIndexDir "latest.json"
    if (Test-Path $previousLatestPath) {
        $previousLatest = Get-Content $previousLatestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $previousLatest.programs.PSObject.Properties) {
            $previousPrograms[$property.Name] = @{
                version = [string]$property.Value.version
                package_hash = [string]$property.Value.package_hash
            }
        }
    }
}

$gitCommit = (git -C $RepoRoot rev-parse HEAD).Trim()
if (-not $gitCommit) {
    throw "Could not resolve repository commit SHA"
}

$generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
$programSpecs = New-Object System.Collections.Generic.List[object]

$programDirs = @()
if (Test-Path $GamesDir) {
    $programDirs += Get-ChildItem $GamesDir -Directory | Where-Object { $_.Name -notin $SkipDirs }
}
if (Test-Path $UtilitiesDir) {
    $programDirs += Get-ChildItem $UtilitiesDir -Directory | Where-Object { $_.Name -notin $SkipDirs }
}

$standaloneUtilities = @()
if (Test-Path $UtilitiesDir) {
    $standaloneUtilities = @(
        Get-ChildItem $UtilitiesDir -File -Filter "*.lua" |
            Where-Object {
                -not (Test-SkipFile $_.Name) -and
                ([System.IO.Path]::GetFileNameWithoutExtension($_.Name).ToLowerInvariant() -notin $HiddenStandalonePrograms)
            }
    )
}

foreach ($dir in ($programDirs | Sort-Object FullName)) {
    $category = if ($dir.FullName.StartsWith($UtilitiesDir, [System.StringComparison]::OrdinalIgnoreCase)) { "Utilities" } else { "Games" }
    $sourceRoot = Get-RelativeFilePath -BaseDir $RepoRoot -FullPath $dir.FullName
    $meta = Get-ProgramMetadata -Dir $dir.FullName -DirName $dir.Name -SourceRoot $sourceRoot -DefaultCategory $category
    $discovered = Get-ProgramFiles -Dir $dir.FullName

    if ((@($discovered.files).Count + @($discovered.config_files).Count) -eq 0) {
        continue
    }

    $libClosure = Get-LibDependencyClosure -RepoRootPath $RepoRoot -PackageRoot $dir.FullName -LuaRelativePaths $discovered.lua_files
    $installFiles = New-Object System.Collections.Generic.List[object]
    $libModules = New-Object System.Collections.Generic.List[string]

    foreach ($file in @($discovered.files)) {
        $repoPath = "$sourceRoot/$file"
        $fullPath = Join-Path $dir.FullName ($file.Replace('/', '\'))
        $installFiles.Add([ordered]@{
            repo_path = $repoPath
            install_path = $file
            sha256 = Get-FileSha256 -Path $fullPath
        })
    }

    foreach ($file in @($discovered.config_files)) {
        $repoPath = "$sourceRoot/$file"
        $fullPath = Join-Path $dir.FullName ($file.Replace('/', '\'))
        $installFiles.Add([ordered]@{
            repo_path = $repoPath
            install_path = $file
            sha256 = Get-FileSha256 -Path $fullPath
            preserve_existing = $true
        })
    }

    foreach ($file in @($discovered.assets)) {
        $repoPath = "$sourceRoot/$file"
        $fullPath = Join-Path $dir.FullName ($file.Replace('/', '\'))
        $installFiles.Add([ordered]@{
            repo_path = $repoPath
            install_path = $file
            sha256 = Get-FileSha256 -Path $fullPath
        })
    }

    foreach ($libFile in $libClosure) {
        $fullPath = Join-Path $GamesDir ("lib\" + $libFile.Replace('/', '\'))
        $installFiles.Add([ordered]@{
            repo_path = "Games/lib/$libFile"
            install_path = "lib/$libFile"
            sha256 = Get-FileSha256 -Path $fullPath
        })

        $moduleName = "lib." + (($libFile -replace '\.lua$', '') -replace '/', '.')
        $libModules.Add($moduleName)
    }

    $installFileList = @($installFiles | Sort-Object install_path, repo_path)
    $packageHashInput = ($installFileList | ForEach-Object {
        "$($_.install_path)|$($_.repo_path)|$([bool]$_.preserve_existing)|$($_.sha256)"
    }) -join "`n"
    $packageHash = Get-StringSha256 -Value $packageHashInput
    $version = Resolve-DisplayVersion -Key $meta.key -PackageHash $packageHash -PreviousPrograms $previousPrograms

    $spec = [ordered]@{
        schema_version = $SchemaVersion
        program = [ordered]@{
            key = $meta.key
            name = $meta.name
            category = $meta.category
            description = $meta.description
            source_root = $meta.source_root
            entrypoint = $meta.entrypoint
            version = $version
        }
        build = [ordered]@{
            commit = $gitCommit
            generated_at = $generatedAt
            package_hash = $packageHash
        }
        install = [ordered]@{
            preserve = @($discovered.config_files)
            files = $installFileList
        }
        runtime = [ordered]@{
            requires_updater = [bool]($libModules -contains "lib.updater")
            lib_modules = @($libModules | Sort-Object -Unique)
        }
    }

    $programSpecs.Add($spec)
}

foreach ($file in $standaloneUtilities | Sort-Object Name) {
    $key = [System.IO.Path]::GetFileNameWithoutExtension($file.Name).ToLowerInvariant()
    if ($programSpecs | Where-Object { $_.program.key -eq $key }) {
        continue
    }

    $fullPath = $file.FullName
    $content = Get-Utf8Content -Path $fullPath
    $description = ""
    foreach ($line in ($content -split "`r?`n" | Select-Object -First 5)) {
        if ($line -match '^\s*--\s*(.+)$') {
            $desc = $Matches[1].Trim()
            if ($desc.Length -gt 10 -and $desc -notmatch '^\S+\.lua$' -and $desc -notmatch '^[-=]{4,}$') {
                $description = $desc
                break
            }
        }
    }

    $installFile = [ordered]@{
        repo_path = "Utilities/$($file.Name)"
        install_path = $file.Name
        sha256 = Get-FileSha256 -Path $fullPath
    }

    $libClosure = Get-LibDependencyClosure -RepoRootPath $RepoRoot -PackageRoot $UtilitiesDir -LuaRelativePaths @($file.Name)
    $installFiles = New-Object System.Collections.Generic.List[object]
    $installFiles.Add($installFile)
    $libModules = New-Object System.Collections.Generic.List[string]

    foreach ($libFile in $libClosure) {
        $libFullPath = Join-Path $GamesDir ("lib\" + $libFile.Replace('/', '\'))
        $installFiles.Add([ordered]@{
            repo_path = "Games/lib/$libFile"
            install_path = "lib/$libFile"
            sha256 = Get-FileSha256 -Path $libFullPath
        })

        $moduleName = "lib." + (($libFile -replace '\.lua$', '') -replace '/', '.')
        $libModules.Add($moduleName)
    }

    $orderedInstallFiles = @($installFiles | Sort-Object install_path, repo_path)
    $packageHashInput = ($orderedInstallFiles | ForEach-Object {
        "$($_.install_path)|$($_.repo_path)|$([bool]$_.preserve_existing)|$($_.sha256)"
    }) -join "`n"
    $packageHash = Get-StringSha256 -Value $packageHashInput
    $version = Resolve-DisplayVersion -Key $key -PackageHash $packageHash -PreviousPrograms $previousPrograms

    $programSpecs.Add([ordered]@{
        schema_version = $SchemaVersion
        program = [ordered]@{
            key = $key
            name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
            category = "Utilities"
            description = $description
            source_root = "Utilities"
            entrypoint = $file.Name
            version = $version
        }
        build = [ordered]@{
            commit = $gitCommit
            generated_at = $generatedAt
            package_hash = $packageHash
        }
        install = [ordered]@{
            preserve = @()
            files = $orderedInstallFiles
        }
        runtime = [ordered]@{
            requires_updater = [bool]($libModules -contains "lib.updater")
            lib_modules = @($libModules | Sort-Object -Unique)
        }
    })
}

if (Test-Path $OutputDir) {
    Remove-Item $OutputDir -Force -Recurse
}

New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutputDir "programs") -Force | Out-Null

$installerFullPath = Join-Path $RepoRoot $InstallerPath
$installerVersion = "2.0.0"
if (Test-Path $installerFullPath) {
    $match = Select-String -Path $installerFullPath -Pattern 'INSTALLER_VERSION\s*=\s*"([^"]+)"' | Select-Object -First 1
    if ($match) {
        $installerVersion = $match.Matches[0].Groups[1].Value
    }
}

$latestPrograms = [ordered]@{}
foreach ($spec in ($programSpecs | Sort-Object { $_.program.key })) {
    $specRelativePath = "programs/$($spec.program.key).json"
    $latestPrograms[$spec.program.key] = [ordered]@{
        name = $spec.program.name
        category = $spec.program.category
        description = $spec.program.description
        version = $spec.program.version
        commit = $spec.build.commit
        package_hash = $spec.build.package_hash
        spec_path = $specRelativePath
    }

    $specJson = ConvertTo-StableJson -InputObject $spec -Depth 8
    Write-Utf8NoBomFile -Path (Join-Path $OutputDir $specRelativePath) -Content $specJson
}

$latest = [ordered]@{
    schema_version = $SchemaVersion
    generated_at = $generatedAt
    repo = [ordered]@{
        owner = $RepoOwner
        name = $RepoName
        branch = $PrimaryBranch
    }
    installer = [ordered]@{
        version = $installerVersion
        commit = $gitCommit
        path = $InstallerPath
        sha256 = Get-FileSha256 -Path $installerFullPath
    }
    programs = $latestPrograms
}

$latestJson = ConvertTo-StableJson -InputObject $latest -Depth 8
Write-Utf8NoBomFile -Path (Join-Path $OutputDir "latest.json") -Content $latestJson

Write-Host "Wrote deploy index to $OutputDir" -ForegroundColor Green
Write-Host "Programs: $($latestPrograms.Count)" -ForegroundColor Gray
