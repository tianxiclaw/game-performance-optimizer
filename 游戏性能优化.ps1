<#
.SYNOPSIS  游戏性能优化脚本 v5.0 (硬件兼容版 + 可视化控制台)
.DESCRIPTION
    v5.0 可视化与工程化改造 (不减少原有功能):
      [新增] 1. 图形界面 游戏性能优化-GUI.ps1: 深色仪表盘, 硬件概览/实时监控/优化项/备份/诊断/日志
      [新增] 2. 命令行参数: -Status / -Report / -DryRun / -ApplyRecommended / -RestoreLatest / -RestoreAll / -Profile
      [新增] 3. 应用前双重备份: JSON 原值备份 + 按注册表键导出的 .reg 快照
      [新增] 4. 待重启追踪与重启后复核; 需要重启的项在界面与控制台中明确标注
      [新增] 5. 只读诊断 (VBS/HVCI/内存XMP/PCIe链路/NVMe健康/系统盘/电源/运行环境) 与报告导出
      [新增] 6. 预设方案 (推荐/全量/仅游戏录制后台) 与自定义方案保存
      [新增] 7. 网络进阶项按驱动实际能力生成 (EEE/中断节流/流控), 没有该属性的网卡不显示
      [新增] 8. 可选关闭 CPU 核心停车 (AC+DC), 默认不勾选
      [改进] 9. 应用/还原/预览逻辑收敛到引擎函数, 控制台、CLI、GUI 行为一致
      [修复]10. 网络进阶项误把 Wi-Fi IEEE11nMode 当作节能以太网 (EEE) 的问题
      [保留]11. v4.8 全部硬件兼容修复与控制台功能

    v4.8 兼容性改造 (不减少原有功能):
      [兼容] 1. 核显/独显改为三源判定 (名称特征 + 厂商 + 注册表显存), 不再只看厂商名
               覆盖 Intel Arc 1xxT/2xxV 核显、Intel Arc A/B 系列独显、AMD APU/独显、
               NVIDIA 独显、Qualcomm Adreno 核显、Microsoft 基本显示、虚拟显卡
      [修复] 2. 网卡 InterfaceGuid 自带大括号, 原代码再包一层 "{...}" 变成 "{{...}}"
               导致 PnPCapabilities 永远定位失败 (日志中的"无法定位网卡注册表子键")
      [修复] 3. 高位 DWORD (0x80000000/0xFFFFFFFF) 写入溢出: PSR bit31 与网络节流
               可能实际未写入, 上层却仍报"成功"; 改为 Int32 位转换 + 写失败真正抛错
      [修复] 4. UAC 提权后 HKCU 可能指向管理员账户: 所有 HKCU 项改为按启动者 SID 写入
      [修复] 5. HAGS 原来只对 Intel 开放; 现在 Intel/NVIDIA/AMD/Qualcomm 真实 GPU 均可
      [修复] 6. "笔记本强制独显"原来把 AMD APU 核显误判为独显; 现在只对真实独显出现
      [修复] 7. Intel 核显专属项不再出现在 Intel Arc 独显/AMD/高通机器上
      [修复] 8. 无 Wi-Fi 的台式机不再出现"无线适配器节能"项
      [修复] 9. 多电池笔记本/AC 状态未知时不再误判为"电池供电"
      [新增]10. AMD 显卡可选 ULPS 深度省电开关 (默认不勾选, 需重启)
      [兼容]11. 脚本带 UTF-8 BOM, 非 UTF-8 系统区域也能正确显示中文
      [兼容]12. 旧备份字段名/旧 Kind 仍可还原, 备份格式保持兼容
      [新增]13. 独显专属优化项: 禁止系统关闭独显(PnPCapabilities), NVIDIA 可选禁用动态P-State;
               纯核显机器不生成任何独显项, 仅在菜单/硬件报告用括号提示该能力存在

    v4.7 修复清单 (均为实测确认的真实缺陷, 非推测):
      [致命] 1. 菜单回车无法应用: APL 函数已定义但主循环从未调用 → 现在回车=应用
      [致命] 2. GPS 函数被内置别名 gps(=Get-Process) 遮蔽 → 改名 PWRST, 三源电源检测恢复工作
      [致命] 3. GSN 函数被内置别名 gsn(=Get-PSSession) 遮蔽 → 改名 SCHNM, 电源方案名恢复显示
      [致命] 4. 19 项优化无处理器: Kind=reg/drr/pnpclean 只在 $RC 登记却没在 $KH 注册
              → 应用时全部抛"未注册Kind", GameDVR/HAGS/网络节流/DRR 等实际从未生效 → 已补齐
      [致命] 5. DEVMODE 结构体 188 字节(应为 220): dmPositionX/Y 误声明为 short, 且缺尾部 6 个字段
              → EnumDisplaySettings 一律返回 0, 刷新率检测与应用全部失效 → 已修正并实测通过
      [致命] 6. 显示器设备名用了注册表 PSPath 而非 \\.\DISPLAY1 → API 必然失败 → 改用真实设备名
      [致命] 7. 旧备份字段名不兼容: 18 个历史备份用 Adapter/Keyword/SubKey/Path/Services,
              还原处理器读 A/K/SK/P/SV → 还原静默失效 → 已做双字段名兼容
      [重要] 8. intelftc 还原无效: idpst(bit4) 与 ipsr(bit31) 共写同一值, 各自记录整值
              → 还原时写回同一污染值, 两个位都清不掉 → 改为按位清除
      [重要] 9. ChassisTypes 是数组, "数组 -in 标量列表" 恒为 False → 改为求交集
      [重要]10. svcquota 机制无法达成其声称效果: DiagTrack 寄生于 svchost.exe -k utcsvc,
              降 svchost 优先级会牵连同组其它服务; 计划任务按进程名 "DiagTrack" 查找,
              而该进程名不存在; Services\<name>\Priority 不是 SCM 认可的配置项 → 已移除该项
      [重要]11. 伪造的显卡注册表项: LowLatencyTip / DisableCudaDumpPreemption / RadeonAntiLag
              均非真实驱动配置项, 且写在类键根而非实例子键 → 已移除(纯安慰剂)
      [次要]12. inteldps 用"删除值"冒充"设为0", 且把"未设置"报告成"已生效" → 改为显式写 0
      [次要]13. scheme 切换: duplicatescheme 会生成新 GUID, 却仍对原 GUID 执行 setactive → 已修正
      [次要]14. GPCI 用 [Convert]::ToInt32 解析 powercfg 十六进制, 遇 0xFFFFFFFF 会溢出 → 改用 UInt32
      [次要]15. ChangeDisplaySettingsEx 用 CDS_FULLSCREEN(0x04, 全屏独占语义) → 改 CDS_UPDATEREGISTRY(0x01)
      [次要]16. DISP_CHANGE 返回码含义写反(-2 是 BADMODE 不是"已是目标值", 1 是 RESTART 不该抛错)
      [次要]17. prefetch 只关 Superfetch 未关 Prefetcher, 与名称不符 → 两个值一起处理
      [次要]18. QPWR_SPS 多了不存在的 Reserved 字段; WSL 函数名与 wsl.exe 撞名 → 已清理
      [次要]19. 新增: dmwappushservice 残留 DelayedAutoStart=1 的可选清理项

    历史版本:
      v4.6: 电源三源交叉判断(P/Invoke+WMI+PnP), 核显三源交叉判断(注册表+WMI+PnP)
      v4.5: 修复HKU驱动器路径兼容性问题, svc类型改为注册表直写
      v4.4: 修复所有 @{S=(if(...)...)} 语法陷阱, 主循环输入防抖
#>

param(
    [switch]$NoElevate,
    [switch]$EngineOnly,
    [switch]$Gui,
    [switch]$ConsoleMode,
    [switch]$ApplyRecommended,
    [switch]$Status,
    [switch]$Report,
    [switch]$DryRun,
    [switch]$RestoreLatest,
    [switch]$RestoreAll,
    [switch]$Yes,
    [switch]$RestorePoint,
    [switch]$Catalog,
    [string]$CatalogOut,
    [string]$Profile,
    [string]$OutFile,
    [string]$Sid
)

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = 'Continue'
$script:AppVersion   = '6.3.0'
$script:TxEngineOnly = [bool]$EngineOnly
$script:TxNoPrompt   = [bool]($EngineOnly -or $Gui)
$script:DRY          = $false
trap {
    Write-Host "`n[严重错误] $($_.Exception.Message)" -ForegroundColor Red
    if ($script:TxEngineOnly) {
        # 桥接进程的 Write-Host 已写入 data\engine.log，这里补上位置与调用栈，方便定位。
        try {
            $logDir = Join-Path $PSScriptRoot 'data'
            if (-not (Test-Path -LiteralPath $logDir)) {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
            }
            $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
            $trace = @(
                "       类型: $($_.Exception.GetType().FullName)",
                "       位置: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber) 第 $($_.InvocationInfo.OffsetInLine) 列",
                "       代码: $(([string]$_.InvocationInfo.Line).Trim())",
                "       栈: $($_.ScriptStackTrace)"
            ) -join [Environment]::NewLine
            Add-Content -LiteralPath (Join-Path $logDir 'engine.log') -Value ($stamp + ' [FATAL]' + [Environment]::NewLine + $trace) -Encoding UTF8 -ErrorAction SilentlyContinue
        } catch {}
    }
    if (-not $script:TxNoPrompt -and $Host.Name -eq 'ConsoleHost') { Read-Host "`n按回车关闭窗口" }
    break
}

