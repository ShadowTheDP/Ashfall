param(
    [string]$Godot = "",
    # Only run steps whose name matches this substring (case-insensitive).
    # Example: -Only audit, -Only probe, -Only run_tests
    [string]$Only = "",
    # Skip the slow seed sweeps and the full end-to-end run. For the inner
    # loop; never for a commit.
    [switch]$Fast,
    # Run scenes at fixed 120 fps so they do not wait in real time (~3x).
    # SMOKE ONLY, never a commit gate: it changes how many physics frames a
    # test sees per wall-clock second. Measured false failures: audit_v2
    # ("two grunts shared one silhouette") because the separation push needs
    # real frames to resolve. A false PASS would be worse, so treat this as a
    # quick "did I break the parse" check only.
    [switch]$Turbo,
    # Print a per-step timing table at the end (always printed anyway).
    [switch]$Timing
)

# Runs every headless check for Ashfall.
# Usage:
#   powershell -ExecutionPolicy Bypass -File tools\check.ps1
#   powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Fast
#   powershell -ExecutionPolicy Bypass -File tools\check.ps1 -Only audit
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
if ($Fast) { Write-Host "Fast mode: slow sweeps skipped" -ForegroundColor Yellow }
if ($Turbo) { Write-Host "Turbo: fixed-fps 120, SMOKE ONLY - it can report false failures (audit_v2). Commit on a plain run." -ForegroundColor Yellow }
if ($Only) { Write-Host "Filter: $Only" -ForegroundColor Yellow }

$script:totals = @()

function Get-Stamp {
    return [System.Diagnostics.Stopwatch]::StartNew()
}

function Add-Total {
    param([string]$Name, [System.Diagnostics.Stopwatch]$Watch)
    $Watch.Stop()
    $script:totals += [pscustomobject]@{ Step = $Name; Seconds = [math]::Round($Watch.Elapsed.TotalSeconds, 1) }
}

function Test-Step {
    param([string]$Name, [switch]$Slow)
    if ($Only -and ($Name -notmatch $Only)) { return $false }
    if ($Slow -and $Fast) { return $false }
    return $true
}

function Invoke-Step {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [switch]$Slow
    )
    if (-not (Test-Step -Name $Name -Slow:$Slow)) { return }
    Write-Host ""
    Write-Host "== $Name ==" -ForegroundColor Cyan
    $watch = Get-Stamp
    & $Godot @Arguments
    $code = $LASTEXITCODE
    Add-Total -Name $Name -Watch $watch
    if ($code -ne 0) {
        Show-Timing
        Write-Host "FAILED: $Name (exit $code)" -ForegroundColor Red
        exit $code
    }
}

# --- scene probes (scene-based: they need autoloads) ------------------------
function Invoke-Probe {
    param([string]$Name, [string]$Scene, [switch]$Slow)
    if (-not (Test-Step -Name $Name -Slow:$Slow)) { return }
    Write-Host ""
    Write-Host "== $Name ==" -ForegroundColor Cyan
    $watch = Get-Stamp
    # Godot writes warnings to stderr; with $ErrorActionPreference = "Stop"
    # PowerShell turns those into terminating errors. Relax it for the call.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    # --fixed-fps runs frames as fast as the machine allows instead of in real
    # time. soak.tscn: 39 s -> 12.6 s with an identical PASS.
    $turboArgs = @()
    if ($Turbo) { $turboArgs = @("--fixed-fps", "120") }
    $out = & $Godot --headless @turboArgs --path $root $Scene 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous
    Add-Total -Name $Name -Watch $watch
    $out | Write-Output
    if ($out -match "FAILED|FAIL:") {
        Show-Timing
        Write-Host "FAILED: $Name" -ForegroundColor Red
        exit 1
    }
    if ($code -ne 0) {
        Show-Timing
        Write-Host "FAILED: $Name (exit $code)" -ForegroundColor Red
        exit $code
    }
}

function Show-Timing {
    if ($script:totals.Count -eq 0) { return }
    Write-Host ""
    Write-Host "== Timing ==" -ForegroundColor DarkGray
    $sum = 0.0
    foreach ($row in ($script:totals | Sort-Object Seconds -Descending)) {
        Write-Host ("  {0,6:N1}s  {1}" -f $row.Seconds, $row.Step) -ForegroundColor DarkGray
        $sum += $row.Seconds
    }
    Write-Host ("  {0,6:N1}s  total" -f $sum) -ForegroundColor DarkGray
}

# Import must run first: every scene below assumes the cache is warm. It is
# also the single most expensive step, so -Only skips it.
if (-not $Only) {
    Invoke-Step -Name "Import assets / compile scripts" -Arguments @(
        "--headless", "--path", $root, "--import"
    )
}

Invoke-Step -Name "Data + damage formula tests" -Arguments @(
    "--headless", "--path", $root, "--script", "res://tests/run_tests.gd"
)

Invoke-Probe -Name "Combat probe (hit, damage, death, i-frames)" -Scene "tests/combat_probe.tscn"
Invoke-Probe -Name "Reward probe (keyboard boon picker)" -Scene "tests/reward_probe.tscn"
Invoke-Probe -Name "Soak (all enemies, waves, victory)" -Scene "tests/soak.tscn"
Invoke-Probe -Name "Hub panels (open/close/buy)" -Scene "tests/esc_probe.tscn"
Invoke-Probe -Name "Hub -> floor handoff" -Scene "tests/floor_probe.tscn"
Invoke-Probe -Name "Restart in a floor (R)" -Scene "tests/restart_probe.tscn"
Invoke-Probe -Name "Generator macro shape" -Scene "tests/gen_stats.tscn"

# The seed sweeps and the end-to-end run are the slow half of this script.
Invoke-Probe -Name "Full run (5 floors -> victory)" -Scene "tests/run_probe.tscn" -Slow
Invoke-Probe -Name "Audit: combat / weapons" -Scene "tests/audit_a1.tscn" -Slow
Invoke-Probe -Name "Audit: save / economy" -Scene "tests/audit_a2.tscn"
Invoke-Probe -Name "Audit: floors / spawns" -Scene "tests/audit_a3.tscn" -Slow
Invoke-Probe -Name "Audit: UI / input" -Scene "tests/audit_a4.tscn"
Invoke-Probe -Name "Audit: vertical traversal" -Scene "tests/audit_v1.tscn" -Slow
Invoke-Probe -Name "Audit: enemies / encounters" -Scene "tests/audit_v2.tscn" -Slow
Invoke-Probe -Name "Audit: run flow / progression" -Scene "tests/audit_v3.tscn" -Slow

Show-Timing
Write-Host ""
Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
