<#
.SYNOPSIS
    把最新构建同步到桌面快捷方式指向的稳定安装目录，并修正快捷方式指向。

.DESCRIPTION
    发布的便携包是带版本号的目录，而桌面快捷方式只能指向一个固定路径。
    每次发版后运行本脚本，把 dist 里最新的“游戏性能优化中心_v*”目录覆盖到
    %LOCALAPPDATA%\Programs\游戏性能优化中心，用户数据（data、backups、
    diagnostics、gui-settings.json）保持不动，快捷方式始终打开新版本。

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-local.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install-local.ps1 -Source "dist\游戏性能优化中心_v6.1.1"
#>
[CmdletBinding()]
param(
    [string]$Source,
    [string]$Target = (Join-Path $env:LOCALAPPDATA 'Programs\游戏性能优化中心'),
    [string]$ShortcutName = '游戏性能优化中心'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

function Get-BuildVersion([string]$folder) {
    $exe = Join-Path $folder 'GamePerfCenter.exe'
    if (-not (Test-Path -LiteralPath $exe)) { return [version]'0.0' }
    $raw = (Get-Item -LiteralPath $exe).VersionInfo.FileVersion
    try { return [version]$raw } catch { return [version]'0.0' }
}

if (-not $Source) {
    $candidates = @(Get-ChildItem -LiteralPath (Join-Path $repo 'dist') -Directory -Filter '游戏性能优化中心_v*' -ErrorAction SilentlyContinue)
    if ($candidates.Count -eq 0) { throw 'dist 下没有构建产物，请先执行 dotnet publish。' }
    $Source = ($candidates | Sort-Object { Get-BuildVersion $_.FullName } -Descending | Select-Object -First 1).FullName
}
$Source = (Resolve-Path -LiteralPath $Source).Path

$sourceExe = Join-Path $Source 'GamePerfCenter.exe'
if (-not (Test-Path -LiteralPath $sourceExe)) { throw "源目录缺少 GamePerfCenter.exe：$Source" }
$version = Get-BuildVersion $Source

$running = @(Get-Process -Name GamePerfCenter -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    throw "游戏性能优化中心正在运行（PID $($running.Id -join ', ')），请先关闭再执行安装。"
}

if (-not (Test-Path -LiteralPath $Target)) {
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
}

# 只覆盖程序文件，保留用户数据。
$excludeDirs = @(
    (Join-Path $Source 'data'), (Join-Path $Target 'data'),
    (Join-Path $Source 'backups'), (Join-Path $Target 'backups'),
    (Join-Path $Source 'diagnostics'), (Join-Path $Target 'diagnostics')
)
$excludeFiles = @(
    (Join-Path $Source 'gui-settings.json'),
    (Join-Path $Target 'gui-settings.json')
)

$arguments = @($Source, $Target, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/R:1', '/W:1',
    '/XD') + $excludeDirs + @('/XF') + $excludeFiles
& robocopy @arguments | Out-Null
$code = $LASTEXITCODE
if ($code -ge 8) { throw "robocopy 失败，退出码 $code。" }

$installedVersion = Get-BuildVersion $Target
if ($installedVersion -ne $version) {
    throw "安装目录版本不一致：期望 $version，实际 $installedVersion。"
}

# 快捷方式可能指向旧目录或已失效，这里统一修正为稳定安装目录。
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop ($ShortcutName + '.lnk')
$shell = New-Object -ComObject WScript.Shell
$shortcut = if (Test-Path -LiteralPath $lnkPath) { $shell.CreateShortcut($lnkPath) } else { $shell.CreateShortcut($lnkPath) }
$shortcut.TargetPath = Join-Path $Target 'GamePerfCenter.exe'
$shortcut.WorkingDirectory = $Target
$shortcut.IconLocation = (Join-Path $Target 'Assets\AppIcon.ico') + ',0'
$shortcut.Description = '游戏性能优化中心'
$shortcut.Save()

Write-Output "已安装 $version -> $Target"
Write-Output "快捷方式：$lnkPath -> $($shortcut.TargetPath)"
Write-Output '用户数据 data / backups / diagnostics / gui-settings.json 未改动。'