# ── 管理员自提升 ─────────────────────────────────────────
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate -and -not $EngineOnly) {
    # ★ v5.0: 透传当前参数, 提权后行为与直接运行一致 (GUI/CLI/控制台均可)
    $relay = @()
    foreach ($k in @($PSBoundParameters.Keys)) {
        if ($k -in @('NoElevate','Sid')) { continue }
        $v = $PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v.IsPresent) { $relay += "-$k" } }
        elseif ($null -ne $v -and "$v" -ne '') { $relay += "-$k"; $relay += [string]$v }
    }
    $argList = @('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',"`"$PSCommandPath`"",'-NoElevate','-Sid',$identity.User.Value) + $relay
    try { Start-Process powershell.exe -ArgumentList $argList -Verb RunAs } catch {}
    exit
}
if (-not $Sid) { $Sid = $identity.User.Value }

# ★ 家庭版兼容: 不依赖HKU PSDrive, 使用完整注册表路径
$HKU_BASE = "Registry::HKEY_USERS\$Sid"
try { if (-not (Get-PSDrive HKU -EA 0)) { New-PSDrive HKU -PSProvider Registry -Root HKEY_USERS -EA 0 | Out-Null } } catch {}

# ★ v5.0: $PSScriptRoot 在 -File 与 dot-source 两种场景下都可靠, 供 GUI 复用引擎
$SD  = $PSScriptRoot
if (-not $SD) { $SD = Split-Path -Parent $MyInvocation.MyCommand.Definition }
$BK  = Join-Path $SD 'backups'; if (-not (Test-Path $BK)) { New-Item -ItemType Directory $BK -Force | Out-Null }
$LOG = Join-Path $SD "optimize_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# ★ 家庭版兼容: URP使用完整路径, 不依赖HKU:驱动器
$URP = "$HKU_BASE\SOFTWARE\Microsoft\DirectX\UserGpuPreferences"

function Log($m, $c='Gray') {
    $l = "[$(Get-Date -Format 'HH:mm:ss')] $m"
    try { $l | Out-File $LOG -Append -Encoding UTF8 } catch {}
    # ★ v5.0: GUI 通过回调把同一条日志渲染到界面, 控制台模式行为不变
    if ($script:TxLogCallback) { try { & $script:TxLogCallback $l $c } catch {} }
    try { Write-Host $l -ForegroundColor $c } catch {}
}

# ══════════════════════════════════════════════════════════
# ★ v4.7 UInt32 位掩码常量
#   PowerShell 会把 0x80000000 / 0xFFFFFFFF 这类十六进制字面量先解析成 Int32
#   (得到 -2147483648 / -1), 再转 [uint32] 时直接抛 OverflowException。
#   实测确认: [uint32]0x80000000 失败, [uint32]2147483648 成功。
#   因此所有超过 Int32.MaxValue 的掩码一律用十进制字面量, 集中在下面定义。
# ══════════════════════════════════════════════════════════
$U32_ALL  = [uint32]4294967295     # 0xFFFFFFFF
$U32_ZERO = [uint32]0
$BM_PNP_POWER = [uint32]24         # 0x18  网卡/核显 PnPCapabilities: bit3(禁用省电) + bit4(禁用唤醒)
$BM_DPST      = [uint32]16         # 0x10  FeatureTestControl bit4: 禁用 DPST 显示器节能
$BM_PSR       = [uint32]2147483648 # 0x80000000  FeatureTestControl bit31: 禁用面板自刷新

# ══════════════════════════════════════════════════════════
# ★ v4.8 数值/GUID 安全转换
#   [uint32]-1 / [uint32]0x80000000 会抛 OverflowException;
#   New-ItemProperty -PropertyType DWord 也不接受 >Int32.MaxValue 的 UInt32 值。
#   统一用 U32 归一化、I32 写回, 避免 bit31/0xFFFFFFFF 这类高位值静默写失败。
# ══════════════════════════════════════════════════════════
function U32($v) {
    if ($null -eq $v) { return [uint32]0 }
    try {
        if ($v -is [uint32]) { return $v }
        $n = [int64]$v
        if ($n -lt 0) { $n += 4294967296 }
        return [uint32]($n -band 4294967295)
    } catch { return [uint32]0 }
}
function I32($v) {
    return [BitConverter]::ToInt32([BitConverter]::GetBytes((U32 $v)), 0)
}
function NGUID([string]$g) {
    if (!$g) { return '' }
    return (($g -replace '[{}]', '').Trim().ToLowerInvariant())
}
# ★ v5.0: 从网卡属性的有效值里找出"关闭"对应的注册表值; 找不到返回 $null
#   放在优化项定义之前, 因为网络进阶项在构建 $O 时就要用到
function Get-NicOffValue($p) {
    try {
        $vals = @($p.ValidRegistryValues)
        $disps = @($p.ValidDisplayValues)
        for ($i = 0; $i -lt $vals.Count; $i++) {
            $d = ''
            if ($i -lt $disps.Count) { $d = [string]$disps[$i] }
            if ($d -match '(?i)^(Disabled|Off|Disable|关闭|禁用|已禁用)$') { return $vals[$i] }
        }
        if ($vals -contains 0) { return 0 }
        if ($vals -contains '0') { return '0' }
        if ($vals -contains 'Disabled') { return 'Disabled' }
        return $null
    } catch { return $null }
}

# ── C# P/Invoke ──────────────────────────────────────────
$CS = $false; $CSFailed = $false
$CSC = @'
using System; using System.Runtime.InteropServices;

public struct QPWR_SPS {
    public byte ACLineStatus, BatteryFlag, BatteryLifePercent, SystemStatusFlag;
    public int  BatteryLifeTime, BatteryFullLifeTime;
}
public static class QPWR {
    [DllImport("kernel32.dll")] public static extern bool GetSystemPowerStatus(out QPWR_SPS s);
}

// ★ v4.7 修正: 原结构体只有 188 字节, Win32 要求 DEVMODEW 为 220 字节, 否则 API 直接返回 0
//   错误1: dmPositionX/dmPositionY 是 LONG(int), 原写成 short
//   错误2: dmTTOption/dmCollate 之后缺少 dmICMMethod..dmPanningHeight 共 8 个 int
[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
public struct DS_DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int   dmFields;
    public int   dmPositionX, dmPositionY;
    public int   dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string dmFormName;
    public short dmLogPixels;
    public int   dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int   dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2;
    public int   dmPanningWidth, dmPanningHeight;
}

[StructLayout(LayoutKind.Sequential, CharSet=CharSet.Auto)]
public struct DS_DISPDEV {
    public int cb;
    [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]  public string DeviceName;
    [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string DeviceString;
    public int StateFlags;
    [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string DeviceID;
    [MarshalAs(UnmanagedType.ByValTStr,SizeConst=128)] public string DeviceKey;
}

public static class DS {
    public const int DM_DISPLAYFREQUENCY   = 0x400000;
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int CDS_UPDATEREGISTRY    = 0x01;   // ★ 持久化(原 CDS_FULLSCREEN=0x04 是全屏独占语义)
    public const int CDS_TEST              = 0x02;
    public const int DISPLAY_DEVICE_ATTACHED_TO_DESKTOP = 0x01;
    [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern int  EnumDisplaySettings(string n, int m, ref DS_DEVMODE d);
    [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern int  ChangeDisplaySettingsEx(string n, ref DS_DEVMODE d, IntPtr h, int f, IntPtr l);
    [DllImport("user32.dll",CharSet=CharSet.Auto)] public static extern bool EnumDisplayDevices(string n, uint d, ref DS_DISPDEV dd, uint f);
}
'@
function ECS {
    if ($script:CS -or $script:CSFailed) { return }
    try {
        $pre = [System.Management.Automation.PSTypeName]'DS_DEVMODE'
        if ($pre.Type) { $script:CS = $true; return }
        Add-Type -TypeDefinition $CSC -EA Stop
        $sz = [Runtime.InteropServices.Marshal]::SizeOf([type][DS_DEVMODE])
        if ($sz -ne 220) { Log "DEVMODE 尺寸异常: $sz (应为220), 刷新率功能将不可用" 'Red'; $script:CSFailed = $true; return }
        $script:CS = $true
    } catch {
        Log "P/Invoke编译失败: $($_.Exception.Message)" 'Red'
        $script:CSFailed = $true
    }
}

# ══════════════════════════════════════════════════════════
# ★ v5.0 硬件查询缓存
#   Get-PnpDevice 单次约 1.5-2 秒, 原代码在显卡/电池/笔记本判断里重复调用 3-4 次。
#   改为一次 Win32_PnPEntity 查询 + 内存过滤, 功能不变, 启动时间大幅下降。
# ══════════════════════════════════════════════════════════
$script:PNP_ALL_CACHE = $null
$script:PNP_ALL_READY = $false
function Get-TxPnpAll {
    if ($script:PNP_ALL_READY) { return $script:PNP_ALL_CACHE }
    $script:PNP_ALL_READY = $true
    # 只取用得到的属性, 全量对象序列化约 1.5 秒, 投影后约 0.8 秒
    try { $script:PNP_ALL_CACHE = @(Get-CimInstance Win32_PnPEntity -Property PNPClass,Status,Name,DeviceID -EA 0) }
    catch { $script:PNP_ALL_CACHE = @() }
    return $script:PNP_ALL_CACHE
}
function Get-TxPnpClass([string]$class) {
    $all = @(Get-TxPnpAll)
    if ($all.Count -gt 0) {
        return @($all | Where-Object { [string]$_.PNPClass -eq $class })
    }
    # 旧系统回退: 统一成 Win32_PnPEntity 的字段名, 调用方无需区分来源
    try {
        return @(Get-PnpDevice -Class $class -EA 0 | ForEach-Object {
            [PSCustomObject]@{
                PNPClass = $class
                Status   = [string]$_.Status
                Name     = [string]$_.FriendlyName
                DeviceID = [string]$_.InstanceId
            }
        })
    } catch { return @() }
}
$script:BATT_WMI_CACHE = $null
$script:BATT_WMI_READY = $false
function Get-TxBatteryWmi {
    if ($script:BATT_WMI_READY) { return $script:BATT_WMI_CACHE }
    $script:BATT_WMI_READY = $true
    try {
        $script:BATT_WMI_CACHE = @(Get-CimInstance Win32_Battery -EA 0 |
            Where-Object { $_.Name -notmatch '(?i)UPS|AC Adapter|AC 适配器|Back-UPS' })
    } catch { $script:BATT_WMI_CACHE = @() }
    return $script:BATT_WMI_CACHE
}
$script:VIDEO_WMI_CACHE = $null
$script:VIDEO_WMI_READY = $false
function Get-TxVideoWmi {
    if ($script:VIDEO_WMI_READY) { return $script:VIDEO_WMI_CACHE }
    $script:VIDEO_WMI_READY = $true
    try { $script:VIDEO_WMI_CACHE = @(Get-CimInstance Win32_VideoController -Property Name,AdapterCompatibility,AdapterRAM,PNPDeviceID -EA 0) }
    catch { $script:VIDEO_WMI_CACHE = @() }
    return $script:VIDEO_WMI_CACHE
}
$script:CHASSIS_CACHE = $null
$script:CHASSIS_READY = $false
function Get-TxChassis {
    if ($script:CHASSIS_READY) { return $script:CHASSIS_CACHE }
    $script:CHASSIS_READY = $true
    try { $script:CHASSIS_CACHE = @(Get-CimInstance Win32_SystemEnclosure -Property ChassisTypes -EA 0) }
    catch { $script:CHASSIS_CACHE = @() }
    return $script:CHASSIS_CACHE
}

# ══════════════════════════════════════════════════════════
# ★ v5.1 并行硬件探测
#   网卡 / PnP / 显卡 / 电池 / 机箱 / GameBar / 系统信息互不依赖,
#   放进独立 runspace 并行执行; 主线程同时做注册表与显示器枚举。
#   实测串行约 2.5 秒, 并行约 1.1 秒。单个 job 失败不影响其它项,
#   等待结果为 $null 时由主线程回退到原来的同步查询。
# ══════════════════════════════════════════════════════════
$script:TX_JOBS = @{}
function Start-TxJob([string]$name, [scriptblock]$body) {
    $rs = $null; $ps = $null
    try {
        $rs = [runspacefactory]::CreateRunspace()
        $rs.Open()
        $ps = [powershell]::Create()
        $ps.Runspace = $rs
        [void]$ps.AddScript($body.ToString())
        $h = $ps.BeginInvoke()
        $script:TX_JOBS[$name] = [PSCustomObject]@{ PS = $ps; RS = $rs; H = $h }
    } catch {
        try { if ($ps) { $ps.Dispose() } } catch {}
        try { if ($rs) { $rs.Close(); $rs.Dispose() } } catch {}
    }
}
function Wait-TxJob([string]$name) {
    if (-not $script:TX_JOBS.ContainsKey($name)) { return $null }
    $j = $script:TX_JOBS[$name]
    $script:TX_JOBS.Remove($name)
    $out = @()
    try { $out = @($j.PS.EndInvoke($j.H)) }
    catch { $out = @() }
    finally {
        try { $j.PS.Dispose() } catch {}
        try { $j.RS.Close(); $j.RS.Dispose() } catch {}
    }
    if ($out.Count -gt 0) { return $out[0] }
    return $null
}

# ══════════════════════════════════════════════════════════
# ★ 三源交叉验证 — 电源状态
# ★ v4.7: 原名 GPS 被内置别名 gps(=Get-Process) 遮蔽, 函数根本没被执行,
#         菜单里恒定显示"供电: 台式机"。改名为 PWRST。
# ══════════════════════════════════════════════════════════
function PWRST {
    $s1 = $null; $s2 = $null; $s3 = $null; $wmiHasBattery = $false

    # 源1: P/Invoke GetSystemPowerStatus (API直读, 最快)
    try {
        ECS
        $ps = New-Object QPWR_SPS
        if ([QPWR]::GetSystemPowerStatus([ref]$ps)) {
            # ACLineStatus: 0=电池 1=交流 255=未知 (未知时不要当成"电池供电")
            if ($ps.ACLineStatus -eq 0 -or $ps.ACLineStatus -eq 1) {
                $onAc1 = ($ps.ACLineStatus -eq 1)
                $s1 = @{ OnAC = $onAc1; Source = 'P/Invoke'; LifePercent = [int]$ps.BatteryLifePercent }
            }
        }
    } catch {}

    # 源2: WMI Win32_Battery (支持多电池, 取第一块状态已知的; 结果缓存)
    try {
        $batts = @(Get-TxBatteryWmi)
        if ($batts.Count -gt 0) {
            $wmiHasBattery = $true
            # BatteryStatus: 1=放电(电池), 2=AC供电, 3=已充满, 4=低, 5=严重, 6=充电中, 7=充电且高, 8=充电且低, 9=充电且严重, 10=未定义, 11=部分充电
            $st = 0
            foreach ($b in $batts) {
                if ($null -ne $b.BatteryStatus -and [int]$b.BatteryStatus -gt 0) { $st = [int]$b.BatteryStatus; break }
            }
            if ($st -gt 0) {
                $onAc2 = ($st -in @(2,3,7,8,9,11))
                $s2 = @{ OnAC = $onAc2; Source = 'WMI'; BatteryStatus = $st }
            }
        }
    } catch {}

    # 源3: PnP设备枚举 (设备层确认有无电池; 使用缓存, 兼容中文"AC 适配器")
    try {
        $battDev = @(Get-TxPnpClass 'Battery' | Where-Object {
            $_.Status -eq 'OK' -and
            $_.Name -notmatch '(?i)AC Adapter|AC 适配器|UPS|Back-UPS|HID'
        })
        $hasB = ($battDev.Count -gt 0)
        $s3 = @{ HasBattery = $hasB; Source = 'PnP' }
    } catch {}

    # ── 共识判断 ──
    $srcList = @()
    if ($s1) { $srcList += "S1:$($s1.Source)" }
    if ($s2) { $srcList += "S2:$($s2.Source)" }
    if ($s3) { $srcList += "S3:$($s3.Source)" }

    if (!$s1 -and !$s2 -and !$s3) {
        return @{ OnAC = $null; IsLaptop = $false; Confidence = 'fail'; Sources = @() }
    }

    $hasBattery = $false
    if ($wmiHasBattery) { $hasBattery = $true }
    if ($s3 -and $s3.HasBattery) { $hasBattery = $true }

    if (-not $hasBattery) {
        return @{ OnAC = $true; IsLaptop = $false; Confidence = 'high'; Sources = $srcList }
    }

    $acVotes = @()
    if ($s1) { $acVotes += $s1.OnAC }
    if ($s2) { $acVotes += $s2.OnAC }

    if ($acVotes.Count -ge 2) {
        if ($acVotes[0] -eq $acVotes[1]) {
            return @{ OnAC = $acVotes[0]; IsLaptop = $true; Confidence = 'high'; Sources = $srcList }
        } else {
            # 两源冲突: 采信 P/Invoke (API 直读, 权威度最高), 并标记降级
            $onAC = $acVotes[0]
            if ($s1) { $onAC = $s1.OnAC }
            return @{ OnAC = $onAC; IsLaptop = $true; Confidence = 'degraded'; Sources = $srcList; Conflict = $true }
        }
    } elseif ($acVotes.Count -eq 1) {
        return @{ OnAC = $acVotes[0]; IsLaptop = $true; Confidence = 'medium'; Sources = $srcList }
    } else {
        return @{ OnAC = $null; IsLaptop = $true; Confidence = 'low'; Sources = $srcList }
    }
}

# ══════════════════════════════════════════════════════════
# ★ v4.8 GPU 检测: 三源合并 + 核显/独显分类
#   只看厂商名不够: Intel Arc 130T/140V 是核显, Arc A770/B580 是独显;
#   AMD APU 也叫 Radeon, 但与 RX 系列独显完全不同。
#   注册表显存同样不可单独采信 (Arc 130T 会上报 18GB 共享显存)。
# ══════════════════════════════════════════════════════════
function Get-GpuKeyName([string]$n) {
    if ([string]::IsNullOrWhiteSpace($n)) { return '' }
    $s = $n.ToLowerInvariant()
    $s = $s -replace '\((tm|r|c)\)', ''
    $s = $s -replace '\(\s*\d+\s*(gb|mb)\s*\)', ''
    $s = $s -replace '[^a-z0-9]+', ' '
    return $s.Trim()
}
function Get-GpuVendor([string]$name, [string]$provider, [string]$pnp) {
    $s = "$name $provider $pnp"
    if ($s -match '(?i)Microsoft Hyper-V|Microsoft Remote Display|Microsoft Basic Render|Citrix|VMware|VirtualBox|Parsec|DameWare|Indirect Display|Virtual Display|DisplayLink|UsbDisplay|\bRDP\b') { return 'Virtual' }
    if ($s -match '(?i)NVIDIA|GeForce|Quadro|\bRTX\b|\bGTX\b|VEN_10DE') { return 'NVIDIA' }
    if ($s -match '(?i)Advanced Micro Devices|\bAMD\b|Radeon|\bATI\b|VEN_1002') { return 'AMD' }
    if ($s -match '(?i)Intel|VEN_8086') { return 'Intel' }
    if ($s -match '(?i)Qualcomm|Adreno|VEN_17CB') { return 'Qualcomm' }
    if ($s -match '(?i)Apple') { return 'Apple' }
    if ($s -match '(?i)Microsoft') { return 'Microsoft' }
    return 'Other'
}
function Test-GpuIntegrated([string]$name, [string]$vendor, [uint64]$vram) {
    $n = [string]$name
    switch ($vendor) {
        'NVIDIA'  { return $false }   # Windows 上的 NVIDIA 显示适配器均为独显
        'Intel'   {
            # Arc A/B 系列、Pro、Data Center、Xe MAX 是独显; 其余 Intel 显示适配器按核显处理
            if ($n -match '(?i)Arc.*\b[AB]\d{2,3}M?\b|Arc.*\bPro\b|Xe\s*MAX|Data Center GPU|Flex Series') { return $false }
            return $true
        }
        'AMD'     {
            # APU 核显命名: Radeon(TM) Graphics / Vega / 780M 这类三位数+M / R5 Graphics / HD 8650G
            if ($n -match '(?i)Radeon(\(TM\))?\s*(Graphics|Vega)|Radeon(\(TM\))?\s+\d{3}M\b|Radeon\s+R\d\s+Graphics|Radeon\s+HD\s+\d{4}G\b') { return $true }
            # 独显命名: RX / Radeon Pro / FirePro / VII / HD 8870M / R7 260X / R5 M330
            if ($n -match '(?i)\bRX\b|Radeon Pro|FirePro|Radeon VII|Radeon\s+HD\s+\d{4}|Radeon\s+R\d\s+\d{3}|Radeon\s+R\d\s+M\d{3}|Radeon\s+\d{3}\s+Series') { return $false }
            # 名称无法判断时用显存兜底 (APU 专用显存通常 <= 1GB)
            return ($vram -lt [uint64]1610612736)
        }
        'Qualcomm' { return $true }
        'Apple'    { return $true }
        'Microsoft' { return $false }  # Basic Display / Basic Render 不是核显也不是独显
        default    { return ($vram -lt [uint64]1610612736) }
    }
}
function Get-GpuInventory {
    $records = New-Object System.Collections.ArrayList
    $seen = @{}
    $seenPnp = @{}

    $add = {
        param($name, $provider, $vram, $key, $keyId, $pnp, $source)
        if ([string]::IsNullOrWhiteSpace([string]$name)) { return }
        $nm = ([string]$name).Trim()
        $k = Get-GpuKeyName $nm
        if (!$k) { return }
        $pk = ''
        if ($pnp) { $pk = ([string]$pnp).Trim().ToLowerInvariant() }

        $rec = $null
        if ($seen.ContainsKey($k)) { $rec = $seen[$k] }
        elseif ($pk -and $seenPnp.ContainsKey($pk)) { $rec = $seenPnp[$pk] }

        if ($rec) {
            if (!$rec.Provider -and $provider) { $rec.Provider = [string]$provider }
            if ($rec.VRAM -eq 0 -and $vram) { $rec.VRAM = [uint64]$vram }
            if (!$rec.RegKey -and $key) { $rec.RegKey = [string]$key; $rec.KeyId = [string]$keyId }
            if (!$rec.PnPId -and $pnp) { $rec.PnPId = [string]$pnp }
            if (@($rec.Sources) -notcontains $source) { $rec.Sources = @($rec.Sources) + $source }
            if (!$rec.Basic -and !$rec.Virtual) {
                $rec.Integrated = [bool](Test-GpuIntegrated $rec.Name $rec.Vendor $rec.VRAM)
                $rec.Dedicated  = -not $rec.Integrated
            }
            return
        }

        $vendor  = Get-GpuVendor $nm $provider $pnp
        $basic   = [bool]($nm -match '(?i)Microsoft Basic Display')
        $virtual = [bool]($vendor -eq 'Virtual')
        $integ = $false; $ded = $false
        if (!$basic -and !$virtual) {
            $integ = [bool](Test-GpuIntegrated $nm $vendor ([uint64]$vram))
            $ded   = -not $integ
        }
        $new = [PSCustomObject]@{
            Name       = $nm
            Key        = $k
            Provider   = [string]$provider
            Vendor     = $vendor
            Integrated = $integ
            Dedicated  = $ded
            Basic      = $basic
            Virtual    = $virtual
            VRAM       = [uint64]$vram
            RegKey     = [string]$key
            KeyId      = [string]$keyId
            PnPId      = [string]$pnp
            Sources    = @($source)
        }
        $seen[$k] = $new
        if ($pk) { $seenPnp[$pk] = $new }
        $null = $records.Add($new)
    }

    # 源1: 注册表 (最详细, 含完整驱动信息与真实键路径)
    try {
        foreach ($s in (Get-ChildItem $DCR -EA 0)) {
            if ($s.PSChildName -notmatch '^\d{4}$') { continue }
            $p = Get-ItemProperty $s.PSPath -EA 0
            if (!$p -or !('DriverDesc' -in $p.PSObject.Properties.Name) -or !$p.DriverDesc) { continue }
            $vram = [uint64]0
            if ('HardwareInformation.qwMemorySize' -in $p.PSObject.Properties.Name -and $p.'HardwareInformation.qwMemorySize') {
                $vram = [uint64]$p.'HardwareInformation.qwMemorySize'
            } elseif ('MemorySize' -in $p.PSObject.Properties.Name -and $p.MemorySize) {
                $vram = [uint64]$p.MemorySize
            }
            $prov = ''
            if ('ProviderName' -in $p.PSObject.Properties.Name) { $prov = [string]$p.ProviderName }
            $pnp = ''
            if ('MatchingDeviceId' -in $p.PSObject.Properties.Name) { $pnp = [string]$p.MatchingDeviceId }
            & $add $p.DriverDesc $prov $vram $s.PSPath $s.PSChildName $pnp 'Registry'
        }
    } catch { Log "GPU检测S1(注册表)失败: $($_.Exception.Message)" 'Yellow' }

    # 源2: WMI Win32_VideoController (标准接口; 启动时已并行预取, 未命中则同步查询)
    try {
        foreach ($g in @(Get-TxVideoWmi)) {
            if (!$g.Name) { continue }
            $vram = [uint64]0
            if ($null -ne $g.AdapterRAM -and [uint64]$g.AdapterRAM -lt 4294967296) { $vram = [uint64]$g.AdapterRAM }
            & $add $g.Name ([string]$g.AdapterCompatibility) $vram '' '' ([string]$g.PNPDeviceID) 'WMI'
        }
    } catch { Log "GPU检测S2(WMI)失败: $($_.Exception.Message)" 'Yellow' }

    # 源3: PnP设备枚举 (设备层确认; 使用缓存, 避免 1.5 秒级重复查询)
    try {
        foreach ($g in @(Get-TxPnpClass 'Display' | Where-Object { $_.Status -eq 'OK' -and $_.Name })) {
            & $add $g.Name '' ([uint64]0) '' '' ([string]$g.DeviceID) 'PnP'
        }
    } catch { Log "GPU检测S3(PnP)失败: $($_.Exception.Message)" 'Yellow' }

    return @($records.ToArray())
}

# ══════════════════════════════════════════════════════════
# ★ v4.7 显示器检测: 必须用 Win32 真实设备名 (\\.\DISPLAY1),
#   注册表 PSPath 传给 EnumDisplaySettings 一定返回 0。
#   同时注册表里没有 CurrentHorizontalResolution 等字段, 不能依赖它。
# ══════════════════════════════════════════════════════════
function Get-DisplayDevices {
    $out = @()
    try {
        Add-Type -AssemblyName System.Windows.Forms -EA 0
        foreach ($s in [System.Windows.Forms.Screen]::AllScreens) {
            if ($s.DeviceName) {
                $lbl = '扩展显示器'
                if ($s.Primary) { $lbl = '主显示器' }
                $out += [PSCustomObject]@{ Name = $s.DeviceName; Desc = $lbl }
            }
        }
    } catch {}
    if ($out.Count -gt 0) { return $out }

    ECS
    try {
        $cbSize = [Runtime.InteropServices.Marshal]::SizeOf([type][DS_DISPDEV])
        $i = 0
        while ($i -lt 16) {
            $dd = New-Object DS_DISPDEV
            $dd.cb = $cbSize
            if (-not [DS]::EnumDisplayDevices($null, [uint32]$i, [ref]$dd, [uint32]0)) { break }
            if ($dd.DeviceName -and (($dd.StateFlags -band [DS]::DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) -ne 0)) {
                $out += [PSCustomObject]@{ Name = $dd.DeviceName; Desc = $dd.DeviceString }
            }
            $i++
        }
    } catch {}
    return $out
}

function Get-CurrentMode($devName) {
    ECS
    if (-not $script:CS) { return $null }
    try {
        $dm = New-Object DS_DEVMODE
        $dm.dmSize = [int16][Runtime.InteropServices.Marshal]::SizeOf([type][DS_DEVMODE])
        if ([DS]::EnumDisplaySettings($devName, [DS]::ENUM_CURRENT_SETTINGS, [ref]$dm) -eq 0) { return $null }
        return [PSCustomObject]@{ W = [int]$dm.dmPelsWidth; H = [int]$dm.dmPelsHeight; RR = [int]$dm.dmDisplayFrequency }
    } catch { return $null }
}

function Get-MaxRefresh($devName, $w, $h, $curR) {
    ECS
    if (-not $script:CS) { return $curR }
    $best = $curR; $i = 0
    try {
        while ($i -lt 600) {
            $dx = New-Object DS_DEVMODE
            $dx.dmSize = [int16][Runtime.InteropServices.Marshal]::SizeOf([type][DS_DEVMODE])
            if ([DS]::EnumDisplaySettings($devName, $i, [ref]$dx) -eq 0) { break }
            if ([int]$dx.dmPelsWidth -eq $w -and [int]$dx.dmPelsHeight -eq $h) {
                $f = [int]$dx.dmDisplayFrequency
                if ($f -gt $best) { $best = $f }
            }
            $i++
        }
    } catch {}
    return $best
}

# ── 硬件检测 ─────────────────────────────────────────────
$AN = @(); $NN = @(); $GN = @(); $CI = $null; $IL = $false; $DI = @()
$GPU = @(); $GREAL = @(); $BASIC = $false; $HAS_WIFI = $false
$HI = $false; $II = $false; $IAR = $false; $HN = $false; $HA = $false; $HQ = $false
$HAS_DGPU = $false; $HAS_IGPU = $false; $HD = $false; $IN = $false; $CMB = $false
$ITS = @(); $DRR = $false; $GBI = $false; $GBE = $false

$IPP = $false; $ISK = $null; $IDP = $false; $IDR = $false; $IDS = $false
$PCD = $false; $TDC = 2
$DCR = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"

# ★ v5.1 并行硬件探测: 互不依赖的查询交给独立 runspace, 主线程同时做注册表与显示器枚举。
#   每个 job 返回 @{ Ok; V }, 失败时 Ok=$false, 主线程回退到原来的同步查询。
Start-TxJob 'nic' {
    try {
        $v = @(Get-NetAdapter -Physical -EA 0 |
            Where-Object { $_.Status -ne 'Not Present' } |
            Sort-Object @{E={$_.Status -eq 'Up'};Descending=$true}, @{E={$_.InterfaceType -eq 71};Descending=$true}, Name |
            ForEach-Object {
                [PSCustomObject]@{
                    Name = [string]$_.Name; Status = [string]$_.Status
                    InterfaceType = [int]$_.InterfaceType
                    PhysicalMediaType = [string]$_.PhysicalMediaType
                    LinkSpeed = [string]$_.LinkSpeed
                    InterfaceDescription = [string]$_.InterfaceDescription
                    InterfaceGuid = [string]$_.InterfaceGuid
                    MacAddress = [string]$_.MacAddress
                }
            })
        [PSCustomObject]@{ Ok = $true; V = $v }
    } catch { [PSCustomObject]@{ Ok = $false; V = @() } }
}
Start-TxJob 'pnp' {
    try {
        $v = @(Get-CimInstance Win32_PnPEntity -Property PNPClass,Status,Name,DeviceID -EA 0 |
            ForEach-Object { [PSCustomObject]@{ PNPClass = [string]$_.PNPClass; Status = [string]$_.Status; Name = [string]$_.Name; DeviceID = [string]$_.DeviceID } })
        [PSCustomObject]@{ Ok = $true; V = $v }
    } catch { [PSCustomObject]@{ Ok = $false; V = @() } }
}
Start-TxJob 'video' {
    try {
        $v = @(Get-CimInstance Win32_VideoController -Property Name,AdapterCompatibility,AdapterRAM,PNPDeviceID -EA 0 |
            ForEach-Object { [PSCustomObject]@{ Name = [string]$_.Name; AdapterCompatibility = [string]$_.AdapterCompatibility; AdapterRAM = $_.AdapterRAM; PNPDeviceID = [string]$_.PNPDeviceID } })
        [PSCustomObject]@{ Ok = $true; V = $v }
    } catch { [PSCustomObject]@{ Ok = $false; V = @() } }
}
Start-TxJob 'batt' {
    try {
        $v = @(Get-CimInstance Win32_Battery -Property Name,BatteryStatus -EA 0 |
            Where-Object { $_.Name -notmatch '(?i)UPS|AC Adapter|AC 适配器|Back-UPS' } |
            ForEach-Object { [PSCustomObject]@{ Name = [string]$_.Name; BatteryStatus = $_.BatteryStatus } })
        [PSCustomObject]@{ Ok = $true; V = $v }
    } catch { [PSCustomObject]@{ Ok = $false; V = @() } }
}
Start-TxJob 'chassis' {
    try {
        $v = @(Get-CimInstance Win32_SystemEnclosure -Property ChassisTypes -EA 0 |
            ForEach-Object { [PSCustomObject]@{ ChassisTypes = @($_.ChassisTypes) } })
        [PSCustomObject]@{ Ok = $true; V = $v }
    } catch { [PSCustomObject]@{ Ok = $false; V = @() } }
}
Start-TxJob 'appx' {
    try {
        $hit = [bool](Get-AppxPackage 'Microsoft.XboxGamingOverlay' -EA 0)
        if (-not $hit) { try { $hit = [bool](Get-AppxPackage 'Microsoft.XboxGamingOverlay' -AllUsers -EA 0) } catch {} }
        [PSCustomObject]@{ Ok = $true; V = $hit }
    } catch { [PSCustomObject]@{ Ok = $false; V = $false } }
}
Start-TxJob 'sysinfo' {
    try {
        $os = $null; $cpu = $null; $mods = @(); $cs = $null; $dg = $null
        try { $os = Get-CimInstance Win32_OperatingSystem -Property Caption,BuildNumber -EA 0 } catch {}
        try { $cpu = Get-CimInstance Win32_Processor -Property Name,NumberOfCores,NumberOfLogicalProcessors -EA 0 | Select-Object -First 1 } catch {}
        try { $mods = @(Get-CimInstance Win32_PhysicalMemory -Property Capacity,Speed,ConfiguredClockSpeed -EA 0) } catch {}
        try { $cs = Get-CimInstance Win32_ComputerSystem -Property Manufacturer,Model -EA 0 } catch {}
        try { $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName 'Win32_DeviceGuard' -Property VirtualizationBasedSecurityStatus,SecurityServicesRunning -EA 0 } catch {}
        [PSCustomObject]@{ Ok = $true; V = [PSCustomObject]@{ OS=$os; CPU=$cpu; Memory=@($mods); Computer=$cs; DeviceGuard=$dg } }
    } catch { [PSCustomObject]@{ Ok = $false; V = $null } }
}

# 主线程: 机型 / Intel 服务 / 其余注册表项 —— 与后台 job 重叠执行
try {
    $bios = Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\BIOS' -EA 0
    if ($bios) {
        $mfr = 'Unknown'; $mdl = 'Unknown'
        if ('SystemManufacturer' -in $bios.PSObject.Properties.Name) { $mfr = $bios.SystemManufacturer }
        if ('SystemProductName'   -in $bios.PSObject.Properties.Name) { $mdl = $bios.SystemProductName }
        $CI = [PSCustomObject]@{ Manufacturer = $mfr; Model = $mdl }
    }
} catch {}
try { $ITS = @(@('ESRV_SVC_QUEENCREEK','SystemUsageReportSvc_QUEENCREEK','IntelCollectorService','IntelTelemetryAgent','DSAService','DSAUpdateService') | Where-Object { Get-Service $_ -EA 0 }) } catch {}
try { $dv = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name DrrMigrationControl -EA 0; if ($dv -and 'DrrMigrationControl' -in $dv.PSObject.Properties.Name) { $DRR = [int]$dv.DrrMigrationControl -eq 0 } } catch {}
$PCR = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Device Driver Packages'
try { $p = Get-ItemProperty $PCR -Name Autorun -EA 0; if ($p -and 'Autorun' -in $p.PSObject.Properties.Name) { $PCD = [int]$p.Autorun -eq 0 } } catch {}
try { $t = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name TdrDelay -EA 0; if ($t -and 'TdrDelay' -in $t.PSObject.Properties.Name) { $TDC = [int]$t.TdrDelay } } catch {}

# ★ v4.7 显示器检测 (真实设备名 + EnumDisplaySettings), 与后台 job 并行
try {
    foreach ($dev in @(Get-DisplayDevices)) {
        $cur = Get-CurrentMode $dev.Name
        if (!$cur -or $cur.W -le 0) { continue }
        $maxR = Get-MaxRefresh $dev.Name $cur.W $cur.H $cur.RR
        $slug = ($dev.Name -replace '[\\\.]','')
        $DI += [PSCustomObject]@{ DN=$dev.Desc; ID=$slug; DID=$dev.Name; W=$cur.W; H=$cur.H; RR=$cur.RR; MR=$maxR }
    }
} catch { Log "显示器检测失败: $($_.Exception.Message)" 'Yellow' }
if (-not $DI) { Log "显示器检测: 未能枚举到活动显示器 (刷新率项将不可用)" 'Yellow' }

# 收网: 网卡 (排除 "Not Present" 的幽灵副本, 避免为不存在的网卡写配置)
$r = Wait-TxJob 'nic'
if ($r -and $r.Ok) {
    $AN = @($r.V)
} else {
    try {
        $AN = @(Get-NetAdapter -Physical -EA 0 | Where-Object { $_.Status -ne 'Not Present' } |
            Sort-Object @{E={$_.Status -eq 'Up'};Descending=$true}, @{E={$_.InterfaceType -eq 71};Descending=$true}, Name)
    } catch { Log "网卡检测失败: $($_.Exception.Message)" 'Yellow' }
}
$NN = @($AN | ForEach-Object { $_.Name })
$HAS_WIFI = [bool](@($AN | Where-Object { $_.InterfaceType -eq 71 -or $_.PhysicalMediaType -match '802.11|Native 802.11|Wireless' }).Count -gt 0)

# 收网: PnP / 显卡 / 电池 / 机箱 / GameBar / 系统信息 (失败则保持未就绪, 由原函数同步回退)
$r = Wait-TxJob 'pnp'
if ($r -and $r.Ok) { $script:PNP_ALL_CACHE = @($r.V); $script:PNP_ALL_READY = $true }
$r = Wait-TxJob 'video'
if ($r -and $r.Ok) { $script:VIDEO_WMI_CACHE = @($r.V); $script:VIDEO_WMI_READY = $true }
$r = Wait-TxJob 'batt'
if ($r -and $r.Ok) { $script:BATT_WMI_CACHE = @($r.V); $script:BATT_WMI_READY = $true }
$r = Wait-TxJob 'chassis'
if ($r -and $r.Ok) { $script:CHASSIS_CACHE = @($r.V); $script:CHASSIS_READY = $true }
$r = Wait-TxJob 'appx'
if ($r -and $r.Ok) { $GBI = [bool]$r.V }
if (!$GBI) { try { if (Get-AppxPackage 'Microsoft.XboxGamingOverlay' -EA 0) { $GBI = $true } } catch {} }
if (!$GBI) { try { if (Get-AppxPackage 'Microsoft.XboxGamingOverlay' -AllUsers -EA 0) { $GBI = $true } } catch {} }
$r = Wait-TxJob 'sysinfo'
if ($r -and $r.Ok -and $r.V) { $script:SYSINFO_CACHE = $r.V }

# 显卡三源合并检测 + 核显/独显分类
$GPU   = @(Get-GpuInventory)
$GREAL = @($GPU | Where-Object { -not $_.Basic -and -not $_.Virtual })
$BASIC = [bool](@($GPU | Where-Object { $_.Basic }).Count -gt 0)
$GN    = @($GREAL | ForEach-Object { $_.Name })
if (!$GN) { $GN = @($GPU | ForEach-Object { $_.Name }) }
if (!$GN) { $GN = @('Unknown GPU') }
$HI  = [bool](@($GREAL | Where-Object { $_.Vendor -eq 'Intel' }).Count -gt 0)
$II  = [bool](@($GREAL | Where-Object { $_.Vendor -eq 'Intel' -and $_.Integrated }).Count -gt 0)
$IAR = [bool](@($GREAL | Where-Object { $_.Vendor -eq 'Intel' -and $_.Dedicated }).Count -gt 0)
$HN  = [bool](@($GREAL | Where-Object { $_.Vendor -eq 'NVIDIA' }).Count -gt 0)
$HA  = [bool](@($GREAL | Where-Object { $_.Vendor -eq 'AMD' }).Count -gt 0)
$HQ  = [bool](@($GREAL | Where-Object { $_.Vendor -eq 'Qualcomm' }).Count -gt 0)
$HAS_DGPU = [bool](@($GREAL | Where-Object { $_.Dedicated }).Count -gt 0)
$HAS_IGPU = [bool](@($GREAL | Where-Object { $_.Integrated }).Count -gt 0)
$HD  = $HAS_DGPU
if ($BASIC) { Log "检测到 Microsoft 基本显示适配器: 显卡厂商驱动可能未安装, 显卡相关优化将自动隐藏" 'Yellow' }

# 笔记本判断: 三源交叉验证 (PnP / 电池缓存已就绪)
$IL = $false
try {
    # 使用缓存; 同时排除中文"AC 适配器", 避免把电源适配器当成电池
    $acpiBatt = @(Get-TxPnpClass 'Battery' | Where-Object {
        $_.Status -eq 'OK' -and
        $_.Name -notmatch '(?i)AC Adapter|AC 适配器|UPS|Back-UPS|HID'
    })
    if ($acpiBatt.Count -gt 0) { $IL = $true }
} catch {}
if (-not $IL) {
    # ★ v4.8: 台式机接 UPS 时 Win32_Battery 也会返回电池, 需排除, 否则会误判为笔记本
    try {
        $wmiBatt = @(Get-TxBatteryWmi)
        if ($wmiBatt.Count -gt 0) { $IL = $true }
    } catch {}
}
if (-not $IL) {
    # ★ v4.7 修正: ChassisTypes 是 UInt16[] 数组, "数组 -in 标量列表" 恒为 False
    try {
        $chassis = @(Get-TxChassis)
        if ($chassis.Count -gt 0) {
            $ctList = @(8,9,10,11,12,14,18,21)
            $hit = @($chassis | ForEach-Object { @($_.ChassisTypes) } | Where-Object { $ctList -contains [int]$_ })
            if ($hit.Count -gt 0) { $IL = $true }
        }
    } catch {}
}
$IN = $false
if ($CI) { $IN = [bool]($CI.Manufacturer -match 'Lenovo|LENOVO') }
$CMB = $IL -and $HAS_DGPU

# ★ v4.8: UAC 提权后 HKCU 可能指向管理员账户, 统一用启动者 SID
try { $gb = Get-ItemProperty "$HKU_BASE\Software\Microsoft\GameBar" -EA 0; if ($gb -and 'AllowAutoGameMode' -in $gb.PSObject.Properties.Name) { $GBE = [int]$gb.AllowAutoGameMode -eq 1 } else { $GBE = $GBI } } catch {}

# Intel 核显子键: 优先选核显, 避免 Intel Arc 独显机器误用独显子键
try {
    $intelRecs = @($GPU | Where-Object { $_.Vendor -eq 'Intel' -and $_.RegKey })
    $pick = @($intelRecs | Where-Object { $_.Integrated }) | Select-Object -First 1
    if (!$pick) { $pick = $intelRecs | Select-Object -First 1 }
    if ($pick) { $ISK = $pick.RegKey }
} catch {}
try {
    if ($ISK) {
        $p = Get-ItemProperty $ISK -EA 0
        if ($p -and 'PnPCapabilities' -in $p.PSObject.Properties.Name) { $IPP = ((U32 $p.PnPCapabilities) -band $BM_PNP_POWER) -ne 0 }
        if ($p -and 'FeatureTestControl' -in $p.PSObject.Properties.Name) { $f = U32 $p.FeatureTestControl; $IDP = ($f -band $BM_DPST) -ne 0; $IDR = ($f -band $BM_PSR) -ne 0 }
        if ($p -and 'DisplayPowerSavings' -in $p.PSObject.Properties.Name) { $IDS = (U32 $p.DisplayPowerSavings) -eq 0 } else { $IDS = $false }
    }
} catch {}

# ── 优化项定义 ────────────────────────────────────────────
$O = @(); function AO($h) { $script:O += [PSCustomObject]$h }
$MM  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$GTP = "$MM\Tasks\Games"
$GRD = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'

# ── v5.0 网卡高级属性缓存 ────────────────────────────────
# Get-NetAdapterAdvancedProperty 单次约 60-90ms, 状态刷新时同一网卡会被查多次。
# 缓存后, 生成优化项 / QI 状态 / 诊断页面共用同一份结果。
$script:NIC_ADV_CACHE = @{}
function Get-TxNicAdvAll([string]$a) {
    if ($script:NIC_ADV_CACHE.ContainsKey($a)) { return $script:NIC_ADV_CACHE[$a] }
    $p = @()
    try { $p = @(Get-NetAdapterAdvancedProperty -Name $a -EA 0) } catch {}
    $script:NIC_ADV_CACHE[$a] = $p
    return $p
}
function Clear-TxNicAdvCache {
    $script:NIC_ADV_CACHE = @{}
}

foreach ($n in $NN) {
    $a = $AN | Where-Object Name -eq $n | Select-Object -First 1
    $w = $false
    if ($a) { $w = (($a.InterfaceType -eq 71) -or ($a.PhysicalMediaType -match '802.11|Native 802.11|Wireless')) }
    AO @{Id="nicp_$n";Cat='网络优化';Name="[$n] 禁止系统关闭网卡以省电";Kind='nicpower';A=$n;T=24;TL='禁止省电(24)';D='系统默认可关闭网卡省电 (改后需重启)';E=$true;R='low'}
    if ($w) {
        AO @{Id="mimo_$n";Cat='网络优化';Name="[$n] MIMO节能→无SMPS";Kind='nic';A=$n;K='MIMOPowerSaveMode';T='3';TL='无SMPS(3)';D='保持全部天线常开';E=$true;R='low'}
        AO @{Id="roam_$n";Cat='进阶可选';Name="[$n] Wi-Fi漫游主动性→中低";Kind='nic';A=$n;K='RoamAggressiveness';T='1';TL='中低(1)';D='单路由器可减少切换AP断流';E=$false;R='med'}
    }
}

# ★ v5.0: 网络进阶项 —— 按驱动实际能力生成, 没有该属性就不出现; 默认不勾选
foreach ($n in $NN) {
    $props = @(Get-TxNicAdvAll $n)
    if (!$props.Count) { continue }
    $specs = @(
        @{Id='eee';    KeyPats=@('*EnergyEfficient*','*GreenEthernet*','*UltraLowPower*'); KeyRegex='(?i)(^|[^I])EEE([^E]|$)'; DispPat='(?i)节能以太网|Energy Efficient|Green Ethernet'; Name='关闭节能以太网 (EEE)'; D='避免链路空闲降速, 降低延迟抖动'},
        @{Id='intmod'; KeyPats=@('*InterruptModeration*');                                          DispPat='(?i)中断节流|Interrupt Moderation';      Name='关闭网络中断节流';       D='降低中断延迟, 会增加少量CPU占用'},
        @{Id='flow';   KeyPats=@('*FlowControl*');                                                  DispPat='(?i)流控|Flow Control';                  Name='关闭以太网流控';         D='避免交换机流控造成突发延迟'}
    )
    $used = @{}
    foreach ($sp in $specs) {
        $hit = $props | Where-Object {
            $k = [string]$_.RegistryKeyword
            $dn = [string]$_.DisplayName
            $keyHit = $false
            foreach ($pat in $sp.KeyPats) { if ($k -like $pat) { $keyHit = $true; break } }
            if (!$keyHit -and $sp.KeyRegex -and $k -match $sp.KeyRegex) { $keyHit = $true }
            $keyHit -or ($dn -and $dn -match $sp.DispPat)
        } | Select-Object -First 1
        if (!$hit -or !$hit.RegistryKeyword) { continue }
        if ($used.ContainsKey([string]$hit.RegistryKeyword)) { continue }
        $used[[string]$hit.RegistryKeyword] = $true
        $off = Get-NicOffValue $hit
        if ($null -eq $off) { continue }
        AO @{Id="net_$($sp.Id)_$n";Cat='网络进阶';Name="[$n] $($sp.Name)";Kind='nic';A=$n;K=$hit.RegistryKeyword;T=$off;TL='关闭';D=$sp.D;E=$false;R='med'}
    }
}
AO @{Id='tcpoffload';Cat='网络优化';Name='禁用TCP任务卸载';Kind='reg';P='HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters';V='DisableTaskOffload';VT='DWord';T=1;TL='禁用(1)';D='让CPU直接处理TCP校验 (需重启)';E=$true;R='low'}
# ★ v4.8: UAC 提权后 HKCU 可能指向管理员账户, 统一写启动者 SID 的 HKCU
AO @{Id='gdvr1';Cat='游戏录制';Name='关闭后台录制 (GameDVR)';Kind='reg';P="$HKU_BASE\System\GameConfigStore";V='GameDVR_Enabled';VT='DWord';T=0;TL='关闭(0)';D='后台录制占用GPU编码单元';E=$true;R='low'}
AO @{Id='gdvr2';Cat='游戏录制';Name='关闭后台捕获 (AppCapture)';Kind='reg';P="$HKU_BASE\Software\Microsoft\Windows\CurrentVersion\GameDVR";V='AppCaptureEnabled';VT='DWord';T=0;TL='关闭(0)';D='游戏栏后台捕获';E=$true;R='low'}
AO @{Id='gdvr3';Cat='游戏录制';Name='关闭回顾录制';Kind='reg';P="$HKU_BASE\Software\Microsoft\Windows\CurrentVersion\GameDVR";V='HistoricalCaptureEnabled';VT='DWord';T=0;TL='关闭(0)';D='常驻缓存最近画面';E=$true;R='low'}
$gbh = '[未安装]'
if ($GBI) { $gbh = '[已安装但未启用]'; if ($GBE) { $gbh = '[已安装且已启用]' } }
AO @{Id='gbarcompact';Cat='游戏录制';Name='Game Bar 紧凑模式';Kind='reg';P="$HKU_BASE\Software\Microsoft\GameBar";V='UseCompactMode';VT='DWord';T=1;TL='开启(1)';D="减少浮窗资源占用. $gbh";E=$true;R='low'}
# ★ v4.8: HAGS 是 WDDM 2.7+ 的通用能力, 不再只对 Intel 开放
if ($GREAL.Count -gt 0 -and [Environment]::OSVersion.Version.Build -ge 19041) {
    AO @{Id='hags';Cat='GPU调度';Name='开启硬件GPU调度 (HAGS)';Kind='reg';P=$GRD;V='HwSchMode';VT='DWord';T=2;TL='开启(2)';D="GPU自管理显存调度, 适用于 $(@($GREAL.Vendor | Select-Object -Unique) -join '/') (需重启)";E=$true;R='low'}
}
foreach ($d in $DI) {
    if ($d.MR -gt $d.RR) {
        AO @{Id="disprr_$($d.ID)";Cat='显示刷新率';Name="$($d.DN)[$($d.DID)] 刷新率→$($d.MR)Hz";Kind='display';DID=$d.DID;DN=$d.DN;RR=$d.RR;MR=$d.MR;W=$d.W;H=$d.H;TL="$($d.MR)Hz";D="当前$($d.RR)Hz, 最高$($d.MR)Hz";Dep='drr_off';DH='建议同时勾选「禁止DRR」';E=$true;R='low'}
    }
}
AO @{Id='drr_off';Cat='显示刷新率';Name='禁止动态刷新率 (DRR)';Kind='drr';T=0;TL='禁用(0)';D='DRR自动降刷新率省电 (需重启)';E=$true;R='low'}
AO @{Id='nthr';Cat='网络优化';Name='禁用多媒体网络节流';Kind='reg';P=$MM;V='NetworkThrottlingIndex';VT='DWord';T=4294967295;TL='禁用(0xFFFFFFFF)';D='默认值10限制网络吞吐';E=$true;R='low'}
AO @{Id='sresp';Cat='网络优化';Name='系统响应度→10';Kind='reg';P=$MM;V='SystemResponsiveness';VT='DWord';T=10;TL='10';D='更多CPU时间片分给前台游戏';E=$true;R='low'}
AO @{Id='gprio';Cat='调度优先级';Name='游戏CPU优先级→High';Kind='reg';P=$GTP;V='Priority';VT='DWord';T=6;TL='High(6)';D='提升游戏进程CPU调度优先级';E=$true;R='low'}
AO @{Id='gsched';Cat='调度优先级';Name='游戏调度类别→High';Kind='reg';P=$GTP;V='Scheduling Category';VT='String';T='High';TL='High';D='MMCSS调度类别';E=$true;R='low'}
AO @{Id='gsfio';Cat='调度优先级';Name='游戏磁盘IO优先级→High';Kind='reg';P=$GTP;V='SFIO Priority';VT='String';T='High';TL='High';D='提升游戏读盘IO优先级';E=$true;R='low'}
AO @{Id='pusb';Cat='电源与供电';Name='禁用USB选择性暂停';Kind='power';SK='SUB_USB';SE='USBSEL';AC=0;DC=0;TL='禁用(AC+DC)';D='USB外设空闲休眠致卡顿';E=$true;R='low'}
AO @{Id='paspm';Cat='电源与供电';Name='PCIe ASPM→关闭';Kind='power';SK='SUB_PCI';SE='ASPM';AC=0;DC=0;TL='关闭(0)';D='NVMe固态降速致延迟尖峰';E=$true;R='low'}
AO @{Id='ppmax';Cat='电源与供电';Name='最大处理器状态→100%';Kind='power';SK='SUB_PROC';SE='PMAX';AC=100;DC=100;TL='100%';D='确保CPU不被限频';E=$true;R='low'}
# ★ v5.0: 核心停车 —— 部分游戏/模拟器对核心唤醒延迟敏感, 可选关闭 (仅建议插电时使用)
AO @{Id='cpark';Cat='进阶可选';Name='关闭CPU核心停车 (AC+DC)';Kind='power';SK='SUB_PROC';SE='CPMINCORES';AC=100;DC=100;TL='100% (不停车)';D='减少核心唤醒延迟, 会增加空闲功耗 (可选)';E=$false;R='med'}
# ★ v4.8: 没有无线网卡的台式机不再出现该项 (避免必然失败)
if ($HAS_WIFI) { AO @{Id='pwlan';Cat='电源与供电';Name='无线适配器节能→最高性能';Kind='power';SK='SUB_WL';SE='WLSAVE';AC=0;DC=0;TL='最高性能(0)';D='防无线网卡空闲降功率';E=$true;R='low'} }
AO @{Id='psch';Cat='电源与供电';Name='切换到「卓越性能」电源方案';Kind='scheme';TG='ULTIMATE';TL='卓越性能';D='比高性能更激进';E=$false;R='med'}
# ★ v4.8: 只要系统中存在 Intel 遥测服务就允许停用, 不再要求 Intel 显卡
if ($ITS.Count -gt 0) { AO @{Id='itel';Cat='进阶可选';Name='停用Intel遥测/监控服务';Kind='svc';SV=$ITS;T='Manual';TL='停用(改手动)';D='ESRV/Collector/DSA等后台遥测';E=$false;R='med'} }
# ★ v4.8: 只有"笔记本 + 真实独显"才出现, 修复 AMD APU 被当成独显的问题
if ($CMB) { AO @{Id='gpupref';Cat='GPU调度';Name='笔记本游戏强制独显运行';Kind='gpupref';T='2';TL='高性能独显';D='强制DWM使用独显';E=$true;R='low'} }
# ★ v4.8: 独显专属项 —— 只在检测到真实独显时出现; 纯核显机器不生成任何独显项
foreach ($dg in @($GPU | Where-Object { $_.Dedicated -and $_.RegKey })) {
    $dgDefE = $true
    if ($IL) { $dgDefE = $false }   # 笔记本默认不勾选: 独显常开会增加功耗/温度
    AO @{Id="dgpupnp_$($dg.KeyId)";Cat='独显优化';Name="[$($dg.Name)] 禁止系统关闭独显以省电";Kind='gpupnp';SK=$dg.RegKey;BM=$BM_PNP_POWER;TL='禁止省电(bit3+4)';D='防止独显被系统断电, 减少唤醒卡顿/掉驱动 (笔记本会增加功耗)';E=$dgDefE;R='med'}
}
foreach ($ng in @($GPU | Where-Object { $_.Vendor -eq 'NVIDIA' -and $_.Dedicated -and $_.RegKey })) {
    AO @{Id="nvpstate_$($ng.KeyId)";Cat='NVIDIA独显';Name="[$($ng.Name)] 禁用动态P-State（锁高频）";Kind='reg';P=$ng.RegKey;V='DisableDynamicPstate';VT='DWord';T=1;TL='禁用(1)';D='减少频率切换造成的帧率波动; 会增加空闲功耗/温度, 部分新驱动可能忽略 (可选, 需重启)';E=$false;R='med'}
}
# ★ v4.8: Intel 专属项只对 Intel 核显开放; Arc 独显 / AMD / 高通机器不再误显示
if ($II) {
    AO @{Id='igpupwr';Cat='Intel核显稳定性';Name='禁止Intel核显省电 (防掉驱动)';Kind='intelpnp';BM=$BM_PNP_POWER;TL='禁止省电(bit3+4)';D='防止系统关闭核显致掉驱动 (需重启)';E=$true;R='low'}
    AO @{Id='idpst';Cat='Intel核显稳定性';Name='禁用Intel DPST显示器节能';Kind='intelftc';BM=$BM_DPST;BL='bit4';TL='禁用DPST';D='防止亮度动态调整引发驱动异常 (需重启)';E=$true;R='low'}
    AO @{Id='ipsr';Cat='Intel核显稳定性';Name='禁用Intel面板自刷新 (PSR)';Kind='intelftc';BM=$BM_PSR;BL='bit31';TL='禁用PSR';D='防止核显停止输出致随机黑屏 (需重启)';E=$true;R='low'}
    AO @{Id='idps';Cat='Intel核显稳定性';Name='关闭Intel Display Power Savings';Kind='inteldps';T=0;TL='关闭(0)';D='防止显示省电降低信号质量致闪屏 (需重启)';E=$true;R='low'}
}
# ★ v4.8 新增: AMD ULPS 深度省电是真实驱动项, 空闲时可能让显卡彻底断电,
#   多屏/高刷下偶发黑屏闪烁。默认不勾选, 需要时手动开启。
foreach ($ag in @($GPU | Where-Object { $_.Vendor -eq 'AMD' -and $_.Dedicated -and $_.RegKey })) {
    AO @{Id="amdulps_$($ag.KeyId)";Cat='AMD显卡';Name="[$($ag.Name)] 禁用AMD ULPS深度省电";Kind='reg';P=$ag.RegKey;V='EnableUlps';VT='DWord';T=0;TL='禁用(0)';D='ULPS空闲断电, 多屏/高刷可能随机黑屏 (可选, 需重启)';E=$false;R='med'}
}
# ★ v4.8: TDR/pnpclean 与显卡厂商无关, 从"Intel核显稳定性"中独立出来
AO @{Id='tdrdelay';Cat='显卡稳定性';Name='TDR超时→8秒 (防驱动重置黑屏)';Kind='tdrdelay';T=8;TL='8秒';D='NVIDIA/AMD/Intel 通用, 默认2秒太短';E=$true;R='low'}
AO @{Id='pnpclean';Cat='系统驱动';Name='禁用pnpclean自动清理驱动包';Kind='pnpclean';T=0;TL='禁用(0)';D='阻止系统自动删除驱动包';E=$true;R='low'}

# ★ v4.7: 原 diagtrack_q / dmwap_q (svcquota) 已移除
#   原因: DiagTrack 寄生在 svchost.exe -k utcsvc 内, 降 svchost 优先级会牵连同组其它服务;
#         维持任务按进程名 "DiagTrack" 查找, 但该进程名根本不存在(实测);
#         Services\<name>\Priority 不是 SCM 认可的配置项, 写了也不生效。
#   现状: DiagTrack 保持系统默认(自动+运行中), 这是正确状态, 禁用它反而会导致 UI 卡顿。
$DMWAP_REG = 'HKLM:\SYSTEM\CurrentControlSet\Services\dmwappushservice'
$dmwapResid = $false
try { $dw = Get-ItemProperty $DMWAP_REG -EA 0; if ($dw -and 'DelayedAutoStart' -in $dw.PSObject.Properties.Name -and [int]$dw.DelayedAutoStart -eq 1) { $dmwapResid = $true } } catch {}
if ($dmwapResid) {
    AO @{Id='dmwap_resid';Cat='系统遥测';Name='清理 dmwappushservice 残留延迟启动标记';Kind='regdel';P=$DMWAP_REG;V='DelayedAutoStart';TL='移除残留值';D='旧版脚本遗留, Manual 启动类型下该值无意义';E=$false;R='low'}
}

# 内存与存储优化
AO @{Id='prefetch';Cat='内存与存储';Name='关闭Prefetch/Superfetch预取';Kind='reg2';P='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters';V='EnableSuperfetch';V2='EnablePrefetcher';VT='DWord';T=0;T2=0;TL='两者均关闭(0)';D='SSD用户关闭预取减少IO占用';E=$false;R='med'}
AO @{Id='vismfx';Cat='内存与存储';Name='关闭视觉特效动画';Kind='reg';P="$HKU_BASE\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects";V='VisualFXSetting';VT='DWord';T=2;TL='最佳性能(2)';D='关闭窗口动画/阴影等视觉特效';E=$false;R='med'}
AO @{Id='bgapp';Cat='内存与存储';Name='禁止后台应用运行';Kind='reg';P="$HKU_BASE\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications";V='GlobalUserDisabled';VT='DWord';T=1;TL='禁用(1)';D='阻止UWP后台运行释放内存';E=$true;R='low'}

# ★ v4.7: 已移除 nvll / nvthread / amdrsm
#   原因: LowLatencyTip、DisableCudaDumpPreemption、RadeonAntiLag 都不是真实的驱动配置项,
#         而且写在显示类键的根上(驱动读的是 0000/0001 实例子键), 写进去纯属安慰剂。
#   NVIDIA 低延迟模式的正确入口是 NVIDIA 控制面板的每程序配置(驱动 DRS), 不在注册表。

# ── 通用引擎 ─────────────────────────────────────────────
function GRV($p, $n) {
    try {
        if (-not $p -or -not (Test-Path $p)) { return @{E=$false;V=$null} }
        $o = Get-ItemProperty $p -EA 0
        if ($o -and $n -in $o.PSObject.Properties.Name) { return @{E=$true;V=$o.$n} }
        return @{E=$false;V=$null}
    } catch { return @{E=$false;V=$null} }
}
function SRV($p, $n, $v, $t) {
    # ★ v5.0: 预览模式只计算不写盘
    if ($script:DRY) { return }
    try {
        if (-not $p) { throw "路径为空" }
        if (!$t) { $t = 'DWord' }
        if (-not (Test-Path $p)) { New-Item $p -Force -EA Stop | Out-Null }
        # ★ v4.8: DWORD 必须转成 Int32 再写, 否则 0x80000000/0xFFFFFFFF 会溢出失败
        $val = $v
        if ($t -eq 'DWord') { $val = I32 $v }
        New-ItemProperty $p -Name $n -Value $val -PropertyType $t -Force -EA Stop | Out-Null
    } catch { throw "写注册表失败[$n]: $($_.Exception.Message)" }
}
# ★ v4.7 兼容层: 旧备份(9/6~9/10共18个)用的字段名是 Adapter/Keyword/SubKey/Path/Services/Name,
#   新代码用 A/K/SK/P/SV/V。还原时两种都接受, 否则还原会静默什么都不做。
function RFLD($r, [string[]]$names) {
    foreach ($n in $names) {
        if ($null -ne $r.$n) { return $r.$n }
    }
    return $null
}

$RC = @{
    'reg'  = @{P={$args[0].P};N={$args[0].V};T={$args[0].VT}}
    'reg2' = @{P={$args[0].P};N={$args[0].V};T={$args[0].VT}}
    'drr'  = @{P={'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'};N={'DrrMigrationControl'};T={'DWord'}}
    'pnpclean' = @{P={'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Device Driver Packages'};N={'Autorun'};T={'DWord'}}
}

function GNS($a, $k) {
    try {
        $p = @(Get-TxNicAdvAll $a) | Where-Object { [string]$_.RegistryKeyword -eq [string]$k } | Select-Object -First 1
        if ($p) { return @{E=$true;V=$p.RegistryValue;D=$p.DisplayValue} }
        return @{E=$false;V=$null;D=$null}
    } catch { return @{E=$false;V=$null;D=$null} }
}
# ★ v5.0: 网卡高级属性写入包装, 预览模式下不调用 cmdlet
function SNAP($a, $k, $v) {
    if ($script:DRY) { return }
    Set-NetAdapterAdvancedProperty -Name $a -RegistryKeyword $k -RegistryValue $v -EA Stop
    # 写入后让该网卡的属性缓存失效, 下一次状态查询拿到新值
    if ($script:NIC_ADV_CACHE.ContainsKey($a)) { [void]$script:NIC_ADV_CACHE.Remove($a) }
}
$NCK = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}'
$script:NIC_REG_CACHE = @{}
function GNPR($a) {
    # v5.0: 网卡名 -> 注册表子键的解析结果缓存, 避免每次状态查询都扫一遍类键
    if ($script:NIC_REG_CACHE.ContainsKey($a)) { return $script:NIC_REG_CACHE[$a] }
    $found = $null
    # ★ v4.8: Get-NetAdapter 的 InterfaceGuid 本身已带 {大括号},
    #   原代码再包一层会变成 {{...}}, 与注册表值永远不相等 -> 日志里的"无法定位网卡注册表子键"
    try {
        $nic = Get-NetAdapter -Name $a -EA 0 | Select-Object -First 1
        if ($nic) {
            $g   = NGUID $nic.InterfaceGuid
            $d   = [string]$nic.InterfaceDescription
            $pnp = NGUID $nic.PnPDeviceID
            foreach ($s in (Get-ChildItem $NCK -EA 0)) {
                if ($s.PSChildName -notmatch '^\d{4}$') { continue }
                $p = Get-ItemProperty $s.PSPath -EA 0
                if (!$p) { continue }
                if (($g -and (NGUID $p.NetCfgInstanceId) -eq $g) -or
                    ($pnp -and (NGUID $p.DeviceInstanceID) -eq $pnp) -or
                    ($d -and $p.DriverDesc -eq $d)) { $found = $s.PSPath; break }
                # 兼容 "Remote NDIS Compatible Device #2" 这类带编号后缀的描述
                if ($d -and $p.DriverDesc -and $d.StartsWith([string]$p.DriverDesc, [StringComparison]::OrdinalIgnoreCase)) { $found = $s.PSPath; break }
            }
        }
    } catch {}
    $script:NIC_REG_CACHE[$a] = $found
    return $found
}
function GNPS($a) {
    $r = GNPR $a
    if ($r) {
        try {
            $p = Get-ItemProperty $r -Name PnPCapabilities -EA 0
            if ($p -and 'PnPCapabilities' -in $p.PSObject.Properties.Name) { return @{E=$true;V=(U32 $p.PnPCapabilities);R=$r;O=$true;PM=$false} }
            return @{E=$true;V=[uint32]0;R=$r;O=$false;PM=$false}
        } catch { return @{E=$true;V=[uint32]0;R=$r;O=$false;PM=$false} }
    }
    # 注册表找不到时, 用受支持的电源管理命令兜底
    try {
        $pm = Get-NetAdapterPowerManagement -Name $a -EA 0
        if ($pm -and 'AllowComputerToTurnOffDevice' -in $pm.PSObject.Properties.Name) {
            $v = [uint32]0
            if ([string]$pm.AllowComputerToTurnOffDevice -eq 'Disabled') { $v = [uint32]24 }
            return @{E=$true;V=$v;R=$null;O=$false;PM=$true}
        }
    } catch {}
    return @{E=$false;V=$null;R=$null;O=$false;PM=$false}
}
function SNPR($r, $v, $adapter) {
    if ($script:DRY) { return }
    $ok = $false
    $nv = U32 $v
    if ($r) {
        try {
            if ($nv -eq 0) { Remove-ItemProperty $r -Name PnPCapabilities -Force -EA 0 }
            else { New-ItemProperty $r -Name PnPCapabilities -Value (I32 $nv) -PropertyType DWord -Force -EA Stop | Out-Null }
            $ok = $true
        } catch { Log "写网卡注册表失败: $($_.Exception.Message)" 'Red' }
    }
    if (!$ok -and $adapter) {
        try {
            if ($nv -ne 0) { Disable-NetAdapterPowerManagement -Name $adapter -EA Stop | Out-Null }
            else { Enable-NetAdapterPowerManagement -Name $adapter -EA Stop | Out-Null }
            $ok = $true
        } catch { Log "网卡电源管理命令失败: $($_.Exception.Message)" 'Red' }
    }
    if (!$ok) { throw "该网卡不支持 PnPCapabilities, 也没有可用的电源管理接口" }
}

function GSS($ns) {
    $m = @{}
    $startMap = @{ 0='Boot'; 1='System'; 2='Automatic'; 3='Manual'; 4='Disabled' }
    foreach ($n in $ns) {
        try {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$n"
            if (Test-Path $regPath) {
                $props = Get-ItemProperty $regPath -EA 0
                $stVal = 3
                if ($props -and 'Start' -in $props.PSObject.Properties.Name) { $stVal = [int]$props.Start }
                $st = 'Manual'
                if ($startMap.ContainsKey($stVal)) { $st = $startMap[$stVal] }
                # v5.0: 用 Get-Service 代替 sc.exe, 避免每个服务启动一次进程 (原 itel 项状态查询约 277ms)
                $svc = Get-Service -Name $n -EA 0
                $svcStatus = 'Stopped'
                if ($svc -and $svc.Status -eq 'Running') { $svcStatus = 'Running' }
                $m[$n] = @{S=$svcStatus;T=$st}
            }
        } catch {}
    }
    return $m
}
function SMT2V($v) { $map = @{'Automatic'=2;'Manual'=3;'Disabled'=4;'Boot'=0;'System'=1}; $sv = [string]$v; if ($map.ContainsKey($sv)) { return $map[$sv] }; if ($sv -match '^\d+$') { return [int]$sv }; return 3 }

function GIPP { if (!$ISK) { return @{E=$false;V=$null;R=$null} }; $s = GRV $ISK 'PnPCapabilities'; $v = [uint32]0; if ($s.E) { $v = U32 $s.V }; return @{E=$true;V=$v;R=$ISK} }
function GIFSAt($k) { return (GRV $k 'FeatureTestControl') }
function GIFS { if (!$ISK) { return @{E=$false;V=$null} }; $r = GIFSAt $ISK; if ($r.E) { $r.V = U32 $r.V }; return $r }
function GIDS { if (!$ISK) { return @{E=$false;V=$null} }; return (GRV $ISK 'DisplayPowerSavings') }

$PW = @{
    SUB_PCI='501a4d13-42af-4429-9fd1-a8218c268e20'; ASPM='ee12f906-d277-404b-b6da-e5fa1a576df5'
    SUB_USB='2a737441-1930-4402-8d77-b2bebba308a3'; USBSEL='48e6b7a6-50f5-4782-a5d4-53bb8f07e226'
    SUB_PROC='54533251-82be-4824-96c1-47b60b740d00'; PMIN='893dee8e-2bef-41e0-89c6-b55d0929964c'; PMAX='bc5038f7-23e0-4960-96da-33abaf5935ec'
    CPMINCORES='0cc5b647-c1df-4637-891a-dec35c318583'
    SUB_WL='19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'; WLSAVE='12bbebe6-58d6-4636-95bb-3217ef867c1a'
    ULTIMATE='e9a42b02-d5df-448d-aa00-03f14749eb61'
}
function RPC([string[]]$a) {
    $pv = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = & powercfg $a 2>$null | ForEach-Object { $_.ToString() } | Out-String; return [PSCustomObject]@{X=$LASTEXITCODE;O=$o} }
    finally { $ErrorActionPreference = $pv }
}
function GPCI($s, $e) {
    # ★ v4.7: 原用 [Convert]::ToInt32(hex), 遇 0xFFFFFFFF 会抛 OverflowException → 改 UInt32
    $r = RPC @('/q','SCHEME_CURRENT',$s,$e)
    if ($r.X) { return @{Ok=$false} }
    $a = $null; $d = $null
    try { if ($r.O -match '(?m)(?:当前交流|Current AC)\s*[^:]*:\s*0x([0-9A-Fa-f]+)') { $a = [uint32][Convert]::ToUInt32($Matches[1],16) } } catch {}
    try { if ($r.O -match '(?m)(?:当前直流|Current DC)\s*[^:]*:\s*0x([0-9A-Fa-f]+)') { $d = [uint32][Convert]::ToUInt32($Matches[1],16) } } catch {}
    if ($null -eq $a -and $null -eq $d) { return @{Ok=$false} }
    return @{Ok=$true;AC=$a;DC=$d}
}
function SPCI($s, $e, $a, $d) {
    if ($script:DRY) { return }
    if ($null -ne $a) { if ((RPC @('/setacvalueindex','SCHEME_CURRENT',$s,$e,[string]$a)).X) { throw "setacvalueindex 失败" } }
    if ($null -ne $d) { if ((RPC @('/setdcvalueindex','SCHEME_CURRENT',$s,$e,[string]$d)).X) { throw "setdcvalueindex 失败" } }
    if ((RPC @('/setactive','SCHEME_CURRENT')).X) { throw "setactive 失败" }
}
function GASG { $r = RPC @('/getactivescheme'); if ($r.O -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})') { return $Matches[1].ToLower() } else { return $null } }

# ★ v4.7: 原名 GSN 被内置别名 gsn(=Get-PSSession) 遮蔽 → 改名 SCHNM
function SCHNM($g) {
    if (!$g) { return '未知' }
    $builtin = @{
        'e9a42b02-d5df-448d-aa00-03f14749eb61' = '卓越性能'
        '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' = '高性能'
        '381b4222-f694-41f0-9685-ff5bb260df2e' = '平衡'
        'a1841308-3541-4fab-bc81-f71556f20b4a' = '节能'
    }
    $gl = $g.ToLower()
    if ($builtin.ContainsKey($gl)) { return $builtin[$gl] }
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$g"
        if (Test-Path $regPath) {
            $props = Get-ItemProperty $regPath -EA 0
            if ($props -and 'FriendlyName' -in $props.PSObject.Properties.Name -and $props.FriendlyName) { return $props.FriendlyName }
            if ($props -and 'Description'   -in $props.PSObject.Properties.Name -and $props.Description)   { return $props.Description }
        }
    } catch {}
    $short = $g
    if ($g.Length -ge 8) { $short = $g.Substring(0,8) }
    return "自定义方案($short)"
}

function SDRR($dn, $f) {
    if ($script:DRY) { return @{Ok=$true;Msg='预览模式未实际切换'} }
    ECS
    if (-not $script:CS) { throw "显示API未就绪" }
    $dm = New-Object DS_DEVMODE
    $dm.dmSize = [int16][Runtime.InteropServices.Marshal]::SizeOf([type][DS_DEVMODE])
    if ([DS]::EnumDisplaySettings($dn, [DS]::ENUM_CURRENT_SETTINGS, [ref]$dm) -eq 0) { throw "EnumDisplaySettings 失败 (设备名: $dn)" }
    if ([int]$dm.dmDisplayFrequency -eq [int]$f) { return @{Ok=$true;Msg='已是目标值'} }
    $dm.dmFields = [DS]::DM_DISPLAYFREQUENCY
    $dm.dmDisplayFrequency = [int]$f
    # ★ v4.7: 先用 CDS_TEST 预检, 避免把屏幕切到不支持的模式
    $test = [DS]::ChangeDisplaySettingsEx($dn, [ref]$dm, [IntPtr]::Zero, [DS]::CDS_TEST, [IntPtr]::Zero)
    if ($test -ne 0) { throw "预检未通过 (DISP_CHANGE=$test)" }
    $ret = [DS]::ChangeDisplaySettingsEx($dn, [ref]$dm, [IntPtr]::Zero, [DS]::CDS_UPDATEREGISTRY, [IntPtr]::Zero)
    # DISP_CHANGE: 0=SUCCESS 1=RESTART -1=FAILED -2=BADMODE -3=BADFLAGS -4=BADPARAM -5=NOTUPDATED
    $msg = switch ($ret) {
        0  { '成功' }
        1  { '成功(需注销或重启生效)' }
        -1 { throw '失败 (DISP_CHANGE_FAILED)' }
        -2 { throw '模式不被支持 (DISP_CHANGE_BADMODE)' }
        -3 { throw '标志无效 (DISP_CHANGE_BADFLAGS)' }
        -4 { throw '参数无效 (DISP_CHANGE_BADPARAM)' }
        -5 { throw '未能写入注册表 (DISP_CHANGE_NOTUPDATED)' }
        default { throw "未知返回码: $ret" }
    }
    Start-Sleep -Milliseconds 1500
    $dm2 = New-Object DS_DEVMODE
    $dm2.dmSize = $dm.dmSize
    if ([DS]::EnumDisplaySettings($dn, [DS]::ENUM_CURRENT_SETTINGS, [ref]$dm2) -ne 0) {
        if ([int]$dm2.dmDisplayFrequency -ne [int]$f -and $ret -eq 0) {
            Log "刷新率验证失败, 回退到 $($dm.dmDisplayFrequency)Hz" 'Red'
            throw "刷新率验证失败 (读回 $($dm2.dmDisplayFrequency)Hz)"
        }
    }
    return @{Ok=$true;Msg=$msg}
}

# ── KindHandlers ─────────────────────────────────────────
$KH = @{
    # ★ v4.7 新增: reg / reg2 / regdel / drr / pnpclean 处理器
    #   原脚本 $RC 里有 reg/drr/pnpclean 的映射, 但 $KH 里没注册,
    #   导致 19 项优化应用时直接抛"未注册Kind" —— 全部从未生效。
    reg = @{
        A = { param($it)
            $p = & $RC['reg'].P $it
            $n = & $RC['reg'].N $it
            $t = & $RC['reg'].T $it
            if (!$t) { $t = 'DWord' }
            $o = GRV $p $n
            $ov = $null
            if ($o.E) { $ov = $o.V }
            SRV $p $n $it.T $t
            return @{Id=$it.Id;Kind='reg';P=$p;V=$n;VT=$t;OV=$ov;OE=$o.E}
        }
        R = { param($r)
            $p = RFLD $r @('P','Path')
            $n = RFLD $r @('V','Name','Value')
            if (!$p -or !$n) { Log "[还原跳过] $($r.Id): 备份缺少路径或值名" 'Yellow'; return }
            $t = RFLD $r @('VT','Type')
            if (!$t) { $t = 'DWord' }
            $oe = RFLD $r @('OE')
            $ov = RFLD $r @('OV')
            if ($oe -and $null -ne $ov) { SRV $p $n $ov $t }
            else { try { Remove-ItemProperty $p -Name $n -Force -EA 0 } catch {} }
        }
    }

    reg2 = @{
        A = { param($it)
            $o1 = GRV $it.P $it.V
            $o2 = GRV $it.P $it.V2
            $v1 = $null; if ($o1.E) { $v1 = $o1.V }
            $v2 = $null; if ($o2.E) { $v2 = $o2.V }
            SRV $it.P $it.V  $it.T  $it.VT
            SRV $it.P $it.V2 $it.T2 $it.VT
            return @{Id=$it.Id;Kind='reg2';P=$it.P;V=$it.V;V2=$it.V2;VT=$it.VT;OV=$v1;OV2=$v2;OE=$o1.E;OE2=$o2.E}
        }
        R = { param($r)
            $p = RFLD $r @('P','Path')
            if (!$p) { return }
            $n1 = RFLD $r @('V','Name');  $n2 = RFLD $r @('V2','Name2')
            $t = RFLD $r @('VT','Type'); if (!$t) { $t = 'DWord' }
            if ($n1) {
                if ($r.OE -and $null -ne $r.OV) { SRV $p $n1 $r.OV $t } else { try { Remove-ItemProperty $p -Name $n1 -Force -EA 0 } catch {} }
            }
            if ($n2) {
                if ($r.OE2 -and $null -ne $r.OV2) { SRV $p $n2 $r.OV2 $t } else { try { Remove-ItemProperty $p -Name $n2 -Force -EA 0 } catch {} }
            }
        }
    }

    regdel = @{
        A = { param($it)
            $o = GRV $it.P $it.V
            $ov = $null
            if ($o.E) { $ov = $o.V }
            # ★ v4.8: 值确实存在时才删除; 删除失败必须抛错, 不能静默报"成功"
            if ($o.E -and -not $script:DRY) {
                try { Remove-ItemProperty $it.P -Name $it.V -Force -EA Stop }
                catch { throw "删除注册表值失败[$($it.V)]: $($_.Exception.Message)" }
            }
            return @{Id=$it.Id;Kind='regdel';P=$it.P;V=$it.V;OV=$ov;OE=$o.E}
        }
        R = { param($r)
            $p = RFLD $r @('P','Path'); $n = RFLD $r @('V','Name')
            if (!$p -or !$n) { return }
            if ($r.OE -and $null -ne $r.OV) { SRV $p $n $r.OV 'DWord' }
        }
    }

    drr = @{
        A = { param($it)
            $p = & $RC['drr'].P $it
            $n = & $RC['drr'].N $it
            $o = GRV $p $n
            $ov = $null; if ($o.E) { $ov = $o.V }
            SRV $p $n $it.T 'DWord'
            return @{Id=$it.Id;Kind='drr';P=$p;V=$n;OV=$ov;OE=$o.E}
        }
        R = { param($r)
            $p = RFLD $r @('P','Path'); $n = RFLD $r @('V','Name')
            if (!$p) { $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' }
            if (!$n) { $n = 'DrrMigrationControl' }
            if ($r.OE -and $null -ne $r.OV) { SRV $p $n $r.OV 'DWord' }
            else { try { Remove-ItemProperty $p -Name $n -Force -EA 0 } catch {} }
        }
    }

    pnpclean = @{
        A = { param($it)
            $p = & $RC['pnpclean'].P $it
            $n = & $RC['pnpclean'].N $it
            $o = GRV $p $n
            $ov = $null; if ($o.E) { $ov = $o.V }
            SRV $p $n $it.T 'DWord'
            return @{Id=$it.Id;Kind='pnpclean';P=$p;V=$n;OV=$ov;OE=$o.E}
        }
        R = { param($r)
            $p = RFLD $r @('P','Path'); $n = RFLD $r @('V','Name')
            if (!$p) { $p = $PCR }
            if (!$n) { $n = 'Autorun' }
            if ($r.OE -and $null -ne $r.OV) { SRV $p $n $r.OV 'DWord' }
            else { try { Remove-ItemProperty $p -Name $n -Force -EA 0 } catch {} }
        }
    }

    svc = @{
        A = { param($it)
            $sb = @{}
            foreach ($n in $it.SV) {
                try {
                    $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$n"
                    if (Test-Path $svcReg) {
                        $props = Get-ItemProperty $svcReg -EA 0
                        $origStart = 3
                        if ($props -and 'Start' -in $props.PSObject.Properties.Name) { $origStart = [int]$props.Start }
                        $sb[$n] = [string]$origStart
                        if (-not $script:DRY) {
                            try { Stop-Service $n -Force -EA 0 } catch {}
                            $newVal = SMT2V $it.T
                            Set-ItemProperty $svcReg -Name Start -Value $newVal -Type DWord -Force -EA 0
                        }
                    }
                } catch { Log "[$n] 服务配置失败: $($_.Exception.Message)" 'Red' }
            }
            return @{Id=$it.Id;Kind='svc';SV=$sb}
        }
        R = { param($r)
            # ★ v4.7: 旧备份字段名是 Services(值为 "Disabled"/"Manual" 字符串),
            #   新备份是 SV(值为 "3"/"2" 数字字符串)。两种都要能还原。
            $map = RFLD $r @('SV','Services')
            if (!$map) { Log "[还原跳过] $($r.Id): 备份中无服务记录" 'Yellow'; return }
            foreach ($p in $map.PSObject.Properties) {
                $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$($p.Name)"
                $num = SMT2V $p.Value
                # ★ 安全闸: 旧备份把 DiagTrack 记为 Disabled, 还原它会重现"UI卡顿"问题
                if ($p.Name -eq 'DiagTrack' -and $num -eq 4) {
                    Log "[已拦截] DiagTrack 还原目标为「禁用」, 已跳过 (禁用会导致系统UI卡顿)" 'Yellow'
                    continue
                }
                try { Set-ItemProperty $svcReg -Name Start -Value $num -Type DWord -Force -EA 0; Log "  $($p.Name) Start→$num" 'Gray' }
                catch { Log "  $($p.Name) 还原失败: $($_.Exception.Message)" 'Red' }
            }
        }
    }

    # ★ v4.7: 仅保留还原能力(用于清理历史残留), 不再作为可选优化项提供
    svcquota = @{
        R = { param($r)
            $map = RFLD $r @('SV','Services')
            if (!$map) { return }
            foreach ($p in $map.PSObject.Properties) {
                $n = $p.Name
                try {
                    $svcReg = "HKLM:\SYSTEM\CurrentControlSet\Services\$n"
                    Remove-ItemProperty $svcReg -Name Priority -Force -EA 0
                    Remove-ItemProperty $svcReg -Name DelayedAutoStart -Force -EA 0
                    Unregister-ScheduledTask -TaskName "SvcQuota_$n" -Confirm:$false -EA 0
                    Log "[$n] 配额残留已清除" 'Green'
                } catch { Log "[$n] 清理失败: $($_.Exception.Message)" 'Red' }
            }
        }
    }

    power = @{
        A = { param($it)
            $ix = GPCI $PW[$it.SK] $PW[$it.SE]
            if (!$ix.Ok) { throw "powercfg读不到该电源项" }
            SPCI $PW[$it.SK] $PW[$it.SE] $it.AC $it.DC
            return @{Id=$it.Id;Kind='power';Sub=$PW[$it.SK];Set=$PW[$it.SE];OAC=$ix.AC;ODC=$ix.DC}
        }
        R = { param($r)
            try { SPCI $r.Sub $r.Set $r.OAC $r.ODC } catch { Log "还原电源失败: $($_.Exception.Message)" 'Red' }
        }
    }

    scheme = @{
        A = { param($it)
            $og = GASG
            if (!$og) { throw "无法读取当前方案GUID" }
            $ng = $PW[$it.TG]
            if ($og -eq $ng) { return @{Id=$it.Id;Kind='scheme';OG=$og;UC=$true} }
            if ($script:DRY) { return @{Id=$it.Id;Kind='scheme';OG=$og;UC=$false} }
            # ★ v4.7 修正: 原代码 duplicatescheme 后仍对"原GUID"执行 setactive,
            #   而 duplicatescheme 生成的是副本(新GUID), 原GUID不存在时必然失败。
            $target = $ng
            $chk = RPC @('/q',$ng)
            if ($chk.X -ne 0) {
                $dup = RPC @('/duplicatescheme',$ng)
                if ($dup.O -match '([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*\(([0-9a-fA-F\-]{36})\)') { $target = $Matches[2].ToLower() }
                elseif ($dup.O -match '(?m)^\s*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*$') { $target = $Matches[1].ToLower() }
                else { throw "复制电源方案失败: $($dup.O.Trim())" }
            }
            if ((RPC @('/setactive',$target)).X) { throw "切换到目标方案失败" }
            $now = GASG
            if ($now -ne $target) { throw "校验不一致: 期望 $target, 实际 $now" }
            return @{Id=$it.Id;Kind='scheme';OG=$og;NG=$target;UC=$false}
        }
        R = { param($r)
            if (!$r.UC -and $r.OG) { try { RPC @('/setactive',$r.OG) | Out-Null } catch {} }
        }
    }

    display = @{
        A = { param($it)
            $dn = RFLD $it @('DID')
            if (!$dn) { throw "缺少显示器设备名" }
            $r = SDRR $dn $it.MR
            return @{Id=$it.Id;Kind='display';DID=$dn;DN=$it.DN;RR=$it.RR;MR=$it.MR;W=$it.W;H=$it.H;Msg=$r.Msg}
        }
        R = { param($r)
            $dn = RFLD $r @('DID')
            if (!$dn) { return }
            try { SDRR $dn $r.RR | Out-Null } catch { Log "还原刷新率失败: $($_.Exception.Message)" 'Red' }
        }
    }

    gpupref = @{
        A = { param($it)
            try {
                $exe = 'C:\Windows\System32\dwm.exe'
                $ov = (Get-ItemProperty $URP -Name $exe -EA 0).$exe
                if (-not $script:DRY) {
                    if (!(Test-Path $URP)) { New-Item $URP -Force | Out-Null }
                    Set-ItemProperty $URP -Name $exe -Value 'GpuPreference=2' -Type String -Force
                }
                $oe = ($null -ne $ov -and $ov -ne '')
                return @{Id=$it.Id;Kind='gpupref';Exe=$exe;OV=$ov;OE=$oe}
            } catch { throw $_ }
        }
        R = { param($r)
            try {
                $exe = RFLD $r @('Exe')
                if (!$exe) { return }
                if ($r.OE -and $r.OV) { Set-ItemProperty $URP -Name $exe -Value $r.OV -Type String -Force }
                else { Remove-ItemProperty $URP -Name $exe -Force -EA 0 }
            } catch {}
        }
    }

    intelpnp = @{
        A = { param($it)
            if (!$ISK) { throw "无法定位Intel核显子键" }
            $o = GIPP
            $base = [uint32]0
            if ($o.E) { $base = U32 $o.V }
            $bm = U32 $it.BM
            $nv = [uint32]($base -bor $bm)
            # ★ v4.8: 只记录"本次新增的位", 还原时不会误清原本已设置的位
            $added = [uint32]($bm -band ($U32_ALL -bxor $base))
            SRV $ISK 'PnPCapabilities' $nv 'DWord'
            $ov = $null; if ($o.E) { $ov = $o.V }
            return @{Id=$it.Id;Kind='intelpnp';BM=$it.BM;AB=$added;OV=$ov;OE=$o.E;SK=$ISK}
        }
        R = { param($r)
            # ★ v4.8: 旧备份的字段名是 Path, 不是 SK/SubKey
            $sk = RFLD $r @('SK','SubKey','Path')
            if (!$sk) { Log "[还原跳过] $($r.Id): 备份缺少子键路径" 'Yellow'; return }
            $bm = RFLD $r @('BM')
            # ★ v4.8: 新备份优先用 AB(本次新增位); 旧备份无 AB 时退回整掩码清除
            $ab = RFLD $r @('AB')
            if ($null -eq $ab) { $ab = $bm }
            if ($null -ne $ab) {
                # ★ v4.7: 按位清除, 不影响同一值上的其它优化位
                $o = GRV $sk 'PnPCapabilities'
                $cur = [uint32]0
                if ($o.E) { $cur = U32 $o.V }
                $nv = [uint32]($cur -band ($U32_ALL -bxor (U32 $ab)))
                SRV $sk 'PnPCapabilities' $nv 'DWord'
                Log ("  {0}: PnPCapabilities 0x{1:X} -> 0x{2:X}" -f $r.Id, $cur, $nv)
            } elseif ($r.OE -and $null -ne $r.OV) {
                SRV $sk 'PnPCapabilities' $r.OV 'DWord'
            } else {
                try { Remove-ItemProperty $sk -Name PnPCapabilities -Force -EA 0 } catch {}
            }
        }
    }

    # ★ v4.8: 独显电源管理 —— 与 intelpnp 同语义, 但子键来自项本身(每块独显独立)
    gpupnp = @{
        A = { param($it)
            $sk = $it.SK
            if (!$sk) { throw "缺少独显子键路径" }
            $o = GRV $sk 'PnPCapabilities'
            $base = [uint32]0
            if ($o.E) { $base = U32 $o.V }
            $bm = U32 $it.BM
            $nv = [uint32]($base -bor $bm)
            $added = [uint32]($bm -band ($U32_ALL -bxor $base))
            SRV $sk 'PnPCapabilities' $nv 'DWord'
            $ov = $null; if ($o.E) { $ov = $o.V }
            return @{Id=$it.Id;Kind='gpupnp';BM=$it.BM;AB=$added;OV=$ov;OE=$o.E;SK=$sk}
        }
        R = { param($r)
            $sk = RFLD $r @('SK','SubKey','Path')
            if (!$sk) { Log "[还原跳过] $($r.Id): 备份缺少子键路径" 'Yellow'; return }
            $bm = RFLD $r @('BM')
            $ab = RFLD $r @('AB')
            if ($null -eq $ab) { $ab = $bm }
            if ($null -ne $ab) {
                $o = GRV $sk 'PnPCapabilities'
                $cur = [uint32]0
                if ($o.E) { $cur = U32 $o.V }
                $nv = [uint32]($cur -band ($U32_ALL -bxor (U32 $ab)))
                SRV $sk 'PnPCapabilities' $nv 'DWord'
                Log ("  {0}: PnPCapabilities 0x{1:X} -> 0x{2:X}" -f $r.Id, $cur, $nv)
            } elseif ($r.OE -and $null -ne $r.OV) {
                SRV $sk 'PnPCapabilities' $r.OV 'DWord'
            } else {
                try { Remove-ItemProperty $sk -Name PnPCapabilities -Force -EA 0 } catch {}
            }
        }
    }

    intelftc = @{
        A = { param($it)
            if (!$ISK) { throw "无法定位Intel核显子键" }
            $o = GIFS
            $cur = [uint32]0
            if ($o.E) { $cur = U32 $o.V }
            $bm = U32 $it.BM
            $nv = [uint32]($cur -bor $bm)
            $added = [uint32]($bm -band ($U32_ALL -bxor $cur))
            SRV $ISK 'FeatureTestControl' $nv 'DWord'
            # ★ v4.7: 记录"本次改动前的完整值"和"本项负责的位掩码"
            #   原代码两项(idpst/ipsr)都记整值, 还原时写回同一个污染值, 两个位都清不掉。
            # ★ v4.8: 同时记录 AB(本次新增位), 原本已设置的位不会被误清
            return @{Id=$it.Id;Kind='intelftc';BM=$it.BM;AB=$added;OV=$cur;OE=$o.E;SK=$ISK}
        }
        R = { param($r)
            $sk = RFLD $r @('SK','SubKey')
            if (!$sk) { Log "[还原跳过] $($r.Id): 备份缺少子键路径" 'Yellow'; return }
            $bm = RFLD $r @('BM')
            $ab = RFLD $r @('AB')
            if ($null -eq $ab) { $ab = $bm }
            if ($null -ne $ab) {
                $o = GIFSAt $sk
                $cur = [uint32]0
                if ($o.E) { $cur = U32 $o.V }
                $nv = [uint32]($cur -band ($U32_ALL -bxor (U32 $ab)))
                SRV $sk 'FeatureTestControl' $nv 'DWord'
                Log ("  {0}: 已清除新增位 0x{1:X}, FeatureTestControl 0x{2:X8} -> 0x{3:X8}" -f $r.Id, (U32 $ab), $cur, $nv)
            } elseif ($r.OE -and $null -ne $r.OV) {
                # 旧备份无 BM: 只能整体写回(注意该值可能已被多次应用污染)
                SRV $sk 'FeatureTestControl' $r.OV 'DWord'
                Log ("  {0}: 旧备份无位掩码, 整体写回 0x{1:X8}" -f $r.Id, (U32 $r.OV)) 'Yellow'
            } else {
                try { Remove-ItemProperty $sk -Name FeatureTestControl -Force -EA 0 } catch {}
            }
        }
    }

    # ★ v4.8: v4.6 及更早备份使用 inteldpst / intelpsr 两个独立 Kind;
    #   它们记录的是整值(可能已被另一项污染), 这里按各自负责的位清除, 保证旧备份能真正还原
    inteldpst = @{
        R = { param($r)
            $sk = RFLD $r @('SK','SubKey')
            if (!$sk) { Log "[还原跳过] $($r.Id): 备份缺少子键路径" 'Yellow'; return }
            $o = GIFSAt $sk
            $cur = [uint32]0
            if ($o.E) { $cur = U32 $o.V }
            $nv = [uint32]($cur -band ($U32_ALL -bxor $BM_DPST))
            SRV $sk 'FeatureTestControl' $nv 'DWord'
            Log ("  {0}: 已清除DPST位, FeatureTestControl 0x{1:X8} -> 0x{2:X8}" -f $r.Id, $cur, $nv)
        }
    }
    intelpsr = @{
        R = { param($r)
            $sk = RFLD $r @('SK','SubKey')
            if (!$sk) { Log "[还原跳过] $($r.Id): 备份缺少子键路径" 'Yellow'; return }
            $o = GIFSAt $sk
            $cur = [uint32]0
            if ($o.E) { $cur = U32 $o.V }
            $nv = [uint32]($cur -band ($U32_ALL -bxor $BM_PSR))
            SRV $sk 'FeatureTestControl' $nv 'DWord'
            Log ("  {0}: 已清除PSR位, FeatureTestControl 0x{1:X8} -> 0x{2:X8}" -f $r.Id, $cur, $nv)
        }
    }

    inteldps = @{
        A = { param($it)
            if (!$ISK) { throw "无法定位Intel核显子键" }
            $o = GIDS
            $ov = $null; if ($o.E) { $ov = $o.V }
            # ★ v4.7: 原代码用"删除值"冒充"设为0", 删除后驱动回落默认(可能反而开启省电)
            SRV $ISK 'DisplayPowerSavings' 0 'DWord'
            return @{Id=$it.Id;Kind='inteldps';OV=$ov;OE=$o.E;SK=$ISK}
        }
        R = { param($r)
            $sk = RFLD $r @('SK','SubKey')
            if (!$sk) { Log "[还原跳过] $($r.Id): 备份缺少子键路径" 'Yellow'; return }
            if ($r.OE -and $null -ne $r.OV) { SRV $sk 'DisplayPowerSavings' $r.OV 'DWord' }
            else { try { Remove-ItemProperty $sk -Name DisplayPowerSavings -Force -EA 0 } catch {} }
        }
    }

    tdrdelay = @{
        A = { param($it)
            $gp = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
            $o = GRV $gp 'TdrDelay'
            SRV $gp 'TdrDelay' $it.T 'DWord'
            $ov = $null; if ($o.E) { $ov = $o.V }
            return @{Id=$it.Id;Kind='tdrdelay';P=$gp;OV=$ov;OE=$o.E}
        }
        R = { param($r)
            $p = RFLD $r @('P','Path')
            if (!$p) { $p = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' }
            if ($r.OE -and $null -ne $r.OV) { SRV $p 'TdrDelay' $r.OV 'DWord' }
            else { try { Remove-ItemProperty $p -Name TdrDelay -Force -EA 0 } catch {} }
        }
    }

    nic = @{
        A = { param($it)
            $o = GNS $it.A $it.K
            if (!$o.E) { throw "网卡不支持该属性 ($($it.K))" }
            SNAP $it.A $it.K $it.T
            return @{Id=$it.Id;Kind='nic';A=$it.A;K=$it.K;OV=$o.V;OE=$true}
        }
        R = { param($r)
            $a = RFLD $r @('A','Adapter')
            $k = RFLD $r @('K','Keyword')
            if (!$a -or !$k) { Log "[还原跳过] $($r.Id): 备份缺少网卡名或属性名" 'Yellow'; return }
            if ($null -eq $r.OV) { Log "[还原跳过] $($r.Id): 备份无原始值" 'Yellow'; return }
            try { Set-NetAdapterAdvancedProperty -Name $a -RegistryKeyword $k -RegistryValue $r.OV }
            catch { Log "还原网卡属性失败($k): $($_.Exception.Message)" 'Red' }
        }
    }

    nicpower = @{
        A = { param($it)
            $o = GNPS $it.A
            if (!$o.E) { throw "该网卡不支持省电设置 (无注册表键且无电源管理接口)" }
            SNPR $o.R $it.T $it.A
            $ov = $null; if ($o.O) { $ov = $o.V }
            return @{Id=$it.Id;Kind='nicpower';A=$it.A;OV=$ov;OE=$o.O;R=$o.R}
        }
        R = { param($r)
            $path = RFLD $r @('R','RegPath')
            $a = RFLD $r @('A','Adapter')
            if (!$path -and $a) { $s = GNPS $a; $path = $s.R }
            if (!$path -and !$a) { Log "[还原跳过] $($r.Id): 无法定位网卡子键" 'Yellow'; return }
            SNPR $path $r.OV $a
        }
    }
}

# ── QI 状态查询 ─────────────────────────────────────────
function QI($it) {
    try {
        switch ($it.Kind) {
            'nic' {
                $s = GNS $it.A $it.K
                if (!$s.E) { return @{S='na';C='不支持'} }
                $st = 'no'
                if ([string]$s.V -eq [string]$it.T) { $st = 'ok' }
                return @{S=$st; C=[string]$s.D}
            }
            'nicpower' {
                $s = GNPS $it.A
                if (!$s.E) { return @{S='na';C='不可用'} }
                $st = 'no'
                if ((U32 $s.V) -eq (U32 $it.T)) { $st = 'ok' }
                return @{S=$st; C="PnPCapabilities=$($s.V)"}
            }
            'svc' {
                $m = GSS $it.SV
                if (!$m.Count) { return @{S='na';C='未找到'} }
                $tgt = 'Manual'
                if ($it.T) { $tgt = $it.T }
                $au = 0; $dis = 0; $ru = 0; $total = $m.Count
                foreach ($kv in $m.GetEnumerator()) {
                    if ($kv.Value.T -eq 'Automatic') { $au++ }
                    if ($kv.Value.T -eq 'Disabled')  { $dis++ }
                    if ($kv.Value.S -eq 'Running')   { $ru++ }
                }
                $ok = $false
                if ($tgt -eq 'Disabled') { if ($dis -eq $total -and $ru -eq 0) { $ok = $true } }
                else { if ($au -eq 0) { $ok = $true } }
                $st = 'no'
                if ($ok) { $st = 'ok' }
                return @{S=$st; C="$ru/$total 运行中"}
            }
            'power' {
                $ix = GPCI $PW[$it.SK] $PW[$it.SE]
                if (!$ix.Ok) { return @{S='na';C='不可读'} }
                $st = 'no'
                if ($null -ne $ix.AC -and $null -ne $ix.DC) {
                    if ((U32 $ix.AC) -eq (U32 $it.AC) -and (U32 $ix.DC) -eq (U32 $it.DC)) { $st = 'ok' }
                }
                return @{S=$st; C="AC=$($ix.AC)/DC=$($ix.DC)"}
            }
            'scheme' {
                $g = GASG
                if (!$g) { return @{S='na';C='无法读取'} }
                $st = 'no'
                if ($g -eq $PW[$it.TG]) { $st = 'ok' }
                return @{S=$st; C=(SCHNM $g)}
            }
            'display' {
                $cur = Get-CurrentMode $it.DID
                $curR = 0
                if ($cur) { $curR = $cur.RR }
                $st = 'no'
                if ($curR -ge $it.MR) { $st = 'ok' }
                return @{S=$st; C="当前${curR}Hz/最高$($it.MR)Hz"}
            }
            'gpupref' {
                $v = (Get-ItemProperty $URP -Name 'C:\Windows\System32\dwm.exe' -EA 0).'C:\Windows\System32\dwm.exe'
                if ($v -and $v -match 'GpuPreference=2') { return @{S='ok';C='已设置高性能独显'} }
                $cv = '未设置'
                if ($v) { $cv = $v }
                return @{S='no';C=$cv}
            }
            'intelpnp' {
                $s = GIPP
                if (!$s.E) { return @{S='na';C='未检测到Intel核显'} }
                $h = ((U32 $s.V) -band $BM_PNP_POWER) -ne 0
                $st = 'no'
                if ($h) { $st = 'ok' }
                return @{S=$st; C="PnP=$($s.V)"}
            }
            'gpupnp' {
                if (!$it.SK) { return @{S='na';C='缺少显卡子键'} }
                $s = GRV $it.SK 'PnPCapabilities'
                if (!$s.E) { return @{S='no';C='未设置'} }
                $h = ((U32 $s.V) -band (U32 $it.BM)) -ne 0
                $st = 'no'
                if ($h) { $st = 'ok' }
                return @{S=$st; C="PnP=$($s.V)"}
            }
            'intelftc' {
                $s = GIFS
                if (!$s.E) { return @{S='no';C="未设置($($it.BL))"} }
                $fv = U32 $s.V
                $h = ($fv -band (U32 $it.BM)) -ne 0
                $st = 'no'
                if ($h) { $st = 'ok' }
                return @{S=$st; C=("FTC=0x{0:X8}" -f $fv)}
            }
            'inteldps' {
                $s = GIDS
                # ★ v4.7: 原代码把"未设置"直接报告成"已生效", 但删除值 ≠ 设为0
                if (!$s.E) { return @{S='no';C='未设置(驱动默认, 未显式关闭)'} }
                $st = 'no'
                if ((U32 $s.V) -eq 0) { $st = 'ok' }
                return @{S=$st; C="DPS=$($s.V)"}
            }
            'regdel' {
                $s = GRV $it.P $it.V
                if (!$s.E) { return @{S='ok';C='已移除'} }
                return @{S='no'; C="残留值=$($s.V)"}
            }
            'tdrdelay' {
                $s = GRV 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'TdrDelay'
                if (!$s.E) { return @{S='no';C='未设置(默认2秒)'} }
                $st = 'no'
                if ([int]$s.V -ge [int]$it.T) { $st = 'ok' }
                return @{S=$st; C="TDR=$($s.V)秒"}
            }
            default {
                if ($RC.ContainsKey($it.Kind)) {
                    $p = & $RC[$it.Kind].P $it
                    $n = & $RC[$it.Kind].N $it
                    $s = GRV $p $n
                    $c = '未设置'
                    if ($s.E) { $c = [string]$s.V }
                    $st = 'no'
                    if ($s.E -and $c -eq [string]$it.T) { $st = 'ok' }
                    if ($it.Kind -eq 'reg2' -and $st -eq 'ok') {
                        $s2 = GRV $it.P $it.V2
                        $c2 = '未设置'
                        if ($s2.E) { $c2 = [string]$s2.V }
                        if ($c2 -ne [string]$it.T2) { $st = 'no' }
                        $c = "$c / $($it.V2)=$c2"
                    }
                    return @{S=$st; C=$c}
                } else {
                    return @{S='na';C='未知类型'}
                }
            }
        }
    } catch {
        return @{S='na';C="查询异常: $($_.Exception.Message)"}
    }
}

# ══════════════════════════════════════════════════════════
# 渲染管线健康检测
# ══════════════════════════════════════════════════════════
function WRH {
    Write-Host "`n【渲染管线健康检测】" -ForegroundColor Yellow

    # ── 电源状态 (三源交叉, ★ v4.7 修复函数名遮蔽后才真正生效) ──
    try {
        $pwr = PWRST
        $confLabel = switch ($pwr.Confidence) {
            'high'     { '[三源一致]' }
            'medium'   { '[单源可用]' }
            'degraded' { '[源间冲突]' }
            'low'      { '[仅设备层]' }
            'fail'     { '[全部失败]' }
            default    { "[$($pwr.Confidence)]" }
        }
        $confColor = 'Gray'
        if ($pwr.Confidence -eq 'high') { $confColor = 'Green' }
        elseif ($pwr.Confidence -eq 'medium' -or $pwr.Confidence -eq 'low') { $confColor = 'Yellow' }
        elseif ($pwr.Confidence -eq 'degraded' -or $pwr.Confidence -eq 'fail') { $confColor = 'Red' }

        if ($pwr.IsLaptop) {
            if ($null -eq $pwr.OnAC) { Write-Host "  供电: 笔记本(电池状态未知) $confLabel" -ForegroundColor $confColor }
            elseif ($pwr.OnAC)       { Write-Host "  供电: 已插电 $confLabel" -ForegroundColor Green }
            else                     { Write-Host "  供电: 电池供电! 请插电! $confLabel" -ForegroundColor Red }
        } else {
            Write-Host "  供电: 台式机(无电池) $confLabel" -ForegroundColor Green
        }
        Write-Host "    数据源: $($pwr.Sources -join ', ')" -ForegroundColor DarkGray
    } catch { Write-Host "  电源检测异常: $($_.Exception.Message)" -ForegroundColor Red }

    try {
        foreach ($g in $GREAL) {
            $tag = '核显'; if ($g.Dedicated) { $tag = '独显' }
            Write-Host "  显卡: $($g.Name) [$($g.Vendor)/$tag]" -ForegroundColor Gray
        }
        if ($BASIC -and $GREAL.Count -eq 0) { Write-Host "  显卡驱动: 仅 Microsoft 基本显示适配器 (厂商驱动未安装/异常)" -ForegroundColor Red }
        elseif ($GREAL.Count -eq 0) { Write-Host "  显卡驱动: 未检测到可用显卡" -ForegroundColor Yellow }
    } catch {}

    try {
        $dtSvc = Get-Service DiagTrack -EA 0
        if (!$dtSvc) { Write-Host "  DiagTrack服务: 不存在!" -ForegroundColor Red }
        elseif ($dtSvc.Status -eq 'Running') {
            Write-Host "  DiagTrack服务: 运行中 [正常, 勿禁用]" -ForegroundColor Green
        } elseif ($dtSvc.StartType -eq 'Disabled') {
            Write-Host "  DiagTrack服务: 已禁用 [危险! 会导致UI卡顿]" -ForegroundColor Red
        } else {
            Write-Host "  DiagTrack服务: $($dtSvc.Status) (启动类型: $($dtSvc.StartType))" -ForegroundColor Yellow
        }
    } catch { Write-Host "  DiagTrack检测异常: $($_.Exception.Message)" -ForegroundColor Red }

    # ★ v4.7: 报告旧版脚本残留
    foreach ($sn in @('DiagTrack','dmwappushservice')) {
        try {
            $sr = "HKLM:\SYSTEM\CurrentControlSet\Services\$sn"
            $sp = Get-ItemProperty $sr -EA 0
            if (!$sp) { continue }
            $resid = @()
            if ('Priority' -in $sp.PSObject.Properties.Name) { $resid += "Priority=$($sp.Priority)" }
            if ('DelayedAutoStart' -in $sp.PSObject.Properties.Name -and [int]$sp.DelayedAutoStart -eq 1 -and [int]$sp.Start -ne 2) { $resid += "DelayedAutoStart=1(无意义)" }
            if ($resid.Count -gt 0) { Write-Host "  残留[$sn]: $($resid -join ', ')  ← 旧版脚本遗留, 可在菜单中清理" -ForegroundColor DarkYellow }
            $tk = Get-ScheduledTask -TaskName "SvcQuota_$sn" -EA 0
            if ($tk) { Write-Host "  残留[计划任务]: SvcQuota_$sn 仍存在 (对 svchost 托管服务无效)" -ForegroundColor DarkYellow }
        } catch {}
    }

    try {
        $drrVal = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name DrrMigrationControl -EA 0
        if ($drrVal -and 'DrrMigrationControl' -in $drrVal.PSObject.Properties.Name) {
            $dv = [int]$drrVal.DrrMigrationControl
            if ($dv -eq 0) { Write-Host "  DRR动态刷新率: 已禁用 (需重启生效)" -ForegroundColor Yellow }
            else { Write-Host "  DRR动态刷新率: 启用 (值=$dv)" -ForegroundColor Gray }
        } else { Write-Host "  DRR动态刷新率: 未修改 (系统默认)" -ForegroundColor Gray }
    } catch {}

    try {
        $hagsVal = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -EA 0
        if ($hagsVal -and 'HwSchMode' -in $hagsVal.PSObject.Properties.Name) {
            $hv = [int]$hagsVal.HwSchMode
            if ($hv -eq 2) { Write-Host "  HAGS硬件GPU调度: 已开启 (需重启生效)" -ForegroundColor Yellow }
            else { Write-Host "  HAGS硬件GPU调度: 关闭 (值=$hv)" -ForegroundColor Gray }
        } else { Write-Host "  HAGS硬件GPU调度: 未修改 (系统默认)" -ForegroundColor Gray }
    } catch {}

    try {
        foreach ($d in $DI) {
            $cur = Get-CurrentMode $d.DID
            $curR = 0
            if ($cur) { $curR = $cur.RR }
            $status = '无法读取'; $color = 'Gray'
            if ($curR -ge $d.MR) { $status = '正常(已跑满)'; $color = 'Green' }
            elseif ($curR -gt 0) { $status = "偏低(最高$($d.MR)Hz)"; $color = 'Yellow' }
            Write-Host "  显示器[$($d.DID)]: $($d.W)x$($d.H) 当前${curR}Hz / 最高$($d.MR)Hz - $status" -ForegroundColor $color
        }
        if (-not $DI) { Write-Host "  显示器: 未枚举到 (刷新率检测不可用)" -ForegroundColor Yellow }
    } catch {}

    try {
        $tdrVal = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name TdrDelay -EA 0
        if ($tdrVal -and 'TdrDelay' -in $tdrVal.PSObject.Properties.Name) {
            $tdrV = [int]$tdrVal.TdrDelay
            $tdrLabel = '[偏短]'; $tdrColor = 'Yellow'
            if ($tdrV -ge 8) { $tdrLabel = '[安全]'; $tdrColor = 'Green' }
            Write-Host "  TDR超时: ${tdrV}秒 $tdrLabel" -ForegroundColor $tdrColor
        } else { Write-Host "  TDR超时: 默认2秒" -ForegroundColor Yellow }
    } catch {}

    if ($II -and $ISK) {
        $ippC = 'Gray'; if ($IPP) { $ippC = 'Green' }
        $idpC = 'Gray'; if ($IDP) { $idpC = 'Green' }
        $idrC = 'Gray'; if ($IDR) { $idrC = 'Green' }
        $idsC = 'Gray'; if ($IDS) { $idsC = 'Green' }
        Write-Host "  Intel核显省电禁止: $(if($IPP){'已设置'}else{'未设置'})" -ForegroundColor $ippC
        Write-Host "  Intel DPST: $(if($IDP){'已禁用'}else{'未禁用'})" -ForegroundColor $idpC
        Write-Host "  Intel PSR: $(if($IDR){'已禁用'}else{'未禁用'})" -ForegroundColor $idrC
        Write-Host "  Display Power Savings: $(if($IDS){'已显式关闭'}else{'未显式关闭'})" -ForegroundColor $idsC
    }
    if ($HA) {
        foreach ($ag in @($GPU | Where-Object { $_.Vendor -eq 'AMD' -and $_.Dedicated -and $_.RegKey })) {
            $u = GRV $ag.RegKey 'EnableUlps'
            $ut = '未设置(驱动默认)'; $uc = 'Gray'
            if ($u.E) {
                $ut = "EnableUlps=$($u.V)"
                if ((U32 $u.V) -eq 0) { $uc = 'Green' } else { $uc = 'Yellow' }
            }
            Write-Host "  AMD ULPS[$($ag.Name)]: $ut" -ForegroundColor $uc
        }
    }
    Write-Host "`n  [提示] 如果网页/UI仍然卡顿, 请尝试关闭浏览器硬件加速:" -ForegroundColor DarkYellow
}

