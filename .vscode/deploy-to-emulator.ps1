# deploy-to-emulator.ps1
# Syncs game files + emulator mocks to CraftOS-PC emulator
# Usage: .\deploy-to-emulator.ps1 [-Game Blackjack] [-Clean] [-ComputerId 0] [-NoMocks]

param(
    [string]$Game = "Blackjack",
    [switch]$Clean,
    [switch]$NoMocks,
    [int]$ComputerId = 0
)

$dataPath = "$env:APPDATA\CraftOS-PC\computer\$ComputerId"
$workspace = Split-Path -Parent $PSScriptRoot   # parent of .vscode/
$gameDir   = Join-Path $workspace "Games\$Game"
$lib       = Join-Path $workspace "Games\lib"
$emulator  = Join-Path $workspace "Games\emulator"

if (-not (Test-Path $gameDir)) {
    Write-Host "ERROR: Game folder not found: $gameDir" -ForegroundColor Red
    return
}

if ($Clean) {
    Write-Host "Cleaning emulator computer $ComputerId..." -ForegroundColor Yellow
    if (Test-Path $dataPath) {
        Get-ChildItem $dataPath -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Clean complete." -ForegroundColor Green
    return
}

Write-Host "Deploying $Game to CraftOS-PC computer $ComputerId..." -ForegroundColor Cyan
Write-Host "  Source: $gameDir"
Write-Host "  Lib:    $lib"
Write-Host "  Target: $dataPath"

# Create target dirs
if (-not (Test-Path $dataPath))     { New-Item -ItemType Directory -Path $dataPath -Force | Out-Null }
if (-not (Test-Path "$dataPath\lib")) { New-Item -ItemType Directory -Path "$dataPath\lib" -Force | Out-Null }

# Copy game files (skip backups and old files)
$copied = 0
Get-ChildItem $gameDir -File | Where-Object {
    $_.Extension -notin @('.bak', '.old') -and
    $_.Name -ne 'debug.txt'
} | ForEach-Object {
    Copy-Item $_.FullName -Destination $dataPath -Force
    $copied++
}
Write-Host "  Copied $copied files from $Game/" -ForegroundColor Gray

# Copy lib files
$libCopied = 0
Get-ChildItem $lib -Filter "*.lua" | ForEach-Object {
    Copy-Item $_.FullName -Destination "$dataPath\lib" -Force
    $libCopied++
}
Write-Host "  Copied $libCopied files from lib/" -ForegroundColor Gray

# Copy emulator mock files (unless -NoMocks)
$emuCopied = 0
if (-not $NoMocks -and (Test-Path $emulator)) {
    if (-not (Test-Path "$dataPath\emulator"))       { New-Item -ItemType Directory -Path "$dataPath\emulator" -Force | Out-Null }
    if (-not (Test-Path "$dataPath\emulator\mocks")) { New-Item -ItemType Directory -Path "$dataPath\emulator\mocks" -Force | Out-Null }

    Get-ChildItem $emulator -Filter "*.lua" -File | ForEach-Object {
        Copy-Item $_.FullName -Destination "$dataPath\emulator" -Force
        $emuCopied++
    }
    $mocksDir = Join-Path $emulator "mocks"
    if (Test-Path $mocksDir) {
        Get-ChildItem $mocksDir -Filter "*.lua" -File | ForEach-Object {
            Copy-Item $_.FullName -Destination "$dataPath\emulator\mocks" -Force
            $emuCopied++
        }
    }

    # Install emulator startup.lua (overwrite the computer's startup)
    Copy-Item "$emulator\emu_startup.lua" -Destination "$dataPath\startup.lua" -Force
    Write-Host "  Installed emu_startup.lua as startup.lua" -ForegroundColor Gray
    Write-Host "  Copied $emuCopied files from emulator/" -ForegroundColor Gray
} else {
    Write-Host "  Skipped emulator mocks (-NoMocks or no emulator/ dir)" -ForegroundColor DarkGray
}

$total = $copied + $libCopied + $emuCopied
Write-Host "Deploy complete! ($total files)" -ForegroundColor Green
Write-Host ""
if (-not $NoMocks) {
    Write-Host "Emulator will auto-boot with mocks. Just start CraftOS-PC!" -ForegroundColor Yellow
} else {
    Write-Host "In CraftOS-PC, run:  startup" -ForegroundColor Yellow
}
