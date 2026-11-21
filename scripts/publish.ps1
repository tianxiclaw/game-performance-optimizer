<#
.SYNOPSIS
    构建发布产物：WinUI 3 便携目录 / zip，以及单文件 CLI。

.DESCRIPTION
    - 构建中间产物统一放在 dist\.build，不再散落在 dist 根目录
    - 最终发布件固定输出到「发布\游戏性能优化中心」，与程序目录放在一起
    - 每次同时生成带版本号的 zip 和固定名称的「游戏性能优化中心_便携版_最新.zip」
    - 只发布 WinUI 3 主程序；旧版 WinForms 入口已归档，不再随包分发
    - CLI 以单文件方式发布，附带引擎脚本
    - 生成 SHA256.txt；可选调用 signtool 对主程序签名

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\publish.ps1

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\publish.ps1 -Runtime win-arm64

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\publish.ps1 -OutputDir D:\发布

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts\publish.ps1 -Sign `
        -PfxPath C:\keys\codesign.pfx -PfxPassword ******
#>
[CmdletBinding()]
param(
    [string]$Version,
    [ValidateSet('win-x64', 'win-arm64')]
    [string]$Runtime = 'win-x64',
    [string]$OutputDir,
    [string]$Dotnet,
    [switch]$SkipWinUI,
    [switch]$SkipCli,
    [switch]$SkipTests,
    [switch]$NoZip,
    [switch]$Force,
    [switch]$Sign,
    [string]$PfxPath,
    [string]$PfxPassword,
    [string]$CertificateThumbprint,
    [string]$TimestampUrl = 'http://timestamp.digicert.com',
    [switch]$SignAll
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $repo 'dist'
$build = Join-Path $dist '.build'
if (-not $OutputDir) { $OutputDir = Join-Path $repo '发布\游戏性能优化中心' }
if (-not [IO.Path]::IsPathRooted($OutputDir)) { $OutputDir = Join-Path $repo $OutputDir }
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
$proj = Join-Path $repo 'src\GamePerfCenter\GamePerfCenter.csproj'
$cliProj = Join-Path $repo 'src\GamePerfCenter.Cli\GamePerfCenter.Cli.csproj'

function Write-Step([string]$Text) { Write-Host "==> $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "    $Text" -ForegroundColor Green }

function Resolve-SignTool {
    $command = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kits) {
        $candidate = Get-ChildItem -LiteralPath $kits -Directory |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName 'x64\signtool.exe' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($candidate) { return $candidate }
    }
    throw '找不到 signtool.exe，请安装 Windows SDK 或把 signtool 加入 PATH。'
}

function Invoke-SignTool([string]$SignTool, [string]$File) {
    $arguments = @('sign', '/fd', 'SHA256', '/td', 'SHA256', '/tr', $TimestampUrl)
    if ($PfxPath) {
        $arguments += @('/f', $PfxPath)
        if ($PfxPassword) { $arguments += @('/p', $PfxPassword) }
    } elseif ($CertificateThumbprint) {
        $arguments += @('/sha1', $CertificateThumbprint)
    }
    $arguments += $File
    & $SignTool @arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "签名失败：$File" }
    Write-Ok "已签名 $(Split-Path -Leaf $File)"
}

# Windows PowerShell 5.1 在没有 BOM 时按系统 ANSI 代码页读取 .ps1。
# 中文脚本被存成无 BOM UTF-8 后，在中文/英文系统上会解码成乱码，引擎文件名随之失效。
function Ensure-Utf8Bom([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return $false
    }
    $merged = [byte[]]::new($bytes.Length + 3)
    $merged[0] = 0xEF
    $merged[1] = 0xBB
    $merged[2] = 0xBF
    [Array]::Copy($bytes, 0, $merged, 3, $bytes.Length)
    [IO.File]::WriteAllBytes($Path, $merged)
    return $true
}

# 版本号唯一来源：Directory.Build.props。csproj、CLI、引擎脚本、安装包都从这里取值。
$versionProps = Join-Path $repo 'Directory.Build.props'
if (-not $Version) {
    if (-not (Test-Path -LiteralPath $versionProps)) { throw "缺少版本源文件：$versionProps" }
    [xml]$xml = [IO.File]::ReadAllText($versionProps, [Text.Encoding]::UTF8)
    $Version = [string]$xml.Project.PropertyGroup.AppVersion
}
if (-not $Version) { throw '无法从 Directory.Build.props 读取 AppVersion，请用 -Version 指定。' }

# 引擎脚本里的版本号是脚本自身可见的展示值，构建时统一改写，避免与程序集版本漂移。
function Set-StagedAppVersion([string]$Root) {
    $count = 0
    foreach ($file in (Get-ChildItem -LiteralPath $Root -Filter '*.ps1' -File -Recurse)) {
        $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        $updated = [regex]::Replace($text, "(?m)^(\`$script:AppVersion\s*=\s*)'[^']*'", "`${1}'$Version'")
        if ($updated -ne $text) {
            [IO.File]::WriteAllText($file.FullName, $updated, (New-Object Text.UTF8Encoding($false)))
            $count++
        }
    }
    return $count
}

