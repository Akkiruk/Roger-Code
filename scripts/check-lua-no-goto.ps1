param(
    [string]$RepoRoot = (Join-Path $PSScriptRoot "..")
)

# CC:Tweaked runs Lua 5.1, which has no goto and no ::labels::. Either one is a syntax error on a real
# computer, so fail the check when any Lua file contains one (comments and string literals are ignored).

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path $RepoRoot).Path

function Get-CodeLine {
    param([string]$Line)

    $withoutLineComment = ($Line -replace '--.*$', '')
    $withoutDoubleQuoted = ($withoutLineComment -replace '"(?:[^"\\]|\\.)*"', '""')
    return ($withoutDoubleQuoted -replace "'(?:[^'\\]|\\.)*'", "''")
}

$findings = @()
$luaFiles = Get-ChildItem -Path $RepoRoot -Recurse -File -Filter "*.lua" |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules)[\\/]' } |
    Sort-Object FullName

foreach ($file in $luaFiles) {
    $lines = Get-Content -Path $file.FullName
    $inBlockComment = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $raw = $lines[$i]
        if ($inBlockComment) {
            if ($raw -match '\]\]') { $inBlockComment = $false }
            continue
        }
        if ($raw -match '--\[=*\[' -and $raw -notmatch '\]=*\]') {
            $inBlockComment = $true
            continue
        }
        $line = Get-CodeLine $raw
        if ($line -match '\bgoto\s+[A-Za-z_]' -or $line -match '::[A-Za-z_][A-Za-z0-9_]*::') {
            $relative = $file.FullName.Substring($RepoRoot.Length + 1).Replace('\', '/')
            $findings += "${relative}:$($i + 1): $($raw.Trim())"
        }
    }
}

if ($findings.Count -gt 0) {
    Write-Host "goto/label found (not valid in CC:Tweaked Lua 5.1):"
    $findings | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host "No goto or labels found in $($luaFiles.Count) Lua files."
exit 0