# ── 公共摘要 ─────────────────────────────────────────────
# ★ v4.7: 原名 WSL 与 wsl.exe 撞名(函数优先级更高所以能用, 但仍改名避免歧义)
function WLINE($l, $v, $c) { Write-Host ("  {0}: {1}" -f $l,$v) -ForegroundColor $c }
function WIS {
    if ($GREAL.Count -eq 0 -and -not $BASIC) { return }
    Write-Host "`n【显卡驱动稳定性检查】" -ForegroundColor Yellow
    $tdrV = "${TDC}秒"; $tdrC = 'Yellow'; if ($TDC -ge 8) { $tdrC = 'Green' }
    $pcdV = '未禁用';   $pcdC = 'Yellow'; if ($PCD) { $pcdV = '已禁用';     $pcdC = 'Green' }
    if ($BASIC -and $GREAL.Count -eq 0) { WLINE '显示适配器' '仅Microsoft基本显示(需安装厂商驱动)' 'Red' }
    WLINE 'TDR超时' $tdrV $tdrC
    WLINE 'pnpclean' $pcdV $pcdC

    # ★ v4.8: 独显电源状态 (仅有独显时显示)
    if ($HAS_DGPU) {
        Write-Host "`n【独显电源状态】" -ForegroundColor Yellow
        foreach ($dg in @($GPU | Where-Object { $_.Dedicated -and $_.RegKey })) {
            $pp = GRV $dg.RegKey 'PnPCapabilities'
            $pv = '未设置(允许系统关闭)'; $pc = 'Yellow'
            if ($pp.E) {
                $pv = "PnPCapabilities=$($pp.V)"
                if (((U32 $pp.V) -band $BM_PNP_POWER) -ne 0) { $pc = 'Green' } else { $pc = 'Yellow' }
            }
            WLINE "[$($dg.Name)] 禁止系统关闭" $pv $pc
            if ($dg.Vendor -eq 'NVIDIA') {
                $ps = GRV $dg.RegKey 'DisableDynamicPstate'
                $psv = '未设置(动态P-State)'; $psc = 'Gray'
                if ($ps.E) {
                    $psv = "DisableDynamicPstate=$($ps.V)"
                    if ((U32 $ps.V) -eq 1) { $psc = 'Green' } else { $psc = 'Yellow' }
                }
                WLINE "[$($dg.Name)] 动态P-State" $psv $psc
            }
        }
    }

    if ($II) {
        Write-Host "`n【Intel核显稳定性】" -ForegroundColor Yellow
        $ippV = '允许省电'; $ippC = 'Red';   if ($IPP) { $ippV = '已禁止省电'; $ippC = 'Green' }
        $idpV = '未禁用';   $idpC = 'Yellow'; if ($IDP) { $idpV = '已禁用';     $idpC = 'Green' }
        $idrV = '未禁用';   $idrC = 'Red';    if ($IDR) { $idrV = '已禁用';     $idrC = 'Green' }
        $idsV = '未关闭';   $idsC = 'Yellow'; if ($IDS) { $idsV = '已关闭';     $idsC = 'Green' }
        WLINE 'Intel核显电源管理' $ippV $ippC
        WLINE 'Intel DPST' $idpV $idpC
        WLINE 'Intel PSR' $idrV $idrC
        WLINE 'Display Power Savings' $idsV $idsC
    }
    if ($HA) {
        Write-Host "`n【AMD显卡稳定性】" -ForegroundColor Yellow
        foreach ($ag in @($GPU | Where-Object { $_.Vendor -eq 'AMD' -and $_.Dedicated -and $_.RegKey })) {
            $u = GRV $ag.RegKey 'EnableUlps'
            $uv = '未设置(驱动默认)'; $uc = 'Gray'
            if ($u.E) { $uv = "EnableUlps=$($u.V)"; if ((U32 $u.V) -eq 0) { $uc = 'Green' } else { $uc = 'Yellow' } }
            WLINE "ULPS[$($ag.Name)]" $uv $uc
        }
    }
}
function WHW {
    Write-Host "`n【检测到的硬件】" -ForegroundColor Yellow
    if ($CI) { Write-Host "  机型: $($CI.Manufacturer) $($CI.Model)" -ForegroundColor Gray }
    Write-Host "  网卡: $($NN -join ', ')" -ForegroundColor Gray
    Write-Host "  显卡: $($GN -join ' + ')" -ForegroundColor Gray
    foreach ($g in $GPU) {
        $tag = '其他'
        if ($g.Basic) { $tag = '基础显示(无厂商驱动)' }
        elseif ($g.Virtual) { $tag = '虚拟/远程' }
        elseif ($g.Integrated) { $tag = '核显' }
        elseif ($g.Dedicated) { $tag = '独显' }
        $extra = ''
        if ($g.Vendor -and $g.Vendor -ne 'Other') { $extra = "/$($g.Vendor)" }
        if ($g.Dedicated -and $g.VRAM -gt 0) { $extra += " | 显存约$([math]::Round($g.VRAM / 1GB, 1))GB" }
        Write-Host "    - $($g.Name) [$tag$extra]" -ForegroundColor Gray
    }
    if (-not $HAS_DGPU) { Write-Host "    （独显专属优化项在检测到独立显卡时自动出现）" -ForegroundColor DarkGray }
    $laptopStr = '否'
    if ($IL) { $laptopStr = '是' }
    Write-Host "  笔记本: $laptopStr" -ForegroundColor Gray
    foreach ($d in $DI) {
        $dColor = 'Green'
        if ($d.MR -gt $d.RR) { $dColor = 'Yellow' }
        Write-Host "  显示器: $($d.DID) [$($d.DN)] | $($d.W)x$($d.H) | 当前$($d.RR)Hz / 最高$($d.MR)Hz" -ForegroundColor $dColor
    }
}
function SRT { WHW; Write-Host "`n========================================================`n" -ForegroundColor Cyan }

