@echo off
REM Wrapper that runs the PowerShell script with execution-policy bypass
REM so users can just double-click this file.

setlocal
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Bindings Toolkit [ENH][NXT][4.8.0][LIVE].ps1"

echo.
pause
