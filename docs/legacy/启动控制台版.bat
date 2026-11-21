@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

REM ============================================================
REM  Game Performance Optimizer - Console Launcher
REM  Preserves the classic text menu. Self-elevates to admin.
REM ============================================================

set "MAINPATH="
for %%f in ("%~dp0*.ps1") do (
    set "N=%%~nf"
    if /i not "!N:~-4!"=="-GUI" set "MAINPATH=%%~ff"
)
if not defined MAINPATH (
    echo [ERROR] Main PowerShell script not found.
    pause
    exit /b 1
)

REM Remove the "downloaded from internet" mark so scripts from QQ/zip run normally
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Filter *.ps1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>nul

powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%MAINPATH%"
exit /b 0