# ── 自检 ─────────────────────────────────────────────────
function SSC {
    Clear-Host; Write-Host "=============== 自检 ===============" -ForegroundColor Cyan
    Write-Host "  时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkGray
    Write-Host "`n【系统】" -ForegroundColor Yellow
    try {
        $osVer = [System.Environment]::OSVersion
        $cpuName = (Get-ItemProperty 'HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0' -EA 0).ProcessorNameString
        Write-Host "  系统: Windows $($osVer.Version)" -ForegroundColor Gray
        Write-Host "  CPU: $cpuName" -ForegroundColor Gray
        Write-Host "  P/Invoke: $(if($script:CS){'就绪'}elseif($script:CSFailed){'编译失败(刷新率功能不可用)'}else{'未初始化'})" -ForegroundColor Gray
    } catch {}
    WHW; WIS; WRH
    Write-Host "`n【电源】" -ForegroundColor Yellow
    try {
        $pwr = PWRST
        $confTag = switch ($pwr.Confidence) {
            'high'     { '[三源一致]' }
            'medium'   { '[单源]' }
            'degraded' { '[源冲突]' }
            'low'      { '[仅设备层]' }
            'fail'     { '[检测失败]' }
            default    { "[$($pwr.Confidence)]" }
        }
        if ($pwr.IsLaptop) {
            if ($null -eq $pwr.OnAC) { Write-Host "  供电: 笔记本(未知) $confTag" -ForegroundColor Yellow }
            elseif ($pwr.OnAC)       { Write-Host "  供电: 已插电 $confTag" -ForegroundColor Green }
            else                     { Write-Host "  供电: 电池! 请插电 $confTag" -ForegroundColor Red }
        } else {
            Write-Host "  供电: 台式机 $confTag" -ForegroundColor Green
        }
        Write-Host "  方案: $(SCHNM (GASG))" -ForegroundColor Gray
    } catch { Write-Host "  电源检测异常: $($_.Exception.Message)" -ForegroundColor Red }

    Write-Host "`n【优化项状态】" -ForegroundColor Yellow
    $ap=0; $pn=0; $na=0
    foreach ($cat in ($O.Cat | Select-Object -Unique)) {
        Write-Host "`n  [$cat]" -ForegroundColor DarkCyan
        foreach ($it in ($O | Where-Object Cat -eq $cat)) {
            $q = QI $it
            $mk = '[不适用]'; $cl = 'DarkGray'
            if ($q.S -eq 'ok')      { $mk = '[已生效]'; $cl = 'Green';  $ap++ }
            elseif ($q.S -eq 'no')  { $mk = '[待应用]'; $cl = 'Yellow'; $pn++ }
            else                    { $na++ }
            Write-Host "    $mk $($it.Name) | $($q.C)" -ForegroundColor $cl
        }
    }
    Write-Host "`n  汇总: 已生效${ap} | 待应用${pn} | 不适用${na} | 总计$($O.Count)" -ForegroundColor Cyan
    Write-Host "`n=====================================" -ForegroundColor Cyan
    Read-Host "`n按回车返回"
}