# Inno Setup 脚本不在构建链里，但同样不能带着旧版本号。构建时顺手对齐。
function Set-IssVersion([string]$Root) {
    $count = 0
    foreach ($file in (Get-ChildItem -LiteralPath $Root -Filter '*.iss' -File -Recurse -ErrorAction SilentlyContinue)) {
        $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        $updated = [regex]::Replace($text, '(?m)^(#define\s+MyAppVersion\s+)"[^"]*"', "`${1}`"$Version`"")
        if ($updated -ne $text) {
            [IO.File]::WriteAllText($file.FullName, $updated, (New-Object Text.UTF8Encoding($true)))
            $count++
        }
    }
    return $count
}

$issFixed = Set-IssVersion (Join-Path $repo '安装包')
if ($issFixed -gt 0) { Write-Host "    已同步 $issFixed 个 Inno Setup 脚本版本号" -ForegroundColor DarkGray }

if ($Runtime -eq 'win-arm64' -and $SignAll) { Write-Host '    ARM64 产物同样可以签名。' -ForegroundColor DarkGray }

if (-not $Dotnet) {
    $candidate = Join-Path $env:USERPROFILE '.dotnet\dotnet.exe'
    $Dotnet = if (Test-Path -LiteralPath $candidate) { $candidate } else { 'dotnet' }
}
if (-not (Get-Command $Dotnet -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $Dotnet)) {
    throw "找不到 dotnet：$Dotnet"
}

if (-not $SkipTests) {
    Write-Step '运行功能测试'
    $testProj = Join-Path $repo 'src\GamePerfCenter.Tests\GamePerfCenter.Tests.csproj'
    & $Dotnet run --project $testProj -c Release -v:minimal
    if ($LASTEXITCODE -ne 0) { throw "功能测试失败，退出码 $LASTEXITCODE。已停止发布。" }
    Write-Ok '测试全部通过'
}

# 先检查再构建：不要花几分钟编译完才发现主程序正开着、无法同步安装目录。
if (-not $SkipWinUI) {
    $running = @(Get-Process -Name GamePerfCenter -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        throw ("游戏性能优化中心正在运行（PID $($running.Id -join ', ')）。" +
               "如果主窗口已关闭，它可能还停留在托盘：右键托盘图标选择「退出」，再重新发布。")
    }
}

$runtimeSuffix = if ($Runtime -eq 'win-x64') { '' } else { '_arm64' }
$stage = Join-Path $build ("游戏性能优化中心_v$Version$runtimeSuffix")
$publishDir = Join-Path $build $Runtime
$zip = Join-Path $OutputDir ("游戏性能优化中心_v$Version${runtimeSuffix}_便携版.zip")
$latestZip = Join-Path $OutputDir '游戏性能优化中心_便携版_最新.zip'

New-Item -ItemType Directory -Path $build -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

if (-not $SkipWinUI) {
    if ((Test-Path -LiteralPath $stage) -and -not $Force) {
        throw "目录已存在：$stage。确认要覆盖时加 -Force。"
    }
    if ($Sign -and -not $PfxPath -and -not $CertificateThumbprint) {
        throw '启用 -Sign 时必须提供 -PfxPath（可选 -PfxPassword）或 -CertificateThumbprint。'
    }

    Write-Step "发布 WinUI 3 $Version ($Runtime)"
    $platform = if ($Runtime -eq 'win-arm64') { 'ARM64' } else { 'x64' }
    & $Dotnet publish $proj -c Release -p:Platform=$platform -r $Runtime --self-contained true `
        -p:AppVersion=$Version `
        -p:PublishReadyToRun=false -p:DebugType=None -p:DebugSymbols=false `
        -o $publishDir -v:minimal
    if ($LASTEXITCODE -ne 0) { throw "WinUI 发布失败，退出码 $LASTEXITCODE。" }

    # 程序集版本必须与构建版本一致，否则界面、包名、引擎脚本会再次漂移。
    $exePath = Join-Path $publishDir 'GamePerfCenter.exe'
    if (Test-Path -LiteralPath $exePath) {
        $fileVersion = [Diagnostics.FileVersionInfo]::GetVersionInfo($exePath).FileVersion
        $expected = "$Version.0"
        if ($fileVersion -ne $expected) {
            throw "发布产物版本不一致：程序集 $fileVersion，期望 $expected。"
        }
    }
    Write-Ok "已发布到 $publishDir"

    if ($Sign) {
        Write-Step '签名主程序'
        $signTool = Resolve-SignTool
        if ($SignAll) {
            Get-ChildItem -LiteralPath $publishDir -File -Recurse -Include *.exe, *.dll |
                ForEach-Object { Invoke-SignTool $signTool $_.FullName }
        } else {
            $exe = Join-Path $publishDir 'GamePerfCenter.exe'
            if (Test-Path -LiteralPath $exe) { Invoke-SignTool $signTool $exe }
        }
        Write-Ok "使用 $signTool"
    } else {
        Write-Host '    未签名（未提供代码签名证书）。SmartScreen 可能仍会提示。' -ForegroundColor Yellow
    }

    Write-Step '整理便携目录'
    if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Copy-Item -Path (Join-Path $publishDir '*') -Destination $stage -Recurse -Force
    Get-ChildItem -LiteralPath $stage -Filter *.pdb -Recurse -File | Remove-Item -Force

    Copy-Item -LiteralPath (Join-Path $repo 'README.md') -Destination $stage -Force
    Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination $stage -Force

    Write-Step '统一引擎脚本版本号'
    $patched = Set-StagedAppVersion $stage
    Write-Ok "已改写 $patched 个脚本的 `$script:AppVersion = '$Version'"

    Write-Step '检查脚本编码'
    $fixed = 0
    foreach ($script in (Get-ChildItem -LiteralPath $stage -Filter '*.ps1' -File -Recurse)) {
        if (Ensure-Utf8Bom $script.FullName) { $fixed++ }
    }
    Write-Ok "脚本均为 UTF-8 BOM（本次修正 $fixed 个）"

    Write-Step '生成 SHA256.txt'
    $root = (Get-Item -LiteralPath $stage).FullName
    $lines = foreach ($file in (Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($root.Length + 1)
        '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash, $relative
    }
    [IO.File]::WriteAllLines((Join-Path $stage 'SHA256.txt'), $lines, (New-Object Text.UTF8Encoding($false)))
    Write-Ok "已写入 $stage\SHA256.txt"

    if (-not $NoZip) {
        if ((Test-Path -LiteralPath $zip) -and -not $Force) {
            throw "zip 已存在：$zip。确认要覆盖时加 -Force。"
        }
        Write-Step '打包便携版 zip'
        Compress-Archive -Path $stage -DestinationPath $zip -CompressionLevel Optimal -Force
        Copy-Item -LiteralPath $zip -Destination $latestZip -Force
        Write-Ok "$zip ($([math]::Round((Get-Item -LiteralPath $zip).Length / 1MB, 1)) MB)"
        Write-Ok "最新：$latestZip"
    }

    # 桌面快捷方式指向稳定安装目录，复用安装脚本同步程序文件并修正快捷方式。
    Write-Step '同步本地程序目录'
    & (Join-Path $PSScriptRoot 'install-local.ps1') -Source $stage | ForEach-Object { Write-Ok $_ }
}

if (-not $SkipCli) {
    $cliDir = Join-Path $build ("cli\$Runtime")
    $cliZip = Join-Path $OutputDir ("游戏性能优化中心_CLI_v$Version`_$Runtime.zip")
    if ((Test-Path -LiteralPath $cliDir) -and -not $Force) {
        throw "CLI 目录已存在：$cliDir。确认要覆盖时加 -Force。"
    }

    Write-Step "发布单文件 CLI $Version ($Runtime)"
    & $Dotnet publish $cliProj -c Release -r $Runtime --self-contained true `
        -p:AppVersion=$Version `
        -p:PublishSingleFile=true -p:EnableCompressionInSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None -p:DebugSymbols=false `
        -o $cliDir -v:minimal
    if ($LASTEXITCODE -ne 0) { throw "CLI 发布失败，退出码 $LASTEXITCODE。" }

    if ($Sign) {
        $gpc = Join-Path $cliDir 'gpc.exe'
        if (Test-Path -LiteralPath $gpc) { Invoke-SignTool (Resolve-SignTool) $gpc }
    }

    if (-not $NoZip) {
        if ((Test-Path -LiteralPath $cliZip) -and -not $Force) {
            throw "zip 已存在：$cliZip。确认要覆盖时加 -Force。"
        }
        Compress-Archive -Path (Join-Path $cliDir '*') -DestinationPath $cliZip -CompressionLevel Optimal -Force
        Write-Ok "$cliZip"
    } else {
        Write-Ok $cliDir
    }
}

Write-Step '完成'
Write-Host "版本：$Version"
if (-not $SkipWinUI) { Write-Host "便携目录：$stage" }
Write-Host "发布目录：$OutputDir"
if (-not $NoZip -and -not $SkipWinUI) { Write-Host "固定入口：$latestZip" }
