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

# --- meta layer probes (scene-based: they need autoloads) -------------------
function Invoke-Probe {
    param([string]$Name, [string]$Scene)
    Write-Host ""
    Write-Host "== $Name ==" -ForegroundColor Cyan
    # Godot writes warnings to stderr; with $ErrorActionPreference = "Stop"
    # PowerShell turns those into terminating errors. Relax it for the call.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $out = & $Godot --headless --path $root $Scene 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    $out | Write-Output
    if ($out -match "FAILED|FAIL:") {
        Write-Host "FAILED: $Name" -ForegroundColor Red
        exit 1
    }
    if ($code -ne 0) {
        Write-Host "FAILED: $Name (exit $code)" -ForegroundColor Red
        exit $code
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

Invoke-Step -Name "Reward probe (keyboard boon picker)" -Arguments @(
    "--headless", "--path", $root, "tests/reward_probe.tscn"
)

Invoke-Step -Name "Soak (all enemies, 3 waves, victory)" -Arguments @(
    "--headless", "--path", $root, "tests/soak.tscn"
)

Invoke-Probe -Name "Hub panels (open/close/buy)" -Scene "tests/esc_probe.tscn"
Invoke-Probe -Name "Hub -> floor handoff" -Scene "tests/floor_probe.tscn"
Invoke-Probe -Name "Full run (5 floors -> victory)" -Scene "tests/run_probe.tscn"
Invoke-Probe -Name "Audit: combat / weapons" -Scene "tests/audit_a1.tscn"
Invoke-Probe -Name "Audit: save / economy" -Scene "tests/audit_a2.tscn"
Invoke-Probe -Name "Audit: floors / spawns" -Scene "tests/audit_a3.tscn"
Invoke-Probe -Name "Audit: UI / input" -Scene "tests/audit_a4.tscn"
Invoke-Probe -Name "Audit: vertical traversal" -Scene "tests/audit_v1.tscn"
Invoke-Probe -Name "Audit: enemies / encounters" -Scene "tests/audit_v2.tscn"
Invoke-Probe -Name "Audit: run flow / progression" -Scene "tests/audit_v3.tscn"

Write-Host ""
Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
