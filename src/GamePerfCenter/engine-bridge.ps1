# 游戏性能优化中心 · WinUI 3 引擎桥
# 通过标准输入输出接收 JSON 命令，复用 游戏性能优化.ps1 的全部引擎逻辑。
# 该进程由 GUI 以隐藏窗口启动，不直接面向用户。

param(
    [string]$Sid
)

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { [Console]::InputEncoding = [System.Text.Encoding]::UTF8 } catch {}
try { $OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$script:DataDir = Join-Path $PSScriptRoot 'data'
$script:EngineLog = Join-Path $script:DataDir 'engine.log'

# 引擎镜像日志：即使 PowerShell 进程崩溃，界面上也还能看到最后执行到哪一步。
function Write-EngineLog {
    param(
        [string]$Level,
        [string]$Message
    )
    try {
        if (-not (Test-Path -LiteralPath $script:DataDir)) {
            New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null
        }
        if ((Test-Path -LiteralPath $script:EngineLog) -and
            (Get-Item -LiteralPath $script:EngineLog -ErrorAction SilentlyContinue).Length -gt 2MB) {
            Move-Item -LiteralPath $script:EngineLog -Destination ($script:EngineLog + '.1') -Force
        }
        $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level, $Message
        Add-Content -LiteralPath $script:EngineLog -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch {}
}

trap {
    try { Write-EngineLog 'FATAL' ($_ | Out-String) } catch {}
    try { [Console]::Error.WriteLine($_.Exception.Message) } catch {}
    exit 1
}

$script:LogBuf = New-Object System.Collections.ArrayList

# 接管引擎内的 Write-Host，避免污染 stdout 的 JSON 协议；同时落盘，崩溃后仍可追溯。
function Write-Host {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        $Object,
        [ConsoleColor]$ForegroundColor,
        [ConsoleColor]$BackgroundColor,
        [switch]$NoNewline,
        $Separator
    )
    process {
        if ($null -eq $Object) { return }
        $text = [string]$Object
        if ($text.Length -gt 0) {
            [void]$script:LogBuf.Add($text)
            Write-EngineLog 'INFO' $text
        }
    }
}


$engine = Join-Path $PSScriptRoot '游戏性能优化.ps1'
if (-not (Test-Path -LiteralPath $engine)) {
    Write-EngineLog 'FATAL' "引擎缺失: $engine"
    @{ id = 'boot'; ok = $false; error = "引擎缺失: $engine" } | ConvertTo-Json -Compress | Write-Output
    return
}

try {
    if (-not $Sid) {
        try {
            $Sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        } catch { $Sid = '' }
    }
    Write-EngineLog 'BOOT' "加载引擎 $engine (PID $PID, PS $($PSVersionTable.PSVersion))"
    $null = . $engine -EngineOnly -NoElevate -Sid $Sid
    if (-not (Get-Command Get-TxSnapshot -ErrorAction SilentlyContinue)) {
        throw '引擎脚本已停止执行：核心函数未加载，可能被系统策略、安全软件或语法错误中断'
    }
    if (@($script:O).Count -eq 0) {
        throw '引擎初始化未完成：优化项目录为空，可能被系统策略或安全软件中断'
    }
    Write-EngineLog 'BOOT' "引擎加载完成"
} catch {
    Write-EngineLog 'FATAL' "引擎加载失败: $($_ | Out-String)"
    @{ id = 'boot'; ok = $false; error = "引擎加载失败: $($_.Exception.Message)" } | ConvertTo-Json -Compress | Write-Output
    return
}

# 引擎脚本内也有 trap，dot-source 会覆盖上面的同名处理；加载完成后重新挂回桥接层的兜底。
trap {
    try { Write-EngineLog 'FATAL' ($_ | Out-String) } catch {}
    try { [Console]::Error.WriteLine($_.Exception.Message) } catch {}
    exit 1
}

# 把 PowerShell 的 ErrorRecord 拆成界面能读懂的结构，写入 JSON 的 errorDetail。
function Get-ErrorDetail {
    param($ErrorRecord)
    $detail = [ordered]@{}
    try {
        $ex = $ErrorRecord.Exception
        if ($ex) {
            $detail.type = $ex.GetType().FullName
            if ($ex.InnerException) {
                $detail.inner = $ex.InnerException.GetType().FullName + ': ' + $ex.InnerException.Message
            }
        }
        if ($ErrorRecord.FullyQualifiedErrorId) { $detail.id = [string]$ErrorRecord.FullyQualifiedErrorId }
        if ($ErrorRecord.CategoryInfo -and $ErrorRecord.CategoryInfo.Category) {
            $detail.category = [string]$ErrorRecord.CategoryInfo.Category
        }
        $inv = $ErrorRecord.InvocationInfo
        if ($inv) {
            if ($inv.ScriptName) { $detail.script = [string]$inv.ScriptName }
            if ($inv.ScriptLineNumber) { $detail.line = [string]$inv.ScriptLineNumber }
            if ($null -ne $inv.OffsetInLine) { $detail.position = [string]$inv.OffsetInLine }
            if ($inv.Line) { $detail.code = ([string]$inv.Line).Trim() }
        }
        if ($ErrorRecord.ScriptStackTrace) { $detail.stack = [string]$ErrorRecord.ScriptStackTrace }
    } catch {}
    return $detail
}

function Send-Response {
    param(
        [string]$Id,
        [bool]$Ok,
        $Data = $null,
        [string]$ErrorText = '',
        $Logs = $null,
        $Detail = $null
    )
    $obj = [ordered]@{ id = $Id; ok = $Ok }
    if ($Ok) {
        $obj.data = @($Data)
        if ($Data -is [System.Collections.IDictionary] -or $Data -is [PSCustomObject]) {
            $obj.data = $Data
        }
    } else {
        $obj.error = $ErrorText
        if ($Detail -and @($Detail.Keys).Count -gt 0) { $obj.errorDetail = $Detail }
    }
    if ($Logs -and @($Logs).Count -gt 0) { $obj.logs = @($Logs) }
    $json = $obj | ConvertTo-Json -Depth 14 -Compress
    [Console]::Out.WriteLine($json)
    [Console]::Out.Flush()
}

function ArgVal($Obj, [string]$Name, $Default = $null) {
    if ($null -eq $Obj) { return $Default }
    try {
        $p = $Obj.PSObject.Properties[$Name]
        if ($p) { return $p.Value }
    } catch {}
    return $Default
}

while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    $line = $line.Trim().TrimStart([char]0xFEFF)
    if (-not $line) { continue }

    $script:LogBuf.Clear()
    $id = ''
    $cmd = ''
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $req = $line | ConvertFrom-Json
        $id = [string](ArgVal $req 'id' '')
        $cmd = [string](ArgVal $req 'cmd' '')
        $a = ArgVal $req 'args' $null
        Write-EngineLog 'CMD' "$cmd (id $id)"

        switch ($cmd) {
            'ping' {
                Send-Response $id $true ([ordered]@{ pong = $true; pid = $PID; version = $script:AppVersion; engine = $PSVersionTable.PSVersion.ToString() }) '' $script:LogBuf
            }
            'snapshot' {
                $provisional = [bool](ArgVal $a 'provisional' $false)
                $snap = Get-TxSnapshot -Provisional:$provisional
                Send-Response $id $true $snap '' $script:LogBuf
            }
            'apply' {
                $ids = @(ArgVal $a 'ids' @())
                $sel = @($O | Where-Object { $ids -contains [string]$_.Id })
                if ($sel.Count -eq 0) { throw '没有选中有效的优化项' }
                $dry = [bool](ArgVal $a 'dryRun' $false)
                $rp = [bool](ArgVal $a 'restorePoint' $false)
                $r = Invoke-TxApply -Items $sel -DryRun:$dry -Yes -RestorePoint:$rp
                $data = [ordered]@{
                    Ok = [int]$r.Ok; Fail = [int]$r.Fail
                    Preview = @($r.Preview); Errors = @($r.Errors)
                    Backup = $r.Backup; RegDir = $r.RegDir
                    RestorePoint = $r.RestorePoint; DryRun = [bool]$r.DryRun
                }
                Send-Response $id $true $data '' $script:LogBuf
            }
            'restore' {
                $path = [string](ArgVal $a 'path' '')
                if (-not $path) {
                    $fs = @(Get-ChildItem $BK -Filter 'backup_*.json' -ErrorAction SilentlyContinue |
                        Sort-Object LastWriteTime -Descending)
                    if ($fs.Count -eq 0) { throw '没有可用备份' }
                    $path = $fs[0].FullName
                }
                $r = Restore-TxBackupFile -Path $path
                try { Clear-TxPendingRebootCache } catch {}
                Send-Response $id $true $r '' $script:LogBuf
            }
            'restore_all' {
                $r = Restore-TxAll
                Send-Response $id $true $r '' $script:LogBuf
            }
            'restore_point' {
                $r = New-TxRestorePoint
                Send-Response $id $true $r '' $script:LogBuf
            }
            'backups' {
                $files = @(Get-ChildItem $BK -Filter 'backup_*.json' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending)
                $list = @()
                foreach ($f in $files) {
                    $time = $f.LastWriteTime.ToString('s')
                    $count = 0
                    try {
                        $j = Get-Content -Raw -LiteralPath $f.FullName | ConvertFrom-Json
                        if ($j.Time) { $time = [string]$j.Time }
                        $count = @($j.Records).Count
                    } catch {}
                    $list += [PSCustomObject]@{
                        Name = $f.Name; Path = $f.FullName; Time = $time
                        Size = [long]$f.Length; Records = [int]$count
                    }
                }
                Send-Response $id $true @($list) '' $script:LogBuf
            }
            'profiles' {
                Send-Response $id $true @(Get-TxProfiles) '' $script:LogBuf
            }
            'save_profile' {
                $name = [string](ArgVal $a 'name' '')
                $ids = @(ArgVal $a 'ids' @())
                $r = Save-TxProfile -Name $name -Ids $ids
                Send-Response $id $true ([string]$r) '' $script:LogBuf
            }
            'diagnostics' {
                $d = Get-TxDiagnostics
                Send-Response $id $true @($d) '' $script:LogBuf
            }
            'report' {
                $p = [string](ArgVal $a 'path' '')
                $f = Export-TxReport -Path $p
                Send-Response $id $true ([string]$f) '' $script:LogBuf
            }
            'bundle' {
                $p = [string](ArgVal $a 'path' '')
                $f = Export-TxDiagnosticBundle -OutDir $p
                Send-Response $id $true ([string]$f) '' $script:LogBuf
            }
            'games' {
                $force = [bool](ArgVal $a 'force' $false)
                $g = Get-TxGames -Force:$force
                Send-Response $id $true @($g) '' $script:LogBuf
            }
            'game_save' {
                $exe = [string](ArgVal $a 'exe' '')
                $profile = ArgVal $a 'profile' $null
                $r = Save-TxGameProfile -exe $exe -profile $profile
                Send-Response $id $true $r '' $script:LogBuf
            }
            'game_apply' {
                $exe = [string](ArgVal $a 'exe' '')
                $profile = ArgVal $a 'profile' $null
                $r = Apply-TxGameProfile -exe $exe -profile $profile
                Send-Response $id $true $r '' $script:LogBuf
            }
            'game_remove' {
                $exe = [string](ArgVal $a 'exe' '')
                $r = Remove-TxGameProfile -exe $exe
                Send-Response $id $true $r '' $script:LogBuf
            }
            'game_start' {
                $exe = [string](ArgVal $a 'exe' '')
                $profile = ArgVal $a 'profile' $null
                $r = Start-TxGame -exe $exe -profile $profile
                Send-Response $id $true $r '' $script:LogBuf
            }
            'game_add' {
                $name = [string](ArgVal $a 'name' '')
                $exe = [string](ArgVal $a 'exe' '')
                $r = Add-TxManualGame -Name $name -Exe $exe
                Send-Response $id $true ([string]$r) '' $script:LogBuf
            }
            'game_delete' {
                $exe = [string](ArgVal $a 'exe' '')
                $r = Remove-TxManualGame -Exe $exe
                Send-Response $id $true ([ordered]@{ Ok = $true; Result = [string]$r }) '' $script:LogBuf
            }
            'startup' {
                Send-Response $id $true @(Get-TxStartupEntries) '' $script:LogBuf
            }
            'background' {
                $top = 14
                try { $top = [int](ArgVal $a 'top' 14) } catch {}
                Send-Response $id $true @(Get-TxBackgroundProcesses -Top $top) '' $script:LogBuf
            }
            'driver_history' {
                $h = Read-TxDriverHistory
                $data = [ordered]@{ Devices = $h.Devices; LastChanges = @($h.LastChanges) }
                Send-Response $id $true $data '' $script:LogBuf
            }
            'driver_update_history' {
                $devices = @(ArgVal $a 'devices' @())
                $r = Update-TxDriverHistory -Devices $devices -NoSave:([bool](ArgVal $a 'noSave' $false))
                Send-Response $id $true $r '' $script:LogBuf
            }
            'bye' {
                Write-EngineLog 'EXIT' '收到 bye，桥接进程退出'
                $obj = [ordered]@{ id = $id; ok = $true; data = [ordered]@{ bye = $true } }
                [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress))
                [Console]::Out.Flush()
                return
            }
            default {
                throw "未知命令: $cmd"
            }
        }
        Write-EngineLog 'OK' "$cmd 完成，用时 $($sw.ElapsedMilliseconds) ms"
    } catch {
        $detail = Get-ErrorDetail $_
        Write-EngineLog 'ERROR' "$cmd 失败: $($_ | Out-String)"
        try {
            Send-Response $id $false $null $_.Exception.Message $script:LogBuf $detail
        } catch {
            try {
                [Console]::Out.WriteLine((@{ id = $id; ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress))
                [Console]::Out.Flush()
            } catch {}
        }
    } finally {
        $sw.Stop()
    }
}

Write-EngineLog 'EXIT' 'stdin 已关闭，桥接进程退出'