# ── 菜单 ─────────────────────────────────────────────────
function SMN {
    Clear-Host; Write-Host "================ 游戏性能优化脚本 v5.0 ================" -ForegroundColor Green
    $sm = @()
    if ($CI) { $sm += "$($CI.Manufacturer) $($CI.Model)".Trim() }
    if ($GREAL.Count -gt 0) {
        $gpuSm = @($GREAL | ForEach-Object { $t = '核显'; if ($_.Dedicated) { $t = '独显' }; "$($_.Name)[$t]" })
        $sm += ($gpuSm -join ' + ')
    } elseif ($GN) { $sm += ($GN -join ' + ') }
    if ($NN) { $sm += "网卡: $($NN -join ', ')" }
    Write-Host "  $($sm -join ' | ')" -ForegroundColor DarkGray
    if ($BASIC -and $GREAL.Count -eq 0) { Write-Host "  [警告] 仅检测到 Microsoft 基本显示适配器, 请先安装显卡驱动" -ForegroundColor Red }
    # ★ v4.8: 纯核显机器不显示任何独显选项, 只在菜单顶部用括号提示该能力存在
    if (-not $HAS_DGPU) { Write-Host "  （未检测到独立显卡：独显专属优化项仅在检测到独显时显示）" -ForegroundColor DarkGray }
    Write-Host "--------------------------------------------------" -ForegroundColor DarkGray

    # ── 渲染管线状态 (★ v4.7 修复遮蔽后真正生效) ──
    Write-Host "`n【渲染管线状态】" -ForegroundColor Yellow
    try {
        $pwr = PWRST
        $confTag = switch ($pwr.Confidence) {
            'high'     { '[三源一致]' }
            'medium'   { '[单源]' }
            'degraded' { '[源冲突]' }
            'low'      { '[仅设备层]' }
            'fail'     { '[检测失败]' }
            default    { "[$($pwr.Confidence)]" }
        }
        if ($pwr.IsLaptop) {
            if ($null -eq $pwr.OnAC) { Write-Host "  供电: 笔记本(未知) $confTag" -ForegroundColor Yellow }
            elseif ($pwr.OnAC)       { Write-Host "  供电: 已插电 $confTag" -ForegroundColor Green }
            else                     { Write-Host "  供电: 电池! 请插电 $confTag" -ForegroundColor Red }
        } else {
            Write-Host "  供电: 台式机 $confTag" -ForegroundColor Green
        }
    } catch { Write-Host "  供电: 检测异常" -ForegroundColor Red }

    try {
        $dtSvc = Get-Service DiagTrack -EA 0
        if ($dtSvc -and $dtSvc.Status -eq 'Running') { Write-Host "  DiagTrack: 运行中 (正常)" -ForegroundColor Green }
        elseif ($dtSvc -and $dtSvc.StartType -eq 'Disabled') { Write-Host "  DiagTrack: 已禁用 [危险!]" -ForegroundColor Red }
        elseif ($dtSvc) { Write-Host "  DiagTrack: $($dtSvc.Status)" -ForegroundColor Yellow }
        else { Write-Host "  DiagTrack: 不存在" -ForegroundColor Red }
    } catch { Write-Host "  DiagTrack: 检测异常" -ForegroundColor Red }

    try {
        $drrVal = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name DrrMigrationControl -EA 0
        if ($drrVal -and 'DrrMigrationControl' -in $drrVal.PSObject.Properties.Name) {
            $drrLabel = '启用'; $drrColor = 'Gray'
            if ([int]$drrVal.DrrMigrationControl -eq 0) { $drrLabel = '已禁用'; $drrColor = 'Yellow' }
            Write-Host "  DRR: $drrLabel" -ForegroundColor $drrColor
        } else { Write-Host "  DRR: 默认" -ForegroundColor Gray }
    } catch {}

    try {
        $hagsVal = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -EA 0
        if ($hagsVal -and 'HwSchMode' -in $hagsVal.PSObject.Properties.Name) {
            $hagsLabel = '关闭'; $hagsColor = 'Gray'
            if ([int]$hagsVal.HwSchMode -eq 2) { $hagsLabel = '已开启'; $hagsColor = 'Yellow' }
            Write-Host "  HAGS: $hagsLabel" -ForegroundColor $hagsColor
        } else { Write-Host "  HAGS: 默认" -ForegroundColor Gray }
    } catch {}

    try {
        foreach ($d in $DI) {
            $cur = Get-CurrentMode $d.DID
            $curR = 0
            if ($cur) { $curR = $cur.RR }
            $rrColor = 'Yellow'
            if ($curR -ge $d.MR) { $rrColor = 'Green' }
            Write-Host "  刷新率[$($d.DID)]: ${curR}Hz/$($d.MR)Hz ($($d.W)x$($d.H))" -ForegroundColor $rrColor
        }
        if (-not $DI) { Write-Host "  刷新率: 未枚举到显示器" -ForegroundColor Yellow }
    } catch {}

    Write-Host "`n--------------------------------------------------" -ForegroundColor DarkGray
    $idx = 0; $script:IM = @{}
    foreach ($cat in ($O.Cat | Select-Object -Unique)) {
        Write-Host "`n【$cat】" -ForegroundColor Yellow
        foreach ($it in ($O | Where-Object Cat -eq $cat)) {
            $idx++; $script:IM[$idx] = $it
            $mk = '[ ]'; $nameColor = 'Gray'
            if ($it.E) { $mk = '[X]'; $nameColor = 'Green' }
            $q = QI $it
            $sm2 = ''; $sc = 'DarkGray'
            if ($q.S -eq 'ok') { $sm2 = '[已生效]'; $sc = 'Green' }
            elseif ($it.E -and $q.S -eq 'no') { $sm2 = '[待应用]'; $sc = 'Yellow' }
            Write-Host "  $($idx.ToString().PadRight(3)) $mk $($it.Name)" -ForegroundColor $nameColor
            Write-Host "       当前: $($q.C) -> 目标: $($it.TL)" -ForegroundColor DarkCyan
            if ($sm2) { Write-Host "       $sm2" -ForegroundColor $sc }
            if ($it.R -eq 'med') { Write-Host "       [进阶] $($it.D)" -ForegroundColor DarkYellow }
            if ($it.Dep) {
                $depName = ($O | Where-Object Id -eq $it.Dep | Select-Object -First 1).Name
                if ($depName) { Write-Host "       [依赖] $depName" -ForegroundColor DarkCyan }
            }
        }
    }
    Write-Host "`n--------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  编号=切换 | A=全选推荐 | N=全不选 | D=预览 | P=方案" -ForegroundColor White
    Write-Host "  S=自检 | G=报告 | E=导出报告 | T=还原点 | L=全部还原" -ForegroundColor White
    Write-Host "  Enter=应用勾选项 | R=还原单个备份 | Q=退出" -ForegroundColor White
    Write-Host "--------------------------------------------------" -ForegroundColor DarkGray
}

function PMN {
    $ps = @(Get-TxProfiles)
    Write-Host "`n【预设方案】" -ForegroundColor Yellow
    $i = 0
    foreach ($p in $ps) {
        $i++
        $tag = ' [内置]'; if (!$p.Builtin) { $tag = ' [自定义]' }
        Write-Host "  $i. $($p.Name)$tag" -ForegroundColor Gray
    }
    Write-Host "  S. 保存当前勾选为新方案" -ForegroundColor DarkCyan
    $ch = Read-Host "`n选择编号 (回车=取消)"
    if (!$ch) { return }
    if ($ch -match '^[Ss]$') {
        $name = Read-Host "方案名称"
        if ($name) {
            Save-TxProfile -Name $name -Ids @($O | Where-Object E | ForEach-Object Id) | Out-Null
            Write-Host "已保存方案: $name" -ForegroundColor Green
        }
        Read-Host '按回车返回'; return
    }
    if ($ch -match '^\d+$') {
        $idx = [int]$ch - 1
        if ($idx -ge 0 -and $idx -lt $ps.Count) {
            Set-TxSelectionByProfile -Name $ps[$idx].Name | Out-Null
            Write-Host "已载入方案: $($ps[$idx].Name)" -ForegroundColor Green
        } else {
            Write-Host "编号超出范围" -ForegroundColor Red
        }
    }
    Read-Host '按回车返回'
}

function CDK($sel) {
    $ids = @($sel | ForEach-Object { $_.Id })
    return @($sel | Where-Object { $_.Dep -and $ids -notcontains $_.Dep } | ForEach-Object {
        $dep = $O | Where-Object Id -eq $_.Dep | Select-Object -First 1
        $dn = $_.Dep
        if ($dep) { $dn = $dep.Name }
        [PSCustomObject]@{Item=$_.Name; Dep=$dn; Hint=$_.DH}
    })
}

# ══════════════════════════════════════════════════════════
# ★ v5.0 引擎层: 应用/还原/预览/备份/诊断/报告/方案
#   控制台、CLI、GUI 共用同一套逻辑, 避免三份实现漂移
# ══════════════════════════════════════════════════════════
function Format-TxVal($v, $exists) {
    if ($null -eq $v -or $exists -eq $false) { return '(未设置)' }
    return [string]$v
}
function Get-TxNeedsReboot($it) {
    if ($it.Kind -in @('nicpower','intelpnp','gpupnp','inteldps','tdrdelay','pnpclean','drr')) { return $true }
    if ($it.Id -in @('hags','tcpoffload','idpst','ipsr','nvpstate','amdulps')) { return $true }
    return $false
}

