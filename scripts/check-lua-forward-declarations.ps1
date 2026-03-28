param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot "..")
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path $RepoRoot).Path
$scanRoots = @(
    (Join-Path $RepoRoot "Games"),
    (Join-Path $RepoRoot "Utilities")
) | Where-Object { Test-Path $_ }
$excludedRelativePaths = @(
    "Games/lib/basalt.lua"
)

function Get-CodeLine {
    param([string]$Line)

    $withoutLineComment = ($Line -replace '--.*$', '')
    $withoutDoubleQuoted = ($withoutLineComment -replace '"(?:[^"\\]|\\.)*"', '""')
    $withoutSingleQuoted = ($withoutDoubleQuoted -replace "'(?:[^'\\]|\\.)*'", "''")
    return $withoutSingleQuoted
}

$findings = @()
$luaFiles = Get-ChildItem -Path $scanRoots -Recurse -File -Filter "*.lua" |
    Where-Object {
        $relativePath = $_.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
        $excludedRelativePaths -notcontains $relativePath
    } |
    Sort-Object FullName

foreach ($file in $luaFiles) {
    $lines = Get-Content -Path $file.FullName
    $symbols = @{}

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNumber = $i + 1
        $line = Get-CodeLine $lines[$i]

        if ($line -match '^\s*local function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(') {
            $name = $matches[1]
            if (-not $symbols.ContainsKey($name)) {
                $symbols[$name] = @{
                    LocalLine = $lineNumber
                    FunctionLine = $lineNumber
                }
            } else {
                if (-not $symbols[$name].LocalLine -or $lineNumber -lt $symbols[$name].LocalLine) {
                    $symbols[$name].LocalLine = $lineNumber
                }
                if (-not $symbols[$name].FunctionLine -or $lineNumber -lt $symbols[$name].FunctionLine) {
                    $symbols[$name].FunctionLine = $lineNumber
                }
            }
            continue
        }

        if ($line -match '^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\s*\(') {
            $name = $matches[1]
            if (-not $symbols.ContainsKey($name)) {
                $symbols[$name] = @{
                    LocalLine = $lineNumber
                    FunctionLine = $lineNumber
                }
            } else {
                if (-not $symbols[$name].LocalLine -or $lineNumber -lt $symbols[$name].LocalLine) {
                    $symbols[$name].LocalLine = $lineNumber
                }
                if (-not $symbols[$name].FunctionLine -or $lineNumber -lt $symbols[$name].FunctionLine) {
                    $symbols[$name].FunctionLine = $lineNumber
                }
            }
            continue
        }

        if ($line -match '^\s*local\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:=\s*nil\s*)?$') {
            $name = $matches[1]
            if (-not $symbols.ContainsKey($name)) {
                $symbols[$name] = @{
                    LocalLine = $lineNumber
                    FunctionLine = $null
                }
            } elseif (-not $symbols[$name].LocalLine -or $lineNumber -lt $symbols[$name].LocalLine) {
                $symbols[$name].LocalLine = $lineNumber
            }
        }
    }

    foreach ($symbol in $symbols.GetEnumerator()) {
        $name = $symbol.Key
        $info = $symbol.Value
        if (-not $info.FunctionLine -or -not $info.LocalLine) {
            continue
        }

        $pattern = '(?<![\.:])\b' + [regex]::Escape($name) + '\s*\('
        for ($i = 0; $i -lt ($info.LocalLine - 1); $i++) {
            $line = Get-CodeLine $lines[$i]
            if ($line -match $pattern) {
                $findings += [pscustomobject]@{
                    File = $file.FullName
                    Name = $name
                    ReferenceLine = $i + 1
                    DeclarationLine = $info.LocalLine
                    SourceLine = $lines[$i].Trim()
                }
                break
            }
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Host "Lua forward-declaration check failed:" -ForegroundColor Red
    foreach ($finding in $findings | Sort-Object File, ReferenceLine, Name) {
        Write-Host ("- {0}:{1} uses local function '{2}' before its local scope starts at line {3}" -f $finding.File, $finding.ReferenceLine, $finding.Name, $finding.DeclarationLine) -ForegroundColor Yellow
        Write-Host ("  {0}" -f $finding.SourceLine) -ForegroundColor DarkGray
    }
    exit 1
}

Write-Host "Lua forward-declaration check passed." -ForegroundColor Green
