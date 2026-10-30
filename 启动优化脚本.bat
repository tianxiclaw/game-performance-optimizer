@echo off
setlocal
cd /d "%~dp0"

REM ============================================================
REM  Game Performance Optimizer - GUI Launcher
REM  Double-click to start. The GUI will request admin rights.
REM ============================================================

set "GUIPATH="
for %%f in ("%~dp0*-GUI.ps1") do set "GUIPATH=%%~ff"
if not defined GUIPATH (
    echo [ERROR] GUI script not found in this folder.
    pause
    exit /b 1
)

REM Remove the "downloaded from internet" mark so scripts from QQ/zip run normally
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Filter *.ps1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>nul

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%GUIPATH%"
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to start. Please run this file as administrator.
    pause
)
exit /b 0