# ── 待重启追踪 ────────────────────────────────────────────
$PENDING = Join-Path $BK 'state_last_apply.json'
$script:PR_CACHE = $null
$script:PR_CACHE_AT = [datetime]::MinValue
function Clear-TxPendingRebootCache {
    $script:PR_CACHE = $null
    $script:PR_CACHE_AT = [datetime]::MinValue
}
function Get-TxPendingFileRename {
    # 只统计 Windows 能真正处理的条目: 来源必须是 \??\、\SystemRoot\ 或 \DosDevices\ 路径,
    # 且来源文件仍存在。安装器写坏的记录(如 "*1\??\..." 前缀)系统不会处理,
    # 重启多少次都不会消失, 不能当作“系统等待重启”。
    $valid = $false
    $ignored = 0
    try {
        $p = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -EA 0
        if ($p -and 'PendingFileRenameOperations' -in $p.PSObject.Properties.Name) {
            $vals = @($p.PendingFileRenameOperations)
            for ($i = 0; $i -lt $vals.Count; $i += 2) {
                $src = [string]$vals[$i]
                if ([string]::IsNullOrWhiteSpace($src)) { continue }
                $path = $null
                if ($src.StartsWith('\??\')) { $path = $src.Substring(4) }
                elseif ($src.StartsWith('\SystemRoot\', [StringComparison]::OrdinalIgnoreCase)) { $path = Join-Path $env:SystemRoot $src.Substring(12) }
                elseif ($src.StartsWith('\DosDevices\', [StringComparison]::OrdinalIgnoreCase)) { $path = $src.Substring(12) }
                if (-not $path) { $ignored++; continue }
                if (Test-Path -LiteralPath $path) { $valid = $true }
            }
        }
    } catch {}
    return [PSCustomObject]@{ Pending = $valid; Ignored = $ignored }
}
function Get-TxPendingReboot {
    # v5.0: 3 秒短缓存, 同一轮快照/诊断不再重复读取注册表
    $now = Get-Date
    if ($script:PR_CACHE -and (($now - $script:PR_CACHE_AT).TotalSeconds -lt 3)) { return $script:PR_CACHE }
    $reasons = @()
    $ignored = 0
    try { if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') { $reasons += 'CBS' } } catch {}
    try { if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') { $reasons += 'WindowsUpdate' } } catch {}
    try {
        $pf = Get-TxPendingFileRename
        if ($pf.Pending) { $reasons += 'PendingFileRename' }
        $ignored = [int]$pf.Ignored
    } catch {}
    try { if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending') { $reasons += 'PackagesPending' } } catch {}
    $script:PR_CACHE = [PSCustomObject]@{ Pending = ($reasons.Count -gt 0); Reasons = @($reasons); Ignored = $ignored }
    $script:PR_CACHE_AT = $now
    return $script:PR_CACHE
}
function Set-TxPendingState {
    param($Items, $Errors, $Backup)
    try {
        $o = [PSCustomObject]@{
            Time   = (Get-Date).ToString('s')
            Items  = @($Items | ForEach-Object { [PSCustomObject]@{ Id = $_.Id; Name = $_.Name } })
            Errors = @($Errors | ForEach-Object { [PSCustomObject]@{ Id = $_.Id; Message = $_.Message } })
            Backup = $Backup
            Checked = $false
        }
        $o | ConvertTo-Json -Depth 6 | Out-File $PENDING -Encoding UTF8
    } catch {}
}
function Get-TxPendingState {
    try { if (Test-Path $PENDING) { return (Get-Content -Raw $PENDING | ConvertFrom-Json) } } catch {}
    return $null
}
function Test-TxPendingState {
    $s = Get-TxPendingState
    if (!$s -or $s.Checked) { return $null }
    $rb = Get-TxPendingReboot
    $cnt = @($s.Items).Count
    if ($rb.Pending) {
        return [PSCustomObject]@{ Stage='waiting'; Msg="上次应用 $cnt 项, 系统等待重启 (原因: $($rb.Reasons -join ', '))"; State=$s }
    }
    $ok = 0; $still = New-Object System.Collections.ArrayList
    foreach ($x in @($s.Items)) {
        $it = $O | Where-Object Id -eq $x.Id | Select-Object -First 1
        if ($it) {
            $q = QI $it
            if ($q.S -eq 'ok') { $ok++ } else { [void]$still.Add($x.Name) }
        }
    }
    $s.Checked = $true
    try {
        $s | Add-Member -NotePropertyName Result -NotePropertyValue "已生效 $ok / 未生效 $($still.Count)" -Force
        $s | ConvertTo-Json -Depth 6 | Out-File $PENDING -Encoding UTF8
    } catch {}
    $msg = "上次应用复核: 已生效 $ok 项"
    if ($still.Count) { $msg += ", 仍未生效: $($still -join '、')" }
    return [PSCustomObject]@{ Stage='checked'; Msg=$msg; State=$s }
}

# ── .reg 快照 / 系统还原点 ────────────────────────────────
function ConvertTo-RegPath($p) {
    if (!$p) { return $null }
    $s = [string]$p
    $s = $s -replace '^Microsoft\.PowerShell\.Core\\Registry::',''
    $s = $s -replace '^Registry::',''
    if ($s -match '^HKEY_LOCAL_MACHINE') { $s = $s -replace '^HKEY_LOCAL_MACHINE','HKLM' }
    elseif ($s -match '^HKEY_CURRENT_USER') { $s = $s -replace '^HKEY_CURRENT_USER','HKCU' }
    elseif ($s -match '^HKEY_USERS') { $s = $s -replace '^HKEY_USERS','HKU' }
    return $s
}
function Export-TxRegSnapshot {
    param([object[]]$Records)
    $keys = @{}
    foreach ($r in @($Records)) {
        foreach ($f in @('P','SK','R','SubKey','Path')) {
            $v = RFLD $r @($f)
            if ($v) {
                $rp = ConvertTo-RegPath $v
                if ($rp) { $keys[$rp] = $true }
            }
        }
    }
    if (!$keys.Count) { return $null }
    $dir = Join-Path $BK "reg_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -ItemType Directory $dir -Force | Out-Null
    $i = 0
    foreach ($k in @($keys.Keys)) {
        $i++
        $safe = ($k -replace '[^A-Za-z0-9_\-]','_')
        if ($safe.Length -gt 70) { $safe = $safe.Substring($safe.Length - 70) }
        $f = Join-Path $dir ("{0:D2}_{1}.reg" -f $i, $safe)
        try { & reg.exe export $k $f /y 2>$null | Out-Null } catch {}
    }
    return $dir
}
function New-TxRestorePoint {
    try {
        Checkpoint-Computer -Description '游戏性能优化 - 应用前' -RestorePointType MODIFY_SETTINGS -EA Stop | Out-Null
        return [PSCustomObject]@{ Ok=$true; Msg='已创建系统还原点' }
    } catch {
        return [PSCustomObject]@{ Ok=$false; Msg=$_.Exception.Message }
    }
}

# ── 应用 (含 DryRun 预演) ─────────────────────────────────
function Invoke-TxApply {
    param(
        [Parameter(Mandatory=$true)][object[]]$Items,
        [switch]$DryRun,
        [switch]$Yes,
        [switch]$NoBackup,
        [switch]$RestorePoint,
        [switch]$NoRegSnapshot
    )
    $sel = @($Items)
    $res = [PSCustomObject]@{
        Ok=0; Fail=0; Records=@(); Errors=@(); Preview=@()
        Backup=$null; RegDir=$null; RestorePoint=$null; DryRun=[bool]$DryRun
    }
    if (!$sel.Count) { return $res }

    $errors  = New-Object System.Collections.ArrayList
    $recs    = New-Object System.Collections.ArrayList
    $preview = New-Object System.Collections.ArrayList

    # 第一遍: 只读预演, 拿到当前值、生成预览、导出 .reg 快照
    $script:DRY = $true
    try {
        foreach ($it in $sel) {
            try {
                $h = $KH[$it.Kind]
                if (!$h -or !$h.A) { throw "未注册Kind: $($it.Kind)" }
                $r = & $h.A $it
                if ($null -ne $r) {
                    [void]$recs.Add($r)
                    # 当前已处于推荐值的项不算变更，预览中不再列出（应用流程保持不变）
                    $qs = QI $it
                    if ($qs.S -ne 'ok') {
                        $ov = RFLD $r @('OV')
                        $oe = RFLD $r @('OE')
                        if ($null -eq $oe) { $oe = ($null -ne $ov) }
                        [void]$preview.Add([PSCustomObject]@{
                            Id=$it.Id; Name=$it.Name; Cat=$it.Cat; Kind=$it.Kind
                            Current=(Format-TxVal $ov $oe); Target=$it.TL; Risk=$it.R
                            NeedsReboot=(Get-TxNeedsReboot $it)
                        })
                    }
                }
            } catch {
                [void]$errors.Add([PSCustomObject]@{ Id=$it.Id; Name=$it.Name; Message=$_.Exception.Message; Stage='plan' })
            }
        }
    } finally { $script:DRY = $false }

    $res.Preview = @($preview.ToArray())
    $res.Errors  = @($errors.ToArray())

    if ($DryRun) {
        $res.Ok = $sel.Count - $errors.Count
        $res.Fail = $errors.Count
        $res.Records = @($recs.ToArray())
        return $res
    }

    if (-not $NoRegSnapshot -and $recs.Count -gt 0) {
        try { $res.RegDir = Export-TxRegSnapshot -Records @($recs.ToArray()) }
        catch { Log "[.reg快照失败] $($_.Exception.Message)" 'Yellow' }
    }
    if ($RestorePoint) {
        $res.RestorePoint = New-TxRestorePoint
        if ($res.RestorePoint.Ok) { Log "[还原点] $($res.RestorePoint.Msg)" 'Green' }
        else { Log "[还原点] 未创建: $($res.RestorePoint.Msg)" 'Yellow' }
    }

    # 第二遍: 正式写入
    $recs2   = New-Object System.Collections.ArrayList
    $errors2 = New-Object System.Collections.ArrayList
    $ok = 0; $fail = 0
    foreach ($it in $sel) {
        try {
            $h = $KH[$it.Kind]
            if (!$h -or !$h.A) { throw "未注册Kind: $($it.Kind)" }
            $r = & $h.A $it
            if ($null -ne $r) { [void]$recs2.Add($r) }
            Log "[成功] $($it.Name)" 'Green'
            $ok++
        } catch {
            [void]$errors2.Add([PSCustomObject]@{ Id=$it.Id; Name=$it.Name; Message=$_.Exception.Message; Stage='apply' })
            Log "[失败] $($it.Name) -> $($_.Exception.Message)" 'Red'
            $fail++
        }
    }

    $backup = $null
    if (-not $NoBackup -and $recs2.Count -gt 0) {
        $backup = Join-Path $BK "backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        try {
            @{ Time=(Get-Date).ToString('s'); Version='v5.0'; Records=@($recs2.ToArray()) } |
                ConvertTo-Json -Depth 8 | Out-File $backup -Encoding UTF8
            Log "[备份] $backup" 'Cyan'
        } catch {
            Log "[备份失败] $($_.Exception.Message) — 本次改动无法自动还原!" 'Red'
            $backup = $null
        }
    }

    $errIds = @($errors2 | ForEach-Object { $_.Id })
    $okItems = @($sel | Where-Object { $errIds -notcontains $_.Id })
    if ($okItems.Count -gt 0) {
        Set-TxPendingState -Items $okItems -Errors @($errors2.ToArray()) -Backup $backup
    }

    $res.Ok=$ok; $res.Fail=$fail; $res.Records=@($recs2.ToArray())
    $res.Errors=@($errors2.ToArray()); $res.Backup=$backup
    # v5.0: 写入后让状态/待重启缓存失效
    try { Clear-TxNicAdvCache } catch {}
    try { Clear-TxPendingRebootCache } catch {}
    return $res
}

# ── 还原 ──────────────────────────────────────────────────
function Restore-TxBackupFile {
    param([Parameter(Mandatory=$true)][string]$Path)
    $res = [PSCustomObject]@{ Ok=0; Fail=0; Errors=@(); File=$Path; Version=$null; Records=0 }
    if (!(Test-Path $Path)) { throw "备份不存在: $Path" }
    $data = $null
    try { $data = Get-Content -Raw $Path | ConvertFrom-Json } catch { throw "备份解析失败: $($_.Exception.Message)" }
    if (!$data -or !$data.Records) { throw "备份中无记录" }
    $res.Version = $data.Version
    $recList = @($data.Records)
    $res.Records = $recList.Count
    # ★ v4.7: 逆序还原 —— 同一注册表值被多项按位修改时, 逆序才能正确回退
    [array]::Reverse($recList)
    $errors = New-Object System.Collections.ArrayList
    foreach ($r in $recList) {
        try {
            $h = $KH[$r.Kind]
            if (!$h -or !$h.R) { throw "未注册Kind: $($r.Kind)" }
            & $h.R $r
            Log "[还原] $($r.Id)" 'Green'
            $res.Ok++
        } catch {
            [void]$errors.Add([PSCustomObject]@{ Id=$r.Id; Message=$_.Exception.Message })
            Log "[失败] $($r.Id) -> $($_.Exception.Message)" 'Red'
            $res.Fail++
        }
    }
    $res.Errors = @($errors.ToArray())
    # v5.0: 还原后让网卡属性/待重启缓存失效
    try { Clear-TxNicAdvCache } catch {}
    try { Clear-TxPendingRebootCache } catch {}
    return $res
}
function Restore-TxAll {
    $fs = @(Get-ChildItem $BK -Filter backup_*.json -EA 0 | Sort-Object LastWriteTime -Descending)
    $agg = [PSCustomObject]@{ Ok=0; Fail=0; Files=0; Errors=@(); Report=@() }
    if (!$fs.Count) { return $agg }
    $errs = New-Object System.Collections.ArrayList
    $rep  = New-Object System.Collections.ArrayList
    foreach ($f in $fs) {
        try {
            $r = Restore-TxBackupFile -Path $f.FullName
            $agg.Ok += $r.Ok; $agg.Fail += $r.Fail; $agg.Files++
            [void]$rep.Add([PSCustomObject]@{ File=$f.Name; Ok=$r.Ok; Fail=$r.Fail })
            foreach ($e in @($r.Errors)) { [void]$errs.Add($e) }
        } catch {
            $agg.Fail++
            [void]$errs.Add([PSCustomObject]@{ Id=$f.Name; Message=$_.Exception.Message })
            [void]$rep.Add([PSCustomObject]@{ File=$f.Name; Ok=0; Fail=1 })
        }
    }
    $agg.Errors = @($errs.ToArray())
    $agg.Report = @($rep.ToArray())
    return $agg
}

# ── v5.0 系统盘信息 (避免加载 Storage 模块, Get-Volume 首次约 1.5-2 秒) ──
$script:VOL_C_CACHE = $null
function Get-TxSystemVolume {
    if ($script:VOL_C_CACHE) { return $script:VOL_C_CACHE }
    $v = $null
    try {
        $di = New-Object System.IO.DriveInfo 'C'
        if ($di.IsReady) {
            $v = [PSCustomObject]@{ Size = [double]$di.TotalSize; SizeRemaining = [double]$di.AvailableFreeSpace }
        }
    } catch {}
    if (!$v) { try { $v = Get-Volume -DriveLetter C -EA 0 } catch {} }
    $script:VOL_C_CACHE = $v
    return $v
}

# ── v5.0 系统信息缓存 (快照/诊断共用) ────────────────────
# v5.1: 不再在这里重置; 启动时的并行 job 可能已经预热了 $script:SYSINFO_CACHE
function Get-TxSystemInfo {
    if ($script:SYSINFO_CACHE) { return $script:SYSINFO_CACHE }
    $os = $null; $cpu = $null; $mods = @(); $cs = $null; $dg = $null
    # 只取需要的属性, 避免整类序列化: Win32_Processor 全属性约 1.1-1.5s, 投影后约 30ms
    try { $os = Get-CimInstance Win32_OperatingSystem -Property Caption,BuildNumber -EA 0 } catch {}
    try { $cpu = Get-CimInstance Win32_Processor -Property Name,NumberOfCores,NumberOfLogicalProcessors -EA 0 | Select-Object -First 1 } catch {}
    try { $mods = @(Get-CimInstance Win32_PhysicalMemory -Property Capacity,Speed,ConfiguredClockSpeed -EA 0) } catch {}
    try { $cs = Get-CimInstance Win32_ComputerSystem -Property Manufacturer,Model -EA 0 } catch {}
    try { $dg = Get-CimInstance -Namespace 'root\Microsoft\Windows\DeviceGuard' -ClassName Win32_DeviceGuard -Property VirtualizationBasedSecurityStatus,SecurityServicesRunning -EA 0 } catch {}
    $script:SYSINFO_CACHE = [PSCustomObject]@{ OS=$os; CPU=$cpu; Memory=$mods; Computer=$cs; DeviceGuard=$dg }
    return $script:SYSINFO_CACHE
}

# ── v5.0 概览用轻量诊断 ──────────────────────────────────
# 只读取硬件卡片需要的字段, 不碰磁盘健康/PCIe/网络等慢查询。
# 完整诊断留给「诊断报告」页按需执行。
function Get-TxBriefDiagnostics {
    $d = New-Object System.Collections.ArrayList
    $add = {
        param($g,$n,$v,$lvl='Gray',$hint='')
        [void]$d.Add([PSCustomObject]@{ Group=$g; Name=$n; Value=[string]$v; Level=$lvl; Hint=[string]$hint })
    }
    $si = Get-TxSystemInfo
    if ($si.OS) { & $add '系统' '操作系统' ("$($si.OS.Caption) build $($si.OS.BuildNumber)") 'Gray' }
    if ($si.CPU) {
        $cn = [string]$si.CPU.Name
        if ($cn) { & $add '系统' 'CPU' ("$($cn.Trim()) | $($si.CPU.NumberOfCores)核$($si.CPU.NumberOfLogicalProcessors)线程") 'Gray' }
    }
    $mods = @($si.Memory)
    if ($mods.Count) {
        $total = ($mods | Measure-Object Capacity -Sum).Sum / 1GB
        & $add '系统' '内存' ("{0:N1} GB | {1} 根" -f $total, $mods.Count) 'Gray'
        $rated = @($mods | ForEach-Object { [int]$_.Speed } | Where-Object { $_ -gt 0 } | Sort-Object -Descending | Select-Object -First 1)
        $conf  = @($mods | ForEach-Object { [int]$_.ConfiguredClockSpeed } | Where-Object { $_ -gt 0 } | Sort-Object -Descending | Select-Object -First 1)
        if ($rated.Count -and $conf.Count) {
            $lvl = 'Green'; $hint = ''
            if ($conf[0] -lt $rated[0]) { $lvl = 'Yellow'; $hint = '运行频率低于标称, XMP/EXPO 可能未开启' }
            & $add '系统' '内存频率' ("配置 $($conf[0]) MT/s / 标称 $($rated[0]) MT/s") $lvl $hint
        }
    }
    if ($si.Computer) {
        & $add '系统' '机型' ("$($si.Computer.Manufacturer) $($si.Computer.Model)".Trim()) 'Gray'
        $isVM = ($si.Computer.Model -match '(?i)VirtualBox|VMware|Virtual Machine|KVM|QEMU') -or ($si.Computer.Manufacturer -match '(?i)VMware|innotek|QEMU')
        $isRdp = ($env:SESSIONNAME -match '^RDP')
        $envText = '物理机/本地'; $envLvl = 'Green'; $envHint = ''
        if ($isVM) { $envText = '虚拟机'; $envLvl = 'Yellow'; $envHint = '显示/刷新率相关项可能不适用' }
        elseif ($isRdp) { $envText = '远程桌面'; $envLvl = 'Yellow'; $envHint = '显示/刷新率相关项可能不适用' }
        & $add '系统' '运行环境' $envText $envLvl $envHint
    }
    if ($si.DeviceGuard) {
        $dg = $si.DeviceGuard
        $vbsCode = [int]$dg.VirtualizationBasedSecurityStatus
        $vbsText = switch ($vbsCode) { 0 {'未启用'} 1 {'已启用(未运行)'} 2 {'运行中'} default {'未知'} }
        $hvci = (@($dg.SecurityServicesRunning) -contains 2)
        $lvl = 'Gray'; $hint = ''
        if ($vbsCode -eq 2) { $lvl = 'Yellow'; $hint = 'VBS 运行中, 部分游戏帧率可能下降 5%-15%; 关闭有安全代价, 请自行权衡' }
        & $add '安全' 'VBS 虚拟化安全' $vbsText $lvl $hint
        & $add '安全' '内存完整性 HVCI' $(if ($hvci) { '运行中' } else { '未运行' }) $(if ($hvci) { 'Yellow' } else { 'Green' }) $(if ($hvci) { 'HVCI 对部分游戏有性能开销' } else { '' })
    } else { & $add '安全' 'VBS/HVCI' '不可用' 'Gray' '' }
    foreach ($g in @($GPU | Where-Object { -not $_.Basic -and -not $_.Virtual })) {
        $tag = '核显'; if ($g.Dedicated) { $tag = '独显' }
        $dv = ''
        try {
            if ($g.RegKey) {
                $p = Get-ItemProperty $g.RegKey -EA 0
                if ($p -and 'DriverVersion' -in $p.PSObject.Properties.Name) { $dv = [string]$p.DriverVersion }
                if ($p -and 'DriverDate' -in $p.PSObject.Properties.Name) { $dv += " / $($p.DriverDate)" }
            }
        } catch {}
        & $add '显卡' "$($g.Name) [$tag]" $(if ($dv) { "驱动 $dv" } else { '驱动版本未知' }) 'Gray' ''
    }
    try {
        $vol = Get-TxSystemVolume
        if ($vol -and $vol.Size) {
            $freePct = [math]::Round($vol.SizeRemaining / $vol.Size * 100, 1)
            $lvl = 'Green'; $hint = ''
            if ($freePct -lt 10) { $lvl = 'Red'; $hint = '系统盘剩余空间不足 10%' }
            elseif ($freePct -lt 20) { $lvl = 'Yellow'; $hint = '系统盘剩余偏低' }
            & $add '存储' '系统盘剩余' ("$freePct% / $([math]::Round($vol.SizeRemaining/1GB,1)) GB") $lvl $hint
        }
    } catch {}
    return @($d.ToArray())
}

# ── v5.0 诊断缓存 ────────────────────────────────────────
$script:PCIE_CACHE = @{}
function Get-TxPcieProp([string]$id, [string]$key) {
    $ck = "$id|$key"
    if ($script:PCIE_CACHE.ContainsKey($ck)) { return $script:PCIE_CACHE[$ck] }
    $v = $null
    try { $v = Get-PnpDeviceProperty -InstanceId $id -KeyName $key -EA 0 } catch {}
    $script:PCIE_CACHE[$ck] = $v
    return $v
}
$script:REL_CACHE = @{}
function Get-TxReliability($disk) {
    $id = [string]$disk.DeviceId
    $now = Get-Date
    if ($script:REL_CACHE.ContainsKey($id)) {
        $e = $script:REL_CACHE[$id]
        if (($now - $e.At).TotalSeconds -lt 60) { return $e.Val }
    }
    $r = $null
    try { $r = Get-StorageReliabilityCounter -PhysicalDisk $disk -EA 0 } catch {}
    $script:REL_CACHE[$id] = @{ At = $now; Val = $r }
    return $r
}

# ── 只读诊断 ──────────────────────────────────────────────
function Get-TxDiagnostics {
    $d = New-Object System.Collections.ArrayList
    $add = {
        param($g,$n,$v,$lvl='Gray',$hint='')
        [void]$d.Add([PSCustomObject]@{ Group=$g; Name=$n; Value=[string]$v; Level=$lvl; Hint=[string]$hint })
    }

    $si = Get-TxSystemInfo
    try {
        $os = $si.OS
        if ($os) { & $add '系统' '操作系统' ("$($os.Caption) build $($os.BuildNumber)") 'Gray' }
    } catch {}
    try {
        $cpu = $si.CPU
        if ($cpu) { & $add '系统' 'CPU' ("$($cpu.Name.Trim()) | $($cpu.NumberOfCores)核$($cpu.NumberOfLogicalProcessors)线程") 'Gray' }
    } catch {}
    try {
        $mods = @($si.Memory)
        if ($mods.Count) {
            $total = ($mods | Measure-Object Capacity -Sum).Sum / 1GB
            & $add '系统' '内存' ("{0:N1} GB | {1} 根" -f $total, $mods.Count) 'Gray'
            $rated = @($mods | ForEach-Object { [int]$_.Speed } | Where-Object { $_ -gt 0 } | Sort-Object -Descending | Select-Object -First 1)
            $conf  = @($mods | ForEach-Object { [int]$_.ConfiguredClockSpeed } | Where-Object { $_ -gt 0 } | Sort-Object -Descending | Select-Object -First 1)
            if ($rated.Count -and $conf.Count) {
                $lvl = 'Green'; $hint = ''
                if ($conf[0] -lt $rated[0]) { $lvl = 'Yellow'; $hint = '运行频率低于标称, XMP/EXPO 可能未开启' }
                & $add '系统' '内存频率' ("配置 $($conf[0]) MT/s / 标称 $($rated[0]) MT/s") $lvl $hint
            }
        }
    } catch {}
    try {
        $cs = $si.Computer
        if ($cs) {
            & $add '系统' '机型' ("$($cs.Manufacturer) $($cs.Model)".Trim()) 'Gray'
            $isVM = ($cs.Model -match '(?i)VirtualBox|VMware|Virtual Machine|KVM|QEMU') -or ($cs.Manufacturer -match '(?i)VMware|innotek|QEMU')
            $isRdp = ($env:SESSIONNAME -match '^RDP')
            $envText = '物理机/本地'; $envLvl = 'Green'; $envHint = ''
            if ($isVM) { $envText = '虚拟机'; $envLvl = 'Yellow'; $envHint = '显示/刷新率相关项可能不适用' }
            elseif ($isRdp) { $envText = '远程桌面'; $envLvl = 'Yellow'; $envHint = '显示/刷新率相关项可能不适用' }
            & $add '系统' '运行环境' $envText $envLvl $envHint
        }
    } catch {}

    try {
        $dg = $si.DeviceGuard
        if ($dg) {
            $vbsCode = [int]$dg.VirtualizationBasedSecurityStatus
            $vbsText = switch ($vbsCode) { 0 {'未启用'} 1 {'已启用(未运行)'} 2 {'运行中'} default {'未知'} }
            $hvci = (@($dg.SecurityServicesRunning) -contains 2)
            $lvl = 'Gray'; $hint = ''
            if ($vbsCode -eq 2) { $lvl = 'Yellow'; $hint = 'VBS 运行中, 部分游戏帧率可能下降 5%-15%; 关闭有安全代价, 请自行权衡' }
            & $add '安全' 'VBS 虚拟化安全' $vbsText $lvl $hint
            & $add '安全' '内存完整性 HVCI' $(if ($hvci) { '运行中' } else { '未运行' }) $(if ($hvci) { 'Yellow' } else { 'Green' }) $(if ($hvci) { 'HVCI 对部分游戏有性能开销' } else { '' })
        } else { & $add '安全' 'VBS/HVCI' '不可用' 'Gray' '' }
    } catch { & $add '安全' 'VBS/HVCI' '查询失败' 'Gray' '' }

    foreach ($g in @($GPU | Where-Object { -not $_.Basic -and -not $_.Virtual })) {
        $tag = '核显'; if ($g.Dedicated) { $tag = '独显' }
        $dv = ''
        try {
            if ($g.RegKey) {
                $p = Get-ItemProperty $g.RegKey -EA 0
                if ($p -and 'DriverVersion' -in $p.PSObject.Properties.Name) { $dv = [string]$p.DriverVersion }
                if ($p -and 'DriverDate' -in $p.PSObject.Properties.Name) { $dv += " / $($p.DriverDate)" }
            }
        } catch {}
        & $add '显卡' "$($g.Name) [$tag]" $(if ($dv) { "驱动 $dv" } else { '驱动版本未知' }) 'Gray' ''
        if ($g.Dedicated -and $g.PnPId) {
            try {
                $w  = Get-TxPcieProp $g.PnPId 'DEVPKEY_PciDevice_CurrentLinkWidth'
                $s  = Get-TxPcieProp $g.PnPId 'DEVPKEY_PciDevice_CurrentLinkSpeed'
                $mw = Get-TxPcieProp $g.PnPId 'DEVPKEY_PciDevice_MaxLinkWidth'
                $ms = Get-TxPcieProp $g.PnPId 'DEVPKEY_PciDevice_MaxLinkSpeed'
                $cur = "x$($w.Data) @ $($s.Data)"
                $max = "x$($mw.Data) @ $($ms.Data)"
                $lvl = 'Green'; $hint = ''
                if ($w.Data -and $mw.Data -and [int]$w.Data -lt [int]$mw.Data) { $lvl = 'Yellow'; $hint = 'PCIe 链路宽度低于上限, 可能插槽/通道受限' }
                & $add '显卡' "$($g.Name) PCIe" ("当前 $cur / 上限 $max") $lvl $hint
            } catch {}
        }
    }
    foreach ($disp in $DI) {
        $lvl = 'Green'; $hint = ''
        if ($disp.MR -gt $disp.RR) { $lvl = 'Yellow'; $hint = '当前刷新率未达面板最高值' }
        & $add '显示' "$($disp.DID) [$($disp.DN)]" "$($disp.W)x$($disp.H) | $($disp.RR)Hz / 最高 $($disp.MR)Hz" $lvl $hint
    }

    try {
        # v5.0: MSFT_PhysicalDisk 约 40ms, 原 Get-PhysicalDisk 首次约 1.6s; 字段等价
        # BusType/MediaType 首次查询为数字(17/4), 加载存储模块后类型适配器
        # 会返回字符串(NVMe/SSD), 两种形式都要兼容
        $disks = @(Get-CimInstance -Namespace 'root\Microsoft\Windows\Storage' -ClassName MSFT_PhysicalDisk -EA 0 |
            Where-Object {
                $bt = [string]$_.BusType; $mt = [string]$_.MediaType
                $bt -in @('17','NVMe') -or $mt -in @('4','SSD')
            })
        if (-not $disks) {
            # 旧系统/存储服务异常时回退到原 cmdlet, 保证诊断项不丢失
            try { $disks = @(Get-PhysicalDisk -EA 0 | Where-Object { $_.BusType -eq 'NVMe' -or $_.MediaType -eq 'SSD' }) } catch {}
        }
        foreach ($disk in $disks) {
            $extra = ''
            # 注意: Get-StorageReliabilityCounter 绑定 CIM 参数时可能改写传入对象的
            # BusType(17 -> 'NVMe'), 因此先快照显示所需字段再查询可靠性
            $busRaw = [string]$disk.BusType
            $fn = [string]$disk.FriendlyName
            $sz = [double]$disk.Size
            try {
                $rel = Get-TxReliability $disk
                if ($rel) {
                    if ($null -ne $rel.Temperature) { $extra += " | 温度 $($rel.Temperature)°C" }
                    if ($null -ne $rel.Wear) { $extra += " | 磨损 $($rel.Wear)%" }
                    if ($null -ne $rel.PowerOnHours) { $extra += " | 通电 $($rel.PowerOnHours)h" }
                }
            } catch {}
            $bus = switch ($busRaw) {
                '17' {'NVMe'} 'NVMe' {'NVMe'}
                '11' {'SATA'} 'SATA' {'SATA'}
                '8' {'RAID'} 'RAID' {'RAID'}
                default { $busRaw }
            }
            & $add '存储' $fn ("$bus / $([math]::Round($sz/1GB))GB$extra") 'Gray' ''
        }
    } catch {}
    try {
        $vol = Get-TxSystemVolume
        if ($vol -and $vol.Size) {
            $freePct = [math]::Round($vol.SizeRemaining / $vol.Size * 100, 1)
            $lvl = 'Green'; $hint = ''
            if ($freePct -lt 10) { $lvl = 'Red'; $hint = '系统盘剩余空间不足 10%' }
            elseif ($freePct -lt 20) { $lvl = 'Yellow'; $hint = '系统盘剩余空间偏低' }
            & $add '存储' '系统盘剩余' ("$freePct% / $([math]::Round($vol.SizeRemaining/1GB,1)) GB") $lvl $hint
        }
    } catch {}

    foreach ($n in $NN) {
        try {
            $props = @(Get-TxNicAdvAll $n)
            $names = @()
            foreach ($pat in @('*EEE*','*EnergyEfficient*','*GreenEthernet*','*InterruptModeration*','*FlowControl*')) {
                $h = $props | Where-Object { $_.RegistryKeyword -like $pat } | Select-Object -First 1
                if ($h) { $names += "$($h.DisplayName)=$($h.DisplayValue)" }
            }
            $link = ''
            try { $a = Get-NetAdapter -Name $n -EA 0; if ($a) { $link = "$($a.LinkSpeed) / $($a.Status)" } } catch {}
            & $add '网络' $n $(if ($names.Count) { "$link | $($names -join '; ')" } else { $link }) 'Gray' ''
        } catch {}
    }

    try {
        $p = PWRST
        $conf = switch ($p.Confidence) { 'high' {'三源一致'} 'medium' {'单源'} 'degraded' {'源冲突'} 'low' {'仅设备层'} 'fail' {'失败'} default {$p.Confidence} }
        $pv = if (!$p.IsLaptop) { '台式机' } elseif ($null -eq $p.OnAC) { '笔记本/供电未知' } elseif ($p.OnAC) { '笔记本/已插电' } else { '笔记本/电池供电' }
        & $add '电源' '供电' "$pv [$conf]" $(if ($p.IsLaptop -and $p.OnAC -eq $false) { 'Red' } else { 'Green' }) ''
    } catch {}
    try { & $add '电源' '当前方案' (SCHNM (GASG)) 'Gray' '' } catch {}
    try {
        $t = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name TdrDelay -EA 0
        $tv = '默认(2秒)'; $lvl = 'Yellow'
        if ($t -and 'TdrDelay' -in $t.PSObject.Properties.Name) { $tv = "$($t.TdrDelay)秒"; if ([int]$t.TdrDelay -ge 8) { $lvl = 'Green' } }
        & $add '显卡' 'TDR 超时' $tv $lvl $(if ($lvl -eq 'Yellow') { '建议 8 秒, 可减少驱动重置黑屏' } else { '' })
    } catch {}
    try {
        $h = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name HwSchMode -EA 0
        $hv = '默认'
        if ($h -and 'HwSchMode' -in $h.PSObject.Properties.Name) { if ([int]$h.HwSchMode -eq 2) { $hv = '已开启' } else { $hv = '已关闭' } }
        & $add '显卡' 'HAGS' $hv 'Gray' ''
    } catch {}
    try {
        $dr = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name DrrMigrationControl -EA 0
        $dv = '默认'
        if ($dr -and 'DrrMigrationControl' -in $dr.PSObject.Properties.Name) { if ([int]$dr.DrrMigrationControl -eq 0) { $dv = '已禁用' } else { $dv = '已启用' } }
        & $add '显示' 'DRR 动态刷新率' $dv 'Gray' ''
    } catch {}
    try {
        $gb = Get-ItemProperty "$HKU_BASE\Software\Microsoft\GameBar" -EA 0
        $gv = '默认(开启)'
        if ($gb -and 'AutoGameModeEnabled' -in $gb.PSObject.Properties.Name) { if ([int]$gb.AutoGameModeEnabled -eq 1) { $gv = '已开启' } else { $gv = '已关闭' } }
        & $add '系统' '游戏模式' $gv 'Gray' ''
    } catch {}

    try {
        $rb = Get-TxPendingReboot
        $rbText = if ($rb.Pending) { "是 ($($rb.Reasons -join ', '))" } elseif ($rb.Ignored -gt 0) { "否 (已忽略 $($rb.Ignored) 条无效记录)" } else { '否' }
        & $add '系统' '待重启' $rbText $(if ($rb.Pending) { 'Yellow' } else { 'Green' }) ''
    } catch {}
    try {
        $last = Get-TxPendingState
        if ($last) {
            $st = '已记录'
            if ($last.Checked -and $last.Result) { $st = [string]$last.Result }
            & $add '系统' '上次应用' "$($last.Time) | $(@($last.Items).Count) 项 | $st" 'Gray' ''
        }
    } catch {}

    return @($d.ToArray())
}

# ── 报告导出 ──────────────────────────────────────────────
function Export-TxReport {
    param([string]$Path)
    if (!$Path) { $Path = Join-Path $SD "report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt" }
    $L = New-Object System.Collections.ArrayList
    $add = { param($t='') [void]$L.Add([string]$t) }
    & $add '============================================================'
    & $add ' 游戏性能优化 诊断报告 v5.0'
    & $add " 生成时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    & $add " 脚本目录: $SD"
    & $add '============================================================'
    & $add ''
    & $add '【硬件概览】'
    if ($CI) { & $add "  机型: $($CI.Manufacturer) $($CI.Model)" }
    & $add "  笔记本: $(if ($IL) { '是' } else { '否' })"
    & $add "  网卡: $($NN -join ', ')"
    foreach ($g in $GPU) {
        $tag = '其他'
        if ($g.Basic) { $tag = '基础显示' } elseif ($g.Virtual) { $tag = '虚拟' } elseif ($g.Integrated) { $tag = '核显' } elseif ($g.Dedicated) { $tag = '独显' }
        & $add "  显卡: $($g.Name) [$tag/$($g.Vendor)] 显存 $([math]::Round($g.VRAM/1GB,1))GB 键 $($g.KeyId)"
    }
    foreach ($disp in $DI) { & $add "  显示器: $($disp.DID) [$($disp.DN)] $($disp.W)x$($disp.H) $($disp.RR)Hz/最高$($disp.MR)Hz" }
    & $add ''
    & $add '【诊断】'
    foreach ($x in @(Get-TxDiagnostics)) {
        $hint = ''
        if ($x.Hint) { $hint = "  ($($x.Hint))" }
        & $add ("  [{0}] {1} - {2}: {3}{4}" -f $x.Level, $x.Group, $x.Name, $x.Value, $hint)
    }
    & $add ''
    & $add '【优化项状态】'
    foreach ($cat in ($O.Cat | Select-Object -Unique)) {
        & $add "  [$cat]"
        foreach ($it in ($O | Where-Object Cat -eq $cat)) {
            $q = QI $it
            $mark = '待应用'
            if ($q.S -eq 'ok') { $mark = '已生效' } elseif ($q.S -eq 'na') { $mark = '不适用' }
            $sel = '否'; if ($it.E) { $sel = '是' }
            & $add ("    [{0}] {1} | 当前: {2} -> 目标: {3} | 勾选: {4} | 风险: {5}" -f $mark, $it.Name, $q.C, $it.TL, $sel, $it.R)
        }
    }
    & $add ''
    & $add '【备份】'
    $fs = @(Get-ChildItem $BK -Filter backup_*.json -EA 0 | Sort-Object LastWriteTime -Descending)
    & $add "  备份数量: $($fs.Count)"
    foreach ($f in @($fs | Select-Object -First 10)) {
        & $add "  - $($f.Name) | $($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')) | $([math]::Round($f.Length/1KB,1)) KB"
    }
    & $add ''
    & $add '【待重启】'
    $rb = Get-TxPendingReboot
    $rbLine = if ($rb.Pending) { "是 ($($rb.Reasons -join ', '))" } elseif ($rb.Ignored -gt 0) { "否 (已忽略 $($rb.Ignored) 条无效记录)" } else { '否' }
    & $add "  $rbLine"
    & $add ''
    & $add "日志文件: $LOG"
    & $add '============================================================'
    $L | Out-File -FilePath $Path -Encoding UTF8
    return $Path
}

# ── 快照 (CLI/GUI 共用) ───────────────────────────────────
# ★ v5.1: -Provisional 只构造硬件/占位信息, 不做 32 项状态检查;
#   GUI 先用它完成首屏绘制, 窗口显示后再调用完整快照补齐状态。
function Get-TxSnapshot {
    param([switch]$Provisional)
    $items = @(); $ok = 0; $no = 0; $na = 0; $chk = 0
    foreach ($it in $O) {
        if ($Provisional) {
            $q = @{ S = 'checking'; C = '正在检测...' }
        } else {
            $q = QI $it
        }
        if ($q.S -eq 'ok') { $ok++ } elseif ($q.S -eq 'no') { $no++ } elseif ($q.S -eq 'na') { $na++ } else { $chk++ }
        $items += [PSCustomObject]@{
            Id=$it.Id; Cat=$it.Cat; Name=$it.Name; Desc=$it.D
            Kind=$it.Kind; Selected=[bool]$it.E; Risk=$it.R; Target=$it.TL
            Status=$q.S; StatusText=$q.C; NeedsReboot=$(if ($Provisional) { $false } else { Get-TxNeedsReboot $it })
            Dep=$it.Dep; DepHint=$it.DH
        }
    }
    $pwr = $null
    try { $pwr = PWRST } catch {}
    return [PSCustomObject]@{
        Version = 'v5.0'
        Time = (Get-Date).ToString('s')
        Machine = $(if ($CI) { "$($CI.Manufacturer) $($CI.Model)".Trim() } else { 'Unknown' })
        IsLaptop = [bool]$IL
        OnAC = $(if ($pwr) { $pwr.OnAC } else { $null })
        PowerConfidence = $(if ($pwr) { $pwr.Confidence } else { 'fail' })
        Gpus = @($GPU | ForEach-Object { [PSCustomObject]@{ Name=$_.Name; Vendor=$_.Vendor; Integrated=$_.Integrated; Dedicated=$_.Dedicated; Basic=$_.Basic; Virtual=$_.Virtual; VRAM=$_.VRAM; DriverKey=$_.RegKey } })
        Displays = @($DI | ForEach-Object { [PSCustomObject]@{ Device=$_.DID; Name=$_.DN; Width=$_.W; Height=$_.H; Refresh=$_.RR; MaxRefresh=$_.MR } })
        Nics = @($NN)
        Items = @($items)
        Summary = [PSCustomObject]@{ Total=$items.Count; Applied=$ok; Pending=$no; NotApplicable=$na; Checking=$chk }
        PendingReboot = (Get-TxPendingReboot)
        LastApply = (Get-TxPendingState)
        # v5.0: 快照只带概览需要的轻量诊断; 完整诊断由「诊断报告」页按需加载
        Diagnostics = @(Get-TxBriefDiagnostics)
    }
}

# ── 预设方案 ──────────────────────────────────────────────
$PROFILES = Join-Path $SD 'profiles.json'
function Get-TxProfiles {
    $builtin = @(
        [PSCustomObject]@{ Name='推荐'; Builtin=$true; Ids=@($O | Where-Object R -eq 'low' | ForEach-Object { $_.Id }) },
        [PSCustomObject]@{ Name='全量'; Builtin=$true; Ids=@($O | ForEach-Object { $_.Id }) },
        [PSCustomObject]@{ Name='仅游戏录制/后台'; Builtin=$true; Ids=@($O | Where-Object { $_.Cat -in @('游戏录制','内存与存储') } | ForEach-Object { $_.Id }) }
    )
    $custom = @()
    try {
        if (Test-Path $PROFILES) {
            $j = Get-Content -Raw $PROFILES | ConvertFrom-Json
            if ($j -and $j.Profiles) {
                $custom = @($j.Profiles | ForEach-Object { [PSCustomObject]@{ Name=[string]$_.Name; Builtin=$false; Ids=@($_.Ids) } })
            }
        }
    } catch {}
    return @($builtin + $custom)
}
function Save-TxProfile {
    param([string]$Name, [string[]]$Ids)
    if (!$Name) { throw '方案名称不能为空' }
    $custom = @()
    try {
        if (Test-Path $PROFILES) {
            $j = Get-Content -Raw $PROFILES | ConvertFrom-Json
            if ($j -and $j.Profiles) { $custom = @($j.Profiles) }
        }
    } catch {}
    $custom = @($custom | Where-Object { [string]$_.Name -ne $Name })
    $custom += [PSCustomObject]@{ Name=$Name; Ids=@($Ids) }
    @{ Profiles=@($custom) } | ConvertTo-Json -Depth 6 | Out-File $PROFILES -Encoding UTF8
    return $Name
}
function Set-TxSelectionByProfile {
    param([string]$Name)
    $p = Get-TxProfiles | Where-Object { $_.Name -eq $Name } | Select-Object -First 1
    if (!$p) { throw "方案不存在: $Name" }
    $ids = @($p.Ids)
    foreach ($it in $O) { $it.E = ($ids -contains $it.Id) }
    return $p
}

function Show-TxPreview($Preview) {
    $pv = @($Preview)
    if (!$pv.Count) { Write-Host "`n[预览] 所选项目均已处于推荐值，无需变更" -ForegroundColor Green; return }
    Write-Host "`n[变更预览] 共 $($pv.Count) 项 (预览模式不会写入系统)" -ForegroundColor Cyan
    foreach ($p in $pv) {
        $tag = ''
        if ($p.NeedsReboot) { $tag = ' [需重启]' }
        Write-Host ("  {0}`n      当前: {1}  ->  目标: {2}{3}" -f $p.Name, $p.Current, $p.Target, $tag) -ForegroundColor Gray
    }
}

# ★ v4.7 关键修复: APL 原先从未被主循环调用过, 菜单提示"Enter=应用"却什么都不做
function APL {
    param([switch]$Preview)
    $sel = @($O | Where-Object E)
    if (!$sel) { Write-Host "`n[提示] 未勾选任何项 (按 A 可全选推荐项)" -ForegroundColor Yellow; Read-Host '按回车继续'; return }
    $deps = CDK $sel
    if ($deps) {
        Write-Host "`n[依赖提醒]" -ForegroundColor Yellow
        foreach ($d in $deps) { Write-Host "  ● $($d.Item) → 建议同时勾选: $($d.Dep)" -ForegroundColor Yellow }
        if (!$Preview) {
            Write-Host "`n继续? (Y/N): " -NoNewline -ForegroundColor Yellow
            $k = [Console]::ReadKey($true); Write-Host $k.KeyChar
            if ($k.KeyChar -notmatch '^[Yy是]') { return }
        }
    }

    if ($Preview) {
        Log "===== 预览 $($sel.Count) 项 =====" 'Cyan'
        $r = Invoke-TxApply -Items $sel -DryRun
        Show-TxPreview $r.Preview
        if ($r.Errors.Count) {
            Write-Host "`n[预览中发现的问题]" -ForegroundColor Yellow
            foreach ($e in $r.Errors) { Write-Host "  - $($e.Name): $($e.Message)" -ForegroundColor Red }
        }
        Write-Host "`n  * 预览不会修改系统; 确认无误后回菜单按 Enter 应用" -ForegroundColor DarkGray
        Read-Host '按回车返回'
        return
    }

    Write-Host "`n即将应用 $($sel.Count) 项:" -ForegroundColor Cyan
    $sel | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
    Write-Host "`n确认? (Y/N): " -NoNewline -ForegroundColor Cyan
    $k = [Console]::ReadKey($true); Write-Host $k.KeyChar
    if ($k.KeyChar -notmatch '^[Yy是]') { Write-Host "已取消" -ForegroundColor Yellow; Read-Host '按回车继续'; return }

    Log "===== 应用 $($sel.Count) 项 =====" 'Cyan'
    $r = Invoke-TxApply -Items $sel -Yes
    if ($r.RegDir) { Log "[.reg快照] $($r.RegDir)" 'Cyan' }
    if ($r.Backup) { Log "[JSON备份] $($r.Backup)" 'Cyan' }
    Log "===== 完成: 成功$($r.Ok) 失败$($r.Fail) =====" 'Green'
    Write-Host "`n  * 需重启生效: HAGS / DRR / TCP卸载 / Intel核显四项 / 网卡省电 / 独显项" -ForegroundColor Yellow
    Write-Host "  * 即时生效: 注册表游戏项 / 电源项 / 刷新率" -ForegroundColor Yellow
    if ($r.Errors.Count) {
        Write-Host "`n  [失败明细]" -ForegroundColor Red
        foreach ($e in $r.Errors) { Write-Host "  - $($e.Name): $($e.Message)" -ForegroundColor Red }
    }
    Read-Host "`n按回车返回"
}

function RST {
    $fs = @(Get-ChildItem $BK -Filter backup_*.json -EA 0 | Sort-Object LastWriteTime -Descending)
    if (!$fs -or $fs.Count -eq 0) { Write-Host "`n[提示] 无备份" -ForegroundColor Yellow; Read-Host '按回车继续'; return }
    Write-Host "`n可用备份:" -ForegroundColor Cyan
    $i = 0
    foreach ($f in $fs) { $i++; Write-Host "  $i. $($f.Name) ($($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))" -ForegroundColor Gray }
    $pk = Read-Host "`n编号 (回车=最新, N=取消)"
    if ($pk -match '^[Nn]') { return }
    $tg = $null
    if (!$pk) { $tg = $fs[0] }
    elseif ($pk -match '^\d+$') {
        $pi = [int]$pk - 1
        if ($pi -ge 0 -and $pi -lt $fs.Count) { $tg = $fs[$pi] }
    }
    if (!$tg) { Write-Host "无效编号" -ForegroundColor Red; Read-Host '按回车继续'; return }

    Log "===== 还原 $($tg.Name) =====" 'Cyan'
    try {
        $r = Restore-TxBackupFile -Path $tg.FullName
    } catch {
        Write-Host "备份解析失败: $($_.Exception.Message)" -ForegroundColor Red
        Read-Host '按回车继续'; return
    }
    $ver = '旧版(字段名兼容模式)'
    if ($r.Version) { $ver = $r.Version }
    Write-Host "`n备份版本: $ver | 记录数: $($r.Records)" -ForegroundColor DarkGray
    Log "===== 还原完成: 成功$($r.Ok) 失败$($r.Fail) =====" 'Green'
    if ($r.Errors.Count) {
        Write-Host "  [失败明细]" -ForegroundColor Red
        foreach ($e in $r.Errors) { Write-Host "  - $($e.Id): $($e.Message)" -ForegroundColor Red }
    }
    Write-Host "  * 部分项(核显/DRR/HAGS/网卡)需重启后才完全恢复" -ForegroundColor Yellow
    Read-Host "按回车返回"
}

# ══════════════════════════════════════════════════════════
# v5.2 扩展: 驱动历史 / 游戏库 / 诊断包 / 启动项
# 全部数据留在本机脚本目录, 不联网、不上传
# ══════════════════════════════════════════════════════════
$TX_DATA = Join-Path $SD 'data'
if (-not (Test-Path -LiteralPath $TX_DATA)) { try { New-Item -ItemType Directory -Path $TX_DATA -Force | Out-Null } catch {} }
$TX_HIST  = Join-Path $TX_DATA 'driver-history.json'
$TX_GAMES = Join-Path $TX_DATA 'games.json'
$TX_DIAG  = Join-Path $SD 'diagnostics'

# ── 版本比较 (引擎侧, 不依赖 GUI) ─────────────────────────
function Compare-TxEngineVersion([string]$a, [string]$b) {
    if (-not $a -and -not $b) { return 0 }
    if (-not $a) { return -1 }
    if (-not $b) { return 1 }
    $pa = @([regex]::Matches($a, '\d+') | ForEach-Object { [int]$_.Value })
    $pb = @([regex]::Matches($b, '\d+') | ForEach-Object { [int]$_.Value })
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $x = 0; $y = 0
        if ($i -lt $pa.Count) { $x = $pa[$i] }
        if ($i -lt $pb.Count) { $y = $pb[$i] }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return 1 }
    }
    return 0
}

# ── 驱动版本历史 / 回退检测 ───────────────────────────────
function Read-TxDriverHistory {
    $empty = @{ Devices = @{}; LastChanges = @() }
    if (-not (Test-Path -LiteralPath $TX_HIST)) { return $empty }
    try {
        $j = Get-Content -Raw -LiteralPath $TX_HIST | ConvertFrom-Json
        $map = @{}
        if ($j -and $j.Devices) {
            foreach ($p in $j.Devices.PSObject.Properties) { $map[$p.Name] = $p.Value }
        }
        $last = @()
        if ($j -and $j.LastChanges) { $last = @($j.LastChanges) }
        return @{ Devices = $map; LastChanges = $last }
    } catch { return $empty }
}

function Save-TxDriverHistory($hist) {
    try {
        $obj = [ordered]@{
            Version     = 1
            Updated     = (Get-Date).ToString('s')
            Devices     = $hist.Devices
            LastChanges = @($hist.LastChanges)
        }
        ($obj | ConvertTo-Json -Depth 8) | Out-File -LiteralPath $TX_HIST -Encoding UTF8
        return $true
    } catch { return $false }
}

# 比对本次扫描与上次记录, 返回变化列表并更新历史
function Update-TxDriverHistory {
    param($Devices, [switch]$NoSave)
    $hist = Read-TxDriverHistory
    $map = $hist.Devices
    $changes = New-Object System.Collections.ArrayList
    $now = (Get-Date).ToString('s')
    foreach ($d in @($Devices)) {
        if (-not $d) { continue }
        $id = [string]$d.DeviceId
        $ver = [string]$d.Version
        if (-not $id -or -not $ver) { continue }
        $inf = [string]$d.InfName
        $old = $null
        if ($map.ContainsKey($id)) { $old = $map[$id] }
        if ($old -and $old.Version) {
            $fromVer = [string]$old.Version
            $fromInf = ''
            try { $fromInf = [string]$old.Inf } catch {}
            $cmp = Compare-TxEngineVersion $ver $fromVer
            if ($cmp -lt 0) {
                [void]$changes.Add([PSCustomObject]@{
                    Type = 'RolledBack'; DeviceId = $id; Name = [string]$d.Name
                    From = $fromVer; To = $ver; FromInf = $fromInf; ToInf = $inf; At = $now
                })
            } elseif ($cmp -gt 0) {
                [void]$changes.Add([PSCustomObject]@{
                    Type = 'Updated'; DeviceId = $id; Name = [string]$d.Name
                    From = $fromVer; To = $ver; FromInf = $fromInf; ToInf = $inf; At = $now
                })
            } elseif ($inf -and $fromInf -and $inf -ne $fromInf) {
                [void]$changes.Add([PSCustomObject]@{
                    Type = 'Rebound'; DeviceId = $id; Name = [string]$d.Name
                    From = $fromVer; To = $ver; FromInf = $fromInf; ToInf = $inf; At = $now
                })
            }
        }
        $map[$id] = [PSCustomObject]@{
            Name = [string]$d.Name; Class = [string]$d.Class; Inf = $inf
            Version = $ver; Date = [string]$d.Date; At = $now
        }
    }
    $last = @($hist.LastChanges)
    if ($changes.Count -gt 0) { $last = @(@($last) + @($changes.ToArray()) | Select-Object -Last 20) }
    $hist.LastChanges = @($last)
    if (-not $NoSave) { $null = Save-TxDriverHistory $hist }
    return [PSCustomObject]@{ Changes = @($changes.ToArray()); Hist = $hist }
}

# ── 游戏库: Steam / Epic 扫描 ─────────────────────────────
function Get-TxSteamRoots {
    $roots = New-Object System.Collections.ArrayList
    $cands = New-Object System.Collections.ArrayList
    try {
        $p = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction SilentlyContinue).SteamPath
        if ($p) { [void]$cands.Add([string]$p) }
    } catch {}
    foreach ($k in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $p = (Get-ItemProperty -Path $k -Name InstallPath -ErrorAction SilentlyContinue).InstallPath
            if ($p) { [void]$cands.Add([string]$p) }
        } catch {}
    }
    foreach ($c in @($cands.ToArray())) {
        if (-not $c -or -not (Test-Path -LiteralPath $c)) { continue }
        try { $c = [IO.Path]::GetFullPath($c) } catch { continue }
        $have = $false
        foreach ($x in $roots) { if ($x -eq $c) { $have = $true; break } }
        if (-not $have) { [void]$roots.Add($c) }
        foreach ($vdf in @((Join-Path $c 'steamapps\libraryfolders.vdf'), (Join-Path $c 'config\libraryfolders.vdf'))) {
            if (-not (Test-Path -LiteralPath $vdf)) { continue }
            try {
                $txt = Get-Content -Raw -LiteralPath $vdf
                foreach ($m in [regex]::Matches($txt, '"path"\s+"([^"]+)"')) {
                    $lp = $m.Groups[1].Value -replace '\\\\', '\'
                    if (-not (Test-Path -LiteralPath $lp)) { continue }
                    try { $lp = [IO.Path]::GetFullPath($lp) } catch { continue }
                    $have = $false
                    foreach ($x in $roots) { if ($x -eq $lp) { $have = $true; break } }
                    if (-not $have) { [void]$roots.Add($lp) }
                }
            } catch {}
        }
    }
    return @($roots.ToArray())
}

function Test-TxGameExeCandidate([string]$path) {
    if (-not $path) { return $false }
    $name = [IO.Path]::GetFileName($path)
    if ($name -match '(?i)unins|setup|install|vcredist|redist|dxsetup|dxwebsetup|crash|report|update|dotnet|benchmark|bugreport|tinydl|teniodl|launcher|proxy|helper|service|sguard|anticheat|icreate|ffmpeg|ffprobe|obs-|recorder|epicwebhelper|msdk|cosupload|crossproxy|browser|diagnose') { return $false }
    if ($path -match '(?i)\\(engine|thirdparty|redist|runtime|plugins|anticheatexpert|icreatesdk|recorder-release|aclos|common_apps|downloading)(\\|$)') { return $false }
    return $true
}

function Find-TxGameExe([string]$dir, [string]$name) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return '' }
    $best = ''
    try {
        $exes = @(Get-ChildItem -LiteralPath $dir -Filter *.exe -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
            Where-Object { Test-TxGameExeCandidate $_.FullName })
        if ($exes.Count -eq 0) { return '' }
        $key = ($name -replace '[^0-9A-Za-z\u4e00-\u9fa5]', '').ToLowerInvariant()
        $max = 0
        foreach ($e in $exes) {
            $n = [IO.Path]::GetFileNameWithoutExtension($e.Name).ToLowerInvariant()
            $k = ($n -replace '[^0-9A-Za-z\u4e00-\u9fa5]', '')
            if ($key.Length -ge 3 -and $k.Length -ge 3 -and ($key.Contains($k) -or $k.Contains($key))) { return $e.FullName }
            if ($e.Length -gt $max) { $max = $e.Length; $best = $e.FullName }
        }
    } catch {}
    return $best
}

function Find-TxWeGameExe([string]$dir) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return '' }
    $best = ''
    $bestScore = [long]-1
    try {
        $exes = @(Get-ChildItem -LiteralPath $dir -Filter *.exe -File -Recurse -ErrorAction SilentlyContinue)
        foreach ($e in $exes) {
            if ([long]$e.Length -lt 1048576) { continue }
            if (-not (Test-TxGameExeCandidate $e.FullName)) { continue }
            $score = [long]$e.Length
            if ($e.Name -match '(?i)-Win64-Shipping\.exe$') { $score += [long]5000000000 }
            if ($e.FullName -match '(?i)\\Binaries\\Win64\\') { $score += [long]1000000000 }
            if ($score -gt $bestScore) { $bestScore = $score; $best = $e.FullName }
        }
    } catch {}
    return $best
}

