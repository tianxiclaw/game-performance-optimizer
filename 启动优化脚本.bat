@echo off
setlocal
cd /d "%~dp0"

REM ============================================================
REM  Game Performance Optimizer - GUI Launcher
REM  Double-click to start. The GUI will request admin rights.
REM  First run re-enters hidden, so no console window lingers
REM  while the UAC prompt is waiting.
REM ============================================================

if /i "%~1"=="__hidden" goto run

powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "try { Start-Process -FilePath '%~f0' -ArgumentList '__hidden' -WindowStyle Hidden -ErrorAction Stop } catch { Start-Process -FilePath '%~f0' -ArgumentList '__hidden' }" >nul 2>nul
if not errorlevel 1 exit /b 0

:run
REM 优先启动 WinUI 3 主程序；仅当主程序不存在时，才回退到旧版 WinForms 界面。
if exist "%~dp0GamePerfCenter.exe" (
    start "" "%~dp0GamePerfCenter.exe"
    exit /b 0
)

set "GUIPATH="
for %%f in ("%~dp0*-GUI.ps1") do set "GUIPATH=%%~ff"
if not defined GUIPATH (
    powershell.exe -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('GUI script not found. Please extract the whole zip first.','Game Performance Optimizer','OK','Error')" >nul 2>nul
    exit /b 1
)

REM Remove the "downloaded from internet" mark so scripts from QQ/zip run normally
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0' -Filter *.ps1 -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue" >nul 2>nul

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%GUIPATH%"
if errorlevel 1 (
    powershell.exe -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('Failed to start. Right-click this file and choose Run as administrator.','Game Performance Optimizer','OK','Error')" >nul 2>nul
)
exit /b 0
