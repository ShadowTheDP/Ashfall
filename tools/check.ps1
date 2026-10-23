param(
    [string]$Godot = ""
)

# Runs every headless check for Ashfall.
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\check.ps1
#   powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Godot "C:\Path\Godot_console.exe"

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

if (-not $Godot) {
    $candidates = @()
    $candidates += (Join-Path $root ".tools\Godot_v4.7.2-stable_win64_console.exe")
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($command) { $candidates += $command.Source }
    $Godot = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}

if (-not $Godot -or -not (Test-Path $Godot)) {
    throw "Godot console binary not found. Run tools\fetch_godot.ps1 first, pass -Godot <path>, or place it in .tools\."
}

Write-Host "Godot: $Godot" -ForegroundColor DarkGray
Write-Host "Project: $root" -ForegroundColor DarkGray

function Invoke-Step {
    param(
        [string]$Name,
        [string[]]$Arguments
    )
    Write-Host ""
    Write-Host "== $Name ==" -ForegroundColor Cyan
    & $Godot @Arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAILED: $Name (exit $LASTEXITCODE)" -ForegroundColor Red
        exit $LASTEXITCODE
    }
}

Invoke-Step -Name "Import assets / compile scripts" -Arguments @(
    "--headless", "--path", $root, "--import"
)

Invoke-Step -Name "Data + damage formula tests" -Arguments @(
    "--headless", "--path", $root, "--script", "res://tests/run_tests.gd"
)

Invoke-Step -Name "Combat probe (hit, damage, death, i-frames)" -Arguments @(
    "--headless", "--path", $root, "tests/combat_probe.tscn"
)

Invoke-Step -Name "Soak (all enemies, 3 waves, victory)" -Arguments @(
    "--headless", "--path", $root, "tests/soak.tscn"
)

Write-Host ""
Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