function Get-TxWeGameRoots {
    $roots = New-Object System.Collections.ArrayList
    $cands = New-Object System.Collections.ArrayList
    if ($env:ProgramFiles) { [void]$cands.Add((Join-Path $env:ProgramFiles 'WeGameApps')) }
    if (${env:ProgramFiles(x86)}) { [void]$cands.Add((Join-Path ${env:ProgramFiles(x86)} 'WeGameApps')) }
    try {
        foreach ($d in [IO.DriveInfo]::GetDrives()) {
            try {
                if ($d.DriveType -eq [IO.DriveType]::Fixed -and $d.IsReady) {
                    [void]$cands.Add((Join-Path $d.RootDirectory.FullName 'WeGameApps'))
                }
            } catch {}
        }
    } catch {}
    foreach ($c in @($cands.ToArray())) {
        if (-not $c) { continue }
        if (-not (Test-Path -LiteralPath $c)) { continue }
        try { $c = [IO.Path]::GetFullPath($c) } catch { continue }
        $have = $false
        foreach ($x in $roots) { if ($x -eq $c) { $have = $true; break } }
        if (-not $have) { [void]$roots.Add($c) }
    }
    return @($roots.ToArray())
}

function Get-TxWeGameGames {
    $out = New-Object System.Collections.ArrayList
    foreach ($root in @(Get-TxWeGameRoots)) {
        $rail = Join-Path $root 'rail_apps'
        if (-not (Test-Path -LiteralPath $rail)) { continue }
        foreach ($g in @(Get-ChildItem -LiteralPath $rail -Directory -ErrorAction SilentlyContinue)) {
            try {
                $name = [string]$g.Name
                $appId = ''
                $m = [regex]::Match($name, '^(.*?)\s*\((\d+)\)\s*$')
                if ($m.Success) { $name = $m.Groups[1].Value.Trim(); $appId = $m.Groups[2].Value }
                $idf = Join-Path (Join-Path $g.FullName 'rail_files') 'rail_game_identify.json'
                if (Test-Path -LiteralPath $idf) {
                    try {
                        $j = Get-Content -Raw -LiteralPath $idf | ConvertFrom-Json
                        if ($j.game_id) { $appId = [string]$j.game_id }
                    } catch {}
                }
                $exe = Find-TxWeGameExe $g.FullName
                if (-not $exe) { continue }
                [void]$out.Add([PSCustomObject]@{
                    Name = $name; Exe = $exe; Dir = $g.FullName; Source = 'WeGame'; AppId = $appId
                })
            } catch {}
        }
    }
    return @($out.ToArray())
}

function Get-TxSteamGames {
    $out = New-Object System.Collections.ArrayList
    foreach ($root in @(Get-TxSteamRoots)) {
        $apps = Join-Path $root 'steamapps'
        if (-not (Test-Path -LiteralPath $apps)) { continue }
        foreach ($acf in @(Get-ChildItem -LiteralPath $apps -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
            try {
                $txt = Get-Content -Raw -LiteralPath $acf.FullName
                $mn = [regex]::Match($txt, '"name"\s+"([^"]*)"')
                $mi = [regex]::Match($txt, '"installdir"\s+"([^"]*)"')
                if (-not $mn.Success -or -not $mi.Success) { continue }
                $name = $mn.Groups[1].Value
                $inst = $mi.Groups[1].Value
                $dir = Join-Path (Join-Path $apps 'common') $inst
                if (-not (Test-Path -LiteralPath $dir)) { continue }
                $exe = Find-TxGameExe $dir $name
                if (-not $exe) { continue }
                $ma = [regex]::Match($txt, '"appid"\s+"([^"]*)"')
                [void]$out.Add([PSCustomObject]@{
                    Name = $name; Exe = $exe; Dir = $dir; Source = 'Steam'
                    AppId = $(if ($ma.Success) { $ma.Groups[1].Value } else { '' })
                })
            } catch {}
        }
    }
    return @($out.ToArray())
}

function Get-TxEpicGames {
    $out = New-Object System.Collections.ArrayList
    $dir = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter *.item -File -ErrorAction SilentlyContinue)) {
        try {
            $j = Get-Content -Raw -LiteralPath $f.FullName | ConvertFrom-Json
            $loc = [string]$j.InstallLocation
            if (-not $loc -or -not (Test-Path -LiteralPath $loc)) { continue }
            $exe = ''
            $le = [string]$j.LaunchExecutable
            if ($le) {
                $p = $le
                if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $loc $le }
                if (Test-Path -LiteralPath $p) { $exe = $p }
            }
            if (-not $exe) { $exe = Find-TxGameExe $loc ([string]$j.DisplayName) }
            if (-not $exe) { continue }
            [void]$out.Add([PSCustomObject]@{
                Name = [string]$j.DisplayName; Exe = $exe; Dir = $loc; Source = 'Epic'; AppId = [string]$j.AppName
            })
        } catch {}
    }
    return @($out.ToArray())
}

