<#
.SYNOPSIS
    构建发布产物：WinUI 3 便携目录 / zip，以及单文件 CLI。

.DESCRIPTION
    - 构建中间产物统一放在 dist\.build，不再散落在 dist 根目录
    - 最终发布件固定输出到仓库根目录的「发布」文件夹
    - 每次同时生成带版本号的 zip 和固定名称的「游戏性能优化中心_便携版_最新.zip」
    - 备用 WinForms 入口一并放入“备用-WinForms”
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
if (-not $OutputDir) { $OutputDir = Join-Path $repo '发布' }
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

if (-not $Version) {
    [xml]$xml = [IO.File]::ReadAllText($proj, [Text.Encoding]::UTF8)
    $Version = [string]$xml.Project.PropertyGroup.Version
}
if (-not $Version) { throw '无法从 csproj 读取版本号，请用 -Version 指定。' }
if ($Runtime -eq 'win-arm64' -and $SignAll) { Write-Host '    ARM64 产物同样可以签名。' -ForegroundColor DarkGray }

if (-not $Dotnet) {
    $candidate = Join-Path $env:USERPROFILE '.dotnet\dotnet.exe'
    $Dotnet = if (Test-Path -LiteralPath $candidate) { $candidate } else { 'dotnet' }
}
if (-not (Get-Command $Dotnet -ErrorAction SilentlyContinue) -and -not (Test-Path -LiteralPath $Dotnet)) {
    throw "找不到 dotnet：$Dotnet"
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
        -p:PublishReadyToRun=false -p:DebugType=None -p:DebugSymbols=false `
        -o $publishDir -v:minimal
    if ($LASTEXITCODE -ne 0) { throw "WinUI 发布失败，退出码 $LASTEXITCODE。" }
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

    $fallback = Join-Path $stage '备用-WinForms'
    New-Item -ItemType Directory -Path $fallback -Force | Out-Null
    foreach ($name in @('游戏性能优化-GUI.ps1', '游戏性能优化.ps1', '启动优化脚本.bat',
                        '启动控制台版.bat', '赞赏码.png', '使用说明.txt')) {
        $source = Join-Path $repo $name
        if (-not (Test-Path -LiteralPath $source)) { throw "缺少文件：$name" }
        Copy-Item -LiteralPath $source -Destination $fallback -Force
    }
    Copy-Item -LiteralPath (Join-Path $repo 'README.md') -Destination $stage -Force
    Copy-Item -LiteralPath (Join-Path $repo 'LICENSE') -Destination $stage -Force

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
}

if (-not $SkipCli) {
    $cliDir = Join-Path $build ("cli\$Runtime")
    $cliZip = Join-Path $OutputDir ("游戏性能优化中心_CLI_v$Version`_$Runtime.zip")
    if ((Test-Path -LiteralPath $cliDir) -and -not $Force) {
        throw "CLI 目录已存在：$cliDir。确认要覆盖时加 -Force。"
    }

    Write-Step "发布单文件 CLI $Version ($Runtime)"
    & $Dotnet publish $cliProj -c Release -r $Runtime --self-contained true `
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
