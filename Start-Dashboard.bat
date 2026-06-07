@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Dashboard\Start-Dashboard.ps1"

if errorlevel 1 (
    echo.
    echo Dashboard non avviata. Controllare gli errori sopra.
    pause
    exit /b %errorlevel%
)

