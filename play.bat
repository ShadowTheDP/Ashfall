@echo off
cd /d "%~dp0"

if not exist ".tools\Godot_v4.7.2-stable_win64.exe" (
    echo Godot 4.7.2 was not found in .tools\
    echo Run this once first:
    echo   powershell -ExecutionPolicy Bypass -File tools\fetch_godot.ps1
    pause
    exit /b 1
)

start "Ashfall" ".tools\Godot_v4.7.2-stable_win64.exe" --path .
