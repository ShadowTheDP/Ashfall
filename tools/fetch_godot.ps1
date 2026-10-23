param(
    [string]$Version = "4.7.2"
)

# Downloads the pinned Godot build used by this project into .tools/.
# Usage: powershell -ExecutionPolicy Bypass -File tools\fetch_godot.ps1

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root ".tools"
$console = Join-Path $tools "Godot_v$Version-stable_win64_console.exe"

if (Test-Path $console) {
    Write-Host "Already installed: $console" -ForegroundColor Green
    exit 0
}

New-Item -ItemType Directory -Force -Path $tools | Out-Null
$url = "https://github.com/godotengine/godot/releases/download/$Version-stable/Godot_v$Version-stable_win64.exe.zip"
$zip = Join-Path $tools "Godot_v$Version-stable_win64.exe.zip"

Write-Host "Downloading $url" -ForegroundColor Cyan
Invoke-WebRequest -Uri $url -OutFile $zip
Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $zip -DestinationPath $tools -Force
Remove-Item $zip

Write-Host "Installed: $console" -ForegroundColor Green
