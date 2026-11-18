@echo off
cd /d "%~dp0"

if not exist ".tools\Godot_v4.7.2-stable_win64.exe" (
    echo Godot 4.7.2 was not found in .tools\
    echo Download Godot 4.7.2 from the official release and extract it into .tools\
    echo See README.md and docs\launching.md. Do not bypass antivirus warnings.
    pause
    exit /b 1
)

start "Ashfall" ".tools\Godot_v4.7.2-stable_win64.exe" --path .