# ── 游戏配置文档 ──────────────────────────────────────────
function Read-TxGameDoc {
    $empty = @{ Version = 1; Manual = @(); Profiles = @{} }
    if (-not (Test-Path -LiteralPath $TX_GAMES)) { return $empty }
    try {
        $j = Get-Content -Raw -LiteralPath $TX_GAMES | ConvertFrom-Json
        $manual = @()
        if ($j -and $j.Manual) {
            $manual = @($j.Manual | ForEach-Object {
                [PSCustomObject]@{ Name = [string]$_.Name; Exe = [string]$_.Exe; Dir = [string]$_.Dir }
            })
        }
        $prof = @{}
        if ($j -and $j.Profiles) {
            foreach ($p in $j.Profiles.PSObject.Properties) { $prof[$p.Name.ToLowerInvariant()] = $p.Value }
        }
        return @{ Version = 1; Manual = $manual; Profiles = $prof }
    } catch { return $empty }
}

function Save-TxGameDoc($doc) {
    try {
        $obj = [ordered]@{
            Version = 1
            Updated = (Get-Date).ToString('s')
            Manual  = @($doc.Manual)
            Profiles = $doc.Profiles
        }
        $json = $obj | ConvertTo-Json -Depth 10
        $dir = Split-Path -Parent $TX_GAMES
        if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [IO.File]::WriteAllText($TX_GAMES, $json, (New-Object System.Text.UTF8Encoding($true)))
        return $true
    } catch { return $false }
}

function Convert-TxGameProfile($raw) {
    $p = [PSCustomObject]@{
        Priority = 'Normal'; Affinity = 'All'; FsOff = $false; GpuHigh = $false
        RunAsAdmin = $false; Args = ''; HasSaved = $false
    }
    if ($raw) {
        $p.HasSaved = $true
        try { if ($raw.Priority) { $p.Priority = [string]$raw.Priority } } catch {}
        try { if ($raw.Affinity) { $p.Affinity = [string]$raw.Affinity } } catch {}
        try { if ($null -ne $raw.FsOff) { $p.FsOff = [bool]$raw.FsOff } } catch {}
        try { if ($null -ne $raw.GpuHigh) { $p.GpuHigh = [bool]$raw.GpuHigh } } catch {}
        try { if ($null -ne $raw.RunAsAdmin) { $p.RunAsAdmin = [bool]$raw.RunAsAdmin } } catch {}
        try { if ($raw.Args) { $p.Args = [string]$raw.Args } } catch {}
    }
    return $p
}

function Get-TxGames {
    param([switch]$Force)
    if (-not $Force -and $script:TxGameCache -and ((Get-Date) - $script:TxGameAt).TotalSeconds -lt 60) {
        return @($script:TxGameCache)
    }
    $doc = Read-TxGameDoc
    $list = New-Object System.Collections.ArrayList
    $seen = @{}
    $all = @()
    $all += @(Get-TxSteamGames)
    $all += @(Get-TxEpicGames)
    $all += @(Get-TxWeGameGames)
    $all += @($doc.Manual | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Exe = $_.Exe; Dir = $_.Dir; Source = '手动'; AppId = '' }
    })
    foreach ($g in $all) {
        if (-not $g -or -not $g.Exe) { continue }
        $k = ([string]$g.Exe).ToLowerInvariant()
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        $prof = $null
        if ($doc.Profiles.ContainsKey($k)) { $prof = $doc.Profiles[$k] }
        [void]$list.Add([PSCustomObject]@{
            Name    = [string]$g.Name
            Exe     = [string]$g.Exe
            Dir     = [string]$g.Dir
            Source  = [string]$g.Source
            AppId   = [string]$g.AppId
            Exists  = (Test-Path -LiteralPath ([string]$g.Exe))
            Manual  = ([string]$g.Source -eq '手动')
            Profile = (Convert-TxGameProfile $prof)
        })
    }
    $sorted = @($list.ToArray() | Sort-Object Name)
    $script:TxGameCache = $sorted
    $script:TxGameAt = Get-Date
    return @($sorted)
}

function Add-TxManualGame([string]$name, [string]$exe) {
    $exe = ([string]$exe).Trim().Trim('"')
    if (-not $exe) { throw '请选择游戏程序' }
    try { $exe = [IO.Path]::GetFullPath($exe) } catch {}
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "程序文件不存在: $exe" }
    if (-not $name) { $name = [IO.Path]::GetFileNameWithoutExtension($exe) }
    $doc = Read-TxGameDoc
    $exists = @($doc.Manual | Where-Object { ([string]$_.Exe).ToLowerInvariant() -eq $exe.ToLowerInvariant() })
    if ($exists.Count -eq 0) {
        $doc.Manual = @(@($doc.Manual) + @([PSCustomObject]@{ Name = $name; Exe = $exe; Dir = (Split-Path -Parent $exe) }))
    } else {
        $doc.Manual = @($doc.Manual | ForEach-Object {
            if (([string]$_.Exe).ToLowerInvariant() -eq $exe.ToLowerInvariant()) {
                [PSCustomObject]@{ Name = $name; Exe = $exe; Dir = (Split-Path -Parent $exe) }
            } else { $_ }
        })
    }
    if (-not (Save-TxGameDoc $doc)) { throw "无法写入游戏库数据，请检查目录权限: $TX_GAMES" }
    $script:TxGameAt = [DateTime]::MinValue
    return $name
}

function Remove-TxManualGame([string]$exe) {
    $exe = ([string]$exe).Trim().Trim('"')
    if ($exe) { $null = Remove-TxGameProfile -exe $exe }
    $doc = Read-TxGameDoc
    $doc.Manual = @($doc.Manual | Where-Object { ([string]$_.Exe).ToLowerInvariant() -ne $exe.ToLowerInvariant() })
    if ($doc.Profiles.ContainsKey($exe.ToLowerInvariant())) { $doc.Profiles.Remove($exe.ToLowerInvariant()) }
    if (-not (Save-TxGameDoc $doc)) { throw "无法写入游戏库数据，请检查目录权限: $TX_GAMES" }
    $script:TxGameAt = [DateTime]::MinValue
    return '已从游戏库移除'
}

# ── 单游戏配置: 应用的注册表项都可还原 ────────────────────
function Get-TxRegValueAt([string]$path, [string]$name) {
    try {
        $k = Get-Item -LiteralPath $path -ErrorAction Stop
        $v = $k.GetValue($name)
        if ($null -eq $v) { return [PSCustomObject]@{ Exists = $false; Value = '' } }
        return [PSCustomObject]@{ Exists = $true; Value = [string]$v }
    } catch { return [PSCustomObject]@{ Exists = $false; Value = '' } }
}

function Set-TxRegValueAt([string]$path, [string]$name, $value) {
    if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
    if ($null -eq $value -or [string]$value -eq '') {
        Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    } else {
        New-ItemProperty -Path $path -Name $name -Value ([string]$value) -PropertyType String -Force | Out-Null
    }
}

function Get-TxGameRegistryPaths {
    return [PSCustomObject]@{
        Layers = "$HKU_BASE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"
        Gpu    = "$HKU_BASE\SOFTWARE\Microsoft\DirectX\UserGpuPreferences"
    }
}

function Save-TxGameProfile([string]$exe, $profile) {
    if (-not $exe) { throw '缺少程序路径' }
    $doc = Read-TxGameDoc
    $key = $exe.ToLowerInvariant()
    $p = [ordered]@{
        Priority = [string]$profile.Priority
        Affinity = [string]$profile.Affinity
        FsOff = [bool]$profile.FsOff
        GpuHigh = [bool]$profile.GpuHigh
        RunAsAdmin = [bool]$profile.RunAsAdmin
        Args = [string]$profile.Args
        Updated = (Get-Date).ToString('s')
    }
    $old = $null
    if ($doc.Profiles.ContainsKey($key)) { $old = $doc.Profiles[$key] }
    $rp = Get-TxGameRegistryPaths
    if ($old) {
        try {
            if ($null -ne $old.PSObject.Properties['OrigLayerExists']) {
                $p.OrigLayerExists = [bool]$old.OrigLayerExists
                $p.OrigLayer = [string]$old.OrigLayer
                $p.OrigGpuExists = [bool]$old.OrigGpuExists
                $p.OrigGpu = [string]$old.OrigGpu
            }
        } catch {}
    }
    if (-not $p.Contains('OrigLayerExists')) {
        $cur = Get-TxRegValueAt $rp.Layers $exe
        $p.OrigLayerExists = [bool]$cur.Exists
        $p.OrigLayer = [string]$cur.Value
        $curG = Get-TxRegValueAt $rp.Gpu $exe
        $p.OrigGpuExists = [bool]$curG.Exists
        $p.OrigGpu = [string]$curG.Value
    }
    $doc.Profiles[$key] = [PSCustomObject]$p
    if (-not (Save-TxGameDoc $doc)) { throw "无法写入游戏库数据，请检查目录权限: $TX_GAMES" }
    $script:TxGameAt = [DateTime]::MinValue
    return $true
}

function Apply-TxGameProfile([string]$exe, $profile) {
    $res = [PSCustomObject]@{ Ok = $false; Msg = '' }
    if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { $res.Msg = '程序文件不存在'; return $res }
    try {
        $rp = Get-TxGameRegistryPaths
        $flags = @()
        if ($profile.FsOff) { $flags += 'DISABLEDXMAXIMIZEDWINDOWEDMODE' }
        if ($profile.RunAsAdmin) { $flags += 'RUNASADMIN' }
        $layerVal = ''
        if ($flags.Count -gt 0) { $layerVal = '~ ' + ($flags -join ' ') }
        Set-TxRegValueAt $rp.Layers $exe $layerVal
        if ($profile.GpuHigh) { Set-TxRegValueAt $rp.Gpu $exe 'GpuPreference=2;' }
        else { Set-TxRegValueAt $rp.Gpu $exe $null }
        $res.Ok = $true
        $res.Msg = '单游戏配置已写入'
    } catch {
        $res.Msg = $_.Exception.Message
    }
    return $res
}

function Remove-TxGameProfile([string]$exe) {
    $res = [PSCustomObject]@{ Ok = $false; Msg = '' }
    try {
        $doc = Read-TxGameDoc
        $key = $exe.ToLowerInvariant()
        $old = $null
        if ($doc.Profiles.ContainsKey($key)) { $old = $doc.Profiles[$key] }
        $rp = Get-TxGameRegistryPaths
        if ($old) {
            $le = $true; $lv = ''; $ge = $true; $gv = ''
            try {
                if ($null -ne $old.PSObject.Properties['OrigLayerExists']) {
                    $le = [bool]$old.OrigLayerExists; $lv = [string]$old.OrigLayer
                    $ge = [bool]$old.OrigGpuExists; $gv = [string]$old.OrigGpu
                }
            } catch {}
            if ($le) { Set-TxRegValueAt $rp.Layers $exe $lv } else { Set-TxRegValueAt $rp.Layers $exe $null }
            if ($ge) { Set-TxRegValueAt $rp.Gpu $exe $gv } else { Set-TxRegValueAt $rp.Gpu $exe $null }
            $doc.Profiles.Remove($key)
            $null = Save-TxGameDoc $doc
            $script:TxGameAt = [DateTime]::MinValue
            $res.Ok = $true
            $res.Msg = '已还原到配置前的状态'
        } else {
            $res.Ok = $true
            $res.Msg = '没有保存过配置'
        }
    } catch { $res.Msg = $_.Exception.Message }
    return $res
}

function Start-TxGame([string]$exe, $profile) {
    $r = [PSCustomObject]@{ Ok = $false; Pid = 0; Msg = ''; Message = '' }
    try {
        $exe = ([string]$exe).Trim().Trim('"')
        if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "程序文件不存在: $exe" }
        $wd = Split-Path -Parent $exe
        $argList = @()
        if ($profile -and $profile.Args) {
            $argText = ([string]$profile.Args).Trim()
            if ($argText) {
                $argList = @([regex]::Matches($argText, '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') })
            }
        }
        $useAdmin = $false
        try { $useAdmin = [bool]$profile.RunAsAdmin } catch {}
        $sp = @{ FilePath = $exe; WorkingDirectory = $wd; PassThru = $true; ErrorAction = 'Stop' }
        if ($argList.Count -gt 0) { $sp.ArgumentList = $argList }
        if ($useAdmin) { $sp.Verb = 'RunAs' }
        $p = Start-Process @sp
        $r.Pid = [int]$p.Id
        $prio = '默认'
        $aff = '全部核心'
        try {
            if ($profile.Priority -eq 'High') { $p.PriorityClass = [Diagnostics.ProcessPriorityClass]::High; $prio = '高' }
            elseif ($profile.Priority -eq 'AboveNormal') { $p.PriorityClass = [Diagnostics.ProcessPriorityClass]::AboveNormal; $prio = '高于正常' }
        } catch { $prio = '默认(设置失败)' }
        if ($profile.Affinity -eq 'Physical') {
            try {
                $n = 0
                foreach ($cpu in @(Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue)) { $n += [int]$cpu.NumberOfCores }
                if ($n -ge 1 -and $n -lt 63) {
                    $mask = [long](([long]1 -shl $n) - 1)
                    $p.ProcessorAffinity = [IntPtr]$mask
                    $aff = "前 $n 个逻辑处理器"
                }
            } catch { $aff = '全部核心(设置失败)' }
        }
        $r.Ok = $true
        $r.Msg = "已启动 · 优先级 $prio · 亲和性 $aff"
    } catch { $r.Msg = $_.Exception.Message }
    $r.Message = $r.Msg
    return $r
}

# ── 启动项 / 后台进程 (只读) ──────────────────────────────
function Get-TxStartupEntries {
    $list = New-Object System.Collections.ArrayList
    $seen = @{}
    $add = {
        param($name, $cmd, $src, $loc)
        if (-not $name -and -not $cmd) { return }
        $key = ([string]$name + '|' + [string]$cmd).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { return }
        $seen[$key] = $true
        [void]$list.Add([PSCustomObject]@{
            Name = [string]$name; Command = [string]$cmd; Source = [string]$src; Location = [string]$loc
        })
    }
    $keys = @(
        @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; S = '注册表 · 本机' },
        @{ P = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; S = '注册表 · 本机(32位)' },
        @{ P = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; S = '注册表 · 当前用户' },
        @{ P = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; S = '注册表 · 仅一次' },
        @{ P = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce'; S = '注册表 · 仅一次' }
    )
    foreach ($k in $keys) {
        try {
            $item = Get-ItemProperty -Path $k.P -ErrorAction SilentlyContinue
            if (-not $item) { continue }
            foreach ($p in $item.PSObject.Properties) {
                if ($p.Name -like 'PS*') { continue }
                & $add $p.Name ([string]$p.Value) $k.S $k.P
            }
        } catch {}
    }
    $folders = @()
    try { $folders += [Environment]::GetFolderPath('Startup') } catch {}
    try { $folders += [Environment]::GetFolderPath('CommonStartup') } catch {}
    foreach ($f in $folders) {
        if (-not $f -or -not (Test-Path -LiteralPath $f)) { continue }
        foreach ($file in @(Get-ChildItem -LiteralPath $f -File -ErrorAction SilentlyContinue)) {
            & $add $file.BaseName $file.FullName '启动文件夹' $f
        }
    }
    return @($list.ToArray() | Sort-Object Name)
}

function Get-TxBackgroundProcesses([int]$Top = 12) {
    $list = @()
    try {
        $list = @(Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.Id -ne 0 -and $_.ProcessName -notin @('System', 'Idle', 'Registry')
        } | ForEach-Object {
            $mem = 0.0
            try { $mem = [double]$_.WorkingSet64 / 1MB } catch {}
            [PSCustomObject]@{
                Name = [string]$_.ProcessName
                Title = [string]$_.MainWindowTitle
                Id = [int]$_.Id
                MemMB = [Math]::Round($mem, 1)
                Foreground = [bool]($_.MainWindowHandle -ne 0)
            }
        } | Sort-Object MemMB -Descending | Select-Object -First $Top)
    } catch {}
    return @($list)
}

# ── 诊断包导出 ────────────────────────────────────────────
function Export-TxDiagnosticBundle {
    param([string]$OutDir)
    if (-not $OutDir) { $OutDir = $TX_DIAG }
    if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
    $stamp = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $tmp = Join-Path $env:TEMP ('txdiag_' + $stamp)
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $utf8 = New-Object System.Text.UTF8Encoding($true)
    $write = {
        param($name, $lines)
        $p = Join-Path $tmp $name
        [IO.File]::WriteAllLines($p, [string[]]@($lines), $utf8)
    }
    try {
        # 系统信息
        $sys = New-Object System.Collections.ArrayList
        [void]$sys.Add("时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
        [void]$sys.Add("计算机: $env:COMPUTERNAME · 用户: $env:USERNAME")
        [void]$sys.Add("管理员: $isAdmin · PowerShell: $($PSVersionTable.PSVersion)")
        try {
            $si = Get-TxSystemInfo
            if ($si.OS) { [void]$sys.Add("系统: $($si.OS.Caption) build $($si.OS.BuildNumber)") }
            if ($si.CPU) { [void]$sys.Add("CPU: $([string]$si.CPU.Name) · $($si.CPU.NumberOfCores) 核 / $($si.CPU.NumberOfLogicalProcessors) 线程") }
            $mods = @($si.Memory)
            if ($mods.Count) {
                $total = ($mods | Measure-Object Capacity -Sum).Sum / 1GB
                [void]$sys.Add(("内存: {0:N1} GB · {1} 根" -f $total, $mods.Count))
            }
            if ($si.Computer) { [void]$sys.Add("机型: $($si.Computer.Manufacturer) $($si.Computer.Model)") }
        } catch {}
        try { [void]$sys.Add("电源: $(if ($null -ne (PWRST)) { (PWRST).OnAC } else { '未知' })") } catch {}
        try { [void]$sys.Add("脚本目录: $SD") } catch {}
        & $write 'system.txt' $sys

        # dxdiag
        try {
            $dx = Join-Path $tmp 'dxdiag.txt'
            $p = Start-Process -FilePath 'dxdiag.exe' -ArgumentList @('/t', $dx) -PassThru -WindowStyle Hidden -ErrorAction Stop
            if ($p) { $null = $p.WaitForExit(30000) }
        } catch {}

        # 驱动清单
        try {
            $lines = @(& pnputil.exe /enum-drivers 2>&1 | ForEach-Object { [string]$_ })
            & $write 'drivers.txt' $lines
        } catch {}
        try {
            $lines = @(& pnputil.exe /enum-devices /connected 2>&1 | ForEach-Object { [string]$_ })
            & $write 'devices.txt' $lines
        } catch {}

        # 最近 24 小时错误事件
        $ev = New-Object System.Collections.ArrayList
        foreach ($log in @('System', 'Application')) {
            try {
                $rows = @(Get-WinEvent -FilterHashtable @{ LogName = $log; Level = @(1, 2, 3); StartTime = (Get-Date).AddHours(-24) } -MaxEvents 120 -ErrorAction SilentlyContinue)
                foreach ($e in $rows) {
                    $msg = [string]$e.Message
                    try { $msg = ($msg -replace "`r?`n", ' ') } catch {}
                    if ($msg.Length -gt 300) { $msg = $msg.Substring(0, 300) + '...' }
                    [void]$ev.Add(("{0} | {1} | {2} | {3}" -f $e.TimeCreated, $e.LevelDisplayName, $e.ProviderName, $msg))
                }
            } catch {}
        }
        & $write 'events.txt' $ev

        # 当前优化状态
        try {
            $snap = Get-TxSnapshot
            $json = $snap | ConvertTo-Json -Depth 5
            [IO.File]::WriteAllText((Join-Path $tmp 'optimization-state.json'), $json, $utf8)
        } catch {}

        # 本机配置与日志
        $copies = @(
            @{ Src = (Join-Path $SD 'gui-settings.json'); Name = 'gui-settings.json' },
            @{ Src = (Join-Path $SD 'profiles.json'); Name = 'profiles.json' },
            @{ Src = (Join-Path $TX_DATA 'driver-history.json'); Name = 'driver-history.json' },
            @{ Src = (Join-Path $TX_DATA 'games.json'); Name = 'games.json' }
        )
        foreach ($c in $copies) {
            try { if (Test-Path -LiteralPath $c.Src) { Copy-Item -LiteralPath $c.Src -Destination (Join-Path $tmp $c.Name) -Force } } catch {}
        }
        try {
            $logs = @(Get-ChildItem -LiteralPath $SD -Filter 'optimize_*.log' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3)
            foreach ($lg in $logs) {
                try { Copy-Item -LiteralPath $lg.FullName -Destination (Join-Path $tmp $lg.Name) -Force } catch {}
            }
        } catch {}

        $zip = Join-Path $OutDir ("诊断包_$stamp.zip")
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue }
        Compress-Archive -Path (Join-Path $tmp '*') -DestinationPath $zip -CompressionLevel Optimal -ErrorAction Stop
        return $zip
    } finally {
        try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
    }
}

# ── 优化项目录导出 (v6.2: 供 C# Core / CLI 读取完整定义) ──
# 检测与硬件分支仍由 PowerShell 维护，执行/备份/还原由 Core 统一完成。
if ($Catalog) {
    try {
        $catalogData = [PSCustomObject]@{
            Version = $script:AppVersion
            Time    = (Get-Date).ToString('s')
            Context = [PSCustomObject]@{
                Machine         = $(if ($CI) { "$($CI.Manufacturer) $($CI.Model)".Trim() } else { 'Unknown' })
                IsLaptop        = [bool]$IL
                HasDedicatedGpu = [bool]$HAS_DGPU
                HasIntegratedGpu= [bool]$HAS_IGPU
                HasWifi         = [bool]$HAS_WIFI
                IsIntel         = [bool]$II
                IsCombo         = [bool]$CMB
                OsBuild         = [Environment]::OSVersion.Version.Build
                UserSid         = $Sid
                IntelKey        = $ISK
                GpuPreferencesPath = $URP
            }
            Items   = @($O)
        }
        $json = $catalogData | ConvertTo-Json -Depth 12
        if ($CatalogOut) {
            $dir = Split-Path -Parent $CatalogOut
            if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.File]::WriteAllText($CatalogOut, $json, (New-Object System.Text.UTF8Encoding($false)))
            Write-Host "目录已写入: $CatalogOut" -ForegroundColor Green
        } else {
            Write-Output $json
        }
    } catch {
        Write-Host "目录导出失败: $($_.Exception.Message)" -ForegroundColor Red
    }
    return
}

# ── 命令行 / GUI 入口 ─────────────────────────────────────
if ($EngineOnly) { return }

if ($Gui) {
    $gui = Join-Path $SD '游戏性能优化-GUI.ps1'
    if (Test-Path $gui) {
        # ★ v5.0: 图形界面独立进程运行, 隐藏控制台窗口; GUI 已继承管理员权限与启动者 SID
        try {
            Start-Process powershell.exe -ArgumentList @(
                '-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden',
                '-File',"`"$gui`"",'-NoElevate','-Sid',$Sid
            ) | Out-Null
        } catch {
            Write-Host "GUI 启动失败: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "GUI 文件缺失: $gui" -ForegroundColor Red
    }
    return
}

if ($Status) {
    $snap = Get-TxSnapshot
    $json = $snap | ConvertTo-Json -Depth 8
    if ($OutFile) {
        $json | Out-File -FilePath $OutFile -Encoding UTF8
        Write-Host "状态已写入: $OutFile" -ForegroundColor Green
    } else {
        Write-Output $json
    }
    return
}

if ($Report) {
    $f = Export-TxReport -Path $OutFile
    Write-Host "报告已导出: $f" -ForegroundColor Green
    return
}

if ($Profile) {
    try { Set-TxSelectionByProfile -Name $Profile | Out-Null }
    catch { Write-Host "载入方案失败: $($_.Exception.Message)" -ForegroundColor Red; return }
} elseif ($ApplyRecommended) {
    $O | Where-Object R -eq 'low' | ForEach-Object { $_.E = $true }
}

if ($DryRun -or $ApplyRecommended) {
    $sel = @($O | Where-Object E)
    if (!$sel.Count) { Write-Host "没有选中项" -ForegroundColor Yellow; return }
    $r = Invoke-TxApply -Items $sel -DryRun:$DryRun -Yes:$Yes -RestorePoint:$RestorePoint
    if ($DryRun) {
        Show-TxPreview $r.Preview
        if ($r.Errors.Count) {
            Write-Host "`n[预览中发现的问题]" -ForegroundColor Yellow
            foreach ($e in $r.Errors) { Write-Host "  - $($e.Name): $($e.Message)" -ForegroundColor Red }
        }
    } else {
        if ($r.RegDir) { Write-Host ".reg 快照: $($r.RegDir)" -ForegroundColor Cyan }
        if ($r.Backup) { Write-Host "JSON 备份: $($r.Backup)" -ForegroundColor Cyan }
        Write-Host "应用完成: 成功$($r.Ok) 失败$($r.Fail)" -ForegroundColor Green
        if ($r.Errors.Count) {
            foreach ($e in $r.Errors) { Write-Host "  - $($e.Name): $($e.Message)" -ForegroundColor Red }
        }
    }
    return
}

if ($RestoreLatest) {
    $fs = @(Get-ChildItem $BK -Filter backup_*.json -EA 0 | Sort-Object LastWriteTime -Descending)
    if (!$fs.Count) { Write-Host '无备份' -ForegroundColor Yellow; return }
    try {
        $r = Restore-TxBackupFile -Path $fs[0].FullName
        Write-Host "还原完成($($fs[0].Name)): 成功$($r.Ok) 失败$($r.Fail)" -ForegroundColor Green
        foreach ($e in @($r.Errors)) { Write-Host "  - $($e.Id): $($e.Message)" -ForegroundColor Red }
    } catch { Write-Host "还原失败: $($_.Exception.Message)" -ForegroundColor Red }
    return
}

if ($RestoreAll) {
    $r = Restore-TxAll
    Write-Host "全量还原完成: $($r.Files) 份备份, 成功$($r.Ok) 失败$($r.Fail)" -ForegroundColor Green
    foreach ($e in @($r.Errors)) { Write-Host "  - $($e.Id): $($e.Message)" -ForegroundColor Red }
    return
}

# ── 控制台主循环 ──────────────────────────────────────────
$pendMsg = $null
try {
    $p = Test-TxPendingState
    if ($p) { $pendMsg = "[$($p.Stage)] $($p.Msg)" }
} catch {}
while ($true) {
    SMN
    if ($pendMsg) { Write-Host "  [上次应用] $pendMsg" -ForegroundColor Yellow; $pendMsg = $null }
    while ([Console]::KeyAvailable) { [Console]::ReadKey($true) | Out-Null }
    [string]$ch = (Read-Host "`n请选择").Trim()
    # ★ v4.7: 空输入 = 应用 (菜单一直这么写, 但原代码在这里直接 continue 重画菜单)
    if ([string]::IsNullOrEmpty($ch)) { APL; continue }
    switch -Regex ($ch) {
        '^[Qq]$'  { Log "退出"; Write-Host "已退出, 日志: $LOG" -ForegroundColor Green; return }
        '^[Aa]$'  { $O | Where-Object R -eq 'low' | ForEach-Object { $_.E = $true } }
        '^[Nn]$'  { $O | ForEach-Object { $_.E = $false } }
        '^[Dd]$'  { APL -Preview }
        '^[Pp]$'  { PMN }
        '^[Ss]$'  { SSC }
        '^[Gg]$'  { SRT; Read-Host '按回车返回' }
        '^[Ee]$'  {
            $f = Export-TxReport
            Write-Host "`n报告已导出: $f" -ForegroundColor Green
            Read-Host '按回车返回'
        }
        '^[Tt]$'  {
            Write-Host "`n正在创建系统还原点 (可能需要 10-30 秒)..." -ForegroundColor Cyan
            $r = New-TxRestorePoint
            if ($r.Ok) { Write-Host "  $($r.Msg)" -ForegroundColor Green }
            else { Write-Host "  未创建: $($r.Msg)" -ForegroundColor Yellow }
            Read-Host '按回车返回'
        }
        '^[Ll]$'  {
            $fs = @(Get-ChildItem $BK -Filter backup_*.json -EA 0)
            Write-Host "`n[全量还原] 将按时间倒序回放 $($fs.Count) 份备份, 最终回到最早一次应用前的状态。" -ForegroundColor Yellow
            Write-Host "此操作会覆盖之后的设置, 确定? (Y/N): " -NoNewline -ForegroundColor Yellow
            $k = [Console]::ReadKey($true); Write-Host $k.KeyChar
            if ($k.KeyChar -match '^[Yy是]') {
                $r = Restore-TxAll
                Log "===== 全量还原完成: 文件$($r.Files) 成功$($r.Ok) 失败$($r.Fail) =====" 'Green'
                if ($r.Errors.Count) {
                    foreach ($e in @($r.Errors)) { Write-Host "  - $($e.Id): $($e.Message)" -ForegroundColor Red }
                }
            } else { Write-Host '已取消' -ForegroundColor Yellow }
            Read-Host '按回车返回'
        }
        '^[Rr]$'  { RST }
        '^\d+$'   {
            $n = [int]$ch
            if ($script:IM.ContainsKey($n)) { $script:IM[$n].E = !$script:IM[$n].E }
            else { Write-Host "超出范围 (1-$($script:IM.Count))" -ForegroundColor Red; Start-Sleep -Milliseconds 800 }
        }
        default  {
            Write-Host "无法识别: '$ch'" -ForegroundColor Red
            Start-Sleep -Milliseconds 800
        }
    }
}
