param(
    [switch]$NoElevate,
    [string]$Sid,
    [string]$Preview,
    [string]$PreviewPage = 'all',
    [switch]$SelfTest,
    [string]$OutFile
)

# 引擎 dot-source 时会声明同名 $OutFile 参数并清空, 先保存 GUI 自己的参数
$script:GuiOutFile = $OutFile

# ══════════════════════════════════════════════════════════
# 游戏性能优化中心 · 旧版 WinForms 备用界面（随 v6 便携包分发）
# 引擎、控制台、CLI、GUI 共用 游戏性能优化.ps1 的同一套逻辑
# ══════════════════════════════════════════════════════════

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ── 界面设置 (实验性功能) ─────────────────────────────────
# 设置文件默认放在脚本目录; TX_GUI_SETTINGS 仅用于测试时指向临时文件
$script:GuiSettingsFile = Join-Path $PSScriptRoot 'gui-settings.json'
if ($env:TX_GUI_SETTINGS) { $script:GuiSettingsFile = [string]$env:TX_GUI_SETTINGS }
$script:AppVersion = '6.3.0'
$script:RepoSlug   = 'tianxiclaw/game-performance-optimizer'
$script:GuiCfg = [ordered]@{
    ExperimentalDpi = $false
    ShowRenderInfo  = $false
    Theme           = 'dark'
    MinimizeToTray  = $false
    NotifyDriver    = $true
}

function Load-GuiSettings {
    try {
        if (-not (Test-Path -LiteralPath $script:GuiSettingsFile)) { return }
        $j = Get-Content -Raw -LiteralPath $script:GuiSettingsFile | ConvertFrom-Json
        if ($null -ne $j.ExperimentalDpi) { $script:GuiCfg.ExperimentalDpi = [bool]$j.ExperimentalDpi }
        if ($null -ne $j.ShowRenderInfo)  { $script:GuiCfg.ShowRenderInfo  = [bool]$j.ShowRenderInfo }
        if ([string]$j.Theme -eq 'light') { $script:GuiCfg.Theme = 'light' }
        else { $script:GuiCfg.Theme = 'dark' }
        if ($null -ne $j.MinimizeToTray) { $script:GuiCfg.MinimizeToTray = [bool]$j.MinimizeToTray }
        if ($null -ne $j.NotifyDriver)   { $script:GuiCfg.NotifyDriver   = [bool]$j.NotifyDriver }
    } catch {}
}

function Save-GuiSettings {
    try {
        $obj = [ordered]@{
            Version         = 2
            ExperimentalDpi = [bool]$script:GuiCfg.ExperimentalDpi
            ShowRenderInfo  = [bool]$script:GuiCfg.ShowRenderInfo
            Theme           = [string]$script:GuiCfg.Theme
            MinimizeToTray  = [bool]$script:GuiCfg.MinimizeToTray
            NotifyDriver    = [bool]$script:GuiCfg.NotifyDriver
            Updated         = (Get-Date).ToString('s')
        }
        ($obj | ConvertTo-Json -Depth 4) | Out-File -LiteralPath $script:GuiSettingsFile -Encoding UTF8
        return $true
    } catch { return $false }
}

Load-GuiSettings

# ── 管理员检查 / 自提升 ───────────────────────────────────
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin  = (New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate -and -not $Preview -and -not $SelfTest) {
    $sid0 = $identity.User.Value
    try {
        Start-Process powershell.exe -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-STA','-WindowStyle','Hidden',
            '-File',"`"$PSCommandPath`"",'-NoElevate','-Sid',$sid0
        ) -Verb RunAs | Out-Null
    } catch {}
    exit
}
if (-not $Sid) { $Sid = $identity.User.Value }

# ── 实验性高 DPI: 必须在加载 System.Drawing / 创建任何字体或窗口之前设置 ──
# GDI+ 初始化时会缓存屏幕 DPI。若先创建 FontFamily/Font, 点值字体将永久按
# 96 DPI 计算, 导致高缩放比下"布局放大但文字仍很小"。
$script:DPI_NOW = 96
$script:DPI_AWARE = 0
$script:DPI_ENABLED = $false
$script:UI_SCALE = 1.0
if ([bool]$script:GuiCfg.ExperimentalDpi) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class TxDpiBridge
{
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetProcessDpiAwarenessContext(IntPtr ctx);
    [DllImport("user32.dll")]
    public static extern uint GetDpiForSystem();
    [DllImport("user32.dll")]
    public static extern IntPtr GetThreadDpiAwarenessContext();
    [DllImport("user32.dll")]
    public static extern int GetAwarenessFromDpiAwarenessContext(IntPtr ctx);

    public static bool EnablePmv2()
    {
        try { return SetProcessDpiAwarenessContext(new IntPtr(-4)); }
        catch { return false; }
    }
    public static int SystemDpi()
    {
        try { return (int)GetDpiForSystem(); }
        catch { return 96; }
    }
    public static int Awareness()
    {
        try { return GetAwarenessFromDpiAwarenessContext(GetThreadDpiAwarenessContext()); }
        catch { return 0; }
    }
}
'@
    } catch {}
    try {
        [void][TxDpiBridge]::EnablePmv2()
        $script:DPI_AWARE = [TxDpiBridge]::Awareness()
        $script:DPI_NOW = [TxDpiBridge]::SystemDpi()
        if ($script:DPI_AWARE -ge 2) {
            $script:DPI_ENABLED = $true
            if ($script:DPI_NOW -gt 96) {
                $script:UI_SCALE = [Math]::Round([Math]::Min(3.0, [double]$script:DPI_NOW / 96.0), 2)
                if ($script:UI_SCALE -lt 1.0) { $script:UI_SCALE = 1.0 }
            }
        }
    } catch {}
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Core
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# ── 主题 ─────────────────────────────────────────────────
$script:C_BG      = [Drawing.Color]::FromArgb(11,15,22)
$script:C_PANEL   = [Drawing.Color]::FromArgb(18,24,36)
$script:C_PANEL2  = [Drawing.Color]::FromArgb(14,20,29)
$script:C_BORDER  = [Drawing.Color]::FromArgb(38,50,74)
$script:C_TEXT    = [Drawing.Color]::FromArgb(230,237,243)
$script:C_SUB     = [Drawing.Color]::FromArgb(143,163,184)
$script:C_DIM     = [Drawing.Color]::FromArgb(100,116,139)
$script:C_CYAN    = [Drawing.Color]::FromArgb(76,194,224)
$script:C_GREEN   = [Drawing.Color]::FromArgb(61,214,140)
$script:C_ORANGE  = [Drawing.Color]::FromArgb(230,180,92)
$script:C_RED     = [Drawing.Color]::FromArgb(240,113,120)
$script:C_PURPLE  = [Drawing.Color]::FromArgb(139,124,246)
$script:C_BLUE    = [Drawing.Color]::FromArgb(96,165,250)
$script:C_GREEN_BG  = [Drawing.Color]::FromArgb(17,46,36)
$script:C_GREEN_BD  = [Drawing.Color]::FromArgb(38,104,76)
$script:C_ORANGE_BG = [Drawing.Color]::FromArgb(43,35,22)
$script:C_ORANGE_BD = [Drawing.Color]::FromArgb(113,88,42)
$script:C_GRAY_BG   = [Drawing.Color]::FromArgb(26,34,49)
$script:C_GRAY_BD   = [Drawing.Color]::FromArgb(51,65,85)
$script:C_RED_BG    = [Drawing.Color]::FromArgb(48,24,28)
$script:C_RED_BD    = [Drawing.Color]::FromArgb(122,50,56)

# 浅色主题: 只替换语义色板; 内联颜色统一走 TC() 做映射
$script:ThemeName = 'dark'
try { if ([string]$script:GuiCfg.Theme -eq 'light') { $script:ThemeName = 'light' } } catch {}
if ($script:ThemeName -eq 'light') {
    $script:C_BG      = [Drawing.Color]::FromArgb(243,246,250)
    $script:C_PANEL   = [Drawing.Color]::FromArgb(255,255,255)
    $script:C_PANEL2  = [Drawing.Color]::FromArgb(236,241,247)
    $script:C_BORDER  = [Drawing.Color]::FromArgb(214,222,232)
    $script:C_TEXT    = [Drawing.Color]::FromArgb(30,41,59)
    $script:C_SUB     = [Drawing.Color]::FromArgb(71,85,105)
    $script:C_DIM     = [Drawing.Color]::FromArgb(100,116,139)
    $script:C_CYAN    = [Drawing.Color]::FromArgb(0,115,140)
    $script:C_GREEN   = [Drawing.Color]::FromArgb(0,128,72)
    $script:C_ORANGE  = [Drawing.Color]::FromArgb(163,98,0)
    $script:C_RED     = [Drawing.Color]::FromArgb(200,45,45)
    $script:C_PURPLE  = [Drawing.Color]::FromArgb(96,64,200)
    $script:C_BLUE    = [Drawing.Color]::FromArgb(28,92,205)
    $script:C_GREEN_BG  = [Drawing.Color]::FromArgb(226,246,235)
    $script:C_GREEN_BD  = [Drawing.Color]::FromArgb(150,214,178)
    $script:C_ORANGE_BG = [Drawing.Color]::FromArgb(255,244,226)
    $script:C_ORANGE_BD = [Drawing.Color]::FromArgb(235,199,136)
    $script:C_GRAY_BG   = [Drawing.Color]::FromArgb(240,244,249)
    $script:C_GRAY_BD   = [Drawing.Color]::FromArgb(214,222,232)
    $script:C_RED_BG    = [Drawing.Color]::FromArgb(254,236,238)
    $script:C_RED_BD    = [Drawing.Color]::FromArgb(238,172,176)
}

function Get-TxHsl([int]$r, [int]$g, [int]$b) {
    $rf = $r / 255.0; $gf = $g / 255.0; $bf = $b / 255.0
    $max = [Math]::Max($rf, [Math]::Max($gf, $bf))
    $min = [Math]::Min($rf, [Math]::Min($gf, $bf))
    $l = ($max + $min) / 2.0
    $h = 0.0; $s = 0.0
    if ($max -ne $min) {
        $d = $max - $min
        if ($l -gt 0.5) { $s = $d / (2.0 - $max - $min) } else { $s = $d / ($max + $min) }
        if ($max -eq $rf) { $h = (($gf - $bf) / $d) + $(if ($gf -lt $bf) { 6 } else { 0 }) }
        elseif ($max -eq $gf) { $h = (($bf - $rf) / $d) + 2 }
        else { $h = (($rf - $gf) / $d) + 4 }
        $h = $h / 6.0
    }
    return @($h, $s, $l)
}

function Get-TxRgbFromHsl([double]$h, [double]$s, [double]$l) {
    if ($s -le 0) { $v = [int][Math]::Round($l * 255); return @($v, $v, $v) }
    $q = $l * (1 + $s)
    if ($l -ge 0.5) { $q = $l + $s - ($l * $s) }
    $p = 2 * $l - $q
    $conv = {
        param($t)
        if ($t -lt 0) { $t += 1 }
        if ($t -gt 1) { $t -= 1 }
        if ($t -lt (1.0 / 6.0)) { return $p + ($q - $p) * 6 * $t }
        if ($t -lt 0.5) { return $q }
        if ($t -lt (2.0 / 3.0)) { return $p + ($q - $p) * ((2.0 / 3.0) - $t) * 6 }
        return $p
    }
    $r = [int][Math]::Round((& $conv ($h + 1.0 / 3.0)) * 255)
    $g = [int][Math]::Round((& $conv $h) * 255)
    $b = [int][Math]::Round((& $conv ($h - 1.0 / 3.0)) * 255)
    return @($r, $g, $b)
}

# 深色主题原样返回; 浅色主题把深底/亮字映射成浅底/深字
function TC {
    param([int]$a, [int]$b, [int]$c, $d = $null)
    if ($script:ThemeName -ne 'light') {
        if ($null -ne $d) { return [Drawing.Color]::FromArgb($a, $b, $c, [int]$d) }
        return [Drawing.Color]::FromArgb($a, $b, $c)
    }
    $alpha = 255; $r = $a; $g = $b; $bl = $c
    if ($null -ne $d) { $alpha = $a; $r = $b; $g = $c; $bl = [int]$d }
    $hsl = Get-TxHsl $r $g $bl
    $h = [double]$hsl[0]; $s = [double]$hsl[1]; $l = [double]$hsl[2]
    if ($s -gt 0.45 -and $l -ge 0.38) {
        # 彩色强调色: 压到中等明度, 保证浅底上可辨认
        $l2 = 0.36
        $s2 = [Math]::Min($s, 0.9)
    } elseif ($l -ge 0.45) {
        # 浅色前景 / 文字
        $l2 = 1.0 - $l
        if ($l2 -lt 0.06) { $l2 = 0.06 }
        $s2 = [Math]::Min($s, 0.14)
    } elseif ($l -ge 0.30) {
        # 中间调: 保留层次感, 用于分隔线/次要边框
        $l2 = 1.0 - $l
        $s2 = [Math]::Min($s, 0.14)
    } else {
        # 深色面板 / 按钮底色
        $l2 = 0.86 + 0.10 * ($l / 0.30)
        if ($l2 -gt 0.975) { $l2 = 0.975 }
        $s2 = [Math]::Min($s, 0.14)
    }
    $rgb = Get-TxRgbFromHsl $h $s2 $l2
    $rr = [Math]::Min(255, [Math]::Max(0, [int]$rgb[0]))
    $gg = [Math]::Min(255, [Math]::Max(0, [int]$rgb[1]))
    $bb = [Math]::Min(255, [Math]::Max(0, [int]$rgb[2]))
    return [Drawing.Color]::FromArgb($alpha, $rr, $gg, $bb)
}

$script:FF = 'Microsoft YaHei UI'
try { $null = New-Object Drawing.FontFamily -ArgumentList $script:FF } catch { $script:FF = 'Microsoft YaHei' }

function F([double]$size, [bool]$bold = $false) {
    $st = [Drawing.FontStyle]::Regular
    if ($bold) { $st = [Drawing.FontStyle]::Bold }
    return New-Object Drawing.Font -ArgumentList @([string]$script:FF, [single]$size, $st)
}

$script:NavNumF = F 8 $false

# 按钮图标 / 悬停说明：按文案统一映射，避免每个调用点重复传参
$script:BtnIconMap = @{
    '一键优化' = 'bolt'
    '预览变更' = 'eye'
    '撤销上次优化' = 'undo'
    '查看全部' = 'arrow-right'
    '扫描本机驱动' = 'scan'
    '检测更新' = 'download'
    '设备管理器' = 'device'
    '变化记录' = 'history'
    '还原选中' = 'undo'
    '还原最近' = 'undo'
    '全部还原' = 'undo'
    '创建还原点' = 'shield'
    '打开备份目录' = 'folder'
    '刷新' = 'refresh'
    '重新扫描' = 'scan'
    '手动添加' = 'plus'
    '打开游戏目录' = 'folder'
    '保存并应用' = 'save'
    '启动游戏' = 'play'
    '恢复原值' = 'undo'
    '移除手动添加' = 'trash'
    '刷新诊断' = 'refresh'
    '导出报告' = 'download'
    '复制全部' = 'copy'
    '导出诊断包' = 'download'
    '刷新列表' = 'refresh'
    '任务管理器' = 'activity'
    '启动应用设置' = 'settings'
    '清空界面' = 'trash'
    '打开日志文件' = 'log'
    '打开脚本目录' = 'folder'
    '复制日志' = 'copy'
    '检查更新' = 'download'
    '支持作者' = 'heart'
    '查看说明' = 'info'
    '导出便携包' = 'package'
    '复制分享话术' = 'copy'
    '重启界面' = 'refresh'
    '载入方案' = 'folder'
    '保存方案' = 'save'
    '应用选中项' = 'check'
    '全选推荐' = 'check'
    '重新绑定驱动' = 'refresh'
    '清理所选旧包' = 'trash'
    '安装所选更新' = 'download'
    '隐藏所选更新' = 'eye'
    '切换所选驱动' = 'refresh'
    '复制预览' = 'copy'
    '关闭' = 'close'
    '管理' = 'settings'
}

$script:BtnTipMap = @{
    '一键优化' = '按推荐方案应用全部可优化项，应用前会自动备份原值'
    '预览变更' = '只展示将要修改的项目，不会写入系统'
    '撤销上次优化' = '按最近一次应用的备份恢复原值'
    '查看全部' = '跳转到优化项页面查看全部待应用项'
    '扫描本机驱动' = '读取本机驱动与设备信息，全程不联网'
    '检测更新' = '使用厂商官方工具检测可用驱动更新'
    '设备管理器' = '打开 Windows 设备管理器'
    '变化记录' = '查看每次扫描的驱动版本变化与回退记录'
    '还原选中' = '恢复选中备份里的原值'
    '还原最近' = '恢复最近一次应用前的状态'
    '全部还原' = '按全部备份回放原值，执行前会再次确认'
    '创建还原点' = '创建一份新的系统还原点'
    '打开备份目录' = '在资源管理器中打开 backups 文件夹'
    '刷新' = '重新读取当前页面的数据'
    '重新扫描' = '重新识别本机游戏库'
    '手动添加' = '手动选择游戏可执行文件加入游戏库'
    '打开游戏目录' = '打开所选游戏所在的文件夹'
    '保存并应用' = '保存该游戏配置并立即写入当前用户设置'
    '启动游戏' = '按当前配置启动所选游戏'
    '恢复原值' = '撤销该游戏的优先级、亲和性与显卡偏好'
    '移除手动添加' = '从游戏库移除手动添加的条目，不改动游戏文件'
    '刷新诊断' = '重新执行只读诊断检查'
    '导出报告' = '把诊断结果导出为文本报告'
    '复制全部' = '复制全部诊断结果到剪贴板'
    '导出诊断包' = '打包日志、系统信息、dxdiag 与驱动列表为 ZIP'
    '刷新列表' = '重新读取启动项与后台进程'
    '任务管理器' = '打开 Windows 任务管理器'
    '启动应用设置' = '打开 Windows 启动应用设置页'
    '清空界面' = '只清空界面显示，不删除日志文件'
    '打开日志文件' = '用默认编辑器打开当前日志'
    '打开脚本目录' = '在资源管理器中打开程序目录'
    '复制日志' = '复制界面中的日志到剪贴板'
    '检查更新' = '访问 GitHub Releases 查询最新版本，仅点击时联网'
    '支持作者' = '查看作者赞赏码'
    '查看说明' = '查看 GPU 渲染与 WPF 后端的评估说明'
    '导出便携包' = '重新打包当前程序为便携 ZIP，便于分享'
    '复制分享话术' = '复制一段可直接发给朋友的分享文案'
    '重启界面' = '保存设置并重启图形界面'
    '载入方案' = '从本地文件载入自定义优化方案'
    '保存方案' = '把当前勾选保存为自定义方案'
    '应用选中项' = '应用当前勾选的优化项，应用前自动备份'
    '全选推荐' = '勾选全部推荐项'
    '重新绑定驱动' = '把驱动重新绑定到本机 INF'
    '清理所选旧包' = '删除选中的旧驱动安装包'
    '安装所选更新' = '调用厂商官方工具安装所选更新'
    '隐藏所选更新' = '在列表中隐藏所选更新，不卸载驱动'
    '切换所选驱动' = '切换到所选的历史驱动版本'
    '复制预览' = '复制预览变更清单'
    '关闭' = '关闭当前窗口'
    '管理' = '查看该设备的驱动详情与操作'
}

$script:NavTips = @{
    overview = '硬件概览、实时监控与系统状态'
    driver   = '驱动扫描、更新检测与版本变化记录'
    game     = '为单个游戏配置优先级、亲和性与启动参数'
    items    = '按分类和风险筛选，勾选后统一应用'
    backup   = '原值备份、单项还原与全部回放'
    diag     = '只读诊断：系统、显卡、存储与驱动'
    startup  = '查看开机启动项与后台进程，不提供一键禁用'
    log      = '运行日志与错误信息'
    settings = '主题、高 DPI、托盘与通知设置'
    about    = '版本信息、能力说明与检查更新'
}

function Get-Tip {
    if ($null -eq $script:Tip) {
        $t = New-Object System.Windows.Forms.ToolTip
        $t.AutoPopDelay = 9000
        $t.InitialDelay = 400
        $t.ReshowDelay = 100
        $t.BackColor = $script:C_PANEL2
        $t.ForeColor = $script:C_TEXT
        $script:Tip = $t
    }
    return $script:Tip
}

function New-IconBitmap([string]$name, [int]$px, $color) {
    if ($px -lt 8) { $px = 8 }
    $bmp = New-Object Drawing.Bitmap -ArgumentList @($px, $px)
    $g = [Drawing.Graphics]::FromImage($bmp)
    try {
        $g.Clear([Drawing.Color]::Transparent)
        $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $r = New-Object Drawing.RectangleF -ArgumentList @(0, 0, [single]$px, [single]$px)
        [TxUi.Icons]::Draw($g, $name, $r, $color, [single]1.7)
    } finally {
        $g.Dispose()
    }
    return $bmp
}

function UiPx([double]$v) {
    return [int][Math]::Round($v * [double]$script:UI_SCALE)
}

function New-Label($parent, $text, [int]$x, [int]$y, [int]$w, [int]$h, [double]$size = 9, [bool]$bold = $false, $color = $null, $align = 'MiddleLeft') {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = [string]$text
    $l.Location = New-Object Drawing.Point -ArgumentList @($x, $y)
    $l.Size = New-Object Drawing.Size -ArgumentList @($w, $h)
    $l.Font = F $size $bold
    if ($null -eq $color) { $color = $script:C_TEXT }
    $l.ForeColor = $color
    $l.BackColor = [Drawing.Color]::Transparent
    $l.TextAlign = $align
    $l.AutoEllipsis = $true
    $parent.Controls.Add($l)
    return $l
}

function New-Badge($parent, $text, [int]$x, [int]$y, [int]$w, [int]$h, $fill, $border, $fore, [double]$size = 8) {
    $b = New-Object TxUi.Badge
    $b.Text = [string]$text
    $b.Location = New-Object Drawing.Point -ArgumentList @($x, $y)
    $b.Size = New-Object Drawing.Size -ArgumentList @($w, $h)
    $b.Fill = $fill
    $b.BorderColor = $border
    $b.ForeColor = $fore
    $b.Radius = [int][Math]::Round(8 * $script:UI_SCALE)
    $b.Font = F $size $true
    $parent.Controls.Add($b)
    return $b
}

function New-Btn($parent, $text, [int]$x, [int]$y, [int]$w, [int]$h, $bg, $fg, [double]$size = 9, [bool]$bold = $true) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = [string]$text
    $b.Location = New-Object Drawing.Point -ArgumentList @($x, $y)
    $b.Size = New-Object Drawing.Size -ArgumentList @($w, $h)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.FlatAppearance.MouseOverBackColor = $bg
    $b.FlatAppearance.MouseDownBackColor = $bg
    $b.BackColor = $bg
    $b.ForeColor = $fg
    $b.Font = F $size $bold
    $b.Cursor = [System.Windows.Forms.Cursors]::Hand
    $b.UseVisualStyleBackColor = $false
    try {
        $iconName = ''
        if ($script:BtnIconMap.ContainsKey([string]$text)) { $iconName = $script:BtnIconMap[[string]$text] }
        if ($iconName -ne '' -and $w -ge 88 -and $h -ge 28) {
            $px = [int][Math]::Round(15 * [double]$script:UI_SCALE)
            $b.Image = New-IconBitmap $iconName $px $fg
            $b.ImageAlign = 'MiddleLeft'
            $b.TextAlign = 'MiddleLeft'
            $b.TextImageRelation = 'ImageBeforeText'
            $b.Padding = New-Object System.Windows.Forms.Padding -ArgumentList @(8, 0, 0, 0)
        }
    } catch {}
    try {
        if ($script:BtnTipMap.ContainsKey([string]$text)) {
            (Get-Tip).SetToolTip($b, $script:BtnTipMap[[string]$text])
        }
    } catch {}
    $b.Add_MouseEnter({ param($s, $e) $s.FlatAppearance.BorderSize = 1; $s.FlatAppearance.BorderColor = $s.ForeColor })
    $b.Add_MouseLeave({ param($s, $e) $s.FlatAppearance.BorderSize = 0 })
    $parent.Controls.Add($b)
    Set-Round $b ([int][Math]::Round(10 * $script:UI_SCALE))
    return $b
}

function New-Card($parent, [int]$x, [int]$y, [int]$w, [int]$h, [int]$radius = 12, $fill = $null, $border = $null) {
    $c = New-Object TxUi.Card
    $c.Location = New-Object Drawing.Point -ArgumentList @($x, $y)
    $c.Size = New-Object Drawing.Size -ArgumentList @($w, $h)
    $c.Radius = [int][Math]::Round($radius * $script:UI_SCALE)
    if ($null -ne $fill) { $c.Fill = $fill }
    if ($null -ne $border) { $c.BorderColor = $border }
    $c.BackColor = $c.Fill
    $parent.Controls.Add($c)
    try { $c.RefreshRegion() } catch {}
    return $c
}

# ── 统一页面标题栏 / 卡片小标题 ──────────────────────────
$script:PageHF = @{
    Tag   = F 8 $true
    Title = F 20 $true
    Sub   = F 9
    Stat  = F 11 $true
    StatL = F 8
}

function New-PageHero($page, [string]$eyebrow, [string]$title, [string]$subtitle, $stats = $null, [int]$x = 20, [int]$y = 16, [int]$w = 0, [int]$h = 126) {
    if ($w -le 0) { $w = $cw - 40 }
    $card = New-Card $page $x $y $w $h 16 $script:C_PANEL $script:C_BORDER
    $card.Anchor = 'Top, Left, Right'
    $card.Tag = @{ Eyebrow = $eyebrow; Title = $title; Subtitle = $subtitle }
    $card.Add_Paint({
        param($s, $e)
        try {
            $sc = [double]$script:UI_SCALE
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $r = New-Object Drawing.Rectangle -ArgumentList @(0, 0, ($s.Width - 1), ($s.Height - 1))
            $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @($r, (TC 14 32 46), (TC 24 28 52), [single](20 * $sc))
            $g.FillRectangle($lg, $r)
            $lg.Dispose()
            $ar = New-Object Drawing.Rectangle -ArgumentList @(0, 1, $s.Width, [int](2 * $sc))
            $ag = New-Object Drawing.SolidBrush -ArgumentList @($script:C_CYAN)
            $g.FillRectangle($ag, $ar)
            $ag.Dispose()
            $glow = New-Object Drawing.SolidBrush -ArgumentList @((TC 10 76 194 224))
            $g.FillEllipse($glow, ($s.Width - 260 * $sc), (-130 * $sc), (300 * $sc), (300 * $sc))
            $glow.Dispose()
            $tg = $s.Tag
            $b1 = New-Object Drawing.SolidBrush -ArgumentList @($script:C_CYAN)
            $g.DrawString([string]$tg.Eyebrow, $script:PageHF.Tag, $b1, (24 * $sc), (12 * $sc))
            $b1.Dispose()
            $b2 = New-Object Drawing.SolidBrush -ArgumentList @($script:C_TEXT)
            $g.DrawString([string]$tg.Title, $script:PageHF.Title, $b2, (22 * $sc), (28 * $sc))
            $b2.Dispose()
            $b3 = New-Object Drawing.SolidBrush -ArgumentList @($script:C_SUB)
            $g.DrawString([string]$tg.Subtitle, $script:PageHF.Sub, $b3, (24 * $sc), (60 * $sc))
            $b3.Dispose()
        } catch {}
    })
    $vals = New-Object System.Collections.ArrayList
    $caps = New-Object System.Collections.ArrayList
    if ($null -ne $stats) {
        $arr = @($stats)
        $n = $arr.Count
        $sx = $w - (104 * $n)
        for ($i = 0; $i -lt $n; $i++) {
            $st = $arr[$i]
            $fg = $script:C_TEXT
            if ($st.ContainsKey('C')) { $fg = $st.C }
            $sz = 18
            if ($st.ContainsKey('S')) { $sz = [double]$st.S }
            $v = New-Label $card ([string]$st.V) ($sx + $i * 104) 28 100 34 $sz $true $fg 'MiddleRight'
            $v.Anchor = 'Top, Right'
            $cp = New-Label $card ([string]$st.T) ($sx + $i * 104) 64 100 18 8.5 $false $script:C_SUB 'MiddleRight'
            $cp.Anchor = 'Top, Right'
            [void]$vals.Add($v)
            [void]$caps.Add($cp)
        }
    }
    return [PSCustomObject]@{ Card = $card; Values = @($vals); Captions = @($caps) }
}

function New-SectionTitle($parent, [string]$text, [int]$x, [int]$y, [int]$w = 240, [double]$size = 11, $color = $null) {
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Location = New-Object Drawing.Point -ArgumentList @(($x + 1), ($y + 5))
    $bar.Size = New-Object Drawing.Size -ArgumentList @(3, 12)
    $bar.BackColor = $script:C_CYAN
    $parent.Controls.Add($bar)
    if ($null -eq $color) { $color = $script:C_TEXT }
    return New-Label $parent $text ($x + 10) $y ($w - 10) 22 $size $true $color
}

function New-Check($parent, $text, [int]$x, [int]$y, [int]$w, [int]$h, [bool]$checked = $false) {
    $c = New-Object TxUi.Check
    $c.Text = [string]$text
    $c.Location = New-Object Drawing.Point -ArgumentList @($x, $y)
    $c.Size = New-Object Drawing.Size -ArgumentList @($w, $h)
    $c.ForeColor = $script:C_TEXT
    $c.BackColor = [Drawing.Color]::Transparent
    $c.Font = F 9
    $c.UiScale = [single]$script:UI_SCALE
    $c.BoxFill = TC 22 30 44
    $c.BoxBorder = TC 71 85 105
    $c.CheckColor = $script:C_CYAN
    $c.Checked = $checked
    $parent.Controls.Add($c)
    return $c
}

function New-Combo($parent, [int]$x, [int]$y, [int]$w) {
    $c = New-Object TxUi.Combo
    $c.Location = New-Object Drawing.Point -ArgumentList @($x, $y)
    $c.Size = New-Object Drawing.Size -ArgumentList @($w, 30)
    $c.Font = F 9
    $c.FillColor = $script:C_PANEL2
    $c.BorderColor = $script:C_BORDER
    $c.TextColor = $script:C_TEXT
    $c.MutedColor = $script:C_DIM
    $c.HoverColor = (TC 24 34 49)
    $c.Radius = [int](8 * $script:UI_SCALE)
    $parent.Controls.Add($c)
    return $c
}

function New-TextBox($parent, [int]$x, [int]$y, [int]$w, [int]$h, [string]$placeholder) {
    $t = New-Object TxUi.Input
    $t.Location = New-Object Drawing.Point -ArgumentList @($x, $y)
    $t.Size = New-Object Drawing.Size -ArgumentList @($w, $h)
    $t.BackColor = $script:C_PANEL2
    $t.ForeColor = $script:C_DIM
    $t.BorderColor = $script:C_BORDER
    $t.FocusBorderColor = $script:C_CYAN
    $t.Font = F 9
    $t.Text = $placeholder
    $t.Tag = @{ Placeholder = $placeholder; Active = $false }
    $t.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Enter') { $e.SuppressKeyPress = $true } })
    $t.Add_GotFocus({
        param($s, $e)
        if (-not $s.Tag.Active) { $s.Text = ''; $s.ForeColor = $script:C_TEXT; $s.Tag.Active = $true }
    })
    $t.Add_LostFocus({
        param($s, $e)
        if ($s.Text.Trim() -eq '') {
            $s.Tag.Active = $false
            $s.ForeColor = $script:C_DIM
            $s.Text = $s.Tag.Placeholder
        }
    })
    $parent.Controls.Add($t)
    return $t
}

function Set-Round($ctrl, [int]$r) {
    try {
        $w = $ctrl.Width; $h = $ctrl.Height; $d = $r * 2
        if ($d -gt $w) { $d = $w }
        if ($d -gt $h) { $d = $h }
        if ($d -le 1) { return }
        $p = New-Object Drawing.Drawing2D.GraphicsPath
        $p.AddArc(0, 0, $d, $d, 180, 90)
        $p.AddArc($w - $d, 0, $d, $d, 270, 90)
        $p.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
        $p.AddArc(0, $h - $d, $d, $d, 90, 90)
        $p.CloseFigure()
        $ctrl.Region = New-Object Drawing.Region -ArgumentList @($p)
        $p.Dispose()
    } catch {}
}

# ── 自定义控件 ───────────────────────────────────────────
$cs = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace TxUi
{
    public static class Native
    {
        public static bool DarkEnabled = true;

        [DllImport("dwmapi.dll")]
        public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        [DllImport("uxtheme.dll", CharSet = CharSet.Unicode)]
        public static extern int SetWindowTheme(IntPtr hWnd, string pszSubAppName, string pszSubIdList);

        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        public static void DarkTitle(IntPtr h)
        {
            if (!DarkEnabled) return;
            int v = 1;
            try { DwmSetWindowAttribute(h, 20, ref v, 4); } catch { }
            try { DwmSetWindowAttribute(h, 19, ref v, 4); } catch { }
        }

        public static void RoundCorners(IntPtr h)
        {
            int v = 2;
            try { DwmSetWindowAttribute(h, 33, ref v, 4); } catch { }
        }

        public static void DragMove(IntPtr h)
        {
            try { ReleaseCapture(); SendMessage(h, 0xA1, new IntPtr(2), IntPtr.Zero); } catch { }
        }

        public static void DarkScroll(IntPtr h)
        {
            if (!DarkEnabled) return;
            try { SetWindowTheme(h, "DarkMode_Explorer", null); } catch { }
        }

        // 输入类控件（ComboBox / TextBox）用 CFD 主题，去掉系统白边
        public static void DarkControl(IntPtr h)
        {
            if (!DarkEnabled) return;
            try { SetWindowTheme(h, "DarkMode_CFD", null); } catch { }
        }

        private delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        private static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc lpEnumFunc, IntPtr lParam);

        // 递归给子窗口（表格滚动条 / 输入框内部窗口）应用深色主题
        public static void DarkChildren(IntPtr h)
        {
            if (!DarkEnabled) return;
            try
            {
                EnumChildWindows(h, delegate(IntPtr child, IntPtr p)
                {
                    try { SetWindowTheme(child, "DarkMode_Explorer", null); } catch { }
                    return true;
                }, IntPtr.Zero);
            }
            catch { }
        }
    }

    // 线性图标：24x24 视口，按目标矩形等比缩放；只描边或少量实心，避免视觉噪声
    public static class Icons
    {
        private static void RR(GraphicsPath p, float x, float y, float w, float h, float r)
        {
            if (r < 0.1f) { p.AddRectangle(new RectangleF(x, y, w, h)); return; }
            float d = r * 2f;
            p.AddArc(x, y, d, d, 180, 90);
            p.AddArc(x + w - d, y, d, d, 270, 90);
            p.AddArc(x + w - d, y + h - d, d, d, 0, 90);
            p.AddArc(x, y + h - d, d, d, 90, 90);
            p.CloseFigure();
        }

        public static void Draw(Graphics g, string name, RectangleF r, Color color, float width)
        {
            if (g == null || string.IsNullOrEmpty(name)) return;
            if (r.Width <= 1f || r.Height <= 1f) return;
            SmoothingMode old = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float s = Math.Min(r.Width, r.Height);
            GraphicsState st = g.Save();
            g.TranslateTransform(r.X + (r.Width - s) / 2f, r.Y + (r.Height - s) / 2f);
            g.ScaleTransform(s / 24f, s / 24f);
            using (Pen p = new Pen(color, width))
            {
                p.StartCap = LineCap.Round;
                p.EndCap = LineCap.Round;
                p.LineJoin = LineJoin.Round;
                using (SolidBrush b = new SolidBrush(color))
                {
                    string n = name.ToLowerInvariant();
                    switch (n)
                    {
                        case "overview":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 3, 3, 7.5f, 7.5f, 1.8f);
                                RR(path, 13.5f, 3, 7.5f, 7.5f, 1.8f);
                                RR(path, 3, 13.5f, 7.5f, 7.5f, 1.8f);
                                RR(path, 13.5f, 13.5f, 7.5f, 7.5f, 1.8f);
                                g.DrawPath(p, path);
                            }
                            break;
                        case "driver":
                        case "device":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 6, 6, 12, 12, 2.2f);
                                g.DrawPath(p, path);
                            }
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 9.2f, 9.2f, 5.6f, 5.6f, 1.2f);
                                g.DrawPath(p, path);
                            }
                            g.DrawLine(p, 9.5f, 2, 9.5f, 6);
                            g.DrawLine(p, 14.5f, 2, 14.5f, 6);
                            g.DrawLine(p, 9.5f, 18, 9.5f, 22);
                            g.DrawLine(p, 14.5f, 18, 14.5f, 22);
                            g.DrawLine(p, 2, 9.5f, 6, 9.5f);
                            g.DrawLine(p, 2, 14.5f, 6, 14.5f);
                            g.DrawLine(p, 18, 9.5f, 22, 9.5f);
                            g.DrawLine(p, 18, 14.5f, 22, 14.5f);
                            break;
                        case "game":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 3, 7.5f, 18, 10, 4.5f);
                                g.DrawPath(p, path);
                            }
                            g.DrawLine(p, 7.4f, 12.5f, 10.6f, 12.5f);
                            g.DrawLine(p, 9, 10.9f, 9, 14.1f);
                            g.FillEllipse(b, 16.1f, 10.7f, 1.8f, 1.8f);
                            g.FillEllipse(b, 13.7f, 12.9f, 1.8f, 1.8f);
                            break;
                        case "items":
                        case "tune":
                        {
                            float[] ys = new float[] { 7f, 12f, 17f };
                            float[] xs = new float[] { 9f, 15f, 7f };
                            for (int i = 0; i < 3; i++)
                            {
                                g.DrawLine(p, 3, ys[i], 21, ys[i]);
                                g.FillEllipse(b, xs[i] - 2f, ys[i] - 2f, 4f, 4f);
                            }
                            break;
                        }
                        case "backup":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 3.5f, 4, 17, 4.5f, 1.2f);
                                g.DrawPath(p, path);
                            }
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 5, 9.5f, 14, 10.5f, 1.6f);
                                g.DrawPath(p, path);
                            }
                            g.DrawLine(p, 9, 13.5f, 15, 13.5f);
                            break;
                        case "diag":
                        case "activity":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 3, 4.5f, 18, 15, 3);
                                g.DrawPath(p, path);
                            }
                            g.DrawLines(p, new PointF[] { new PointF(6, 12), new PointF(9, 12), new PointF(11, 8), new PointF(13, 16), new PointF(15, 12), new PointF(18, 12) });
                            break;
                        case "startup":
                        case "power":
                            g.DrawArc(p, 5, 5, 14, 14, -55, 290);
                            g.DrawLine(p, 12, 3.5f, 12, 11.5f);
                            break;
                        case "log":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 5, 3, 14, 18, 2);
                                g.DrawPath(p, path);
                            }
                            g.DrawLine(p, 8.5f, 8, 15.5f, 8);
                            g.DrawLine(p, 8.5f, 12, 15.5f, 12);
                            g.DrawLine(p, 8.5f, 16, 13, 16);
                            break;
                        case "settings":
                        case "gear":
                            g.DrawEllipse(p, 5.5f, 5.5f, 13, 13);
                            g.DrawEllipse(p, 9, 9, 6, 6);
                            for (int i = 0; i < 8; i++)
                            {
                                double a = i * Math.PI / 4.0;
                                float x1 = (float)(12 + Math.Cos(a) * 6.5);
                                float y1 = (float)(12 + Math.Sin(a) * 6.5);
                                float x2 = (float)(12 + Math.Cos(a) * 8.8);
                                float y2 = (float)(12 + Math.Sin(a) * 8.8);
                                g.DrawLine(p, x1, y1, x2, y2);
                            }
                            break;
                        case "about":
                        case "info":
                            g.DrawEllipse(p, 3, 3, 18, 18);
                            g.DrawLine(p, 12, 10.5f, 12, 17);
                            g.FillEllipse(b, 10.9f, 6.7f, 2.2f, 2.2f);
                            break;
                        case "bolt":
                            g.FillPolygon(b, new PointF[] { new PointF(13, 2), new PointF(5, 13.5f), new PointF(11, 13.5f), new PointF(10, 22), new PointF(19, 10), new PointF(13, 10) });
                            break;
                        case "eye":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                path.AddBezier(2, 12, 6, 5.5f, 18, 5.5f, 22, 12);
                                path.AddBezier(22, 12, 18, 18.5f, 6, 18.5f, 2, 12);
                                g.DrawPath(p, path);
                            }
                            g.DrawEllipse(p, 9.2f, 9.2f, 5.6f, 5.6f);
                            break;
                        case "undo":
                            g.DrawLine(p, 5, 12, 20, 12);
                            g.DrawLine(p, 5, 12, 9.5f, 7.5f);
                            g.DrawLine(p, 5, 12, 9.5f, 16.5f);
                            break;
                        case "arrow-right":
                            g.DrawLine(p, 4, 12, 19, 12);
                            g.DrawLine(p, 19, 12, 14.5f, 7.5f);
                            g.DrawLine(p, 19, 12, 14.5f, 16.5f);
                            break;
                        case "scan":
                            g.DrawLine(p, 3, 8, 3, 3);
                            g.DrawLine(p, 3, 3, 8, 3);
                            g.DrawLine(p, 16, 3, 21, 3);
                            g.DrawLine(p, 21, 3, 21, 8);
                            g.DrawLine(p, 21, 16, 21, 21);
                            g.DrawLine(p, 21, 21, 16, 21);
                            g.DrawLine(p, 8, 21, 3, 21);
                            g.DrawLine(p, 3, 21, 3, 16);
                            g.DrawEllipse(p, 9, 9, 6, 6);
                            break;
                        case "refresh":
                            g.DrawArc(p, 4.5f, 4.5f, 15, 15, -50, 280);
                            g.DrawLine(p, 7.1f, 6.6f, 7.4f, 10.5f);
                            g.DrawLine(p, 7.1f, 6.6f, 11, 7.4f);
                            break;
                        case "download":
                            g.DrawLine(p, 12, 3, 12, 15);
                            g.DrawLine(p, 7, 10, 12, 15);
                            g.DrawLine(p, 17, 10, 12, 15);
                            g.DrawLine(p, 4, 20, 20, 20);
                            break;
                        case "folder":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                path.AddLine(3, 19, 3, 6.5f);
                                path.AddLine(3, 6.5f, 9, 6.5f);
                                path.AddLine(9, 6.5f, 11.2f, 9);
                                path.AddLine(11.2f, 9, 21, 9);
                                path.AddLine(21, 9, 21, 19);
                                path.CloseFigure();
                                g.DrawPath(p, path);
                            }
                            break;
                        case "save":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 4, 4, 16, 16, 2);
                                g.DrawPath(p, path);
                            }
                            g.DrawLine(p, 8, 4, 8, 9);
                            g.DrawLine(p, 8, 9, 16, 9);
                            g.DrawLine(p, 16, 9, 16, 4);
                            g.DrawLine(p, 8, 14, 16, 14);
                            g.DrawLine(p, 16, 14, 16, 19);
                            g.DrawLine(p, 16, 19, 8, 19);
                            g.DrawLine(p, 8, 19, 8, 14);
                            break;
                        case "play":
                            g.FillPolygon(b, new PointF[] { new PointF(8, 5), new PointF(19, 12), new PointF(8, 19) });
                            break;
                        case "trash":
                            g.DrawLine(p, 4, 7, 20, 7);
                            g.DrawLine(p, 9, 4, 15, 4);
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 6, 7, 12, 14, 2);
                                g.DrawPath(p, path);
                            }
                            g.DrawLine(p, 10, 11, 10, 17);
                            g.DrawLine(p, 14, 11, 14, 17);
                            break;
                        case "copy":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 8, 8, 12, 12, 1.6f);
                                g.DrawPath(p, path);
                            }
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                RR(path, 4, 4, 12, 12, 1.6f);
                                g.DrawPath(p, path);
                            }
                            break;
                        case "plus":
                            g.DrawLine(p, 12, 5, 12, 19);
                            g.DrawLine(p, 5, 12, 19, 12);
                            break;
                        case "history":
                        case "clock":
                            g.DrawEllipse(p, 4, 4, 16, 16);
                            g.DrawLine(p, 12, 7.5f, 12, 12);
                            g.DrawLine(p, 12, 12, 15.5f, 14);
                            break;
                        case "check":
                            g.DrawLines(p, new PointF[] { new PointF(5, 12), new PointF(10, 17), new PointF(19, 7) });
                            break;
                        case "close":
                            g.DrawLine(p, 6, 6, 18, 18);
                            g.DrawLine(p, 18, 6, 6, 18);
                            break;
                        case "shield":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                path.AddLine(12, 3, 20, 6.5f);
                                path.AddLine(20, 6.5f, 19, 13.5f);
                                path.AddLine(19, 13.5f, 12, 21);
                                path.AddLine(12, 21, 5, 13.5f);
                                path.AddLine(5, 13.5f, 4, 6.5f);
                                path.CloseFigure();
                                g.DrawPath(p, path);
                            }
                            g.DrawLines(p, new PointF[] { new PointF(8.5f, 12), new PointF(11, 14.5f), new PointF(15.5f, 9.5f) });
                            break;
                        case "heart":
                            using (GraphicsPath path = new GraphicsPath())
                            {
                                path.AddBezier(12, 20, 8, 17, 3, 13.5f, 3, 8.5f);
                                path.AddBezier(3, 8.5f, 3, 5, 7, 4, 9.5f, 6.5f);
                                path.AddBezier(9.5f, 6.5f, 11, 8, 12, 9.5f, 12, 9.5f);
                                path.AddBezier(12, 9.5f, 13, 8, 14.5f, 6.5f, 14.5f, 6.5f);
                                path.AddBezier(14.5f, 6.5f, 17, 4, 21, 5, 21, 8.5f);
                                path.AddBezier(21, 8.5f, 21, 13.5f, 16, 17, 12, 20);
                                g.DrawPath(p, path);
                            }
                            break;
                        case "package":
                            g.DrawLine(p, 3, 8, 12, 3);
                            g.DrawLine(p, 12, 3, 21, 8);
                            g.DrawLine(p, 21, 8, 21, 16);
                            g.DrawLine(p, 21, 16, 12, 21);
                            g.DrawLine(p, 12, 21, 3, 16);
                            g.DrawLine(p, 3, 16, 3, 8);
                            g.DrawLine(p, 3, 8, 12, 13);
                            g.DrawLine(p, 12, 13, 21, 8);
                            g.DrawLine(p, 12, 13, 12, 21);
                            break;
                        default:
                            g.DrawEllipse(p, 8, 8, 8, 8);
                            break;
                    }
                }
            }
            g.Restore(st);
            g.SmoothingMode = old;
        }
    }

    // 自绘下拉框: 系统 ComboBox 的白边和箭头在深色主题下无法彻底去掉
    public class Combo : Control
    {
        public class ItemCollection
        {
            private readonly Combo _owner;
            private readonly List<string> _list = new List<string>();

            public ItemCollection(Combo owner) { _owner = owner; }

            public int Count { get { return _list.Count; } }

            public string this[int index]
            {
                get { return _list[index]; }
                set
                {
                    _list[index] = value == null ? "" : value;
                    if (_owner.SelectedIndex == index) _owner.Invalidate();
                }
            }

            public void Add(string text) { _list.Add(text == null ? "" : text); _owner.Invalidate(); }
            public void AddRange(string[] items)
            {
                if (items == null) return;
                for (int i = 0; i < items.Length; i++) _list.Add(items[i] == null ? "" : items[i]);
                _owner.Invalidate();
            }
            public void Clear() { _list.Clear(); _owner.SelectedIndex = -1; _owner.Invalidate(); }
            public int IndexOf(string text) { return _list.IndexOf(text); }
        }

        public Color FillColor = Color.FromArgb(14, 20, 29);
        public Color BorderColor = Color.FromArgb(38, 50, 74);
        public Color TextColor = Color.FromArgb(230, 237, 243);
        public Color MutedColor = Color.FromArgb(100, 116, 139);
        public Color HoverColor = Color.FromArgb(24, 34, 49);
        public int Radius = 8;

        private readonly ItemCollection _items;
        private ContextMenuStrip _menu;
        private int _selected = -1;
        private bool _hover = false;
        private bool _open = false;

        public event EventHandler SelectedIndexChanged;

        public Combo()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer |
                     ControlStyles.UserPaint | ControlStyles.ResizeRedraw | ControlStyles.Selectable, true);
            SetStyle(ControlStyles.SupportsTransparentBackColor, true);
            BackColor = Color.Transparent;
            _items = new ItemCollection(this);
            Height = 30;
            Cursor = Cursors.Hand;
            TabStop = true;
        }

        public ItemCollection Items { get { return _items; } }

        public int SelectedIndex
        {
            get { return _selected; }
            set
            {
                int v = value;
                if (v < -1) v = -1;
                if (v >= _items.Count) v = _items.Count - 1;
                if (_selected == v) return;
                _selected = v;
                Invalidate();
                if (SelectedIndexChanged != null) SelectedIndexChanged(this, EventArgs.Empty);
            }
        }

        public string SelectedItem
        {
            get { return (_selected >= 0 && _selected < _items.Count) ? _items[_selected] : null; }
        }

        public override string Text
        {
            get { return SelectedItem == null ? "" : SelectedItem; }
            set { }
        }

        private GraphicsPath RoundPath(Rectangle r, int radius)
        {
            GraphicsPath p = new GraphicsPath();
            int d = radius * 2;
            if (d > r.Width) d = r.Width;
            if (d > r.Height) d = r.Height;
            if (d <= 1)
            {
                p.AddRectangle(r);
                return p;
            }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath path = RoundPath(r, Radius))
            {
                using (SolidBrush b = new SolidBrush(FillColor)) g.FillPath(b, path);
                Color bc = (_hover || _open) ? TextColor : BorderColor;
                if (!Enabled) bc = BorderColor;
                using (Pen p = new Pen(bc)) g.DrawPath(p, path);
            }
            float sc = DeviceDpi / 96f;
            string txt = SelectedItem == null ? "" : SelectedItem;
            Color tc = Enabled ? TextColor : MutedColor;
            using (SolidBrush b = new SolidBrush(tc))
            {
                StringFormat sf = new StringFormat();
                sf.LineAlignment = StringAlignment.Center;
                sf.Trimming = StringTrimming.EllipsisCharacter;
                sf.FormatFlags = StringFormatFlags.NoWrap;
                g.DrawString(txt, Font, b, new RectangleF(10 * sc, 0, Width - 30 * sc, Height), sf);
                sf.Dispose();
            }
            using (Pen p = new Pen(Enabled ? MutedColor : BorderColor, 1.4f))
            {
                float cx = Width - 15 * sc;
                float cy = Height / 2f;
                g.DrawLines(p, new PointF[] {
                    new PointF(cx - 4 * sc, cy - 2 * sc),
                    new PointF(cx, cy + 2 * sc),
                    new PointF(cx + 4 * sc, cy - 2 * sc)
                });
            }
        }

        protected override void OnMouseEnter(EventArgs e) { _hover = true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { _hover = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnGotFocus(EventArgs e) { Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { Invalidate(); base.OnLostFocus(e); }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                Focus();
                ShowMenu();
            }
            base.OnMouseDown(e);
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            if (e.Delta > 0) { if (_selected > 0) SelectedIndex = _selected - 1; }
            else if (e.Delta < 0) { if (_selected < _items.Count - 1) SelectedIndex = _selected + 1; }
            base.OnMouseWheel(e);
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Down) { if (_selected < _items.Count - 1) SelectedIndex = _selected + 1; e.Handled = true; }
            else if (e.KeyCode == Keys.Up) { if (_selected > 0) SelectedIndex = _selected - 1; e.Handled = true; }
            else if (e.KeyCode == Keys.Space || e.KeyCode == Keys.Enter) { ShowMenu(); e.Handled = true; }
            else if (e.KeyCode == Keys.Escape && _open) { _menu.Close(); e.Handled = true; }
            base.OnKeyDown(e);
        }

        private void ShowMenu()
        {
            if (!Enabled || _items.Count == 0) return;
            if (_open) { _menu.Close(); return; }
            if (_menu != null) _menu.Dispose();
            _menu = new ContextMenuStrip();
            _menu.ShowImageMargin = false;
            _menu.ShowCheckMargin = false;
            _menu.Padding = new Padding(0, 4, 0, 4);
            _menu.BackColor = FillColor;
            _menu.ForeColor = TextColor;
            _menu.Font = Font;
            _menu.Renderer = new ComboMenuRenderer(this);
            _menu.Closed += delegate { _open = false; Invalidate(); };
            for (int i = 0; i < _items.Count; i++)
            {
                int idx = i;
                string prefix = (i == _selected) ? "●  " : "    ";
                ToolStripMenuItem mi = new ToolStripMenuItem(prefix + _items[i]);
                mi.ForeColor = TextColor;
                mi.BackColor = FillColor;
                mi.Padding = new Padding(2, 5, 10, 5);
                mi.Click += delegate { SelectedIndex = idx; };
                _menu.Items.Add(mi);
            }
            _menu.MinimumSize = new Size(Width, 0);
            _open = true;
            Invalidate();
            _menu.Show(this, 0, Height);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _menu != null) _menu.Dispose();
            base.Dispose(disposing);
        }

        private class ComboMenuRenderer : ToolStripProfessionalRenderer
        {
            private readonly Combo _owner;
            public ComboMenuRenderer(Combo owner) : base(new ComboColorTable(owner))
            {
                _owner = owner;
                RoundedEdges = false;
            }
            protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
            {
                Rectangle r = new Rectangle(0, 0, e.Item.Width, e.Item.Height);
                using (SolidBrush b = new SolidBrush(e.Item.Selected ? _owner.HoverColor : _owner.FillColor))
                {
                    e.Graphics.FillRectangle(b, r);
                }
            }
            protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
            {
                e.TextColor = e.Item.Enabled ? _owner.TextColor : _owner.MutedColor;
                base.OnRenderItemText(e);
            }
        }

        private class ComboColorTable : ProfessionalColorTable
        {
            private readonly Combo _owner;
            public ComboColorTable(Combo owner) { _owner = owner; }
            public override Color ToolStripDropDownBackground { get { return _owner.FillColor; } }
            public override Color MenuBorder { get { return _owner.BorderColor; } }
            public override Color MenuItemSelected { get { return _owner.HoverColor; } }
            public override Color MenuItemBorder { get { return _owner.HoverColor; } }
            public override Color ImageMarginGradientBegin { get { return _owner.FillColor; } }
            public override Color ImageMarginGradientMiddle { get { return _owner.FillColor; } }
            public override Color ImageMarginGradientEnd { get { return _owner.FillColor; } }
            public override Color SeparatorDark { get { return _owner.BorderColor; } }
            public override Color SeparatorLight { get { return _owner.BorderColor; } }
        }
    }

    // 自绘输入框: 去掉系统白边, 保留多行高度以对齐 30/32px 控件
    public class Input : TextBox
    {
        public Color BorderColor = Color.FromArgb(38, 50, 74);
        public Color FocusBorderColor = Color.FromArgb(76, 194, 224);
        private bool _focused = false;

        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

        public Input()
        {
            BorderStyle = BorderStyle.None;
            Multiline = true;
            WordWrap = false;
            AcceptsReturn = false;
            ScrollBars = ScrollBars.None;
            SetStyle(ControlStyles.OptimizedDoubleBuffer, true);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            ApplyMargins();
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            ApplyMargins();
        }

        private void ApplyMargins()
        {
            if (!IsHandleCreated) return;
            float sc = DeviceDpi / 96f;
            int left = (int)Math.Round(10 * sc);
            int right = (int)Math.Round(8 * sc);
            SendMessage(Handle, 0xD3, (IntPtr)3, (IntPtr)((right << 16) | (left & 0xFFFF)));
            int top = Math.Max(0, (Height - Font.Height) / 2);
            RECT rc = new RECT();
            rc.Left = left;
            rc.Top = top;
            rc.Right = Math.Max(left + 1, Width - right);
            rc.Bottom = Math.Max(top + 1, Height - 2);
            SendMessage(Handle, 0xB3, IntPtr.Zero, ref rc);
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, ref RECT lParam);

        protected override void OnGotFocus(EventArgs e) { _focused = true; Invalidate(); base.OnGotFocus(e); }
        protected override void OnLostFocus(EventArgs e) { _focused = false; Invalidate(); base.OnLostFocus(e); }

        protected override void WndProc(ref Message m)
        {
            base.WndProc(ref m);
            if (m.Msg == 0x000F && IsHandleCreated)
            {
                try
                {
                    using (Graphics g = Graphics.FromHwnd(Handle))
                    {
                        using (Pen p = new Pen(_focused ? FocusBorderColor : BorderColor))
                        {
                            g.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
                        }
                    }
                }
                catch { }
            }
        }
    }

    // 启动时的前台规则: 用户从资源管理器 / 终端双击启动时正常激活;
    // 如果在加载期间已经切到别的程序, 则安静显示, 不把焦点抢回来。
    public static class Boot
    {
        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);

        [DllImport("user32.dll")]
        private static extern bool FlashWindowEx(ref FLASHWINFO pfwi);

        [StructLayout(LayoutKind.Sequential)]
        private struct FLASHWINFO
        {
            public uint cbSize;
            public IntPtr hwnd;
            public uint dwFlags;
            public uint uCount;
            public uint dwTimeout;
        }

        public static bool ShouldActivate()
        {
            try
            {
                IntPtr fg = GetForegroundWindow();
                if (fg == IntPtr.Zero) return true;
                uint pid;
                GetWindowThreadProcessId(fg, out pid);
                if (pid == 0) return true;
                if (pid == (uint)System.Diagnostics.Process.GetCurrentProcess().Id) return true;
                string name;
                try { name = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName.ToLowerInvariant(); }
                catch { return true; }
                switch (name)
                {
                    case "explorer":
                    case "cmd":
                    case "powershell":
                    case "pwsh":
                    case "windowsterminal":
                    case "conhost":
                    case "wscript":
                    case "cscript":
                    case "startmenuexperiencehost":
                    case "shellexperiencehost":
                    case "searchapp":
                        return true;
                }
                return false;
            }
            catch { return true; }
        }

        public static void FlashTaskbar(IntPtr h)
        {
            try
            {
                FLASHWINFO f = new FLASHWINFO();
                f.cbSize = (uint)Marshal.SizeOf(typeof(FLASHWINFO));
                f.hwnd = h;
                f.dwFlags = 2 | 12; // FLASHW_TRAY | FLASHW_TIMERNOFG
                f.uCount = 3;
                f.dwTimeout = 0;
                FlashWindowEx(ref f);
            }
            catch { }
        }
    }

    // 主窗体: 允许按启动时的前台状态决定是否激活
    public class MainForm : Form
    {
        public bool QuietShow = false;

        protected override bool ShowWithoutActivation
        {
            get { return QuietShow; }
        }
    }

    public static class Perf
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME
        {
            public uint Low;
            public uint High;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetSystemTimes(out FILETIME idleTime, out FILETIME kernelTime, out FILETIME userTime);

        [StructLayout(LayoutKind.Sequential)]
        private class MEMORYSTATUSEX
        {
            public uint dwLength;
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;
            public MEMORYSTATUSEX() { dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX)); }
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

        public class CpuSample
        {
            public ulong Idle;
            public ulong Kernel;
            public ulong User;
        }

        public class MemSample
        {
            public ulong Total;
            public ulong Avail;
        }

        public static CpuSample GetCpuSample()
        {
            FILETIME i, k, u;
            if (!GetSystemTimes(out i, out k, out u)) return null;
            CpuSample s = new CpuSample();
            s.Idle = ((ulong)i.High << 32) | i.Low;
            s.Kernel = ((ulong)k.High << 32) | k.Low;
            s.User = ((ulong)u.High << 32) | u.Low;
            return s;
        }

        public static MemSample GetMemSample()
        {
            MEMORYSTATUSEX m = new MEMORYSTATUSEX();
            if (!GlobalMemoryStatusEx(m)) return null;
            MemSample s = new MemSample();
            s.Total = m.ullTotalPhys;
            s.Avail = m.ullAvailPhys;
            return s;
        }

    }

    public class LogItem
    {
        public string Text;
        public Color Color;
        public bool Bold;
        public LogItem(string text, Color color, bool bold = false) { Text = text; Color = color; Bold = bold; }
        public override string ToString() { return Text; }
    }

    internal static class Gfx
    {
        public static GraphicsPath Round(Rectangle r, int rad)
        {
            GraphicsPath p = new GraphicsPath();
            int d = rad * 2;
            if (d > r.Width) d = r.Width;
            if (d > r.Height) d = r.Height;
            if (d <= 1) { p.AddRectangle(r); return p; }
            p.AddArc(r.X, r.Y, d, d, 180, 90);
            p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
    }

    public class Card : Panel
    {
        public int Radius = 12;
        public Color Fill = Color.FromArgb(18, 23, 34);
        public Color BorderColor = Color.FromArgb(38, 49, 68);
        public Card()
        {
            DoubleBuffered = true;
            ResizeRedraw = true;
            BackColor = Fill;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
        }
        public void RefreshRegion()
        {
            try { using (GraphicsPath p = Gfx.Round(new Rectangle(0, 0, Width, Height), Radius)) { Region = new Region(p); } } catch { }
        }
        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            RefreshRegion();
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath p = Gfx.Round(r, Radius))
            {
                using (SolidBrush b = new SolidBrush(Fill)) g.FillPath(b, p);
                using (Pen pen = new Pen(BorderColor, 1)) g.DrawPath(pen, p);
            }
            int inset = Math.Max(6, Radius);
            if (r.Width > inset * 2)
            {
                using (Pen hi = new Pen(Color.FromArgb(16, 255, 255, 255), 1))
                    g.DrawLine(hi, r.X + inset, r.Y + 1, r.Right - inset, r.Y + 1);
            }
            base.OnPaint(e);
        }
    }

    public class Meter : Control
    {
        private double _value = 0;
        private string _valueText = "--";
        public double Value
        {
            get { return _value; }
            set { if (_value != value) { _value = value; Invalidate(); } }
        }
        public string ValueText
        {
            get { return _valueText; }
            set { if (_valueText != value) { _valueText = value; Invalidate(); } }
        }
        public string Caption = "--";
        public Color Accent = Color.FromArgb(0, 229, 255);
        public float UiScale = 1f;
        public bool LightMode = false;
        public Meter()
        {
            DoubleBuffered = true;
            ResizeRedraw = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float sc = UiScale > 0f ? UiScale : 1f;
            Color capColor = LightMode ? Color.FromArgb(71, 85, 105) : Color.FromArgb(143, 163, 184);
            Color valColor = LightMode ? Color.FromArgb(30, 41, 59) : Color.FromArgb(235, 241, 248);
            Color trackColor = LightMode ? Color.FromArgb(218, 225, 233) : Color.FromArgb(30, 39, 54);
            using (SolidBrush bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);
            using (Font f1 = new Font("Microsoft YaHei UI", 9f))
            {
                using (SolidBrush br = new SolidBrush(capColor)) g.DrawString(Caption, f1, br, 0, 0);
                SizeF capSz = g.MeasureString(Caption, f1);
                float avail = Width - capSz.Width - 16f * sc;
                if (avail < 40f * sc) avail = Width - 8f * sc;
                float[] sizes = new float[] { 13f, 12f, 11f, 10f, 9f };
                Font f2 = null;
                SizeF sz = SizeF.Empty;
                try
                {
                    for (int i = 0; i < sizes.Length; i++)
                    {
                        Font cand = new Font("Microsoft YaHei UI", sizes[i], FontStyle.Bold);
                        SizeF cs = g.MeasureString(ValueText, cand);
                        if (f2 != null) f2.Dispose();
                        f2 = cand;
                        sz = cs;
                        if (cs.Width <= avail || i == sizes.Length - 1) break;
                    }
                    using (SolidBrush br2 = new SolidBrush(valColor)) g.DrawString(ValueText, f2, br2, Width - sz.Width - sc, -sc);
                }
                finally
                {
                    if (f2 != null) f2.Dispose();
                }
            }
            int ty = Height - (int)Math.Round(9 * sc);
            int trackH = Math.Max(2, (int)Math.Round(6 * sc));
            int trackR = Math.Max(1, (int)Math.Round(3 * sc));
            Rectangle track = new Rectangle(0, ty, Width, trackH);
            using (GraphicsPath p = Gfx.Round(track, trackR))
            using (SolidBrush b = new SolidBrush(trackColor)) g.FillPath(b, p);
            double v = Value;
            if (v < 0) v = 0;
            if (v > 100) v = 100;
            int fw = (int)(Width * v / 100.0);
            if (fw > (int)(3 * sc))
            {
                Rectangle fill = new Rectangle(0, ty, Math.Max(fw, (int)(4 * sc)), trackH);
                using (GraphicsPath p = Gfx.Round(fill, trackR))
                using (LinearGradientBrush lg = new LinearGradientBrush(new Rectangle(0, ty, Math.Max(Width, 10), trackH), Accent, Color.FromArgb(124, 77, 255), 0f))
                    g.FillPath(lg, p);
            }
        }
    }

    public class Badge : Label
    {
        public Color Fill = Color.FromArgb(30, 39, 54);
        public Color BorderColor = Color.FromArgb(51, 65, 85);
        public int Radius = 8;
        public Badge()
        {
            DoubleBuffered = true;
            BackColor = Color.Transparent;
            TextAlign = ContentAlignment.MiddleCenter;
            SetStyle(ControlStyles.SupportsTransparentBackColor | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle r = new Rectangle(0, 0, Width - 1, Height - 1);
            using (GraphicsPath p = Gfx.Round(r, Radius))
            {
                using (SolidBrush b = new SolidBrush(Fill)) g.FillPath(b, p);
                using (Pen pen = new Pen(BorderColor, 1)) g.DrawPath(pen, p);
            }
            base.OnPaint(e);
        }
    }

    public class Check : CheckBox
    {
        public Color BoxFill = Color.FromArgb(22, 30, 44);
        public Color BoxBorder = Color.FromArgb(71, 85, 105);
        public Color CheckColor = Color.FromArgb(0, 229, 255);
        public float UiScale = 1f;
        public Check()
        {
            DoubleBuffered = true;
            BackColor = Color.Transparent;
            SetStyle(ControlStyles.SupportsTransparentBackColor | ControlStyles.OptimizedDoubleBuffer | ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint, true);
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            float sc = UiScale > 0f ? UiScale : 1f;
            Color bg = Parent != null ? Parent.BackColor : BackColor;
            using (SolidBrush b = new SolidBrush(bg)) g.FillRectangle(b, ClientRectangle);
            int box = Math.Max(8, (int)Math.Round(15 * sc));
            int y = (Height - box) / 2;
            int rr = Math.Max(1, (int)Math.Round(3 * sc));
            Rectangle r = new Rectangle(1, y, box, box);
            using (GraphicsPath p = Gfx.Round(r, rr))
            {
                using (SolidBrush b = new SolidBrush(BoxFill)) g.FillPath(b, p);
                using (Pen pen = new Pen(BoxBorder, Math.Max(1f, sc))) g.DrawPath(pen, p);
            }
            if (Checked)
            {
                using (Pen pen = new Pen(CheckColor, Math.Max(1.5f, 2f * sc)))
                {
                    pen.StartCap = LineCap.Round;
                    pen.EndCap = LineCap.Round;
                    g.DrawLines(pen, new Point[] {
                        new Point((int)Math.Round(4 * sc), y + (int)Math.Round(7 * sc)),
                        new Point((int)Math.Round(7 * sc), y + (int)Math.Round(10 * sc)),
                        new Point((int)Math.Round(12 * sc), y + (int)Math.Round(4 * sc))
                    });
                }
            }
            if (!string.IsNullOrEmpty(Text))
            {
                int tx = box + (int)Math.Round(8 * sc);
                Rectangle tr = new Rectangle(tx, 0, Math.Max(0, Width - tx), Height);
                Color tc = Enabled ? ForeColor : Color.FromArgb(100, 116, 139);
                TextRenderer.DrawText(g, Text, Font, tr, tc, TextFormatFlags.NoPrefix | TextFormatFlags.VerticalCenter | TextFormatFlags.EndEllipsis | TextFormatFlags.Left);
            }
        }
    }

    public class Flow : FlowLayoutPanel
    {
        public Flow()
        {
            DoubleBuffered = true;
            ResizeRedraw = true;
            SetStyle(ControlStyles.OptimizedDoubleBuffer, true);
        }
    }

    public class SplashBar : Control
    {
        private Timer _timer;
        private float _phase;

        public SplashBar()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            TabStop = false;
            _timer = new Timer();
            _timer.Interval = 16;
            _timer.Tick += delegate
            {
                _phase += 0.010f;
                if (_phase >= 1f) _phase -= 1f;
                Invalidate();
            };
        }

        public void Start()
        {
            try { if (!_timer.Enabled) _timer.Start(); } catch { }
        }

        public void Stop()
        {
            try { _timer.Stop(); } catch { }
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                try { _timer.Stop(); _timer.Dispose(); } catch { }
            }
            base.Dispose(disposing);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.Clear(BackColor);

            Rectangle r = new Rectangle(0, 0, Math.Max(1, Width - 1), Math.Max(1, Height - 1));
            int rad = Math.Max(2, Math.Min(Height, Width) / 2);
            using (GraphicsPath path = Gfx.Round(r, rad))
            {
                using (SolidBrush track = new SolidBrush(Color.FromArgb(31, 41, 57)))
                    g.FillPath(track, path);

                g.SetClip(path);
                int band = Math.Max(48, Width / 4);
                float x = -band + (Width + band) * _phase;
                RectangleF rect = new RectangleF(x, 0f, band, Height);
                using (LinearGradientBrush lg = new LinearGradientBrush(rect, Color.Transparent, Color.Transparent, LinearGradientMode.Horizontal))
                {
                    ColorBlend cb = new ColorBlend(4);
                    cb.Colors = new Color[] {
                        Color.FromArgb(0, 0, 229, 255),
                        Color.FromArgb(255, 0, 229, 255),
                        Color.FromArgb(255, 0, 230, 118),
                        Color.FromArgb(0, 0, 230, 118)
                    };
                    cb.Positions = new float[] { 0f, 0.3f, 0.7f, 1f };
                    lg.InterpolationColors = cb;
                    g.FillRectangle(lg, rect);
                }
                g.ResetClip();
            }
        }
    }

    public class SplashForm : Form
    {
        private Label _sub;
        private Label _close;
        private SplashBar _bar;
        private int _radius = 18;
        private bool _drag = false;
        private Point _dragStart;
        private Point _dragOrigin;
        public bool UserClosed = false;
        public Label VerLabel;

        public SplashForm() : this(1f) { }

        public SplashForm(float scale)
        {
            float sc = scale <= 0f ? 1f : scale;
            _radius = (int)Math.Round(18 * sc);
            AutoScaleMode = AutoScaleMode.None;
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            Size = new Size(460, 230);
            BackColor = Color.FromArgb(15, 18, 25);
            ShowInTaskbar = false;
            // 不投机取巧抢前台: 不置顶、不激活, 交给 Windows 的窗口层级规则
            DoubleBuffered = true;
            Font = new Font("Microsoft YaHei UI", 9f);
            KeyPreview = true;

            Label title = new Label();
            title.Text = "游戏性能优化中心";
            title.Font = new Font("Microsoft YaHei UI", 19f, FontStyle.Bold);
            title.ForeColor = Color.FromArgb(235, 241, 248);
            title.BackColor = Color.Transparent;
            title.SetBounds(30, 22, 380, 38);
            Controls.Add(title);

            _sub = new Label();
            _sub.Text = "正在初始化...";
            _sub.Font = new Font("Microsoft YaHei UI", 10f);
            _sub.ForeColor = Color.FromArgb(143, 163, 184);
            _sub.BackColor = Color.Transparent;
            _sub.SetBounds(32, 68, 380, 24);
            Controls.Add(_sub);

            _bar = new SplashBar();
            _bar.BackColor = BackColor;
            _bar.SetBounds(32, 112, 396, 7);
            Controls.Add(_bar);

            VerLabel = new Label();
            VerLabel.Text = "硬件兼容版 · 所有改动均可还原";
            VerLabel.Font = new Font("Microsoft YaHei UI", 8f);
            VerLabel.ForeColor = Color.FromArgb(100, 116, 139);
            VerLabel.BackColor = Color.Transparent;
            VerLabel.SetBounds(32, 142, 396, 20);
            Controls.Add(VerLabel);

            Label hint = new Label();
            hint.Text = "可拖动 · 可关闭 · 加载期间界面保持响应";
            hint.Font = new Font("Microsoft YaHei UI", 8f);
            hint.ForeColor = Color.FromArgb(100, 116, 139);
            hint.BackColor = Color.Transparent;
            hint.SetBounds(32, 166, 396, 20);
            Controls.Add(hint);

            _close = new Label();
            _close.Text = "×";
            _close.Font = new Font("Microsoft YaHei UI", 14f, FontStyle.Bold);
            _close.ForeColor = Color.FromArgb(100, 116, 139);
            _close.BackColor = Color.Transparent;
            _close.TextAlign = ContentAlignment.MiddleCenter;
            _close.SetBounds(416, 8, 30, 30);
            _close.Cursor = Cursors.Hand;
            _close.Click += delegate { UserClosed = true; Close(); };
            _close.MouseEnter += delegate { _close.ForeColor = Color.FromArgb(235, 241, 248); };
            _close.MouseLeave += delegate { _close.ForeColor = Color.FromArgb(100, 116, 139); };
            Controls.Add(_close);

            EnableDrag(this);
            EnableDrag(title);
            EnableDrag(_sub);
            EnableDrag(_bar);
            EnableDrag(VerLabel);
            EnableDrag(hint);
            KeyDown += delegate(object s, KeyEventArgs e)
            {
                if (e.KeyCode == Keys.Escape) { UserClosed = true; Close(); }
            };

            Resize += delegate { ApplyRound(); };
            if (sc > 1f) Scale(new SizeF(sc, sc));
            ApplyRound();
        }

        private void ApplyRound()
        {
            try
            {
                using (GraphicsPath p = Gfx.Round(new Rectangle(0, 0, Width, Height), _radius))
                    Region = new Region(p);
            }
            catch { }
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            try { _bar.Start(); } catch { }
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            try { _bar.Stop(); } catch { }
            base.OnFormClosed(e);
        }

        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        private void EnableDrag(Control c)
        {
            if (c == null) return;
            c.MouseDown += DragBegin;
            c.MouseMove += DragMove;
            c.MouseUp += DragEnd;
        }

        private void DragBegin(object sender, MouseEventArgs e)
        {
            if (e.Button != MouseButtons.Left) return;
            _drag = true;
            _dragStart = Cursor.Position;
            _dragOrigin = Location;
            Control c = sender as Control;
            if (c != null) { try { c.Capture = true; } catch { } }
            try { Activate(); } catch { }
        }

        private void DragMove(object sender, MouseEventArgs e)
        {
            if (!_drag) return;
            Point now = Cursor.Position;
            Location = new Point(_dragOrigin.X + (now.X - _dragStart.X), _dragOrigin.Y + (now.Y - _dragStart.Y));
        }

        private void DragEnd(object sender, MouseEventArgs e)
        {
            if (!_drag) return;
            _drag = false;
            Control c = sender as Control;
            if (c != null) { try { c.Capture = false; } catch { } }
        }

        public void SetStatus(string text)
        {
            try
            {
                if (IsDisposed || Disposing) return;
                if (InvokeRequired) { BeginInvoke(new Action<string>(SetStatus), text); return; }
                _sub.Text = text;
            }
            catch { }
        }

        public void CloseSafe()
        {
            try
            {
                if (IsDisposed || Disposing) return;
                if (InvokeRequired) { BeginInvoke(new Action(CloseSafe)); return; }
                Close();
            }
            catch { }
        }
    }
}
'@
Add-Type -TypeDefinition $cs -ReferencedAssemblies @('System','System.Core','System.Drawing','System.Windows.Forms')
try { [TxUi.Native]::DarkEnabled = ($script:ThemeName -ne 'light') } catch {}

# 高 DPI 状态已在脚本入口处确定 (必须先于 GDI+ 初始化)

# ── 启动画面 (独立 STA 线程, 加载期间仍可拖动/关闭) ───────
$script:SplashState = [hashtable]::Synchronized(@{
    Ready = $false; Closed = $false; Done = $false; Form = $null; Error = $null
    Scale = [double]$script:UI_SCALE
    Version = [string]$script:AppVersion
})
$script:SplashScript = @'
param($State)
$ErrorActionPreference = 'SilentlyContinue'
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $f = New-Object TxUi.SplashForm -ArgumentList @([single]$State.Scale)
    try { $f.VerLabel.Text = "v$($State.Version) · 硬件兼容版 · 所有改动均可还原" } catch {}
    $State.Form = $f
    $f.Add_Shown({ $State.Ready = $true })
    [System.Windows.Forms.Application]::Run($f)
} catch {
    $State.Error = $_.Exception.Message
} finally {
    $State.Done = $true
    $State.Ready = $true
}
'@
$script:SplashRS = $null
$script:SplashPS = $null
$script:SplashHandle = $null
# 预览 / 自检不弹启动画面; 用户已经切到别的程序时也不弹, 避免盖住前台窗口
$script:SplashAllowed = $true
try {
    if ($Preview -or $SelfTest) { $script:SplashAllowed = $false }
    elseif (-not [TxUi.Boot]::ShouldActivate()) { $script:SplashAllowed = $false }
} catch {}
if ($script:SplashAllowed) {
try {
    $script:SplashRS = [runspacefactory]::CreateRunspace()
    $script:SplashRS.ApartmentState = 'STA'
    $script:SplashRS.ThreadOptions = 'ReuseThread'
    $script:SplashRS.Open()
    $script:SplashPS = [powershell]::Create()
    $script:SplashPS.Runspace = $script:SplashRS
    [void]$script:SplashPS.AddScript($script:SplashScript).AddParameter('State', $script:SplashState)
    $script:SplashHandle = $script:SplashPS.BeginInvoke()
    $spDeadline = (Get-Date).AddMilliseconds(1500)
    while (-not $script:SplashState.Ready -and (Get-Date) -lt $spDeadline) { Start-Sleep -Milliseconds 20 }
} catch {}
}

function Set-Splash([string]$t) {
    try {
        $st = $script:SplashState
        $f = $st.Form
        if ($f -and -not $st.Closed -and -not $st.Done) { $f.SetStatus($t) }
    } catch {}
}

function Close-Splash {
    try { $script:SplashState.Closed = $true } catch {}
    try {
        $f = $script:SplashState.Form
        if ($f) { $f.CloseSafe() }
    } catch {}
    # 等待独立线程退出消息循环后再释放, 避免跨线程销毁报错
    try {
        $deadline = (Get-Date).AddMilliseconds(600)
        while (-not $script:SplashState.Done -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 20 }
    } catch {}
    try { if ($script:SplashPS) { $script:SplashPS.Dispose() } } catch {}
    try { if ($script:SplashRS) { $script:SplashRS.Close(); $script:SplashRS.Dispose() } } catch {}
    $script:SplashPS = $null; $script:SplashRS = $null; $script:SplashHandle = $null
}

# ── 加载引擎 ─────────────────────────────────────────────
$script:LogBuffer = New-Object System.Collections.ArrayList
$script:LogSink   = $null
$script:Pump      = $false
$script:TxLogCallback = {
    param($line, $color)
    try { [void]$script:LogBuffer.Add([PSCustomObject]@{ Line = [string]$line; Color = [string]$color }) } catch {}
    if ($script:LogSink) { try { & $script:LogSink $line $color } catch {} }
    if ($script:Pump) { try { [System.Windows.Forms.Application]::DoEvents() } catch {} }
}

$enginePath = Join-Path $PSScriptRoot '游戏性能优化.ps1'
if (-not (Test-Path $enginePath)) {
    [System.Windows.Forms.MessageBox]::Show("引擎文件缺失:`n$enginePath", '游戏性能优化中心', 'OK', 'Error') | Out-Null
    Close-Splash
    exit 1
}

Set-Splash '正在加载优化引擎...'
try {
    . $enginePath -EngineOnly -NoElevate -Sid $Sid
    $ErrorActionPreference = 'Continue'
} catch {
    $msg = $_.Exception.Message
    try { Close-Splash } catch {}
    [System.Windows.Forms.MessageBox]::Show("引擎加载失败:`n$msg", '游戏性能优化中心', 'OK', 'Error') | Out-Null
    exit 1
}

Set-Splash '正在准备界面...'
# ★ v5.1 两段式启动: 先用轻量快照完成首屏 (优化项显示"检测中"),
#   窗口显示后再在后台补齐 32 项真实状态, 避免状态检查阻塞首次绘制。
try {
    $script:Snap = Get-TxSnapshot -Provisional
} catch {
    $msg = $_.Exception.Message
    try { Close-Splash } catch {}
    [System.Windows.Forms.MessageBox]::Show("状态读取失败:`n$msg", '游戏性能优化中心', 'OK', 'Error') | Out-Null
    exit 1
}

# ── 主窗体 ───────────────────────────────────────────────
Set-Splash '正在构建可视化界面...'
$form = New-Object TxUi.MainForm
# 启动期间用户已切到别的程序时, 界面安静出现并闪任务栏, 不抢焦点
$form.QuietShow = $false
try {
    if ($Preview -or $SelfTest) {
        # 预览/自检在后台渲染, 绝不抢前台焦点
        $form.QuietShow = $true
        $form.ShowInTaskbar = $false
    } else {
        $form.QuietShow = -not [TxUi.Boot]::ShouldActivate()
    }
} catch {}
$form.Text = "游戏性能优化中心 v$($script:AppVersion)"
$form.BackColor = $script:C_BG
$form.ForeColor = $script:C_TEXT
$form.Font = F 9
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.StartPosition = 'CenterScreen'
try {
    $script:AppIconBmp = New-Object Drawing.Bitmap -ArgumentList @(64, 64)
    $ig = [Drawing.Graphics]::FromImage($script:AppIconBmp)
    $ig.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $ig.Clear([Drawing.Color]::Transparent)
    $bgBrush = New-Object Drawing.SolidBrush $script:C_CYAN
    $ig.FillEllipse($bgBrush, 2, 2, 60, 60)
    [TxUi.Icons]::Draw($ig, 'bolt', (New-Object Drawing.RectangleF -ArgumentList @(14, 12, 36, 40)), (TC 6 18 24), [single]2.6)
    $bgBrush.Dispose()
    $ig.Dispose()
    $script:AppIcon = [Drawing.Icon]::FromHandle($script:AppIconBmp.GetHicon())
    $form.Icon = $script:AppIcon
    $form.ShowIcon = $true
} catch {
    $form.ShowIcon = $false
}
$form.AutoScaleMode = 'None'
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
# WorkingArea 在 PerMonitorV2 下是物理像素, 先换算回 96-DPI 逻辑尺寸
$maxW = [int]($wa.Width / $script:UI_SCALE) - 40
$maxH = [int]($wa.Height / $script:UI_SCALE) - 40
if ($maxW -lt 900) { $maxW = 900 }
if ($maxH -lt 560) { $maxH = 560 }
$fw = [Math]::Min(1320, $maxW)
$fh = [Math]::Min(840, $maxH)
if ($fw -lt 1180) { $fw = [Math]::Min(1180, $maxW) }
if ($fh -lt 700)  { $fh = [Math]::Min(700, $maxH) }
$script:MinW = [Math]::Min(1180, $fw)
$script:MinH = [Math]::Min(700, $fh)
$form.ClientSize = New-Object Drawing.Size -ArgumentList @($fw, $fh)
$form.MinimumSize = New-Object Drawing.Size -ArgumentList @($script:MinW, $script:MinH)

$script:UI = @{}
$script:UI.Form = $form
$script:UI.Pages = @{}
$script:UI.NavBtns = @{}
$script:UI.Busy = $false
$script:UI.CurrentPage = 'overview'
$script:UI.DiagDirty = $true
$script:UI.BackupDirty = $true
$script:UiScaled = $false
$script:UiScaling = $false

# 内容区 (必须先于 Top/Left/Bottom 添加到窗体, Dock 才会正确分配剩余空间)
$content = New-Object System.Windows.Forms.Panel
$content.Dock = 'Fill'
$content.BackColor = $script:C_BG
$content.Size = New-Object Drawing.Size -ArgumentList @(($fw - 200), ($fh - 60 - 26))
$form.Controls.Add($content)

# 顶栏
$top = New-Object System.Windows.Forms.Panel
$top.Dock = 'Top'
$top.Height = 60
$top.Width = $fw
$top.BackColor = $script:C_PANEL2
$form.Controls.Add($top)
$null = New-Badge $top 'TX' 20 14 38 32 $script:C_GRAY_BG $script:C_CYAN $script:C_CYAN 13
$null = New-Label $top '游戏性能优化' 70 11 220 24 12 $true $script:C_TEXT
$null = New-Label $top '本地运行 · 所有改动可还原' 70 33 260 18 8 $false $script:C_DIM
$machineTxt = '未知机型'
if ($script:Snap.Machine) { $machineTxt = [string]$script:Snap.Machine }
$script:MachineTxt = $machineTxt
$lblTopMachine = New-Label $top $machineTxt ($fw - 652) 19 300 22 9 $false $script:C_SUB 'MiddleRight'
$lblTopMachine.Anchor = 'Top, Right'
$adminTxt = '管理员'
if (-not $isAdmin) { $adminTxt = '非管理员' }
$badgeAdmin = New-Badge $top $adminTxt ($fw - 338) 18 72 24 $script:C_GREEN_BG $script:C_GREEN_BD $script:C_GREEN 8
if (-not $isAdmin) { $badgeAdmin.Fill = $script:C_ORANGE_BG; $badgeAdmin.BorderColor = $script:C_ORANGE_BD; $badgeAdmin.ForeColor = $script:C_ORANGE }
$badgeAdmin.Anchor = 'Top, Right'
$lblClock = New-Label $top '' ($fw - 256) 19 224 22 9 $false $script:C_SUB 'MiddleRight'
$lblClock.Anchor = 'Top, Right'
$topLine = New-Object System.Windows.Forms.Panel
$topLine.Dock = 'Bottom'
$topLine.Height = 2
$topLine.BackColor = $script:C_BORDER
$topLine.Add_Paint({
    param($s, $e)
    try {
        $g = $e.Graphics
        $r = New-Object Drawing.Rectangle -ArgumentList @(0, 0, $s.Width, $s.Height)
        $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @($r, $script:C_CYAN, $script:C_PURPLE, [single]0)
        $g.FillRectangle($lg, $r)
        $lg.Dispose()
    } catch {}
})
$top.Controls.Add($topLine)

# 左侧导航
$nav = New-Object System.Windows.Forms.Panel
$nav.Dock = 'Left'
$nav.Width = 200
$nav.BackColor = $script:C_PANEL2
$form.Controls.Add($nav)
$null = New-Label $nav '功能导航' 20 16 130 20 8 $true $script:C_DIM
$navHint = New-Label $nav '?' 168 15 18 20 8.5 $true $script:C_DIM 'MiddleRight'
$navHint.Cursor = [System.Windows.Forms.Cursors]::Help
try { (Get-Tip).SetToolTip($navHint, '悬停导航项、按钮或硬件卡片可查看说明') } catch {}
$navDefs = @(
    @{ Key='overview'; Text='概览';     Glyph='01'; Icon='overview' },
    @{ Key='driver';   Text='驱动中心'; Glyph='02'; Icon='driver' },
    @{ Key='game';     Text='游戏库';   Glyph='03'; Icon='game' },
    @{ Key='items';    Text='优化项';   Glyph='04'; Icon='items' },
    @{ Key='backup';   Text='备份还原'; Glyph='05'; Icon='backup' },
    @{ Key='diag';     Text='诊断报告'; Glyph='06'; Icon='diag' },
    @{ Key='startup';  Text='启动项';   Glyph='07'; Icon='startup' },
    @{ Key='log';      Text='运行日志'; Glyph='08'; Icon='log' },
    @{ Key='settings'; Text='设置';     Glyph='09'; Icon='settings' },
    @{ Key='about';    Text='关于';     Glyph='10'; Icon='about' }
)
$script:UI.NavIcons = @{}
$navIconPx = [int][Math]::Round(18 * [double]$script:UI_SCALE)
foreach ($nd in $navDefs) {
    $script:UI.NavIcons[$nd.Key] = @{
        Off = New-IconBitmap $nd.Icon $navIconPx $script:C_SUB
        On  = New-IconBitmap $nd.Icon $navIconPx $script:C_CYAN
    }
}
$ny = 46
foreach ($nd in $navDefs) {
    $nb = New-Object System.Windows.Forms.Button
    $nb.Text = [string]$nd.Text
    $nb.Location = New-Object Drawing.Point -ArgumentList @(12, $ny)
    $nb.Size = New-Object Drawing.Size -ArgumentList @(176, 40)
    $nb.FlatStyle = 'Flat'
    $nb.FlatAppearance.BorderSize = 0
    $nb.TextAlign = 'MiddleLeft'
    $nb.ImageAlign = 'MiddleLeft'
    $nb.TextImageRelation = 'ImageBeforeText'
    $nb.Image = $script:UI.NavIcons[$nd.Key].Off
    $nb.Padding = New-Object System.Windows.Forms.Padding -ArgumentList @(12, 0, 0, 0)
    $nb.BackColor = $script:C_PANEL2
    $nb.ForeColor = $script:C_SUB
    $nb.Font = F 10
    $nb.Cursor = [System.Windows.Forms.Cursors]::Hand
    $nb.UseVisualStyleBackColor = $false
    $bar = New-Object System.Windows.Forms.Panel
    $bar.Size = New-Object Drawing.Size -ArgumentList @(3, 20)
    $bar.Location = New-Object Drawing.Point -ArgumentList @(0, 11)
    $bar.BackColor = $script:C_CYAN
    $bar.Visible = $false
    $nb.Controls.Add($bar)
    $nb.Tag = @{ Page = $nd.Key; Bar = $bar; Glyph = $nd.Glyph }
    try { (Get-Tip).SetToolTip($nb, $script:NavTips[$nd.Key]) } catch {}
    $nb.Add_Paint({
        param($s, $e)
        try {
            $sc = [double]$script:UI_SCALE
            $g = $e.Graphics
            $fmt = New-Object Drawing.StringFormat
            $fmt.Alignment = [Drawing.StringAlignment]::Far
            $fmt.LineAlignment = [Drawing.StringAlignment]::Center
            $r = New-Object Drawing.RectangleF -ArgumentList @(0, 0, [single]($s.Width - (12 * $sc)), [single]$s.Height)
            $br = New-Object Drawing.SolidBrush $script:C_DIM
            $g.DrawString([string]$s.Tag.Glyph, $script:NavNumF, $br, $r, $fmt)
            $br.Dispose()
            $fmt.Dispose()
        } catch {}
    })
    $nb.Add_Click({
        param($s, $e)
        Show-Page $s.Tag.Page
    })
    $nb.Add_MouseEnter({
        param($s, $e)
        try {
            if ($script:UI.CurrentPage -ne $s.Tag.Page) {
                $s.BackColor = (TC 24 33 48)
                $s.ForeColor = $script:C_TEXT
            }
        } catch {}
    })
    $nb.Add_MouseLeave({
        param($s, $e)
        try {
            if ($script:UI.CurrentPage -ne $s.Tag.Page) {
                $s.BackColor = $script:C_PANEL2
                $s.ForeColor = $script:C_SUB
            }
        } catch {}
    })
    $nav.Controls.Add($nb)
    Set-Round $nb 10
    $script:UI.NavBtns[$nd.Key] = $nb
    $ny += 46
}
$navFoot = New-Label $nav "v$($script:AppVersion)`n核显 / 独显 / 混合显卡`n本地运行 · 不上传数据" 20 ($fh - 200) 164 64 8 $false $script:C_DIM
$navFoot.Anchor = 'Bottom, Left'

# 底部状态栏
$statusBar = New-Object System.Windows.Forms.Panel
$statusBar.Dock = 'Bottom'
$statusBar.Height = 26
$statusBar.BackColor = $script:C_PANEL2
$form.Controls.Add($statusBar)
$lblStatus = New-Label $statusBar '就绪' 14 3 760 20 8.5 $false $script:C_DIM
$lblStatus.Anchor = 'Top, Left, Right'
$statusMode = '管理员模式'
if (-not $isAdmin) { $statusMode = '非管理员模式' }
$lblRender = New-Label $statusBar '' ($fw - 600) 3 300 20 8.5 $false $script:C_DIM 'MiddleRight'
$lblRender.Anchor = 'Top, Right'
$lblRender.Visible = [bool]$script:GuiCfg.ShowRenderInfo
$script:UI.Render = $lblRender
$lblStatusR = New-Label $statusBar "v$($script:AppVersion) · $statusMode" ($fw - 280) 3 260 20 8.5 $false $script:C_DIM 'MiddleRight'
$lblStatusR.Anchor = 'Top, Right'
$statusLine = New-Object System.Windows.Forms.Panel
$statusLine.Dock = 'Top'
$statusLine.Height = 1
$statusLine.BackColor = $script:C_BORDER
$statusBar.Controls.Add($statusLine)

# 内容区已在顶栏之前创建并加入窗体
function New-Page([string]$key) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Dock = 'Fill'
    $p.Size = New-Object Drawing.Size -ArgumentList @($content.ClientSize.Width, $content.ClientSize.Height)
    $p.BackColor = $script:C_BG
    $p.AutoScroll = $true
    $p.Visible = $false
    $content.Controls.Add($p)
    $script:UI.Pages[$key] = $p
    return $p
}

# ══════════════════════════════════════════════════════════
# 概览页
# ══════════════════════════════════════════════════════════
$cw = $fw - 200
$ov = New-Page 'overview'
$script:UI.Ov = $ov
$ov.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, 700)

$hero = New-Card $ov 20 16 ($cw - 40) 126 16 $script:C_PANEL $script:C_BORDER
$script:UI.Hero = $hero
$script:HF = @{
    Tag = F 8 $true
    Title = F 20 $true
    Sub = F 10
    Stat = F 18 $true
    StatLabel = F 8.5
    Small = F 8
}
$hero.Add_Paint({
    param($s, $e)
    $sc = [double]$script:UI_SCALE
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $r = New-Object Drawing.Rectangle -ArgumentList @(0, 0, ($s.Width - 1), ($s.Height - 1))
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @($r, (TC 14 32 46), (TC 24 28 52), [single](20 * $sc))
    $g.FillRectangle($lg, $r)
    $lg.Dispose()
    $accentRect = New-Object Drawing.Rectangle -ArgumentList @(0, 1, $s.Width, [int](2 * $sc))
    $ag = New-Object Drawing.SolidBrush -ArgumentList @($script:C_CYAN)
    $g.FillRectangle($ag, $accentRect)
    $ag.Dispose()
    $glow1 = New-Object Drawing.SolidBrush -ArgumentList @((TC 10 76 194 224))
    $g.FillEllipse($glow1, ($s.Width - 260 * $sc), (-130 * $sc), (300 * $sc), (300 * $sc))
    $glow1.Dispose()
    $bTag = New-Object Drawing.SolidBrush -ArgumentList @($script:C_CYAN)
    $g.DrawString('TIANXI PERFORMANCE LAB', $script:HF.Tag, $bTag, (24 * $sc), (12 * $sc))
    $bTag.Dispose()
    $bTitle = New-Object Drawing.SolidBrush -ArgumentList @($script:C_TEXT)
    $g.DrawString('游戏性能优化中心', $script:HF.Title, $bTitle, (22 * $sc), (28 * $sc))
    $bTitle.Dispose()
    $sub = '正在读取硬件信息'
    try {
        $gs = @($script:Snap.Gpus | ForEach-Object { $t = '核显'; if ($_.Dedicated) { $t = '独显' }; if ($_.Basic) { $t = '基础显示' }; if ($_.Virtual) { $t = '虚拟'; }; "$($_.Name) [$t]" })
        $sub = "$($script:MachineTxt) · $($gs -join ' + ') · $(if($isAdmin){'管理员模式'}else{'非管理员模式'})"
        if (@($script:Snap.Gpus | Where-Object Dedicated).Count -eq 0) { $sub += ' · 未检测到独显' }
    } catch {}
    $bSub = New-Object Drawing.SolidBrush -ArgumentList @($script:C_SUB)
    $g.DrawString($sub, $script:HF.Sub, $bSub, (24 * $sc), (60 * $sc))
    $bSub.Dispose()
    $chk = 0
    try { $chk = [int]$script:Snap.Summary.Checking } catch {}
    $stats = @(
        @{ V = $(if ($chk -gt 0) { '--' } else { $script:Snap.Summary.Applied });      T = '已生效'; C = $script:C_GREEN },
        @{ V = $(if ($chk -gt 0) { '--' } else { $script:Snap.Summary.Pending });      T = '待应用'; C = $script:C_ORANGE },
        @{ V = $(if ($chk -gt 0) { '--' } else { $script:Snap.Summary.NotApplicable });T = '不适用'; C = $script:C_DIM }
    )
    $sx = $s.Width - (312 * $sc)
    $fmt = New-Object Drawing.StringFormat
    $fmt.Alignment = 'Far'
    $fmt.LineAlignment = 'Center'
    foreach ($st in $stats) {
        $bV = New-Object Drawing.SolidBrush -ArgumentList @($st.C)
        $rv = New-Object Drawing.RectangleF -ArgumentList @($sx, (28 * $sc), (100 * $sc), (34 * $sc))
        $g.DrawString([string]$st.V, $script:HF.Stat, $bV, $rv, $fmt)
        $bV.Dispose()
        $bL = New-Object Drawing.SolidBrush -ArgumentList @($script:C_SUB)
        $rl = New-Object Drawing.RectangleF -ArgumentList @($sx, (64 * $sc), (100 * $sc), (18 * $sc))
        $g.DrawString($st.T, $script:HF.StatLabel, $bL, $rl, $fmt)
        $bL.Dispose()
        $sx += 104 * $sc
    }
    $fmt.Dispose()
})
$heroBtnBg = (TC 22 48 62)
$heroBtnBg2 = (TC 22 36 50)
if ($script:ThemeName -eq 'light') {
    $heroBtnBg = [Drawing.Color]::FromArgb(196, 212, 227)
    $heroBtnBg2 = [Drawing.Color]::FromArgb(203, 217, 231)
}
$btnQuick = New-Btn $hero '一键优化' 24 84 116 32 $script:C_GREEN ((TC 6 22 13)) 9
$btnQuick.Add_Click({ Invoke-QuickOptimize })
$btnPreview = New-Btn $hero '预览变更' 148 84 108 32 $heroBtnBg $script:C_TEXT 9
$btnPreview.Add_Click({ Invoke-PreviewSelected })
$btnRestoreLatest = New-Btn $hero '撤销上次优化' 264 84 124 32 $heroBtnBg2 $script:C_SUB 9
$btnRestoreLatest.Add_Click({ Invoke-RestoreLatest })

# 硬件卡片悬停 / 点击
$script:HwPress = $null
$script:UiShownAt = $null
function Set-HwCardHover($card, [bool]$on) {
    try {
        if (-not $card) { return }
        $accent = $script:C_CYAN
        try { if ($card.Tag -and $card.Tag.Accent) { $accent = $card.Tag.Accent } } catch {}
        if ($on) {
            $card.Fill = (TC 24 31 45)
            $card.BorderColor = (TC 130 $accent.R $accent.G $accent.B)
        } else {
            $card.Fill = $script:C_PANEL
            $card.BorderColor = $script:C_BORDER
        }
        $card.Invalidate()
        foreach ($c in @($card.Controls)) { try { $c.Invalidate() } catch {} }
    } catch {}
}

function Enable-HwCardInteraction($card, [string]$key, $accent) {
    if (-not $card) { return }
    $card.Tag = @{ Key = $key; Accent = $accent }
    # 只有在同一张卡上完成"左键按下 -> 左键松开"才视为点击。
    # 启动/激活瞬间的残余鼠标消息、按住拖出卡片后再松开都不会触发详情。
    $down = {
        param($s, $e)
        if (-not $e -or $e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        $c = $s
        if (-not ($c -is [TxUi.Card])) { $c = $c.Parent }
        if ($c) {
            $script:HwPress = @{
                Card = $c
                At   = [DateTime]::UtcNow
                Pos  = [System.Windows.Forms.Cursor]::Position
            }
        }
    }
    $up = {
        param($s, $e)
        $press = $script:HwPress
        $script:HwPress = $null
        if (-not $e -or $e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        $c = $s
        if (-not ($c -is [TxUi.Card])) { $c = $c.Parent }
        if (-not $c -or -not $press -or $press.Card -ne $c) { return }
        # 长按 / 拖拽不算点击
        if (([DateTime]::UtcNow - $press.At).TotalMilliseconds -gt 1200) { return }
        $dx = [Math]::Abs([System.Windows.Forms.Cursor]::Position.X - $press.Pos.X)
        $dy = [Math]::Abs([System.Windows.Forms.Cursor]::Position.Y - $press.Pos.Y)
        if ($dx -gt (UiPx 6) -or $dy -gt (UiPx 6)) { return }
        # 启动初期的残余消息不弹详情
        $now = [DateTime]::UtcNow
        if ($script:UiShownAt -and ($now - $script:UiShownAt).TotalMilliseconds -lt 900) { return }
        if ($c.Tag) { Show-HardwareDetails ([string]$c.Tag.Key) }
    }
    $enter = {
        param($s, $e)
        $c = $s
        if (-not ($c -is [TxUi.Card])) { $c = $c.Parent }
        Set-HwCardHover $c $true
    }
    $leave = {
        param($s, $e)
        $c = $s
        if (-not ($c -is [TxUi.Card])) { $c = $c.Parent }
        if ($c) {
            $pt = $c.PointToClient([System.Windows.Forms.Cursor]::Position)
            if (-not $c.ClientRectangle.Contains($pt)) { Set-HwCardHover $c $false }
        }
    }
    foreach ($c in (@($card) + @($card.Controls))) {
        try {
            $c.Cursor = [System.Windows.Forms.Cursors]::Hand
            $c.Add_MouseEnter($enter)
            $c.Add_MouseLeave($leave)
            $c.Add_MouseDown($down)
            $c.Add_MouseUp($up)
        } catch {}
    }
}

# 硬件卡片
$hwW = [int](($cw - 40 - 36) / 4)
$hwDefs = @(
    @{ Key='cpu';  Label='CPU';  Accent=$script:C_CYAN },
    @{ Key='gpu';  Label='GPU';  Accent=$script:C_PURPLE },
    @{ Key='ram';  Label='RAM';  Accent=$script:C_GREEN },
    @{ Key='disk'; Label='显示 / 存储'; Accent=$script:C_ORANGE }
)
$script:UI.HwCards = @()
$script:UI.Hw = @{}
$null = Get-Tip
$hx = 20
foreach ($hd in $hwDefs) {
    $card = New-Card $ov $hx 160 $hwW 112 12 $script:C_PANEL $script:C_BORDER
    $card.Anchor = 'Top, Left'
    $badgeW = 58
    if ($hd.Key -eq 'disk') { $badgeW = 88 }
    $null = New-Badge $card $hd.Label 14 12 $badgeW 22 $script:C_GRAY_BG $script:C_GRAY_BD $script:C_SUB 7.5
    $v = New-Label $card '--' 14 38 ($hwW - 28) 28 10.5 $true $script:C_TEXT
    $s1 = New-Label $card '' 14 70 ($hwW - 28) 18 8.5 $false $script:C_SUB
    $s2 = New-Label $card '' 14 89 ($hwW - 28) 18 8 $false $script:C_DIM
    $v.Anchor = 'Top, Left, Right'
    $s1.Anchor = 'Top, Left, Right'
    $s2.Anchor = 'Top, Left, Right'
    $script:UI.Hw[$hd.Key] = @{ Value = $v; Sub1 = $s1; Sub2 = $s2; Card = $card }
    $script:UI.HwCards += $card
    Enable-HwCardInteraction $card $hd.Key $hd.Accent
    $hx += $hwW + 12
}

# 实时监控
$mon = New-Card $ov 20 290 ($cw - 40) 168 12 $script:C_PANEL $script:C_BORDER
$script:UI.Mon = $mon
$null = New-SectionTitle $mon '实时监控' 18 12 160 11
$null = New-Label $mon '每 0.25 秒刷新 · 仅本机读取' 124 15 260 18 8 $false $script:C_DIM
$script:UI.Meters = @{}
$meterDefs = @(
    @{ Key='cpu'; Caption='CPU 使用率'; Accent=$script:C_CYAN },
    @{ Key='gpu'; Caption='GPU 3D 负载'; Accent=$script:C_CYAN },
    @{ Key='ram'; Caption='内存占用';   Accent=$script:C_CYAN },
    @{ Key='net'; Caption='网络'; Accent=$script:C_CYAN }
)
$script:UI.MeterCtrls = @()
foreach ($md in $meterDefs) {
    $m = New-Object TxUi.Meter
    $m.Caption = $md.Caption
    $m.ValueText = '--'
    $m.Accent = $md.Accent
    $m.BackColor = $script:C_PANEL
    $m.UiScale = [single]$script:UI_SCALE
    $m.LightMode = ($script:ThemeName -eq 'light')
    $m.Height = 58
    $mon.Controls.Add($m)
    $script:UI.Meters[$md.Key] = $m
    $script:UI.MeterCtrls += $m
}
$innerMon = [int](($cw - 40 - 36 - 36) / 4)
for ($i = 0; $i -lt 4; $i++) {
    $script:UI.MeterCtrls[$i].Location = New-Object Drawing.Point -ArgumentList @((18 + $i * ($innerMon + 12)), 48)
    $script:UI.MeterCtrls[$i].Width = $innerMon
}
$null = New-Label $mon '数据来源: 系统内核计数器 / CIM · 不联网、不上传' 18 140 420 18 8 $false $script:C_DIM

# 待应用项
$leftW = [int](($cw - 40 - 12) * 0.58)
$pendCard = New-Card $ov 20 476 $leftW 180 12 $script:C_PANEL $script:C_BORDER
$script:UI.PendCard = $pendCard
$script:UI.PendTitle = New-SectionTitle $pendCard '待应用项' 16 12 220 11
$btnGoItems = New-Btn $pendCard '查看全部' ($leftW - 92) 12 76 24 ((TC 24 35 50)) $script:C_CYAN 8 $false
$btnGoItems.Anchor = 'Top, Right'
$btnGoItems.Add_Click({ Show-Page 'items' })
$script:UI.PendLabels = @()
for ($i = 0; $i -lt 5; $i++) {
    $pl = New-Label $pendCard '' 16 (44 + $i * 24) ($leftW - 32) 22 9 $false $script:C_SUB
    $script:UI.PendLabels += $pl
}

# 系统状态
$rightW = $cw - 40 - $leftW - 12
$sysCard = New-Card $ov (20 + $leftW + 12) 476 $rightW 180 12 $script:C_PANEL $script:C_BORDER
$script:UI.SysCard = $sysCard
$null = New-SectionTitle $sysCard '系统状态' 16 12 160 11
$sysNames = @('待重启','上次应用','供电','安全','网络','备份','版本')
$script:UI.SysVals = @()
for ($i = 0; $i -lt $sysNames.Count; $i++) {
    $null = New-Label $sysCard $sysNames[$i] 16 (38 + $i * 19) 62 18 8.5 $false $script:C_DIM
    $vv = New-Label $sysCard '--' 80 (38 + $i * 19) ($rightW - 96) 18 8.5 $false $script:C_TEXT
    $script:UI.SysVals += $vv
}

$ov.Add_Resize({
    param($s, $e)
    if ($script:UiScaling) { return }
    try { Layout-Overview } catch {}
})

# ══════════════════════════════════════════════════════════
# 驱动中心
# ══════════════════════════════════════════════════════════
# 数据来源全部在本机: PnP 设备、驱动仓库 (pnputil)、INF 文件、
# Windows Update 的驱动条目。不做静默下载, 所有安装/删除都要确认。
$script:DrvInfCache = @{}
$script:DrvPkgCache = $null
$script:DrvPkgAt = [DateTime]::MinValue
$script:DrvDevCache = $null
$script:DrvDevAt = [DateTime]::MinValue
$script:DrvData = $null
$script:DrvAt = [DateTime]::MinValue
$script:DrvWu = $null
$script:DrvWuAt = [DateTime]::MinValue
# Intel 驱动支持助手 (DSA) 本地数据
$script:DrvDsa = $null
$script:DrvDsaAt = [DateTime]::MinValue
# 其他厂商官方工具 (NVIDIA App / AMD Software) 检测缓存
$script:DrvTools = $null
$script:DrvToolsAt = [DateTime]::MinValue
$script:DrvFilter = '全部'
$script:DrvQuery = ''
$script:DrvNeedRefresh = $false
$script:DrvInstallState = $null
$script:DrvBusy = $false
$script:DrvCardW = UiPx 326
# 渐进式补全: 设备卡片先出来, 驱动包信息逐个填进去
$script:DrvCards = @{}
$script:DrvPkgs = @()
$script:DrvEnrichQueue = $null
$script:DrvEnrichTotal = 0
$script:DrvEnrichDone = 0
# 详情页里做过改动后, 只刷新对应设备
$script:DrvRefreshDevice = ''
$script:DrvRefreshEnum = $false
$script:UI.DriverDirty = $true
$script:DrvHF = @{
    Tag   = F 8 $true
    Title = F 20 $true
    Sub   = F 9
}

# ── 音频端点静音保护 ─────────────────────────────────────
# 任何驱动安装/切换/清理前后都记录一次端点静音状态, 操作结束后比对,
# 只在"静音状态被意外改变"时还原, 不碰用户主动调整的音量和静音。
# 这样即便驱动重装把麦克风重新置为静音, 也会被自动纠正。
$script:TxAudioGuardReady = $false
$script:TxAudioGuardTimer = $null
$script:TxAudioGuardCode = @'
using System;
using System.Runtime.InteropServices;

public static class TxAudioGuard
{
    static readonly Guid CLSID_MMDE =
        new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IE
    {
        [PreserveSig] int EnumAudioEndpoints(int f, int m, out IC c);
        [PreserveSig] int GetDefaultAudioEndpoint(int f, int r, out ID d);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out ID d);
        [PreserveSig] int Reg(IntPtr p);
        [PreserveSig] int Unreg(IntPtr p);
    }

    [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IC
    {
        [PreserveSig] int GetCount(out int c);
        [PreserveSig] int Item(int i, out ID d);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ID
    {
        [PreserveSig] int Activate(ref Guid iid, int c, IntPtr p, out IntPtr o);
        [PreserveSig] int OpenPropertyStore(int a, out IntPtr s);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out int s);
    }

    [ComImport, Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IVol
    {
        [PreserveSig] int RegisterControlChangeNotify(IntPtr n);
        [PreserveSig] int UnregisterControlChangeNotify(IntPtr n);
        [PreserveSig] int GetChannelCount(out int c);
        [PreserveSig] int SetMasterVolumeLevel(float v, Guid g);
        [PreserveSig] int SetMasterVolumeLevelScalar(float v, Guid g);
        [PreserveSig] int GetMasterVolumeLevel(out float v);
        [PreserveSig] int GetMasterVolumeLevelScalar(out float v);
        [PreserveSig] int SetChannelVolumeLevel(uint i, float v, Guid g);
        [PreserveSig] int SetChannelVolumeLevelScalar(uint i, float v, Guid g);
        [PreserveSig] int GetChannelVolumeLevel(uint i, out float v);
        [PreserveSig] int GetChannelVolumeLevelScalar(uint i, out float v);
        [PreserveSig] int SetMute(int m, Guid g);
        [PreserveSig] int GetMute(out int m);
    }

    static Guid IID_VOL = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
    static readonly System.Collections.Generic.Dictionary<string, bool> _snap =
        new System.Collections.Generic.Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);

    // 用 CLSID 激活, 不声明 ComImport coclass:
    // 同一进程里若已有别的包装类用过这个 CLSID, 声明式 coclass 会因 RCW 类型缓存而转型失败。
    static IE Create()
    {
        Type t = Type.GetTypeFromCLSID(CLSID_MMDE, true);
        return (IE)Activator.CreateInstance(t);
    }

    static bool TryState(ID d, out string id, out bool muted)
    {
        id = null; muted = false;
        try
        {
            if (d.GetId(out id) != 0 || string.IsNullOrEmpty(id)) return false;
            IntPtr p;
            if (d.Activate(ref IID_VOL, 23, IntPtr.Zero, out p) != 0 || p == IntPtr.Zero) return false;
            try
            {
                var v = (IVol)Marshal.GetObjectForIUnknown(p);
                int m;
                if (v.GetMute(out m) != 0) return false;
                muted = m != 0;
                return true;
            }
            finally { Marshal.Release(p); }
        }
        catch { return false; }
    }

    static bool TrySetMute(ID d, bool mute)
    {
        try
        {
            IntPtr p;
            if (d.Activate(ref IID_VOL, 23, IntPtr.Zero, out p) != 0 || p == IntPtr.Zero) return false;
            try
            {
                var v = (IVol)Marshal.GetObjectForIUnknown(p);
                return v.SetMute(mute ? 1 : 0, Guid.Empty) == 0;
            }
            finally { Marshal.Release(p); }
        }
        catch { return false; }
    }

    public static int Capture()
    {
        _snap.Clear();
        IE e;
        try { e = Create(); } catch { return 0; }
        for (int flow = 0; flow <= 1; flow++)
        {
            IC col;
            if (e.EnumAudioEndpoints(flow, 1, out col) != 0 || col == null) continue;
            int n;
            if (col.GetCount(out n) != 0) continue;
            for (int i = 0; i < n; i++)
            {
                ID d;
                if (col.Item(i, out d) != 0 || d == null) continue;
                string id; bool muted;
                if (TryState(d, out id, out muted)) _snap[id] = muted;
            }
        }
        return _snap.Count;
    }

    public static int Restore()
    {
        if (_snap.Count == 0) return 0;
        int fixedCount = 0;
        IE e;
        try { e = Create(); } catch { return 0; }
        for (int flow = 0; flow <= 1; flow++)
        {
            IC col;
            if (e.EnumAudioEndpoints(flow, 1, out col) != 0 || col == null) continue;
            int n;
            if (col.GetCount(out n) != 0) continue;
            for (int i = 0; i < n; i++)
            {
                ID d;
                if (col.Item(i, out d) != 0 || d == null) continue;
                string id; bool muted;
                if (!TryState(d, out id, out muted)) continue;
                bool want;
                if (!_snap.TryGetValue(id, out want)) continue;
                if (muted == want) continue;
                if (TrySetMute(d, want)) fixedCount++;
            }
        }
        return fixedCount;
    }
}
'@

function Initialize-TxAudioGuard {
    if ($script:TxAudioGuardReady) { return $true }
    try {
        Add-Type -TypeDefinition $script:TxAudioGuardCode -ErrorAction Stop
        $script:TxAudioGuardReady = $true
        return $true
    } catch { return $false }
}

function Protect-TxAudioBegin {
    if (-not (Initialize-TxAudioGuard)) { return $false }
    try { [void][TxAudioGuard]::Capture(); return $true } catch { return $false }
}

function Protect-TxAudioEnd {
    param([switch]$Deferred)
    if (-not $script:TxAudioGuardReady) { return }
    try {
        $n = [TxAudioGuard]::Restore()
        if ($n -gt 0) { Set-Status "已自动恢复 $n 个音频设备的静音状态" }
    } catch {}
    if (-not $Deferred) { return }
    # 驱动重装后端点可能稍后才重新枚举, 延迟再兜底恢复一次
    try {
        if ($script:TxAudioGuardTimer) { try { $script:TxAudioGuardTimer.Stop(); $script:TxAudioGuardTimer.Dispose() } catch {} }
        $script:TxAudioGuardTimer = New-Object System.Windows.Forms.Timer
        $script:TxAudioGuardTimer.Interval = 2500
        $script:TxAudioGuardTimer.Add_Tick({
            param($s, $e)
            try { $s.Stop() } catch {}
            try {
                $n = [TxAudioGuard]::Restore()
                if ($n -gt 0) { Set-Status "已自动恢复 $n 个音频设备的静音状态" }
            } catch {}
            try { $s.Dispose() } catch {}
            $script:TxAudioGuardTimer = $null
        })
        $script:TxAudioGuardTimer.Start()
    } catch {}
}


function Get-TxHwBase([string]$id) {
    if (-not $id) { return '' }
    return (($id -replace '&REV_[0-9A-Fa-f]+', '').Trim().ToUpperInvariant())
}

function ConvertTo-TxVersionParts([string]$v) {
    $m = [regex]::Match([string]$v, '\d+(?:\.\d+){0,3}')
    if (-not $m.Success) { return @() }
    return @($m.Value.Split('.') | ForEach-Object { [int]$_ })
}

function Compare-TxVersion([string]$a, [string]$b) {
    $va = @(ConvertTo-TxVersionParts $a)
    $vb = @(ConvertTo-TxVersionParts $b)
    $n = [Math]::Max($va.Count, $vb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $x = 0
        $y = 0
        if ($i -lt $va.Count) { $x = [int]$va[$i] }
        if ($i -lt $vb.Count) { $y = [int]$vb[$i] }
        if ($x -lt $y) { return -1 }
        if ($x -gt $y) { return 1 }
    }
    return 0
}

# 解析 INF: 版本 / 日期 / 厂商 / 硬件 ID 列表
function Get-TxInfMeta([string]$infName) {
    if (-not $infName) { return $null }
    $key = ([string]$infName).ToLowerInvariant()
    if ($script:DrvInfCache.ContainsKey($key)) { return $script:DrvInfCache[$key] }
    $meta = $null
    $path = Join-Path (Join-Path $env:WINDIR 'INF') $infName
    if (Test-Path -LiteralPath $path) {
        try {
            $sections = @{}
            $cur = $null
            foreach ($line in @(Get-Content -LiteralPath $path -ErrorAction Stop)) {
                $t = ([string]$line).Trim()
                if ($t -match '^\[(.+)\]$') {
                    $cur = $matches[1]
                    if (-not $sections.ContainsKey($cur)) { $sections[$cur] = New-Object System.Collections.ArrayList }
                    continue
                }
                if ($null -ne $cur -and $t) { [void]$sections[$cur].Add($t) }
            }
            $ver = ''
            $date = ''
            $provider = ''
            $class = ''
            if ($sections.ContainsKey('Version')) {
                foreach ($l in @($sections['Version'])) {
                    if ($l -match '^(?i)DriverVer\s*=\s*([^,]+),\s*(.+)$') { $date = $matches[1].Trim(); $ver = $matches[2].Trim() }
                    elseif ($l -match '^(?i)Provider\s*=\s*(.+)$') { $provider = $matches[1].Trim() }
                    elseif ($l -match '^(?i)Class\s*=\s*(.+)$') { $class = $matches[1].Trim() }
                }
            }
            $strings = @{}
            if ($sections.ContainsKey('Strings')) {
                foreach ($l in @($sections['Strings'])) {
                    if ($l -match '^([^=]+?)\s*=\s*(.+)$') {
                        $strings[$matches[1].Trim()] = $matches[2].Trim().Trim('"')
                    }
                }
            }
            $pm = [regex]::Match($provider, '^%(.+)%$')
            if ($pm.Success -and $strings.ContainsKey($pm.Groups[1].Value)) { $provider = [string]$strings[$pm.Groups[1].Value] }
            $hwids = New-Object 'System.Collections.Generic.HashSet[string]'
            foreach ($sk in @($sections.Keys)) {
                if ($sk -match '^(?i)(Version|Strings|Manufacturer|SourceDisksNames|SourceDisksFiles|DestinationDirs|ControlFlags|ClassInstall.*|AddReg|CopyFiles|DeleteFiles|RenFiles|UpdateInis|UpdateIniFields|Ini2Reg|LogConfig.*|.*\.Services|.*\.HW|.*\.CoInstallers.*)$') { continue }
                foreach ($l in @($sections[$sk])) {
                    if ($l.IndexOf('=') -lt 0) { continue }
                    $parts = $l.Split(',')
                    if ($parts.Count -lt 2) { continue }
                    for ($i = 1; $i -lt $parts.Count; $i++) {
                        $h = ([string]$parts[$i]).Trim()
                        $h = ($h -split ';')[0].Trim()
                        if ($h -match '^(?i)(PCI|USB|HID|ROOT|SWC|ACPI|BTHENUM|BTHLEDEVICE|SCSI|IDE|STORAGE|SWD|DISPLAY|MODEM|MF|PCMCIA|1394|SD|SMBIOS|INTELAUDIO|HDAUDIO)\\') {
                            [void]$hwids.Add($h.ToUpperInvariant())
                        } elseif ($h -match '^\{[0-9A-Fa-f\-]{36}\}$') {
                            [void]$hwids.Add($h.ToUpperInvariant())
                        }
                    }
                }
            }
            $meta = [PSCustomObject]@{
                InfName     = $infName
                Version     = $ver
                Date        = $date
                Provider    = $provider
                Class       = $class
                HardwareIds = @($hwids)
            }
        } catch { $meta = $null }
    }
    $script:DrvInfCache[$key] = $meta
    return $meta
}

# 驱动仓库列表 (pnputil /enum-drivers)
function Get-TxDriverPackages([switch]$Force) {
    if (-not $Force -and $script:DrvPkgCache -and ((Get-Date) - $script:DrvPkgAt).TotalSeconds -lt 30) { return @($script:DrvPkgCache) }
    $list = New-Object System.Collections.ArrayList
    try {
        $lines = & pnputil.exe /enum-drivers 2>&1
        $cur = @{}
        foreach ($line in @($lines)) {
            $t = [string]$line
            if ($t -match '^\s*(Published Name|发布名称)\s*:\s*(.+)$') {
                if ($cur.Count -gt 0) { [void]$list.Add([PSCustomObject]$cur); $cur = @{} }
                $cur['PublishedName'] = $matches[2].Trim()
            } elseif ($t -match '^\s*(Original Name|原始名称)\s*:\s*(.+)$') { $cur['OriginalName'] = $matches[2].Trim() }
            elseif ($t -match '^\s*(Provider Name|提供程序名称)\s*:\s*(.+)$') { $cur['ProviderName'] = $matches[2].Trim() }
            elseif ($t -match '^\s*(Class Name|类名称)\s*:\s*(.+)$') { $cur['ClassName'] = $matches[2].Trim() }
            elseif ($t -match '^\s*(Class GUID|类 GUID)\s*:\s*(.+)$') { $cur['ClassGuid'] = $matches[2].Trim() }
            elseif ($t -match '^\s*(Driver Version|驱动程序版本)\s*:\s*(.+)$') { $cur['DriverVersionRaw'] = $matches[2].Trim() }
        }
        if ($cur.Count -gt 0) { [void]$list.Add([PSCustomObject]$cur) }
    } catch {}
    foreach ($p in $list) {
        $p | Add-Member -NotePropertyName Version -NotePropertyValue '' -Force
        $p | Add-Member -NotePropertyName Date -NotePropertyValue '' -Force
        $raw = [string]$p.DriverVersionRaw
        $m = [regex]::Match($raw, '^(.*?)\s+(\d+(?:\.\d+){1,3})$')
        if ($m.Success) {
            $p.Date = $m.Groups[1].Value.Trim()
            $p.Version = $m.Groups[2].Value.Trim()
        } else {
            $p.Version = $raw
        }
    }
    $script:DrvPkgCache = @($list.ToArray())
    $script:DrvPkgAt = Get-Date
    return @($script:DrvPkgCache)
}

# 设备列表 (pnputil /enum-devices /connected /drivers /ids)
# 一次调用同时拿到设备、当前驱动版本、厂商与硬件 ID。相比逐个遍历
# Win32_PnPSignedDriver + Win32_PnPEntity (两次 WMI 查询, 约 4.4 秒),
# 这里通常 1.5 秒左右, 让卡片能更快出现。
function Get-TxDriverDevices([switch]$Force) {
    if (-not $Force -and $script:DrvDevCache -and ((Get-Date) - $script:DrvDevAt).TotalSeconds -lt 30) { return @($script:DrvDevCache) }
    $raw = New-Object System.Collections.ArrayList
    try {
        $lines = @(& pnputil.exe /enum-devices /connected /drivers /ids 2>&1)
        $cur = $null
        $inHw = $false
        $inDrv = $false
        $drv = $null
        foreach ($line in $lines) {
            $t = [string]$line
            $trim = $t.Trim()
            if ($trim -match '^(Instance ID|设备实例 ID)\s*:\s*(.+)$') {
                if ($cur) { $cur.Candidates = @($cur.CandidateList.ToArray()); [void]$raw.Add($cur) }
                $cur = @{
                    DeviceId      = $matches[2].Trim()
                    Name          = ''
                    ClassName     = ''
                    ClassGuid     = ''
                    Manufacturer  = ''
                    Status        = ''
                    DriverName    = ''
                    HardwareIds   = (New-Object System.Collections.ArrayList)
                    CandidateList = (New-Object System.Collections.ArrayList)
                    Candidates    = @()
                }
                $inHw = $false; $inDrv = $false; $drv = $null
                continue
            }
            if (-not $cur) { continue }
            if ($inHw) {
                if ($t -match '^\s{12,}(\S.*)$') { [void]$cur.HardwareIds.Add($matches[1].Trim()); continue }
                $inHw = $false
            }
            if ($trim -match '^(Matching Drivers|匹配的驱动程序)\s*:') { $inDrv = $true; continue }
            if ($inDrv) {
                if ($t -match '^\s+(Driver Name|驱动程序名称)\s*:\s*(.+)$') {
                    $drv = @{ Name = $matches[2].Trim(); VersionRaw = ''; Provider = ''; Status = '' }
                    [void]$cur.CandidateList.Add($drv)
                } elseif ($t -match '^\s+(Driver Version|驱动程序版本)\s*:\s*(.+)$') {
                    if ($drv) { $drv.VersionRaw = $matches[2].Trim() }
                } elseif ($t -match '^\s+(Provider Name|提供程序名称)\s*:\s*(.+)$') {
                    if ($drv) { $drv.Provider = $matches[2].Trim() }
                } elseif ($t -match '^\s+(Driver Status|驱动程序状态)\s*:\s*(.+)$') {
                    if ($drv) { $drv.Status = $matches[2].Trim() }
                }
                continue
            }
            if ($trim -match '^(Device Description|设备描述)\s*:\s*(.+)$') { $cur.Name = $matches[2].Trim() }
            elseif ($trim -match '^(Class Name|类名称)\s*:\s*(.+)$') { $cur.ClassName = $matches[2].Trim() }
            elseif ($trim -match '^(Class GUID|类 GUID)\s*:\s*(.+)$') { $cur.ClassGuid = $matches[2].Trim() }
            elseif ($trim -match '^(Manufacturer Name|制造商名称)\s*:\s*(.+)$') { $cur.Manufacturer = $matches[2].Trim() }
            elseif ($trim -match '^(Status|状态)\s*:\s*(.+)$') { $cur.Status = $matches[2].Trim() }
            elseif ($trim -match '^(Driver Name|驱动程序名称)\s*:\s*(.+)$') { $cur.DriverName = $matches[2].Trim() }
            elseif ($trim -match '^(Hardware IDs|硬件 ID)\s*:\s*(.+)$') {
                $v = $matches[2].Trim()
                if ($v) { [void]$cur.HardwareIds.Add($v) }
                $inHw = $true
            }
        }
        if ($cur) { $cur.Candidates = @($cur.CandidateList.ToArray()); [void]$raw.Add($cur) }
    } catch {}

    if ($raw.Count -eq 0) {
        $fb = @(Get-TxDriverDevicesCim)
        $script:DrvDevCache = $fb
        $script:DrvDevAt = Get-Date
        return $fb
    }
    $devs = New-Object System.Collections.ArrayList
    $seen = @{}
    foreach ($r in $raw) {
        $cls = ([string]$r.ClassName).ToUpperInvariant()
        if ($cls -notin @('DISPLAY', 'MEDIA', 'MOUSE', 'KEYBOARD', 'HIDCLASS', 'NET', 'BLUETOOTH')) { continue }
        $infName = [string]$r.DriverName
        if (-not $infName -or $infName -eq 'null' -or $infName -match '^(?i)n/a$') { continue }
        $name = [string]$r.Name
        if (-not $name) { continue }
        if ($cls -eq 'DISPLAY' -and ($name -match '(?i)Basic Display|Basic Render')) { continue }
        if ($cls -eq 'HIDCLASS' -and -not ($name -match '(?i)mouse|keyboard|logitech|razer|steelseries|corsair|罗技|雷蛇|键盘|鼠标')) { continue }
        if ($cls -eq 'NET' -and ($name -match '(?i)WAN Miniport|TAP-|VPN|Virtual|Hyper-V|Loopback|Kernel Debug')) { continue }
        $devId = [string]$r.DeviceId
        if (-not $devId) { continue }
        $key = ($devId + '|' + $infName).ToUpperInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        # 当前生效的驱动: 优先取与设备级 Driver Name 一致的那条, 否则取第一条
        $cand = $null
        foreach ($c in @($r.Candidates)) {
            if (([string]$c.Name).ToLowerInvariant() -eq $infName.ToLowerInvariant()) { $cand = $c; break }
        }
        if (-not $cand -and @($r.Candidates).Count -gt 0) { $cand = @($r.Candidates)[0] }
        $verRaw = ''
        $provider = ''
        if ($cand) { $verRaw = [string]$cand.VersionRaw; $provider = [string]$cand.Provider }
        if (-not $provider) { $provider = [string]$r.Manufacturer }
        $ver = $verRaw
        $date = ''
        $m = [regex]::Match($verRaw, '^(.*?)\s+(\d+(?:\.\d+){1,3})$')
        if ($m.Success) {
            $date = $m.Groups[1].Value.Trim()
            $ver = $m.Groups[2].Value.Trim()
            try { if ($date) { $date = ([datetime]::Parse($date)).ToString('yyyy/M/d') } } catch {}
        }

        $statusOk = $true
        $statusText = '正常'
        $st = [string]$r.Status
        if ($st -and $st -notin @('Started', 'OK', 'Unknown')) {
            $statusOk = $false
            if ($st -match '(?i)disabled|已禁用') { $statusText = '已禁用' }
            elseif ($st -match '(?i)stopped|已停止') { $statusText = '已停止' }
            elseif ($st -match '(?i)problem|error|错误') { $statusText = '异常' }
            else { $statusText = $st }
        }

        $cat = '其他'
        switch ($cls) {
            'DISPLAY'   { $cat = '显卡' }
            'MEDIA'     { $cat = '音频' }
            'MOUSE'     { $cat = '外设' }
            'KEYBOARD'  { $cat = '外设' }
            'HIDCLASS'  { $cat = '外设' }
            'NET'       { $cat = '网络' }
            'BLUETOOTH' { $cat = '网络' }
        }
        $hw = ''
        if (@($r.HardwareIds).Count -gt 0) { $hw = [string](@($r.HardwareIds)[0]) }
        $accent = switch ($cat) {
            '显卡' { $script:C_PURPLE }
            '音频' { $script:C_CYAN }
            '外设' { $script:C_GREEN }
            '网络' { $script:C_ORANGE }
            default { $script:C_BLUE }
        }
        [void]$devs.Add([PSCustomObject]@{
            Name        = $name
            Class       = $cls
            Category    = $cat
            DeviceId    = $devId
            HardwareId  = $hw
            InfName     = $infName
            Version     = $ver
            Date        = $date
            Provider    = $provider
            StatusText  = $statusText
            StatusOk    = $statusOk
            Packages    = @()
            Updates     = @()
            Flags       = @()
            HasUpdate   = $false
            UpdateCount = 0
            OldCount    = 0
            Accent      = $accent
            Enriched    = $false
            Vendor      = $null
            VendorState = ''
            VendorNote  = ''
        })
    }
    $order = @{ '显卡' = 0; '音频' = 1; '外设' = 2; '网络' = 3; '其他' = 4 }
    $sorted = @($devs.ToArray() | Sort-Object @{ Expression = { $order[[string]$_.Category] }; Ascending = $true }, @{ Expression = { [string]$_.Name }; Ascending = $true })
    $script:DrvDevCache = $sorted
    $script:DrvDevAt = Get-Date
    return @($script:DrvDevCache)
}

# 兼容兜底: 老系统上 pnputil 不支持 /enum-devices 时, 退回 WMI 查询
function Get-TxDriverDevicesCim {
    $devs = New-Object System.Collections.ArrayList
    try {
        $signed = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction SilentlyContinue)
        $pnpMap = @{}
        foreach ($p in @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)) {
            $k = [string]$p.DeviceID
            if ($k) { $pnpMap[$k.ToUpperInvariant()] = $p }
        }
        $seen = @{}
        foreach ($d in $signed) {
            $cls = ([string]$d.DeviceClass).ToUpperInvariant()
            if ($cls -notin @('DISPLAY', 'MEDIA', 'MOUSE', 'KEYBOARD', 'HIDCLASS', 'NET', 'BLUETOOTH')) { continue }
            $devId = [string]$d.DeviceID
            $infName = [string]$d.InfName
            if (-not $devId -or -not $infName -or $infName -eq 'null') { continue }
            $pnp = $null
            try { $pnp = $pnpMap[$devId.ToUpperInvariant()] } catch {}
            $name = [string]$d.DeviceName
            if (-not $name -and $pnp) { $name = [string]$pnp.Name }
            if (-not $name) { continue }
            if ($cls -eq 'DISPLAY' -and ($name -match '(?i)Basic Display|Basic Render')) { continue }
            if ($cls -eq 'HIDCLASS' -and -not ($name -match '(?i)mouse|keyboard|logitech|razer|steelseries|corsair|罗技|雷蛇|键盘|鼠标')) { continue }
            if ($cls -eq 'NET' -and ($name -match '(?i)WAN Miniport|TAP-|VPN|Virtual|Hyper-V|Loopback|Kernel Debug')) { continue }
            $key = ($devId + '|' + $infName).ToUpperInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $cat = '其他'
            switch ($cls) {
                'DISPLAY'   { $cat = '显卡' }
                'MEDIA'     { $cat = '音频' }
                'MOUSE'     { $cat = '外设' }
                'KEYBOARD'  { $cat = '外设' }
                'HIDCLASS'  { $cat = '外设' }
                'NET'       { $cat = '网络' }
                'BLUETOOTH' { $cat = '网络' }
            }
            $hw = ''
            try {
                if ($d.HardwareID) { $hw = [string](@($d.HardwareID)[0]) }
                if (-not $hw -and $pnp -and $pnp.HardwareID) { $hw = [string](@($pnp.HardwareID)[0]) }
            } catch {}
            $statusOk = $true
            $statusText = '正常'
            try {
                if ($pnp) {
                    $st = [string]$pnp.Status
                    $cer = 0
                    try { $cer = [int]$pnp.ConfigManagerErrorCode } catch {}
                    if ($st -and $st -ne 'OK' -and $st -ne 'Unknown') { $statusText = $st; $statusOk = $false }
                    if ($cer -ne 0) { $statusText = "错误码 $cer"; $statusOk = $false }
                }
            } catch {}
            $curDate = ''
            try { if ($d.DriverDate) { $curDate = ([datetime]$d.DriverDate).ToString('yyyy/M/d') } } catch {}
            $provider = [string]$d.DriverProviderName
            if (-not $provider -and $pnp) { $provider = [string]$pnp.Manufacturer }
            $accent = switch ($cat) {
                '显卡' { $script:C_PURPLE }
                '音频' { $script:C_CYAN }
                '外设' { $script:C_GREEN }
                '网络' { $script:C_ORANGE }
                default { $script:C_BLUE }
            }
            [void]$devs.Add([PSCustomObject]@{
                Name        = $name
                Class       = $cls
                Category    = $cat
                DeviceId    = $devId
                HardwareId  = $hw
                InfName     = $infName
                Version     = [string]$d.DriverVersion
                Date        = $curDate
                Provider    = $provider
                StatusText  = $statusText
                StatusOk    = $statusOk
                Packages    = @()
                Updates     = @()
                Flags       = @()
                HasUpdate   = $false
                UpdateCount = 0
                OldCount    = 0
                Accent      = $accent
                Enriched    = $false
                Vendor      = $null
                VendorState = ''
                VendorNote  = ''
            })
        }
    } catch {}
    $order = @{ '显卡' = 0; '音频' = 1; '外设' = 2; '网络' = 3; '其他' = 4 }
    return @($devs.ToArray() | Sort-Object @{ Expression = { $order[[string]$_.Category] }; Ascending = $true }, @{ Expression = { [string]$_.Name }; Ascending = $true })
}

function Get-TxWuDriverUpdates([switch]$Force) {
    if (-not $Force -and $script:DrvWu -and ((Get-Date) - $script:DrvWuAt).TotalMinutes -lt 5) { return @($script:DrvWu) }
    $list = New-Object System.Collections.ArrayList
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and Type='Driver'")
    foreach ($u in @($result.Updates)) {
        $title = [string]$u.Title
        $ver = ''
        $m = [regex]::Match($title, '\d+\.\d+\.\d+\.\d+')
        if ($m.Success) { $ver = $m.Value }
        $dt = ''
        try { if ($u.DriverVerDate) { $dt = ([datetime]$u.DriverVerDate).ToString('yyyy/M/d') } } catch {}
        [void]$list.Add([PSCustomObject]@{
            Id         = [string]$u.Identity.UpdateID
            Title      = $title
            ClassName  = [string]$u.DriverClass
            HardwareId = [string]$u.DriverHardwareID
            Date       = $dt
            Version    = $ver
            Hidden     = [bool]$u.IsHidden
            Raw        = $u
        })
    }
    $script:DrvWu = @($list.ToArray())
    $script:DrvWuAt = Get-Date
    return @($script:DrvWu)
}

function Get-TxUpdatesForDevice($dev) {
    $out = New-Object System.Collections.ArrayList
    $dh = Get-TxHwBase ([string]$dev.HardwareId)
    if (-not $dh) { return @() }
    foreach ($u in @($script:DrvWu)) {
        if (-not $u) { continue }
        $uh = Get-TxHwBase ([string]$u.HardwareId)
        if (-not $uh) { continue }
        if ($dh -eq $uh -or $dh.StartsWith($uh) -or $uh.StartsWith($dh)) { [void]$out.Add($u) }
    }
    return @($out.ToArray())
}

# ── Intel 驱动支持助手 (DSA) 本地数据 ─────────────────────
# Intel 设备的更新判断以本机 DSA 为准, 而不是 Windows Update:
#   Data\session.xml            设备当前版本 / DSA 判定 / 待更新 ID
#   Data\install-history.json   DSA 实际安装记录 (版本 + 结果)
#   Data\data-*.zip             software-configurations.json 驱动目录
# 三者都只读, 不调用网络, 不触发 DSA 界面。
function Get-TxDsaData([switch]$Force) {
    if (-not $Force -and $null -ne $script:DrvDsa -and ((Get-Date) - $script:DrvDsaAt).TotalSeconds -lt 120) { return $script:DrvDsa }
    $dir = Join-Path $env:ProgramData 'Intel\DSA\Data'
    $res = [PSCustomObject]@{
        Available = $false
        Root      = $dir
        Devices   = @()
        Offered   = @()
        History   = @()
        Catalog   = @()
        At        = (Get-Date)
    }
    if (-not (Test-Path -LiteralPath $dir)) { $script:DrvDsa = $res; $script:DrvDsaAt = Get-Date; return $res }

    $sessionPath = Join-Path $dir 'session.xml'
    if (Test-Path -LiteralPath $sessionPath) {
        try {
            $raw = Get-Content -LiteralPath $sessionPath -Raw -ErrorAction Stop
            $devs = New-Object System.Collections.ArrayList
            foreach ($m in [regex]::Matches($raw, '<d3p1:DeviceComponent>[\s\S]*?</d3p1:DeviceComponent>')) {
                $b = $m.Value
                if ($b -notmatch '<d3p1:IsIntelDevice>true</d3p1:IsIntelDevice>') { continue }
                $name = [regex]::Match($b, '<d3p1:Name>([^<]*)</d3p1:Name><d3p1:ShowMessage>').Groups[1].Value
                $cat = [regex]::Match($b, '<d3p1:Category>([^<]*)</d3p1:Category>').Groups[1].Value
                $ver = [regex]::Match($b, '<d3p1:ResourceKey>DriverVersion</d3p1:ResourceKey><d3p1:Value>([^<]*)</d3p1:Value>').Groups[1].Value
                $uid = [regex]::Match($b, '<d3p1:UpdateId>([^<]*)</d3p1:UpdateId>').Groups[1].Value
                $ust = [regex]::Match($b, '<d3p1:UpdateStatus>([^<]*)</d3p1:UpdateStatus>').Groups[1].Value
                if (-not $ver) { continue }
                [void]$devs.Add([PSCustomObject]@{ Name = $name; Category = $cat; Version = $ver; UpdateId = $uid; UpdateStatus = $ust })
            }
            $res.Devices = @($devs.ToArray())
            $um = [regex]::Match($raw, '<(?:\w+:)?Updates[^>]*>([\s\S]*?)</(?:\w+:)?Updates>')
            $offered = New-Object System.Collections.ArrayList
            if ($um.Success) {
                foreach ($idm in [regex]::Matches($um.Groups[1].Value, '<(?:\w+:)?UpdateId>(\d+)</(?:\w+:)?UpdateId>')) {
                    [void]$offered.Add([int]$idm.Groups[1].Value)
                }
            }
            $res.Offered = @($offered.ToArray())
        } catch {}
    }

    $histPath = Join-Path $dir 'install-history.json'
    if (Test-Path -LiteralPath $histPath) {
        try {
            # 注意: PS 5.1 里 @( ... | ConvertFrom-Json ) 会把整个数组包成一层, 先赋值再展开
            $histObj = Get-Content -LiteralPath $histPath -Raw -ErrorAction Stop | ConvertFrom-Json
            $res.History = @($histObj)
        } catch { $res.History = @() }
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
        $zipPath = Join-Path $dir 'data-zh-CN.zip'
        if (-not (Test-Path -LiteralPath $zipPath)) { $zipPath = Join-Path $dir 'data-en.zip' }
        if (Test-Path -LiteralPath $zipPath) {
            $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
            try {
                $entry = $zip.Entries | Where-Object { $_.FullName -eq 'software-configurations.json' } | Select-Object -First 1
                if ($entry) {
                    $rd = New-Object IO.StreamReader($entry.Open(), [Text.Encoding]::UTF8)
                    try { $json = $rd.ReadToEnd() } finally { $rd.Close() }
                    $cat = New-Object System.Collections.ArrayList
                    $catalogObj = $json | ConvertFrom-Json
                    foreach ($it in @($catalogObj)) {
                        if (-not $it) { continue }
                        $comp = @($it.Components) | Select-Object -First 1
                        $dv = @()
                        $cc = ''
                        if ($comp) { $dv = @($comp.DetectionValues); $cc = [string]$comp.Category }
                        $vv = [regex]::Match([string]$it.Version, '\d+(?:\.\d+){2,3}').Value
                        [void]$cat.Add([PSCustomObject]@{
                            Id             = [int]$it.Id
                            VersionNum     = $vv
                            VersionText    = [string]$it.Version
                            Name           = [string]$it.Name
                            Category       = $cc
                            Url            = [string]$it.Url
                            ReleaseDate    = [string]$it.DisplayReleaseDate
                            DetectionValues = $dv
                        })
                    }
                    $res.Catalog = @($cat.ToArray())
                }
            } finally { $zip.Dispose() }
        }
    } catch {}

    $res.Available = (($res.Devices.Count -gt 0) -or ($res.Catalog.Count -gt 0) -or ($res.History.Count -gt 0))
    $script:DrvDsa = $res
    $script:DrvDsaAt = Get-Date
    return $res
}

# 把设备匹配到 DSA 目录条目, 再结合安装历史判断真实状态
function Get-TxDsaForDevice($dev) {
    if (-not $dev) { return $null }
    $dsa = $script:DrvDsa
    if (-not $dsa -or -not $dsa.Available) { return $null }
    $hw = Get-TxHwBase ([string]$dev.HardwareId)
    if (-not $hw -or $hw -notmatch 'VEN_8086') { return $null }
    $venDev = ($hw -replace '^PCI\\', '')
    $bm = [regex]::Match($venDev, 'VEN_[0-9A-F]+&DEV_[0-9A-F]+')
    $base = $bm.Value
    if (-not $base) { return $null }

    $matched = New-Object System.Collections.ArrayList
    foreach ($c in @($dsa.Catalog)) {
        if (-not $c) { continue }
        $hit = $false
        foreach ($d in @($c.DetectionValues)) {
            $ds = [string]$d
            if (-not $ds) { continue }
            if ($ds -eq $venDev -or $ds -eq $base -or $venDev.StartsWith($ds)) { $hit = $true; break }
        }
        if ($hit) { [void]$matched.Add($c) }
    }
    if ($matched.Count -eq 0) { return $null }

    $latest = $null
    foreach ($c in $matched) {
        if (-not $c.VersionNum) { continue }
        if (-not $latest -or (Compare-TxVersion $c.VersionNum $latest.VersionNum) -gt 0) { $latest = $c }
    }
    if (-not $latest) { return $null }

    $comp = $null
    foreach ($d in @($dsa.Devices)) {
        if ([string]$d.Version -eq [string]$dev.Version) { $comp = $d; break }
    }
    if (-not $comp) {
        foreach ($d in @($dsa.Devices)) {
            if ([string]$d.Category -eq 'Graphics' -and [string]$dev.Class -eq 'DISPLAY') { $comp = $d; break }
        }
    }

    $histHit = $null
    $histDate = ''
    $histVersion = ''
    foreach ($h in @($dsa.History)) {
        if (-not $h) { continue }
        if ([string]$h.Status -ne 'Success') { continue }
        if ([int]$h.Id -ne [int]$latest.Id) { continue }
        $histHit = $h
        break
    }
    if ($histHit) {
        $histVersion = [regex]::Match([string]$histHit.Version, '\d+(?:\.\d+){2,3}').Value
        try { $histDate = ([datetime]$histHit.Timestamp).ToLocalTime().ToString('yyyy/M/d') } catch { $histDate = [string]$histHit.Timestamp }
    }

    $actual = [string]$dev.Version
    $latestVer = [string]$latest.VersionNum
    $offered = $false
    if (@($dsa.Offered).Count -gt 0 -and (@($dsa.Offered) -contains [int]$latest.Id)) { $offered = $true }

    $state = 'UpToDate'
    $note = ''
    $isNewer = ($latestVer -and $actual -and ((Compare-TxVersion $latestVer $actual) -gt 0))
    if ($isNewer) {
        if ($histVersion -and ((Compare-TxVersion $histVersion $actual) -gt 0)) {
            $state = 'RolledBack'
            $when = ''
            if ($histDate) { $when = "在 $histDate " }
            $note = "Intel 支持助手${when}已安装 $histVersion，但系统当前为 $actual，可能被 Windows 更新回退"
        } else {
            $state = 'UpdateAvailable'
            $note = "Intel 支持助手提供 $latestVer"
        }
    } else {
        $state = 'UpToDate'
        $statusText = '已是最新'
        if ($comp -and [string]$comp.UpdateStatus -eq 'UpdateAvailable') { $statusText = '有可用更新' }
        $note = "Intel 支持助手：$statusText"
        if ($histVersion) { $note += "（记录安装 $histVersion）" }
    }

    return [PSCustomObject]@{
        State          = $state
        Latest         = $latestVer
        LatestText     = [string]$latest.VersionText
        LatestName     = [string]$latest.Name
        UpdateId       = [int]$latest.Id
        Link           = [string]$latest.Url
        HistoryVersion = $histVersion
        HistoryDate    = $histDate
        Offered        = $offered
        DeviceStatus   = $(if ($comp) { [string]$comp.UpdateStatus } else { '' })
        Note           = $note
    }
}

# ── NVIDIA / AMD 官方工具检测 ─────────────────────────────
# 只读本机安装信息, 不联网。检测到官方工具才显示对应卡片;
# NVIDIA App / AMD Software 没有 DSA 那样的离线版本目录,
# 因此状态为 Managed(由官方工具管理), 不猜测"有新版本"。
function Get-TxUninstallEntries {
    $list = New-Object System.Collections.ArrayList
    foreach ($p in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        try {
            foreach ($e in @(Get-ItemProperty -Path $p -ErrorAction SilentlyContinue)) {
                if ($e -and $e.DisplayName) { [void]$list.Add($e) }
            }
        } catch {}
    }
    return @($list.ToArray())
}

function Get-TxToolVersion($entry, [string]$exe) {
    $v = ''
    if ($entry) { $v = [string]$entry.DisplayVersion }
    if (-not $v -and $exe -and (Test-Path -LiteralPath $exe)) {
        try { $v = [string](Get-Item -LiteralPath $exe).VersionInfo.FileVersion } catch { $v = '' }
    }
    if ($v -match '\d+(?:\.\d+){1,3}') { return $Matches[0] }
    return $v
}

function Get-TxToolExe($entry, $candidates, [string]$leaf) {
    foreach ($c in @($candidates)) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    if ($entry) {
        $loc = [string]$entry.InstallLocation
        if ($loc -and $leaf) {
            $p = Join-Path $loc $leaf
            if (Test-Path -LiteralPath $p) { return $p }
        }
    }
    return ''
}

function Get-TxNvidiaTool($entries) {
    $pf = [string]$env:ProgramFiles
    $pf86 = [string]${env:ProgramFiles(x86)}
    $app = @($entries | Where-Object { [string]$_.DisplayName -match '^NVIDIA\s+App' }) | Select-Object -First 1
    $cands = @()
    if ($pf) { $cands += (Join-Path $pf 'NVIDIA Corporation\NVIDIA App\NVIDIA App.exe') }
    if ($pf86) { $cands += (Join-Path $pf86 'NVIDIA Corporation\NVIDIA App\NVIDIA App.exe') }
    $exe = Get-TxToolExe $app $cands 'NVIDIA App.exe'
    if ($app -or $exe) {
        return [PSCustomObject]@{
            Tool      = 'NVIDIA App'
            Short     = 'NVIDIA'
            Badge     = 'NVIDIA'
            Version   = (Get-TxToolVersion $app $exe)
            AppPath   = $exe
            AppButton = '打开 NVIDIA App'
            Link      = 'https://www.nvidia.com/en-us/drivers/'
        }
    }
    # 旧版 GeForce Experience
    $gfe = @($entries | Where-Object { [string]$_.DisplayName -match 'NVIDIA GeForce Experience' }) | Select-Object -First 1
    $cands2 = @()
    if ($pf) { $cands2 += (Join-Path $pf 'NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe') }
    if ($pf86) { $cands2 += (Join-Path $pf86 'NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe') }
    $exe2 = Get-TxToolExe $gfe $cands2 'NVIDIA GeForce Experience.exe'
    if ($gfe -or $exe2) {
        return [PSCustomObject]@{
            Tool      = 'NVIDIA GeForce Experience'
            Short     = 'NVIDIA'
            Badge     = 'NVIDIA'
            Version   = (Get-TxToolVersion $gfe $exe2)
            AppPath   = $exe2
            AppButton = '打开 GeForce Experience'
            Link      = 'https://www.nvidia.com/en-us/drivers/'
        }
    }
    return $null
}

function Get-TxAmdTool($entries) {
    $amd = @($entries | Where-Object {
        [string]$_.DisplayName -match '^AMD Software' -or
        [string]$_.DisplayName -match '^AMD Radeon Software' -or
        [string]$_.DisplayName -match 'Adrenalin'
    }) | Select-Object -First 1
    $pf = [string]$env:ProgramFiles
    $cands = @()
    if ($pf) {
        $cands += (Join-Path $pf 'AMD\CNext\CNext\RadeonSoftware.exe')
        $cands += (Join-Path $pf 'AMD\AMD Software\RadeonSoftware.exe')
    }
    $exe = Get-TxToolExe $amd $cands 'RadeonSoftware.exe'
    if ($amd -or $exe) {
        return [PSCustomObject]@{
            Tool      = 'AMD Software: Adrenalin Edition'
            Short     = 'AMD'
            Badge     = 'AMD'
            Version   = (Get-TxToolVersion $amd $exe)
            AppPath   = $exe
            AppButton = '打开 AMD 软件'
            Link      = 'https://www.amd.com/zh-cn/support/download/drivers.html'
        }
    }
    return $null
}

function Get-TxVendorTools([switch]$Force) {
    if (-not $Force -and $null -ne $script:DrvTools -and ((Get-Date) - $script:DrvToolsAt).TotalSeconds -lt 120) { return $script:DrvTools }
    $res = [PSCustomObject]@{ Intel = $null; NVIDIA = $null; AMD = $null }
    $dsa = $null
    try { $dsa = Get-TxDsaData -Force:$Force } catch {}
    if ($dsa -and $dsa.Available) {
        $res.Intel = [PSCustomObject]@{
            Tool      = 'Intel 驱动支持助手'
            Short     = 'Intel'
            Badge     = 'DSA'
            Version   = ''
            AppPath   = ''
            AppButton = ''
            Link      = ''
        }
    }
    $entries = @()
    try { $entries = @(Get-TxUninstallEntries) } catch {}
    try { $res.NVIDIA = Get-TxNvidiaTool $entries } catch {}
    try { $res.AMD = Get-TxAmdTool $entries } catch {}
    $script:DrvTools = $res
    $script:DrvToolsAt = Get-Date
    return $res
}

# AMD Software 在注册表里记录的驱动版本, 用于发现"软件与驱动不匹配"
function Get-TxAmdCnDriverVersion {
    foreach ($p in @('HKLM:\SOFTWARE\AMD\CN', 'HKLM:\SOFTWARE\WOW6432Node\AMD\CN')) {
        try {
            $e = Get-ItemProperty -Path $p -ErrorAction Stop
            foreach ($n in @('DriverVersion', 'RadeonSoftwareVersion', 'CatalystVersion')) {
                $v = [string]$e.$n
                if ($v -match '\d+(?:\.\d+){2,3}') { return [PSCustomObject]@{ Name = $n; Version = $Matches[0] } }
            }
        } catch {}
    }
    return $null
}

# 只有同时检测到对应硬件和官方工具时才返回, 否则调用方不显示任何厂商卡片
function Get-TxVendorForDevice($dev) {
    if (-not $dev) { return $null }
    $hw = Get-TxHwBase ([string]$dev.HardwareId)
    if (-not $hw) { return $null }
    $vendor = ''
    if ($hw -match 'VEN_8086') { $vendor = 'Intel' }
    elseif ($hw -match 'VEN_10DE') { $vendor = 'NVIDIA' }
    elseif ($hw -match 'VEN_1002' -or $hw -match 'VEN_1022') { $vendor = 'AMD' }
    if (-not $vendor) { return $null }
    # NVIDIA / AMD 只对显示设备生效, 避免误挂到同厂商的音频等设备
    if ($vendor -ne 'Intel' -and [string]$dev.Class -ne 'DISPLAY') { return $null }

    $tools = Get-TxVendorTools
    if (-not $tools) { return $null }
    $tool = $tools.$vendor
    if (-not $tool) { return $null }

    if ($vendor -eq 'Intel') {
        $d = $null
        try { $d = Get-TxDsaForDevice $dev } catch { $d = $null }
        if (-not $d) { return $null }
        return [PSCustomObject]@{
            Vendor         = 'Intel'
            Tool           = 'Intel 驱动支持助手'
            Short          = 'Intel'
            Badge          = 'DSA'
            ToolVersion    = ''
            AppPath        = ''
            AppButton      = ''
            Link           = [string]$d.Link
            State          = [string]$d.State
            Latest         = [string]$d.Latest
            Note           = [string]$d.Note
            HistoryVersion = [string]$d.HistoryVersion
            HistoryDate    = [string]$d.HistoryDate
            Dsa            = $d
        }
    }

    $actual = [string]$dev.Version
    $state = 'Managed'
    $note = ''
    if ($vendor -eq 'AMD') {
        $cn = Get-TxAmdCnDriverVersion
        # 只有两边都是 Windows 驱动版本号(32.x)时才比较, 避免把不同编号体系误判为不一致
        if ($cn -and $actual -and $cn.Version -match '^32\.' -and $actual -match '^32\.' -and $cn.Version -ne $actual) {
            $state = 'Mismatch'
            $note = "AMD 软件记录的驱动版本为 $($cn.Version)，系统当前为 $actual，建议打开 AMD 软件重新安装匹配的驱动。"
        }
    }
    if (-not $note) {
        $verTxt = ''
        if ($tool.Version) { $verTxt = " $($tool.Version)" }
        $note = "已检测到 $($tool.Tool)$verTxt，驱动更新由它负责；本工具只读取本机记录，不联网判定。"
    }
    return [PSCustomObject]@{
        Vendor         = $vendor
        Tool           = [string]$tool.Tool
        Short          = [string]$tool.Short
        Badge          = [string]$tool.Badge
        ToolVersion    = [string]$tool.Version
        AppPath        = [string]$tool.AppPath
        AppButton      = [string]$tool.AppButton
        Link           = [string]$tool.Link
        State          = $state
        Latest         = ''
        Note           = $note
        HistoryVersion = ''
        HistoryDate    = ''
        Dsa            = $null
    }
}

function Complete-TxDriverDevice($dev, $pkgs) {
    if (-not $dev) { return $dev }
    $cls = [string]$dev.Class
    $curVer = [string]$dev.Version
    $hw = [string]$dev.HardwareId
    # 本机驱动仓库中与这块设备匹配的包
    $locals = New-Object System.Collections.ArrayList
    $base = Get-TxHwBase $hw
    foreach ($pk in @($pkgs)) {
        if (-not $pk) { continue }
        $pcls = [string]$pk.ClassName
        if ($pcls -ne $cls -and $pcls -ne 'Extension') { continue }
        $meta = Get-TxInfMeta ([string]$pk.PublishedName)
        if (-not $meta) { continue }
        $match = $false
        if ($base) {
            foreach ($ih in @($meta.HardwareIds)) {
                $ib = Get-TxHwBase ([string]$ih)
                if (-not $ib) { continue }
                if ($base -eq $ib -or $base.StartsWith($ib) -or $ib.StartsWith($base)) { $match = $true; break }
            }
        }
        if (-not $match) { continue }
        $ver = [string]$meta.Version
        if (-not $ver) { $ver = [string]$pk.Version }
        $dt = [string]$meta.Date
        if (-not $dt) { $dt = [string]$pk.Date }
        $inUse = (([string]$pk.PublishedName).ToLowerInvariant() -eq ([string]$dev.InfName).ToLowerInvariant())
        $cmp = 0
        if ($ver -and $curVer) { $cmp = Compare-TxVersion $ver $curVer }
        [void]$locals.Add([PSCustomObject]@{
            PublishedName = [string]$pk.PublishedName
            OriginalName  = [string]$pk.OriginalName
            ClassName     = $pcls
            Version       = $ver
            Date          = $dt
            Provider      = [string]$meta.Provider
            InUse         = $inUse
            Compare       = $cmp
        })
    }
    $dev.Packages = @($locals.ToArray() | Sort-Object @{ Expression = { if ($_.InUse) { 0 } else { 1 } } }, @{ Expression = { [string]$_.PublishedName } })

    $flags = New-Object System.Collections.ArrayList
    if (-not $dev.StatusOk) { [void]$flags.Add('设备状态异常') }
    $old = @($dev.Packages | Where-Object { $_.Compare -lt 0 -and -not $_.InUse })
    if ($old.Count -gt 0) { [void]$flags.Add("仓库中有 $($old.Count) 个旧版本包") }
    $extDiff = @($dev.Packages | Where-Object { $_.ClassName -eq 'Extension' -and $_.Version -and $curVer -and (Compare-TxVersion $_.Version $curVer) -ne 0 })
    if ($extDiff.Count -gt 0) { [void]$flags.Add('扩展包版本与主驱动不一致') }

    # 官方工具: Intel DSA / NVIDIA App / AMD Software
    # 只有同时检测到硬件和对应工具时才附加; 否则保持 Windows Update 原逻辑
    $ven = $null
    try { $ven = Get-TxVendorForDevice $dev } catch { $ven = $null }
    $dev.Vendor = $ven
    $dev.VendorState = ''
    $dev.VendorNote = ''
    $venCount = 0
    if ($ven) {
        $dev.VendorState = [string]$ven.State
        $dev.VendorNote = [string]$ven.Note
        if ($ven.State -eq 'RolledBack' -or $ven.State -eq 'Mismatch') {
            [void]$flags.Add([string]$ven.Note)
            $venCount = 1
        } elseif ($ven.State -eq 'UpdateAvailable') {
            [void]$flags.Add("$($ven.Tool)提供 $($ven.Latest)")
            $venCount = 1
        }
    }

    $ups = @(Get-TxUpdatesForDevice $dev)
    $dev.Updates = @($ups)
    $wuCount = @($ups | Where-Object { -not $_.Hidden -and $_.Version -and ((Compare-TxVersion $_.Version $curVer) -gt 0) }).Count
    # 检测到官方工具时, 该设备的可用更新以工具为准, 不再叠加 Windows Update 的旧包
    if ($ven) { $wuCount = 0 }
    $dev.UpdateCount = $wuCount + $venCount
    if ($dev.UpdateCount -gt 0) { [void]$flags.Add("有 $($dev.UpdateCount) 个可用更新") }
    $dev.HasUpdate = ($dev.UpdateCount -gt 0)
    $dev.OldCount = $old.Count
    $dev.Flags = @($flags.ToArray())
    $dev.Enriched = $true
    return $dev
}

function Get-TxDriverSnapshot([switch]$Force) {
    if (-not $Force -and $script:DrvData -and ((Get-Date) - $script:DrvAt).TotalSeconds -lt 30) { return $script:DrvData }
    $devs = @(Get-TxDriverDevices -Force:$Force)
    $pkgs = @(Get-TxDriverPackages -Force:$Force)
    $null = Get-TxVendorTools -Force:$Force
    foreach ($dev in $devs) { $null = Complete-TxDriverDevice $dev $pkgs }
    $script:DrvData = [PSCustomObject]@{
        Devices   = $devs
        ScannedAt = (Get-Date)
        WuChecked = ($null -ne $script:DrvWu)
    }
    $script:DrvAt = Get-Date
    return $script:DrvData
}

# 已有设备列表时重新核对驱动包/更新 (不重新枚举设备), 用于检测更新之后
function Update-TxDriverEnrichment([switch]$ForcePackages) {
    if (-not $script:DrvData) { return }
    $pkgs = @(Get-TxDriverPackages -Force:$ForcePackages)
    foreach ($dev in @($script:DrvData.Devices)) { $null = Complete-TxDriverDevice $dev $pkgs }
    $script:DrvData.WuChecked = ($null -ne $script:DrvWu)
    $script:DrvAt = Get-Date
}

# ── 驱动中心页面 ─────────────────────────────────────────
$drvPage = New-Page 'driver'
$script:UI.DriverPage = $drvPage
$drvPage.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, 640)

$drvHero = New-Card $drvPage 20 16 ($cw - 40) 126 16 $script:C_PANEL $script:C_BORDER
$drvHero.Anchor = 'Top, Left, Right'
$script:UI.DrvHero = $drvHero
$drvHero.Add_Paint({
    param($s, $e)
    try {
        $sc = [double]$script:UI_SCALE
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $r = New-Object Drawing.Rectangle -ArgumentList @(0, 0, ($s.Width - 1), ($s.Height - 1))
        $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @($r, (TC 12 34 50), (TC 30 22 60), [single](20 * $sc))
        $g.FillRectangle($lg, $r)
        $lg.Dispose()
        $ar = New-Object Drawing.Rectangle -ArgumentList @(0, 1, $s.Width, [int](3 * $sc))
        $ag = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @($ar, $script:C_CYAN, $script:C_PURPLE, [single]0)
        $g.FillRectangle($ag, $ar)
        $ag.Dispose()
        $glow = New-Object Drawing.SolidBrush -ArgumentList @((TC 18 0 229 255))
        $g.FillEllipse($glow, ($s.Width - 240 * $sc), (-100 * $sc), (260 * $sc), (260 * $sc))
        $glow.Dispose()
        $b1 = New-Object Drawing.SolidBrush -ArgumentList @($script:C_CYAN)
        $g.DrawString('DRIVER CONTROL CENTER · LOCAL FIRST', $script:DrvHF.Tag, $b1, (24 * $sc), (12 * $sc))
        $b1.Dispose()
        $b2 = New-Object Drawing.SolidBrush -ArgumentList @($script:C_TEXT)
        $g.DrawString('驱动中心', $script:DrvHF.Title, $b2, (22 * $sc), (28 * $sc))
        $b2.Dispose()
        $b3 = New-Object Drawing.SolidBrush -ArgumentList @((TC 168 199 216))
        $g.DrawString('扫描本机驱动 · 核对版本 · Intel / NVIDIA / AMD 更新以本机官方工具为准', $script:DrvHF.Sub, $b3, (24 * $sc), (60 * $sc))
        $b3.Dispose()
    } catch {}
})
$btnDrvScan = New-Btn $drvHero '扫描本机驱动' 24 84 120 32 $script:C_CYAN ((TC 4 20 26)) 9
$btnDrvWu = New-Btn $drvHero '检测更新' 152 84 104 32 $heroBtnBg2 ((TC 214 204 255)) 9
$btnDrvDevMgr = New-Btn $drvHero '设备管理器' 264 84 104 32 $heroBtnBg2 $script:C_SUB 9
$btnDrvHistory = New-Btn $drvHero '变化记录' 376 84 104 32 $heroBtnBg2 $script:C_SUB 9
$btnDrvScan.Add_Click({ Refresh-DriverPage $true })
$btnDrvWu.Add_Click({ Invoke-DriverUpdateCheck })
$btnDrvDevMgr.Add_Click({ try { Start-Process 'devmgmt.msc' } catch {} })
$btnDrvHistory.Add_Click({ Show-DriverHistory })

$drvStatX = ($cw - 40) - 300
$script:UI.DrvStatDev = New-Label $drvHero '0' $drvStatX 28 72 30 19 $true $script:C_TEXT 'MiddleRight'
$script:UI.DrvStatUpd = New-Label $drvHero '0' ($drvStatX + 100) 28 72 30 19 $true $script:C_ORANGE 'MiddleRight'
$script:UI.DrvStatIssue = New-Label $drvHero '0' ($drvStatX + 200) 28 72 30 19 $true $script:C_RED 'MiddleRight'
foreach ($lbl in @($script:UI.DrvStatDev, $script:UI.DrvStatUpd, $script:UI.DrvStatIssue)) { $lbl.Anchor = 'Top, Right' }
$lblCapDev = New-Label $drvHero '设备' $drvStatX 60 72 18 8 $false $script:C_SUB 'MiddleRight'
$lblCapUpd = New-Label $drvHero '可更新' ($drvStatX + 100) 60 72 18 8 $false $script:C_SUB 'MiddleRight'
$lblCapIssue = New-Label $drvHero '需处理' ($drvStatX + 200) 60 72 18 8 $false $script:C_SUB 'MiddleRight'
foreach ($lbl in @($lblCapDev, $lblCapUpd, $lblCapIssue)) { $lbl.Anchor = 'Top, Right' }

$drvFilterCard = New-Card $drvPage 20 150 ($cw - 40) 44 12 $script:C_PANEL $script:C_BORDER
$drvFilterCard.Anchor = 'Top, Left, Right'
$null = New-Label $drvFilterCard '筛选' 16 10 40 24 8 $true $script:C_DIM
$script:UI.DrvFilterBtns = @{}
$fx = 52
foreach ($f in @('全部', '显卡', '音频', '外设', '网络')) {
    $b = New-Btn $drvFilterCard $f $fx 7 76 30 ((TC 22 30 44)) $script:C_SUB 8 $false
    $b.Tag = $f
    $b.Add_Click({
        param($s, $e)
        $script:DrvFilter = [string]$s.Tag
        Update-DriverFilterButtons
        Update-DriverCards
    })
    $script:UI.DrvFilterBtns[$f] = $b
    $fx += 82
}
$script:DrvSearch = New-TextBox $drvFilterCard (($cw - 40) - 16 - 240) 7 240 30 '搜索设备、厂商或版本...'
$script:DrvSearch.Anchor = 'Top, Right'
$script:DrvSearchTimer = New-Object System.Windows.Forms.Timer
$script:DrvSearchTimer.Interval = 180
$script:DrvSearchTimer.Add_Tick({
    param($s, $e)
    $s.Stop()
    Update-DriverCards
})
$script:DrvSearch.Add_TextChanged({
    param($s, $e)
    $q = ''
    if ($s.Tag -and $s.Tag.Active) { $q = ([string]$s.Text).Trim() }
    if ($q -eq $script:DrvQuery) { return }
    $script:DrvQuery = $q
    try { $script:DrvSearchTimer.Stop(); $script:DrvSearchTimer.Start() } catch { Update-DriverCards }
})

$pageH = $fh - 60 - 26
$drvFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$drvFlow.Location = New-Object Drawing.Point -ArgumentList @(20, 204)
$drvFlow.Size = New-Object Drawing.Size -ArgumentList @(($cw - 40), [Math]::Max(260, ($pageH - 204 - 16)))
$drvFlow.Anchor = 'Top, Bottom, Left, Right'
$drvFlow.AutoScroll = $true
$drvFlow.WrapContents = $true
$drvFlow.FlowDirection = 'LeftToRight'
$drvFlow.BackColor = $script:C_BG
$drvFlow.Margin = New-Object System.Windows.Forms.Padding -ArgumentList @(0)
$drvFlow.Padding = New-Object System.Windows.Forms.Padding -ArgumentList @(0)
$drvPage.Controls.Add($drvFlow)
$script:UI.DrvFlow = $drvFlow

# 卡片宽度按可用空间自适应, 避免右侧空出一整列
function Get-DriverCardWidth {
    $flow = $script:UI.DrvFlow
    $avail = $cw - 40
    # 用面板外宽而不是 ClientSize: 竖滚动条出现/消失不会改变外宽,
    # 避免"重建卡片 -> 滚动条切换 -> 再次重建"的循环
    if ($flow) { $avail = [int]$flow.Width }
    $gap = UiPx 12
    $minW = UiPx 300
    $avail = $avail - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
    if ($avail -lt $minW) { $avail = $minW }
    $cols = [Math]::Max(1, [Math]::Floor(($avail + $gap) / ($minW + $gap)))
    # 每张卡都带 12px 右边距, 计算时把最后一列的间距也算进去, 避免横向滚动条
    $w = [Math]::Floor($avail / $cols) - $gap - 2
    if ($w -lt $minW) { $w = $minW }
    return [int]$w
}

$script:DrvResizeTimer = New-Object System.Windows.Forms.Timer
$script:DrvResizeTimer.Interval = 180
$script:DrvResizeTimer.Add_Tick({
    param($s, $e)
    $s.Stop()
    if ($script:DrvBusy) { return }
    $w = Get-DriverCardWidth
    if ([Math]::Abs($w - $script:DrvCardW) -ge 4) {
        $script:DrvCardW = $w
        Update-DriverCards
    }
})
$drvFlow.Add_Resize({
    param($s, $e)
    try { $script:DrvResizeTimer.Stop(); $script:DrvResizeTimer.Start() } catch {}
})

function Get-DriverCardInfo($dev) {
    if (-not $dev.Enriched) { return @{ Text = '正在核对本地驱动包...'; Color = $script:C_DIM } }
    $info = '已是最新'
    $color = $script:C_SUB
    $vs = [string]$dev.VendorState
    if ($vs -eq 'RolledBack') { $info = "$($dev.Vendor.Short) 驱动被回退"; $color = $script:C_RED }
    elseif ($vs -eq 'Mismatch') { $info = "$($dev.Vendor.Short) 驱动与软件版本不匹配"; $color = $script:C_RED }
    elseif ($vs -eq 'UpdateAvailable') { $info = "$($dev.Vendor.Tool) 可更新到 $($dev.Vendor.Latest)"; $color = $script:C_ORANGE }
    elseif ($vs -eq 'Managed') { $info = "由 $($dev.Vendor.Tool) 管理"; $color = $script:C_SUB }
    elseif ($dev.UpdateCount -gt 0) { $info = "发现 $($dev.UpdateCount) 个可用更新"; $color = $script:C_ORANGE }
    elseif ($dev.OldCount -gt 0) { $info = "本地有 $($dev.OldCount) 个旧版本包"; $color = $script:C_ORANGE }
    elseif (-not $dev.StatusOk) { $info = '设备状态异常'; $color = $script:C_RED }
    return @{ Text = $info; Color = $color }
}

function New-DriverCard($dev) {
    $w = [int]$script:DrvCardW
    if ($w -lt (UiPx 280)) { $w = UiPx 300 }
    $h = UiPx 156
    $card = New-Card $script:UI.DrvFlow 0 0 $w $h 14 $script:C_PANEL $script:C_BORDER
    $card.Margin = New-Object System.Windows.Forms.Padding -ArgumentList @(0, 0, (UiPx 12), (UiPx 12))
    $card.Tag = @{ Accent = $dev.Accent; Data = $dev; Labels = @{} }
    $null = New-Badge $card $dev.Category (UiPx 14) (UiPx 12) (UiPx 52) (UiPx 22) $script:C_GRAY_BG $script:C_GRAY_BD $script:C_SUB 8
    $stFill = $script:C_GREEN_BG
    $stBd = $script:C_GREEN_BD
    $stFg = $script:C_GREEN
    if (-not $dev.StatusOk) { $stFill = $script:C_ORANGE_BG; $stBd = $script:C_ORANGE_BD; $stFg = $script:C_ORANGE }
    $null = New-Badge $card $dev.StatusText ($w - (UiPx 88)) (UiPx 12) (UiPx 74) (UiPx 22) $stFill $stBd $stFg 8
    $nm = New-Label $card ([string]$dev.Name) (UiPx 14) (UiPx 38) ($w - (UiPx 28)) (UiPx 24) 10 $true $script:C_TEXT
    $nm.AutoEllipsis = $true
    $verText = [string]$dev.Version
    if (-not $verText) { $verText = '未知' }
    $lblVer = New-Label $card ("当前 " + $verText) (UiPx 14) (UiPx 68) ($w - (UiPx 28)) (UiPx 20) 9.5 $false $script:C_TEXT
    $prov = [string]$dev.Provider
    if (-not $prov) { $prov = '未知厂商' }
    if ($prov.Length -gt 32) { $prov = $prov.Substring(0, 32) + '…' }
    $dateText = [string]$dev.Date
    if (-not $dateText) { $dateText = '--' }
    $lblMeta = New-Label $card ("$prov · $dateText") (UiPx 14) (UiPx 90) ($w - (UiPx 28)) (UiPx 18) 8 $false $script:C_SUB
    $st = Get-DriverCardInfo $dev
    $lblInfo = New-Label $card $st.Text (UiPx 14) (UiPx 112) ($w - (UiPx 96)) (UiPx 20) 8.5 $false $st.Color
    $lblInfo.AutoEllipsis = $true
    $btn = New-Btn $card '管理' ($w - (UiPx 76)) ($h - (UiPx 36)) (UiPx 62) (UiPx 26) $script:C_PANEL2 $script:C_TEXT 8 $false
    $btn.Tag = $dev
    $btn.Add_Click({ param($s, $e) Show-DriverDetails $s.Tag })
    $card.Tag.Labels = @{ Version = $lblVer; Meta = $lblMeta; Info = $lblInfo; Btn = $btn }

    # 整卡可点: 悬停高亮, 左键打开详情 (按钮除外)
    $enter = {
        param($s, $e)
        $c = $s
        if (-not ($c -is [TxUi.Card])) { $c = $c.Parent }
        try { Set-HwCardHover $c $true } catch {}
    }
    $leave = {
        param($s, $e)
        $c = $s
        if (-not ($c -is [TxUi.Card])) { $c = $c.Parent }
        if (-not $c) { return }
        $pt = $c.PointToClient([System.Windows.Forms.Cursor]::Position)
        if (-not $c.ClientRectangle.Contains($pt)) { try { Set-HwCardHover $c $false } catch {} }
    }
    $open = {
        param($s, $e)
        if (-not $e -or $e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        $c = $s
        if (-not ($c -is [TxUi.Card])) { $c = $c.Parent }
        if ($c -and $c.Tag -and $c.Tag.Data) { Show-DriverDetails $c.Tag.Data }
    }
    try { $card.Cursor = [System.Windows.Forms.Cursors]::Hand } catch {}
    $card.Add_MouseEnter($enter)
    $card.Add_MouseLeave($leave)
    $card.Add_MouseUp($open)
    foreach ($c in @($card.Controls)) {
        if ($c -is [System.Windows.Forms.Button]) { continue }
        try {
            $c.Cursor = [System.Windows.Forms.Cursors]::Hand
            $c.Add_MouseEnter($enter)
            $c.Add_MouseLeave($leave)
            $c.Add_MouseUp($open)
        } catch {}
    }
    try { $script:DrvCards[[string]$dev.DeviceId] = $card } catch {}
    return $card
}

# 单个设备补全后, 就地更新卡片, 不重建整个列表
function Update-DriverCardData($dev) {
    if (-not $dev) { return }
    $card = $null
    try { if ($script:DrvCards) { $card = $script:DrvCards[[string]$dev.DeviceId] } } catch {}
    if (-not $card) { return }
    try {
        $ui = $card.Tag.Labels
        if (-not $ui) { return }
        $verText = [string]$dev.Version
        if (-not $verText) { $verText = '未知' }
        if ($ui.Version) { $ui.Version.Text = '当前 ' + $verText }
        $prov = [string]$dev.Provider
        if (-not $prov) { $prov = '未知厂商' }
        if ($prov.Length -gt 32) { $prov = $prov.Substring(0, 32) + '…' }
        $dateText = [string]$dev.Date
        if (-not $dateText) { $dateText = '--' }
        if ($ui.Meta) { $ui.Meta.Text = "$prov · $dateText" }
        $st = Get-DriverCardInfo $dev
        if ($ui.Info) { $ui.Info.Text = $st.Text; $ui.Info.ForeColor = $st.Color }
        if ($ui.Btn) { $ui.Btn.Tag = $dev }
        $card.Tag.Data = $dev
        $card.Invalidate()
    } catch {}
}

function Update-DriverFilterButtons {
    $counts = @{}
    $total = 0
    if ($script:DrvData) {
        foreach ($d in @($script:DrvData.Devices)) {
            $total++
            $cat = [string]$d.Category
            if (-not $counts.ContainsKey($cat)) { $counts[$cat] = 0 }
            $counts[$cat] = [int]$counts[$cat] + 1
        }
    }
    foreach ($k in @($script:UI.DrvFilterBtns.Keys)) {
        $b = $script:UI.DrvFilterBtns[$k]
        $n = 0
        if ($k -eq '全部') { $n = $total }
        elseif ($counts.ContainsKey($k)) { $n = [int]$counts[$k] }
        $b.Text = "$k $n"
        if ($k -eq $script:DrvFilter) {
            $b.BackColor = (TC 22 48 62)
            $b.ForeColor = $script:C_CYAN
        } else {
            $b.BackColor = (TC 22 30 44)
            $b.ForeColor = $script:C_SUB
        }
    }
}

function Update-DriverSummary {
    $devs = @()
    if ($script:DrvData) { $devs = @($script:DrvData.Devices) }
    $upd = 0
    $issue = 0
    foreach ($d in $devs) {
        if ($d.UpdateCount -gt 0) { $upd++ }
        if (-not $d.StatusOk -or $d.OldCount -gt 0 -or [string]$d.VendorState -eq 'RolledBack' -or [string]$d.VendorState -eq 'Mismatch') { $issue++ }
    }
    try { $script:UI.DrvStatDev.Text = [string]$devs.Count } catch {}
    try { $script:UI.DrvStatUpd.Text = [string]$upd } catch {}
    try { $script:UI.DrvStatIssue.Text = [string]$issue } catch {}
}

function Update-DriverCards {
    $flow = $script:UI.DrvFlow
    if (-not $flow) { return }
    $old = @($flow.Controls)
    $script:DrvCards = @{}
    $flow.Controls.Clear()
    foreach ($c in $old) { try { $c.Dispose() } catch {} }
    $script:DrvCardW = Get-DriverCardWidth
    $items = @()
    if ($script:DrvData) { $items = @($script:DrvData.Devices) }
    if ($script:DrvFilter -ne '全部') { $items = @($items | Where-Object { $_.Category -eq $script:DrvFilter }) }
    $q = [string]$script:DrvQuery
    if ($q) {
        $ql = $q.ToLowerInvariant()
        $items = @($items | Where-Object {
            ([string]$_.Name).ToLowerInvariant().Contains($ql) -or
            ([string]$_.Provider).ToLowerInvariant().Contains($ql) -or
            ([string]$_.Version).ToLowerInvariant().Contains($ql) -or
            ([string]$_.Category).ToLowerInvariant().Contains($ql) -or
            ([string]$_.HardwareId).ToLowerInvariant().Contains($ql) -or
            ([string]$_.InfName).ToLowerInvariant().Contains($ql)
        })
    }
    if ($items.Count -eq 0) {
        $boxW = [Math]::Min((UiPx 440), [Math]::Max((UiPx 320), ($script:DrvCardW * 2)))
        $box = New-Card $flow 0 0 $boxW (UiPx 104) 14 $script:C_PANEL $script:C_BORDER
        $box.Margin = New-Object System.Windows.Forms.Padding -ArgumentList @(0, 0, (UiPx 12), (UiPx 12))
        $null = New-Label $box '没有找到匹配的设备' (UiPx 18) (UiPx 14) ($boxW - (UiPx 36)) (UiPx 24) 10 $true $script:C_TEXT
        $null = New-Label $box '试试清空搜索词、切换分类，或重新扫描本机驱动。' (UiPx 18) (UiPx 42) ($boxW - (UiPx 36)) (UiPx 20) 8.5 $false $script:C_SUB
        $b = New-Btn $box '重新扫描' (UiPx 18) (UiPx 66) (UiPx 92) (UiPx 28) ((TC 22 48 62)) $script:C_CYAN 8.5
        $b.Add_Click({ Refresh-DriverPage $true })
        $flow.PerformLayout()
        return
    }
    foreach ($d in $items) { $null = New-DriverCard $d }
    $flow.PerformLayout()
}

function Show-DriverPlaceholder([string]$text) {
    $flow = $script:UI.DrvFlow
    if (-not $flow) { return }
    $old = @($flow.Controls)
    $flow.Controls.Clear()
    foreach ($c in $old) { try { $c.Dispose() } catch {} }
    $lbl = New-Label $flow $text 0 0 (UiPx 520) (UiPx 40) 9.5 $false $script:C_SUB
    $lbl.Margin = New-Object System.Windows.Forms.Padding -ArgumentList @((UiPx 8), (UiPx 12), 0, 0)
    $flow.PerformLayout()
}

# 逐个设备补全驱动包信息: 每个 tick 处理一个, 期间界面保持可交互
$script:DrvEnrichTimer = New-Object System.Windows.Forms.Timer
$script:DrvEnrichTimer.Interval = 12
$script:DrvEnrichTimer.Add_Tick({
    param($s, $e)
    $s.Stop()
    try {
        $q = $script:DrvEnrichQueue
        if (-not $q) { return }
        if ($q.Count -eq 0) { Finish-DriverEnrich; return }
        $dev = $q.Dequeue()
        try { $null = Complete-TxDriverDevice $dev $script:DrvPkgs } catch {}
        $script:DrvEnrichDone++
        Update-DriverCardData $dev
        if (($script:DrvEnrichDone % 3) -eq 0 -or $q.Count -eq 0) {
            Update-DriverFilterButtons
            Update-DriverSummary
            Set-Status "正在核对驱动包 $($script:DrvEnrichDone)/$($script:DrvEnrichTotal)..."
        }
        if ($q.Count -eq 0) { Finish-DriverEnrich; return }
        $s.Start()
    } catch {
        Finish-DriverEnrich
    }
})

function Start-DriverEnrich {
    if (-not $script:DrvData) { return }
    $q = New-Object System.Collections.Queue
    foreach ($d in @($script:DrvData.Devices)) { if (-not $d.Enriched) { $q.Enqueue($d) } }
    $script:DrvEnrichQueue = $q
    $script:DrvEnrichTotal = $q.Count
    $script:DrvEnrichDone = 0
    if ($q.Count -eq 0) { Finish-DriverEnrich; return }
    try { $script:DrvEnrichTimer.Stop(); $script:DrvEnrichTimer.Start() } catch {}
}

function Finish-DriverEnrich {
    try { $script:DrvEnrichTimer.Stop() } catch {}
    $script:DrvEnrichQueue = $null
    try { Update-DriverFilterButtons } catch {}
    try { Update-DriverSummary } catch {}
    $script:DrvAt = Get-Date
    $cnt = 0
    if ($script:DrvData) { $cnt = @($script:DrvData.Devices).Count }
    Set-Status "驱动信息已补全 · $cnt 个设备"
}

function Show-DriverHistory {
    try {
        $h = Read-TxDriverHistory
        $rows = @($h.LastChanges | Sort-Object At -Descending | Select-Object -First 20)
        if (-not $rows.Count) {
            [System.Windows.Forms.MessageBox]::Show($form, "还没有驱动版本变化记录。`n`n每次扫描驱动中心时会与上次结果比对；版本升级、回退或重新绑定都会记录在此。", '驱动变化记录', 'OK', 'Information') | Out-Null
            return
        }
        $lines = @("最近 $($rows.Count) 条驱动版本变化：", '')
        foreach ($c in $rows) {
            $kind = '变化'
            if ([string]$c.Type -eq 'RolledBack') { $kind = '回退' }
            elseif ([string]$c.Type -eq 'Updated') { $kind = '升级' }
            elseif ([string]$c.Type -eq 'Rebound') { $kind = '重新绑定' }
            $t = [string]$c.At
            try { $t = ([datetime]$t).ToString('MM-dd HH:mm') } catch {}
            $lines += "[$t] $kind · $($c.Name)"
            $lines += "    $($c.From) → $($c.To)"
        }
        [System.Windows.Forms.MessageBox]::Show($form, ($lines -join "`n"), '驱动变化记录', 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "读取记录失败:`n$($_.Exception.Message)", '驱动变化记录', 'OK', 'Warning') | Out-Null
    }
}

function Refresh-DriverPage([bool]$force = $false) {
    if ($script:DrvBusy) { return }
    $script:DrvBusy = $true
    try {
        Set-Status '正在枚举本机设备...'
        $btnDrvScan.Enabled = $false
        $btnDrvWu.Enabled = $false
        $btnDrvScan.Text = '扫描中...'
        Show-DriverPlaceholder '正在枚举本机设备（约 1~2 秒）...'
        [System.Windows.Forms.Application]::DoEvents()

        # 第一段: 只枚举设备和当前驱动, 先把卡片显示出来
        $devs = @(Get-TxDriverDevices -Force:$force)
        try {
            $hr = Update-TxDriverHistory $devs
            $chg = @($hr.Changes)
            if ($chg.Count -gt 0) {
                $parts = @()
                foreach ($c in @($chg | Select-Object -First 3)) {
                    $kind = '变化'
                    if ([string]$c.Type -eq 'RolledBack') { $kind = '回退' }
                    elseif ([string]$c.Type -eq 'Updated') { $kind = '升级' }
                    elseif ([string]$c.Type -eq 'Rebound') { $kind = '重新绑定' }
                    $parts += "$($c.Name): $($c.From) → $($c.To)（$kind）"
                }
                $txt = ($parts -join '；')
                if ($chg.Count -gt 3) { $txt += "；另有 $($chg.Count - 3) 项" }
                $kindTip = 'Info'
                if (@($chg | Where-Object { [string]$_.Type -eq 'RolledBack' }).Count -gt 0) { $kindTip = 'Warning' }
                if ([bool]$script:GuiCfg.NotifyDriver) { Show-TrayBalloon '驱动版本发生变化' $txt $kindTip }
                Set-Status "驱动变化: $txt"
            }
        } catch {}
        $script:DrvPkgs = @(Get-TxDriverPackages -Force:$force)
        $null = Get-TxVendorTools -Force:$force
        $script:DrvData = [PSCustomObject]@{
            Devices   = $devs
            ScannedAt = (Get-Date)
            WuChecked = ($null -ne $script:DrvWu)
        }
        foreach ($d in $devs) { $d.Enriched = $false }
        Update-DriverFilterButtons
        Update-DriverSummary
        Update-DriverCards
        try { [TxUi.Native]::DarkScroll($script:UI.DrvFlow.Handle) } catch {}
        $script:UI.DriverDirty = $false
        Set-Status "已发现 $($devs.Count) 个设备 · 正在逐个核对驱动包..."

        # 第二段: 每个设备单独补全, 补完一个更新一张卡
        Start-DriverEnrich
    } catch {
        Set-Status "驱动扫描失败: $($_.Exception.Message)"
    } finally {
        try { $btnDrvScan.Text = '扫描本机驱动' } catch {}
        try { $btnDrvScan.Enabled = $true } catch {}
        try { $btnDrvWu.Enabled = $true } catch {}
        $script:DrvBusy = $false
    }
}

# 详情页操作后只刷新受影响的那一块设备, 不重扫整页
function Refresh-DriverDevice([string]$devId, [bool]$reEnum) {
    if (-not $devId -or -not $script:DrvData) { Refresh-DriverPage $true; return }
    $dev = @($script:DrvData.Devices | Where-Object { [string]$_.DeviceId -eq $devId }) | Select-Object -First 1
    if (-not $dev) { Refresh-DriverPage $true; return }
    try {
        Set-Status "正在刷新设备: $($dev.Name)..."
        [System.Windows.Forms.Application]::DoEvents()
        if ($reEnum) {
            $fresh = @(Get-TxDriverDevices -Force | Where-Object { [string]$_.DeviceId -eq $devId }) | Select-Object -First 1
            if (-not $fresh) { Refresh-DriverPage $true; return }
            foreach ($p in @('Name', 'Class', 'Category', 'HardwareId', 'InfName', 'Version', 'Date', 'Provider', 'StatusText', 'StatusOk', 'Accent')) {
                $dev.$p = $fresh.$p
            }
        }
        $pkgs = @(Get-TxDriverPackages -Force)
        $null = Complete-TxDriverDevice $dev $pkgs
        $carded = $false
        try { $carded = $script:DrvCards.ContainsKey([string]$dev.DeviceId) } catch {}
        if ($carded) { Update-DriverCardData $dev } else { Update-DriverCards }
        Update-DriverFilterButtons
        Update-DriverSummary
        $script:DrvAt = Get-Date
        Set-Status "已刷新 · $($dev.Name)"
    } catch {
        Set-Status "刷新设备失败: $($_.Exception.Message)"
    }
}

function Invoke-DriverUpdateCheck {
    try {
        Set-Status '正在连接 Windows Update 检测驱动更新...'
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()
        $null = Get-TxWuDriverUpdates -Force
        $null = Get-TxVendorTools -Force
        # 只重新核对驱动包和更新, 不再重新枚举设备
        Update-TxDriverEnrichment
        Update-DriverFilterButtons
        Update-DriverSummary
        Update-DriverCards
        $n = 0
        foreach ($d in @($script:DrvData.Devices)) { $n += [int]$d.UpdateCount }
        Set-Status "更新检测完成 · 发现 $n 个可更新设备（Intel / NVIDIA / AMD 以本机官方工具为准）"
    } catch {
        Set-Status "更新检测失败: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($script:UI.Form, ("无法完成驱动更新检测。`n`n" + $_.Exception.Message), '驱动更新', 'OK', 'Warning') | Out-Null
    } finally {
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
    }
}

function Invoke-DriverWuInstall($owner, $update) {
    $result = @{ Ok = $false; Error = ''; Reboot = $false }
    $tmpDir = Join-Path $env:TEMP ('tx-driver-wu-' + [guid]::NewGuid().ToString('N'))
    try {
        $null = New-Item -ItemType Directory -Path $tmpDir -Force
        $scriptPath = Join-Path $tmpDir 'install-driver.ps1'
        $outFile = Join-Path $tmpDir 'result.json'
        $child = @'
param([string]$UpdateId, [string]$OutFile)
$ErrorActionPreference = 'Stop'
$res = [ordered]@{ Ok = $false; Error = ''; ResultCode = -1; Reboot = $false }
try {
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $found = $searcher.Search("IsInstalled=0 and Type='Driver'")
    $u = @($found.Updates | Where-Object { [string]$_.Identity.UpdateID -eq $UpdateId }) | Select-Object -First 1
    if (-not $u) { throw '更新条目已不存在，请重新检测' }
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    [void]$coll.Add($u)
    try { if (-not $u.EulaAccepted) { $u.AcceptEula() } } catch {}
    $dl = $session.CreateUpdateDownloader()
    $dl.Updates = $coll
    $dr = $dl.Download()
    if ([int]$dr.ResultCode -ne 2) { throw ('下载失败，代码 ' + $dr.ResultCode) }
    $inst = $session.CreateUpdateInstaller()
    $inst.Updates = $coll
    $ir = $inst.Install()
    $res.Ok = ([int]$ir.ResultCode -eq 2)
    $res.ResultCode = [int]$ir.ResultCode
    $res.Reboot = [bool]$ir.RebootRequired
    if (-not $res.Ok) { $res.Error = ('安装返回代码 ' + $ir.ResultCode) }
} catch {
    $res.Error = $_.Exception.Message
}
($res | ConvertTo-Json -Compress) | Out-File -LiteralPath $OutFile -Encoding UTF8
'@
        $child | Out-File -LiteralPath $scriptPath -Encoding UTF8
        $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '" -UpdateId "' + [string]$update.Id + '" -OutFile "' + $outFile + '"'
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -WindowStyle Hidden -PassThru
        $pdlg = New-Object System.Windows.Forms.Form
        $pdlg.Text = '正在安装驱动更新'
        $pdlg.FormBorderStyle = 'FixedDialog'
        $pdlg.MaximizeBox = $false
        $pdlg.MinimizeBox = $false
        $pdlg.ShowIcon = $false
        $pdlg.ShowInTaskbar = $false
        $pdlg.StartPosition = 'CenterParent'
        $pdlg.ClientSize = New-Object Drawing.Size -ArgumentList @((UiPx 480), (UiPx 180))
        $pdlg.BackColor = $script:C_BG
        $pdlg.ForeColor = $script:C_TEXT
        $pdlg.ControlBox = $false
        $null = New-Label $pdlg '正在下载并安装驱动更新' (UiPx 24) (UiPx 20) (UiPx 432) (UiPx 26) 11 $true $script:C_TEXT
        $t = [string]$update.Title
        if ($t.Length -gt 60) { $t = $t.Substring(0, 60) + '…' }
        $null = New-Label $pdlg $t (UiPx 24) (UiPx 50) (UiPx 432) (UiPx 22) 8.5 $false $script:C_SUB
        $pb = New-Object System.Windows.Forms.ProgressBar
        $pb.Location = New-Object Drawing.Point -ArgumentList @((UiPx 24), (UiPx 84))
        $pb.Size = New-Object Drawing.Size -ArgumentList @((UiPx 432), (UiPx 18))
        $pb.Style = 'Marquee'
        $pb.MarqueeAnimationSpeed = 28
        $pdlg.Controls.Add($pb)
        $null = New-Label $pdlg '由 Windows Update 执行，下载时间取决于网络，请勿关闭本窗口。' (UiPx 24) (UiPx 114) (UiPx 432) (UiPx 40) 8 $false $script:C_DIM
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 600
        $script:DrvInstallState = @{ Proc = $proc; Dlg = $pdlg; Timer = $timer }
        $timer.Add_Tick({
            param($s, $e)
            $st = $script:DrvInstallState
            if (-not $st) { $s.Stop(); return }
            if ($st.Proc.HasExited) {
                $s.Stop()
                try { $st.Dlg.Close() } catch {}
            }
        })
        $pdlg.Add_Shown({
            param($s, $e)
            try { [TxUi.Native]::DarkTitle($s.Handle) } catch {}
            try { $script:DrvInstallState.Timer.Start() } catch {}
        })
        $pdlg.Add_FormClosing({
            param($s, $e)
            $st = $script:DrvInstallState
            if ($st -and -not $st.Proc.HasExited) { $e.Cancel = $true }
        })
        $pdlg.ShowDialog($owner) | Out-Null
        try { $timer.Stop(); $timer.Dispose() } catch {}
        $script:DrvInstallState = $null
        if (Test-Path -LiteralPath $outFile) {
            try {
                $j = Get-Content -Raw -LiteralPath $outFile | ConvertFrom-Json
                $result.Ok = [bool]$j.Ok
                $result.Reboot = [bool]$j.Reboot
                $result.Error = [string]$j.Error
            } catch { $result.Error = '读取安装结果失败' }
        } else {
            $result.Error = '安装进程未返回结果'
        }
        try { $pdlg.Dispose() } catch {}
    } catch {
        $result.Error = $_.Exception.Message
    } finally {
        try { if ($tmpDir -and (Test-Path -LiteralPath $tmpDir)) { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
    }
    return $result
}

function Update-DriverDetailActions($f) {
    try {
        $ctx = $f.Tag
        if (-not $ctx) { return }
        $lp = $null
        if ($ctx.LocalGrid.SelectedRows.Count -gt 0) { $lp = $ctx.LocalGrid.SelectedRows[0].Tag }
        $up = $null
        if ($ctx.UpdateGrid.SelectedRows.Count -gt 0) { $up = $ctx.UpdateGrid.SelectedRows[0].Tag }
        $ctx.BtnSwitch.Enabled = ($null -ne $lp) -and (-not $lp.InUse)
        $ctx.BtnClean.Enabled = ($null -ne $lp) -and (-not $lp.InUse)
        $ctx.BtnInstall.Enabled = ($null -ne $up) -and (-not $up.Hidden)
        $ctx.BtnHide.Enabled = ($null -ne $up) -and (-not $up.Hidden)
    } catch {}
}

function Fill-DriverLocalGrid($grid, $dev) {
    if (-not $grid) { return }
    try { $grid.Rows.Clear() } catch {}
    foreach ($p in @($dev.Packages)) {
        $state = '可切换'
        $cl = $script:C_SUB
        if ($p.InUse) { $state = '当前使用'; $cl = $script:C_GREEN }
        elseif ($p.Compare -lt 0) { $state = '旧版本'; $cl = $script:C_ORANGE }
        elseif ($p.Compare -gt 0) { $state = '较新'; $cl = $script:C_CYAN }
        elseif ($p.ClassName -eq 'Extension') { $state = '扩展包'; $cl = $script:C_DIM }
        $idx = $grid.Rows.Add([string]$p.Version, [string]$p.ClassName, [string]$p.PublishedName, [string]$p.Date, $state)
        $grid.Rows[$idx].DefaultCellStyle.ForeColor = $cl
        $grid.Rows[$idx].Tag = $p
    }
    if ($grid.Rows.Count -eq 0) {
        $idx = $grid.Rows.Add('--', '--', '未在本机驱动仓库中找到可切换的包', '--', '--')
        $grid.Rows[$idx].DefaultCellStyle.ForeColor = $script:C_DIM
    }
}

function Fill-DriverUpdateGrid($grid, $dev) {
    if (-not $grid) { return }
    try { $grid.Rows.Clear() } catch {}
    foreach ($u in @($dev.Updates)) {
        $state = '可用'
        $cl = $script:C_ORANGE
        if ($u.Hidden) { $state = '已隐藏'; $cl = $script:C_DIM }
        elseif ($u.Version -and (Compare-TxVersion $u.Version $dev.Version) -le 0) { $state = '不高于当前'; $cl = $script:C_SUB }
        $idx = $grid.Rows.Add([string]$u.Version, [string]$u.ClassName, [string]$u.Date, $state, [string]$u.Title)
        $grid.Rows[$idx].DefaultCellStyle.ForeColor = $cl
        $grid.Rows[$idx].Tag = $u
    }
    if ($grid.Rows.Count -eq 0) {
        $idx = $grid.Rows.Add('--', '--', '--', '--', '尚未检测更新，请回到驱动中心点「检测更新」')
        $grid.Rows[$idx].DefaultCellStyle.ForeColor = $script:C_DIM
    }
}

function Show-DriverDetails($dev) {
    if (-not $dev) { return }
    try {
        $accent = $dev.Accent
        if (-not $accent) { $accent = $script:C_CYAN }
        $dw = UiPx 760
        $dh = UiPx 660
        $scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $maxW = [int]($scr.Width * 0.94)
        $maxH = [int]($scr.Height * 0.92)
        if ($dw -gt $maxW) { $dw = $maxW }
        if ($dh -gt $maxH) { $dh = $maxH }
        # 右侧预留滚动条宽度, 避免高 DPI/小屏出现横向滚动
        $w = $dw - (UiPx 40) - (UiPx 24)

        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = '驱动详情'
        $dlg.FormBorderStyle = 'None'
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $dlg.ShowIcon = $false
        $dlg.ShowInTaskbar = $false
        $dlg.StartPosition = 'CenterParent'
        $dlg.AutoScaleMode = 'None'
        $dlg.ClientSize = New-Object Drawing.Size -ArgumentList @($dw, $dh)
        $dlg.BackColor = $script:C_BG
        $dlg.ForeColor = $script:C_TEXT
        $dlg.Font = F 9
        $dlg.SuspendLayout()

        $tbar = New-Object System.Windows.Forms.Panel
        $tbar.Location = New-Object Drawing.Point -ArgumentList @(0, 0)
        $tbar.Size = New-Object Drawing.Size -ArgumentList @($dw, (UiPx 38))
        $tbar.BackColor = $script:C_BG
        $dlg.Controls.Add($tbar)
        $tdot = New-Badge $tbar '' (UiPx 20) (UiPx 16) (UiPx 6) (UiPx 6) $accent $accent $accent 3
        $null = New-Label $tbar '游戏性能优化中心 · 驱动详情' (UiPx 32) 0 ($dw - (UiPx 160)) (UiPx 38) 9 $true $script:C_SUB
        $tclose = New-Label $tbar '✕' ($dw - (UiPx 54)) (UiPx 6) (UiPx 34) (UiPx 26) 10 $false $script:C_SUB 'MiddleCenter'
        try { $tclose.Cursor = [System.Windows.Forms.Cursors]::Hand } catch {}
        $tclose.Add_Click({ param($s, $e) try { $s.FindForm().Close() } catch {} })
        $drag = {
            param($s, $e)
            if ($e -and $e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                try { [TxUi.Native]::DragMove($s.FindForm().Handle) } catch {}
            }
        }
        foreach ($c in @($tbar, $tdot)) { $c.Add_MouseDown($drag) }
        $tline = New-Object System.Windows.Forms.Panel
        $tline.Location = New-Object Drawing.Point -ArgumentList @(0, (UiPx 37))
        $tline.Size = New-Object Drawing.Size -ArgumentList @($dw, (UiPx 1))
        $tline.BackColor = $script:C_BORDER
        $dlg.Controls.Add($tline)
        $dlg.Add_Paint({
            param($s, $e)
            try {
                $pen = New-Object Drawing.Pen $script:C_BORDER, ([single][Math]::Max(1, (UiPx 1)))
                $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1))
                $pen.Dispose()
            } catch {}
        })

        # 内容区可滚动: 高 DPI 或小屏时不会把底部按钮挤出窗口
        $footH = UiPx 60
        $body = New-Object System.Windows.Forms.Panel
        $body.Location = New-Object Drawing.Point -ArgumentList @(0, (UiPx 38))
        $body.Size = New-Object Drawing.Size -ArgumentList @($dw, [Math]::Max((UiPx 120), ($dh - (UiPx 38) - $footH)))
        $body.BackColor = $script:C_BG
        $body.AutoScroll = $true
        $body.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, (UiPx 560))
        $dlg.Controls.Add($body)
        $foot = New-Object System.Windows.Forms.Panel
        $foot.Location = New-Object Drawing.Point -ArgumentList @(0, ($dh - $footH))
        $foot.Size = New-Object Drawing.Size -ArgumentList @($dw, $footH)
        $foot.BackColor = $script:C_BG
        $dlg.Controls.Add($foot)

        $code = switch ($dev.Category) {
            '显卡' { 'GPU' }
            '音频' { 'AUD' }
            '外设' { 'HID' }
            '网络' { 'NET' }
            default { 'DRV' }
        }
        $hdr = New-Card $body (UiPx 20) (UiPx 12) $w (UiPx 88) 14 $script:C_PANEL $script:C_BORDER
        $icon = New-Badge $hdr $code (UiPx 16) (UiPx 15) (UiPx 56) (UiPx 56) (Get-MixColor $script:C_PANEL $accent 0.16) (Get-MixColor $script:C_BORDER $accent 0.60) $accent 11
        try { $icon.Radius = UiPx 14 } catch {}
        $null = New-Label $hdr ([string]$dev.Name) (UiPx 84) (UiPx 10) ($w - (UiPx 220)) (UiPx 30) 13 $true $script:C_TEXT
        $provText = [string]$dev.Provider
        if (-not $provText) { $provText = '未知厂商' }
        $null = New-Label $hdr ("$($dev.Category) · " + $provText) (UiPx 84) (UiPx 42) ($w - (UiPx 220)) (UiPx 20) 8.5 $false $script:C_SUB
        $stFill = $script:C_GREEN_BG
        $stBd = $script:C_GREEN_BD
        $stFg = $script:C_GREEN
        if (-not $dev.StatusOk) { $stFill = $script:C_ORANGE_BG; $stBd = $script:C_ORANGE_BD; $stFg = $script:C_ORANGE }
        $null = New-Badge $hdr $dev.StatusText ($w - (UiPx 130)) (UiPx 14) (UiPx 112) (UiPx 26) $stFill $stBd $stFg 8

        # 官方工具卡片: 只有检测到对应硬件 + 官方工具时才显示
        $shift = 0
        if ($dev.Vendor) {
            $shift = UiPx 110
            $ven = $dev.Vendor
            $vCard = New-Card $body (UiPx 20) (UiPx 110) $w (UiPx 98) 12 $script:C_PANEL $script:C_BORDER
            $vFill = $script:C_GREEN_BG; $vBd = $script:C_GREEN_BD; $vFg = $script:C_GREEN
            $vTxt = '已是最新'
            $vs = [string]$dev.VendorState
            if ($vs -eq 'RolledBack') {
                $vFill = (TC 58 22 26); $vBd = (TC 120 45 45); $vFg = $script:C_RED
                $vTxt = '版本被回退'
            } elseif ($vs -eq 'Mismatch') {
                $vFill = (TC 58 22 26); $vBd = (TC 120 45 45); $vFg = $script:C_RED
                $vTxt = '版本不匹配'
            } elseif ($vs -eq 'UpdateAvailable') {
                $vFill = $script:C_ORANGE_BG; $vBd = $script:C_ORANGE_BD; $vFg = $script:C_ORANGE
                $vTxt = '可更新'
            } elseif ($vs -eq 'Managed') {
                $vFill = $script:C_GRAY_BG; $vBd = $script:C_GRAY_BD; $vFg = $script:C_CYAN
                $vTxt = '官方工具管理'
            }
            $null = New-Badge $vCard ([string]$ven.Badge) (UiPx 16) (UiPx 14) (UiPx 62) (UiPx 22) (Get-MixColor $script:C_PANEL $script:C_CYAN 0.14) (Get-MixColor $script:C_BORDER $script:C_CYAN 0.55) $script:C_CYAN 8
            $vTitle = New-Label $vCard ([string]$ven.Tool) (UiPx 88) (UiPx 15) ($w - (UiPx 260)) (UiPx 20) 9.5 $true $script:C_TEXT
            $vTitle.AutoEllipsis = $true
            $null = New-Badge $vCard $vTxt ($w - (UiPx 154)) (UiPx 14) (UiPx 136) (UiPx 24) $vFill $vBd $vFg 8
            $noteLbl = New-Label $vCard ([string]$ven.Note) (UiPx 16) (UiPx 42) ($w - (UiPx 212)) (UiPx 48) 8.2 $false $script:C_SUB
            $noteLbl.AutoEllipsis = $false
            $btnText = ''
            $btnTarget = ''
            if ([string]$ven.AppPath) { $btnText = [string]$ven.AppButton; $btnTarget = [string]$ven.AppPath }
            elseif ([string]$ven.Link) { $btnText = '打开下载页'; $btnTarget = [string]$ven.Link }
            if ($btnText) {
                $btnVen = New-Btn $vCard $btnText ($w - (UiPx 196)) (UiPx 56) (UiPx 176) (UiPx 28) (Get-MixColor $script:C_PANEL $script:C_CYAN 0.12) $script:C_CYAN 8.3
                $btnVen.Add_Click({ param($s, $e) try { Start-Process $s.Tag } catch {} })
                $btnVen.Tag = $btnTarget
            }
            $body.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, [int]((UiPx 580) + $shift))
        }

        $info = New-Card $body (UiPx 20) ([int]((UiPx 110) + $shift)) $w (UiPx 132) 12 $script:C_PANEL $script:C_BORDER
        $rows = @(
            @('当前版本', $dev.Version),
            @('驱动日期', $dev.Date),
            @('提供程序', $dev.Provider),
            @('INF 文件', $dev.InfName),
            @('硬件 ID', $dev.HardwareId),
            @('设备状态', $dev.StatusText)
        )
        $ry = UiPx 10
        foreach ($r in $rows) {
            $null = New-Label $info $r[0] (UiPx 16) $ry (UiPx 90) (UiPx 19) 8.5 $false $script:C_DIM
            $v = [string]$r[1]
            if (-not $v) { $v = '--' }
            $lv = New-Label $info $v (UiPx 110) $ry ($w - (UiPx 126)) (UiPx 19) 8.5 $false $script:C_TEXT
            $lv.AutoEllipsis = $true
            $ry += UiPx 19
        }

        $null = New-Label $body '本地驱动包（可切换 / 可清理）' (UiPx 22) ([int]((UiPx 252) + $shift)) (UiPx 420) (UiPx 20) 9 $true $script:C_SUB
        $lg = New-Object System.Windows.Forms.DataGridView
        $lg.Location = New-Object Drawing.Point -ArgumentList @((UiPx 20), [int]((UiPx 274) + $shift))
        $lg.Size = New-Object Drawing.Size -ArgumentList @($w, (UiPx 128))
        $lg.Anchor = 'Top, Left, Right'
        $body.Controls.Add($lg)
        Style-Grid $lg
        $lg.RowTemplate.Height = UiPx 30
        $lg.ColumnHeadersHeight = UiPx 34
        $lg.ReadOnly = $true
        $lg.SelectionMode = 'FullRowSelect'
        $lg.MultiSelect = $false
        $lg.RowHeadersVisible = $false
        $lg.AllowUserToAddRows = $false
        $lg.AllowUserToResizeRows = $false
        $null = Add-GridCol $lg 'ver' '版本' 1.0 80
        $null = Add-GridCol $lg 'type' '类型' 0.7 64
        $null = Add-GridCol $lg 'pkg' '包名' 1.0 88
        $null = Add-GridCol $lg 'date' '日期' 0.9 80
        $null = Add-GridCol $lg 'state' '状态' 0.9 88
        foreach ($col in @($lg.Columns)) { $col.MinimumWidth = UiPx ([double]$col.MinimumWidth) }
        Fill-DriverLocalGrid $lg $dev

        $null = New-Label $body 'Windows 更新中的驱动条目' (UiPx 22) ([int]((UiPx 410) + $shift)) (UiPx 420) (UiPx 20) 9 $true $script:C_SUB
        $ug = New-Object System.Windows.Forms.DataGridView
        $ug.Location = New-Object Drawing.Point -ArgumentList @((UiPx 20), [int]((UiPx 432) + $shift))
        $ug.Size = New-Object Drawing.Size -ArgumentList @($w, (UiPx 100))
        $ug.Anchor = 'Top, Left, Right'
        $body.Controls.Add($ug)
        Style-Grid $ug
        $ug.RowTemplate.Height = UiPx 30
        $ug.ColumnHeadersHeight = UiPx 34
        $ug.ReadOnly = $true
        $ug.SelectionMode = 'FullRowSelect'
        $ug.MultiSelect = $false
        $ug.RowHeadersVisible = $false
        $ug.AllowUserToAddRows = $false
        $ug.AllowUserToResizeRows = $false
        $null = Add-GridCol $ug 'ver' '版本' 0.9 76
        $null = Add-GridCol $ug 'type' '类型' 0.7 64
        $null = Add-GridCol $ug 'date' '日期' 0.9 80
        $null = Add-GridCol $ug 'state' '状态' 0.8 78
        $null = Add-GridCol $ug 'title' '标题' 2.4 180
        foreach ($col in @($ug.Columns)) { $col.MinimumWidth = UiPx ([double]$col.MinimumWidth) }
        Fill-DriverUpdateGrid $ug $dev

        $lblMsg = New-Label $body '' (UiPx 22) ([int]((UiPx 536) + $shift)) $w (UiPx 16) 8 $false $script:C_DIM
        $fy = UiPx 13
        $bh = UiPx 34
        $bx = UiPx 20
        $bw = UiPx 100
        $gap = UiPx 6
        $btnSwitch = New-Btn $foot '切换所选驱动' $bx $fy $bw $bh (Get-MixColor $script:C_PANEL $accent 0.14) $script:C_TEXT 8.5
        $bx += $bw + $gap
        $btnClean = New-Btn $foot '清理所选旧包' $bx $fy $bw $bh (Get-MixColor $script:C_PANEL $script:C_ORANGE 0.10) $script:C_ORANGE 8.5
        $bx += $bw + $gap
        $btnInstall = New-Btn $foot '安装所选更新' $bx $fy $bw $bh $accent ((TC 8 14 22)) 8.5
        $bx += $bw + $gap
        $btnHide = New-Btn $foot '隐藏所选更新' $bx $fy $bw $bh ((TC 24 35 50)) $script:C_SUB 8.5
        $bx += $bw + $gap
        $btnDevMgr = New-Btn $foot '设备管理器' $bx $fy (UiPx 96) $bh ((TC 24 35 50)) $script:C_SUB 8.5
        $bx += UiPx 96 + $gap
        $btnRebind = New-Btn $foot '重新绑定驱动' $bx $fy (UiPx 104) $bh ((TC 22 36 50)) $script:C_CYAN 8.5
        $btnClose = New-Btn $foot '关闭' ($dw - (UiPx 20) - (UiPx 72)) $fy (UiPx 72) $bh $script:C_PANEL2 $script:C_SUB 8.5
        $dlg.CancelButton = $btnClose
        $dlg.Tag = @{
            Dev = $dev; LocalGrid = $lg; UpdateGrid = $ug; Msg = $lblMsg
            BtnSwitch = $btnSwitch; BtnClean = $btnClean; BtnInstall = $btnInstall; BtnHide = $btnHide
        }
        $lg.Add_SelectionChanged({ param($s, $e) Update-DriverDetailActions $s.FindForm() })
        $ug.Add_SelectionChanged({ param($s, $e) Update-DriverDetailActions $s.FindForm() })
        Update-DriverDetailActions $dlg
        $btnClose.Add_Click({ param($s, $e) try { $s.FindForm().Close() } catch {} })
        $btnDevMgr.Add_Click({ try { Start-Process 'devmgmt.msc' } catch {} })

        $btnRebind.Add_Click({
            param($s, $e)
            $f = $s.FindForm()
            $ctx = $f.Tag
            $inf = [string]$ctx.Dev.InfName
            if (-not $inf) {
                [System.Windows.Forms.MessageBox]::Show($f, '当前设备没有可用的 INF 文件名，无法重新绑定。', '重新绑定驱动', 'OK', 'Warning') | Out-Null
                return
            }
            if (-not $script:isAdmin) {
                [System.Windows.Forms.MessageBox]::Show($f, '重新绑定驱动需要管理员权限，请以管理员身份重新启动本程序。', '重新绑定驱动', 'OK', 'Warning') | Out-Null
                return
            }
            $infPath = Join-Path (Join-Path $env:WINDIR 'INF') $inf
            if (-not (Test-Path -LiteralPath $infPath)) {
                [System.Windows.Forms.MessageBox]::Show($f, "未找到驱动包：`n$infPath", '重新绑定驱动', 'OK', 'Warning') | Out-Null
                return
            }
            $msg = "将使用当前驱动包重新绑定设备：`n$($ctx.Dev.Name)`n$inf`n`n适用于设备状态异常、驱动被系统回退或重新绑定后仍未识别的情况。`n安装时屏幕可能短暂闪烁，完成后可能需要重启。是否继续？"
            if ([string]$ctx.Dev.Category -eq '音频') { $msg += "`n`n音频设备提示：操作期间声音可能短暂中断，完成后会自动恢复原有静音状态。" }
            $r = [System.Windows.Forms.MessageBox]::Show($f, $msg, '重新绑定驱动', 'YesNo', 'Warning')
            if ($r -ne 'Yes') { return }
            $script:UI.Busy = $true
            $null = Protect-TxAudioBegin
            try {
                Set-Status "正在重新绑定驱动: $inf..."
                [System.Windows.Forms.Application]::DoEvents()
                $out = & pnputil.exe /add-driver $infPath /install 2>&1
                $code = $LASTEXITCODE
                $text = (@($out) | ForEach-Object { [string]$_ }) -join "`n"
                if ($code -eq 0) {
                    $script:DrvNeedRefresh = $true
                    $script:DrvRefreshDevice = [string]$ctx.Dev.DeviceId
                    $script:DrvRefreshEnum = $true
                    [System.Windows.Forms.MessageBox]::Show($f, "重新绑定命令已完成。`n`n$text`n`n如果设备没有立即变化，请重启后再查看。", '重新绑定驱动', 'OK', 'Information') | Out-Null
                    $f.Close()
                } else {
                    [System.Windows.Forms.MessageBox]::Show($f, "重新绑定失败（退出码 $code）。`n`n$text", '重新绑定驱动', 'OK', 'Warning') | Out-Null
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show($f, $_.Exception.Message, '重新绑定驱动', 'OK', 'Warning') | Out-Null
            } finally {
                $script:UI.Busy = $false
            }
        })

        $btnSwitch.Add_Click({
            param($s, $e)
            $f = $s.FindForm()
            $ctx = $f.Tag
            if (-not $ctx.LocalGrid.SelectedRows.Count) {
                [System.Windows.Forms.MessageBox]::Show($f, '请先在「本地驱动包」列表中选择一个包。', '切换驱动', 'OK', 'Information') | Out-Null
                return
            }
            $pkg = $ctx.LocalGrid.SelectedRows[0].Tag
            if (-not $pkg) { return }
            if ($pkg.InUse) {
                [System.Windows.Forms.MessageBox]::Show($f, '选中的已经是当前正在使用的驱动包。', '切换驱动', 'OK', 'Information') | Out-Null
                return
            }
            if (-not $script:isAdmin) {
                [System.Windows.Forms.MessageBox]::Show($f, '切换驱动需要管理员权限，请以管理员身份重新启动本程序。', '切换驱动', 'OK', 'Warning') | Out-Null
                return
            }
            $msg = "将把`n$($ctx.Dev.Name)`n切换到驱动包 $($pkg.Version)（$($pkg.PublishedName)）。`n`n安装时屏幕可能短暂闪烁，完成后可能需要重启。`n是否继续？"
            if ([string]$ctx.Dev.Category -eq '音频') { $msg += "`n`n音频设备提示：操作期间声音可能短暂中断，完成后会自动恢复原有静音状态。" }
            $r = [System.Windows.Forms.MessageBox]::Show($f, $msg, '切换驱动', 'YesNo', 'Warning')
            if ($r -ne 'Yes') { return }
            $script:UI.Busy = $true
            $null = Protect-TxAudioBegin
            try {
                $inf = Join-Path (Join-Path $env:WINDIR 'INF') $pkg.PublishedName
                Set-Status "正在切换驱动: $($pkg.PublishedName)..."
                [System.Windows.Forms.Application]::DoEvents()
                $out = & pnputil.exe /add-driver $inf /install 2>&1
                $code = $LASTEXITCODE
                $text = (@($out) | ForEach-Object { [string]$_ }) -join "`n"
                if ($code -eq 0) {
                    $script:DrvNeedRefresh = $true
                    $script:DrvRefreshDevice = [string]$ctx.Dev.DeviceId
                    $script:DrvRefreshEnum = $true
                    [System.Windows.Forms.MessageBox]::Show($f, "驱动安装命令已完成。`n`n$text`n`n如果设备没有立即变化，请重启后再查看。", '切换驱动', 'OK', 'Information') | Out-Null
                    $f.Close()
                } else {
                    [System.Windows.Forms.MessageBox]::Show($f, "切换失败（退出码 $code）。`n`n$text", '切换驱动', 'OK', 'Warning') | Out-Null
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show($f, $_.Exception.Message, '切换驱动', 'OK', 'Warning') | Out-Null
            } finally {
                Protect-TxAudioEnd -Deferred
                $script:UI.Busy = $false
            }
        })

        $btnClean.Add_Click({
            param($s, $e)
            $f = $s.FindForm()
            $ctx = $f.Tag
            if (-not $ctx.LocalGrid.SelectedRows.Count) {
                [System.Windows.Forms.MessageBox]::Show($f, '请先在「本地驱动包」列表中选择一个包。', '清理旧包', 'OK', 'Information') | Out-Null
                return
            }
            $pkg = $ctx.LocalGrid.SelectedRows[0].Tag
            if (-not $pkg) { return }
            if ($pkg.InUse) {
                [System.Windows.Forms.MessageBox]::Show($f, '当前正在使用的驱动包不能删除。', '清理旧包', 'OK', 'Warning') | Out-Null
                return
            }
            if (-not $script:isAdmin) {
                [System.Windows.Forms.MessageBox]::Show($f, '清理驱动包需要管理员权限，请以管理员身份重新启动本程序。', '清理旧包', 'OK', 'Warning') | Out-Null
                return
            }
            $msg = "将从本机驱动仓库删除：`n$($pkg.PublishedName)  v$($pkg.Version)`n`n该操作无法通过本界面撤销。是否继续？"
            if ([string]$ctx.Dev.Category -eq '音频') { $msg += "`n`n音频设备提示：操作期间声音可能短暂中断，完成后会自动恢复原有静音状态。" }
            $r = [System.Windows.Forms.MessageBox]::Show($f, $msg, '清理旧包', 'YesNo', 'Warning')
            if ($r -ne 'Yes') { return }
            $script:UI.Busy = $true
            $null = Protect-TxAudioBegin
            try {
                Set-Status "正在清理驱动包: $($pkg.PublishedName)..."
                [System.Windows.Forms.Application]::DoEvents()
                $out = & pnputil.exe /delete-driver $pkg.PublishedName /uninstall 2>&1
                $code = $LASTEXITCODE
                $text = (@($out) | ForEach-Object { [string]$_ }) -join "`n"
                if ($code -eq 0) {
                    $script:DrvNeedRefresh = $true
                    $script:DrvRefreshDevice = [string]$ctx.Dev.DeviceId
                    $script:DrvRefreshEnum = $false
                    # 只重新核对这一台设备, 不重扫整页
                    try {
                        $pkgs = @(Get-TxDriverPackages -Force)
                        $null = Complete-TxDriverDevice $ctx.Dev $pkgs
                        Fill-DriverLocalGrid $ctx.LocalGrid $ctx.Dev
                        Update-DriverCardData $ctx.Dev
                        Update-DriverFilterButtons
                        Update-DriverSummary
                        Set-Status "已清理旧包 · $($ctx.Dev.Name)"
                        $ctx.Msg.Text = "已删除 $($pkg.PublishedName)"
                        # 页面已经同步, 关闭对话框后不必再刷新一次
                        $script:DrvNeedRefresh = $false
                        $script:DrvRefreshDevice = ''
                    } catch {}
                    [System.Windows.Forms.MessageBox]::Show($f, "驱动包已删除。`n`n$text", '清理旧包', 'OK', 'Information') | Out-Null
                } else {
                    [System.Windows.Forms.MessageBox]::Show($f, "删除失败（退出码 $code）。`n`n$text`n`n如果提示设备正在使用，请重启后再清理。", '清理旧包', 'OK', 'Warning') | Out-Null
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show($f, $_.Exception.Message, '清理旧包', 'OK', 'Warning') | Out-Null
            } finally {
                Protect-TxAudioEnd -Deferred
                $script:UI.Busy = $false
            }
        })

        $btnInstall.Add_Click({
            param($s, $e)
            $f = $s.FindForm()
            $ctx = $f.Tag
            if (-not $ctx.UpdateGrid.SelectedRows.Count) {
                [System.Windows.Forms.MessageBox]::Show($f, '请先在「Windows 更新」列表中选择一条更新。', '安装更新', 'OK', 'Information') | Out-Null
                return
            }
            $u = $ctx.UpdateGrid.SelectedRows[0].Tag
            if (-not $u) { return }
            if ($u.Hidden) {
                [System.Windows.Forms.MessageBox]::Show($f, '该更新当前处于隐藏状态，不能在这里安装。', '安装更新', 'OK', 'Information') | Out-Null
                return
            }
            if (-not $script:isAdmin) {
                [System.Windows.Forms.MessageBox]::Show($f, '安装驱动更新需要管理员权限，请以管理员身份重新启动本程序。', '安装更新', 'OK', 'Warning') | Out-Null
                return
            }
            $msg = "将从 Windows Update 下载并安装：`n$($u.Title)`n`n下载时间取决于网络，安装期间请不要关闭本窗口。是否继续？"
            if ([string]$ctx.Dev.Category -eq '音频') { $msg += "`n`n音频设备提示：操作期间声音可能短暂中断，完成后会自动恢复原有静音状态。" }
            $r = [System.Windows.Forms.MessageBox]::Show($f, $msg, '安装更新', 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
            $null = Protect-TxAudioBegin
            try {
                $res = Invoke-DriverWuInstall $f $u
            } catch {
                $res = @{ Ok = $false; Error = $_.Exception.Message; Reboot = $false }
            } finally {
                Protect-TxAudioEnd -Deferred
            }
            if ($res.Ok) {
                $script:DrvNeedRefresh = $true
                $script:DrvRefreshDevice = [string]$ctx.Dev.DeviceId
                $script:DrvRefreshEnum = $true
                $m = '驱动更新已安装完成。'
                if ($res.Reboot) { $m += ' 需要重启后生效。' }
                [System.Windows.Forms.MessageBox]::Show($f, $m, '安装更新', 'OK', 'Information') | Out-Null
                $f.Close()
            } else {
                $err = '安装未完成。'
                if ($res.Error) { $err += "`n`n" + $res.Error }
                [System.Windows.Forms.MessageBox]::Show($f, $err, '安装更新', 'OK', 'Warning') | Out-Null
            }
        })

        $btnHide.Add_Click({
            param($s, $e)
            $f = $s.FindForm()
            $ctx = $f.Tag
            if (-not $ctx.UpdateGrid.SelectedRows.Count) {
                [System.Windows.Forms.MessageBox]::Show($f, '请先在「Windows 更新」列表中选择一条更新。', '隐藏更新', 'OK', 'Information') | Out-Null
                return
            }
            $u = $ctx.UpdateGrid.SelectedRows[0].Tag
            if (-not $u) { return }
            if ($u.Hidden) {
                [System.Windows.Forms.MessageBox]::Show($f, '该更新已经是隐藏状态。', '隐藏更新', 'OK', 'Information') | Out-Null
                return
            }
            if (-not $script:isAdmin) {
                [System.Windows.Forms.MessageBox]::Show($f, '隐藏更新需要管理员权限，请以管理员身份重新启动本程序。', '隐藏更新', 'OK', 'Warning') | Out-Null
                return
            }
            $r = [System.Windows.Forms.MessageBox]::Show($f, "将隐藏这条驱动更新，系统不会再自动推送它。`n`n$($u.Title)`n`n是否继续？", '隐藏更新', 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
            try {
                $u.Raw.IsHidden = $true
                $u.Hidden = $true
                $script:DrvNeedRefresh = $true
                $script:DrvRefreshDevice = [string]$ctx.Dev.DeviceId
                $script:DrvRefreshEnum = $false
                try {
                    $pkgs = @(Get-TxDriverPackages)
                    $null = Complete-TxDriverDevice $ctx.Dev $pkgs
                    Fill-DriverUpdateGrid $ctx.UpdateGrid $ctx.Dev
                    Update-DriverCardData $ctx.Dev
                    Update-DriverFilterButtons
                    Update-DriverSummary
                    Update-DriverDetailActions $f
                    # 页面已经同步, 关闭对话框后不必再刷新一次
                    $script:DrvNeedRefresh = $false
                    $script:DrvRefreshDevice = ''
                } catch {}
                [System.Windows.Forms.MessageBox]::Show($f, '已隐藏该驱动更新。', '隐藏更新', 'OK', 'Information') | Out-Null
            } catch {
                [System.Windows.Forms.MessageBox]::Show($f, ("隐藏失败：`n" + $_.Exception.Message), '隐藏更新', 'OK', 'Warning') | Out-Null
            }
        })

        $dlg.ResumeLayout($true)
        $dlg.Add_Shown({
            param($s, $e)
            try { [TxUi.Native]::DarkTitle($s.Handle) } catch {}
            try { [TxUi.Native]::DarkScroll($body.Handle) } catch {}
        })
        $dlg.ShowDialog($script:UI.Form) | Out-Null
        $need = $script:DrvNeedRefresh
        $script:DrvNeedRefresh = $false
        $devId = [string]$script:DrvRefreshDevice
        $reEnum = [bool]$script:DrvRefreshEnum
        $script:DrvRefreshDevice = ''
        $script:DrvRefreshEnum = $false
        try { $dlg.Dispose() } catch {}
        if ($devId) { Refresh-DriverDevice $devId $reEnum }
        elseif ($need) { Refresh-DriverPage $true }
    } catch {
        Set-Status "打开驱动详情失败: $($_.Exception.Message)"
    }
}

# ══════════════════════════════════════════════════════════
# 优化项页
# ══════════════════════════════════════════════════════════
$script:SnapMap = @{}
foreach ($x in @($script:Snap.Items)) { $script:SnapMap[$x.Id] = $x }

$itPage = New-Page 'items'
$script:UI.ItemsPage = $itPage
$tw = $cw - 40
$itemHero = New-PageHero $itPage 'TWEAK LIBRARY · LOCAL FIRST' '优化项' '按分类、状态与风险筛选 · 勾选后应用，所有改动均可还原' @(
    @{ V = '0'; T = '已选'; C = $script:C_CYAN },
    @{ V = '0'; T = '待应用'; C = $script:C_ORANGE },
    @{ V = '0'; T = '已生效'; C = $script:C_GREEN }
)
$script:UI.ItemHero = $itemHero.Card
$script:UI.ItemStatSel = $itemHero.Values[0]
$script:UI.ItemStatPend = $itemHero.Values[1]
$script:UI.ItemStatOk = $itemHero.Values[2]

$tool = New-Card $itPage 20 150 $tw 100 12 $script:C_PANEL $script:C_BORDER
$tool.Anchor = 'Top, Left, Right'
$script:UI.ItemsTool = $tool

$search = New-TextBox $tool 16 12 230 30 '搜索优化项名称或说明...'
$script:UI.Search = $search
$search.Add_TextChanged({ Rebuild-Items })
$catCombo = New-Combo $tool 258 13 120
$script:UI.CatCombo = $catCombo
[void]$catCombo.Items.Add('全部分类')
foreach ($cat in @($O.Cat | Select-Object -Unique)) { [void]$catCombo.Items.Add([string]$cat) }
$catCombo.SelectedIndex = 0
$catCombo.Add_SelectedIndexChanged({ Rebuild-Items })
$statusCombo = New-Combo $tool 390 13 110
$script:UI.StatusCombo = $statusCombo
foreach ($st in @('全部状态','待应用','已生效','不适用')) { [void]$statusCombo.Items.Add($st) }
$statusCombo.SelectedIndex = 0
$statusCombo.Add_SelectedIndexChanged({ Rebuild-Items })
$onlyRec = New-Check $tool '仅推荐项' 512 16 88 24
$script:UI.OnlyRec = $onlyRec
$onlyRec.Add_CheckedChanged({ Rebuild-Items })
$btnSelRec = New-Btn $tool '全选推荐' 610 12 90 30 ((TC 24 35 50)) $script:C_GREEN 8
$btnSelNone = New-Btn $tool '全不选' 708 12 72 30 ((TC 24 35 50)) $script:C_SUB 8
$btnSelRec.Add_Click({ Select-Recommended })
$btnSelNone.Add_Click({
    foreach ($it in $O) { $it.E = $false }
    Rebuild-Items
    Set-Status '已取消全部勾选'
})

$profileCombo = New-Combo $tool 16 56 160
$script:UI.ProfileCombo = $profileCombo
$btnPLoad = New-Btn $tool '载入方案' 184 56 76 30 ((TC 24 35 50)) $script:C_CYAN 8
$btnPSave = New-Btn $tool '保存方案' 268 56 76 30 ((TC 24 35 50)) $script:C_SUB 8
$restoreChk = New-Check $tool '应用前创建还原点' 352 58 150 24
$script:UI.RestoreChk = $restoreChk
$btnItemPreview = New-Btn $tool '预览变更' ($tw - 268) 56 120 30 ((TC 24 35 50)) $script:C_TEXT 9
$btnItemPreview.Anchor = 'Top, Right'
$btnItemApply = New-Btn $tool '应用选中项' ($tw - 136) 56 120 30 $script:C_GREEN ((TC 6 22 13)) 9
$btnItemApply.Anchor = 'Top, Right'
$script:UI.BtnItemPreview = $btnItemPreview
$script:UI.BtnItemApply = $btnItemApply

$btnItemPreview.Add_Click({ Invoke-PreviewSelected })
$btnItemApply.Add_Click({ Invoke-ApplySelected })
$btnPLoad.Add_Click({
    $n = [string]$script:UI.ProfileCombo.SelectedItem
    if (-not $n) { return }
    try {
        Set-TxSelectionByProfile -Name $n | Out-Null
        Rebuild-Items
        Set-Status "已载入方案: $n"
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '载入方案', 'OK', 'Warning') | Out-Null
    }
})
$btnPSave.Add_Click({
    $n = Show-InputDialog '保存方案' '给当前勾选组合起一个名字：' '我的方案'
    if (-not $n) { return }
    try {
        $ids = @($O | Where-Object E | ForEach-Object { $_.Id })
        Save-TxProfile -Name $n -Ids $ids | Out-Null
        Refresh-Profiles $n
        Set-Status "已保存方案: $n ($($ids.Count) 项)"
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '保存方案', 'OK', 'Warning') | Out-Null
    }
})

$lblItemSummary = New-Label $itPage '已选 0 项' 22 258 420 22 9 $false $script:C_SUB
$script:UI.ItemSummary = $lblItemSummary
if ($HAS_DGPU) {
    $hintText = '已检测到独立显卡：独显专属优化项已加入列表'
} else {
    $hintText = '核显机型：独显专属项已隐藏（检测到独显后会自动出现）'
}
$lblDgpuHint = New-Label $itPage $hintText ($cw - 480) 258 456 22 8.5 $false $script:C_DIM 'MiddleRight'
$lblDgpuHint.Anchor = 'Top, Right'

$itemsFlow = New-Object TxUi.Flow
$itemsFlow.Location = New-Object Drawing.Point -ArgumentList @(20, 286)
$itemsFlow.Size = New-Object Drawing.Size -ArgumentList @(($cw - 40), 408)
$itemsFlow.Anchor = 'Top, Bottom, Left, Right'
$itemsFlow.BackColor = $script:C_BG
$itemsFlow.AutoScroll = $true
$itemsFlow.FlowDirection = 'TopDown'
$itemsFlow.WrapContents = $false
$itemsFlow.Padding = New-Object System.Windows.Forms.Padding -ArgumentList @(0, 0, 0, 0)
$itPage.Controls.Add($itemsFlow)
$script:UI.ItemsFlow = $itemsFlow
$itemsFlow.Add_Resize({
    param($s, $e)
    try {
        if ($script:UiScaling) { return }
        $sc = [double]$script:UI_SCALE
        $rw = $s.ClientSize.Width - [int](24 * $sc)
        if ($rw -lt [int](400 * $sc)) { return }
        foreach ($r in @($s.Controls)) {
            $r.Width = $rw
            $nm = $r.Controls.Find('nm', $false)
            $ds = $r.Controls.Find('ds', $false)
            if ($nm.Count -gt 0) { $nm[0].Width = $rw - [int](470 * $sc) }
            if ($ds.Count -gt 0) { $ds[0].Width = $rw - [int](470 * $sc) }
        }
    } catch {}
})
$itPage.Add_Resize({
    param($s, $e)
    try {
        if ($script:UiScaling) { return }
        $sc = [double]$script:UI_SCALE
        $w = $s.ClientSize.Width
        if ($w -lt [int](500 * $sc)) { return }
        $script:UI.ItemsTool.Width = $w - [int](40 * $sc)
        $script:UI.ItemsFlow.Width = $w - [int](40 * $sc)
        $script:UI.ItemsFlow.Height = $s.ClientSize.Height - [int](306 * $sc)
    } catch {}
})

function Get-SearchText {
    $t = $script:UI.Search
    if ($t.Tag.Active) { return $t.Text.Trim() }
    return ''
}

function Get-ItemSnapshot($it) {
    $si = $script:SnapMap[$it.Id]
    if ($si) { return $si }
    $q = QI $it
    return [PSCustomObject]@{
        Id = $it.Id; Status = $q.S; StatusText = $q.C; Target = $it.TL
        NeedsReboot = (Get-TxNeedsReboot $it); Risk = $it.R
    }
}

function New-ItemRow($it, $si, [int]$rowW) {
    $sc = [double]$script:UI_SCALE
    $row = New-Card $script:UI.ItemsFlow 0 0 $rowW ([int](62 * $sc)) 10 $script:C_PANEL $script:C_BORDER
    $row.Margin = New-Object System.Windows.Forms.Padding -ArgumentList @(0, 0, 0, [int](8 * $sc))

    $cb = New-Check $row '' ([int](14 * $sc)) ([int](21 * $sc)) ([int](20 * $sc)) ([int](20 * $sc)) ([bool]$it.E)
    $cb.Tag = $it
    if ($si.Status -eq 'na') {
        $cb.Enabled = $false
        $cb.ForeColor = $script:C_DIM
    }
    $cb.Add_CheckedChanged({
        param($s, $e)
        try { $s.Tag.E = [bool]$s.Checked } catch {}
        Update-ItemSummary
    })

    $nameW = $rowW - [int](470 * $sc)
    if ($nameW -lt [int](120 * $sc)) { $nameW = [int](120 * $sc) }
    $nm = New-Label $row ([string]$it.Name) ([int](42 * $sc)) ([int](8 * $sc)) $nameW ([int](24 * $sc)) 10 $true $script:C_TEXT
    $nm.Name = 'nm'
    $ds = New-Label $row ([string]$it.D) ([int](42 * $sc)) ([int](32 * $sc)) $nameW ([int](20 * $sc)) 8.5 $false $script:C_SUB
    $ds.Name = 'ds'

    $cur = New-Label $row ("当前: " + [string]$si.StatusText) ($rowW - [int](436 * $sc)) ([int](8 * $sc)) ([int](118 * $sc)) ([int](20 * $sc)) 8 $false $script:C_DIM 'MiddleRight'
    $cur.Anchor = 'Top, Right'
    $tgt = New-Label $row ("目标: " + [string]$it.TL) ($rowW - [int](436 * $sc)) ([int](30 * $sc)) ([int](118 * $sc)) ([int](20 * $sc)) 8 $false $script:C_TEXT 'MiddleRight'
    $tgt.Anchor = 'Top, Right'

    $catColor = $script:C_GRAY_BG
    $catBorder = $script:C_GRAY_BD
    $catBadge = New-Badge $row ([string]$it.Cat) ($rowW - [int](312 * $sc)) ([int](19 * $sc)) ([int](72 * $sc)) ([int](24 * $sc)) $catColor $catBorder $script:C_SUB 7.5
    $catBadge.Anchor = 'Top, Right'

    if ($si.NeedsReboot) {
        $rb = New-Badge $row '需重启' ($rowW - [int](238 * $sc)) ([int](19 * $sc)) ([int](64 * $sc)) ([int](24 * $sc)) $script:C_GRAY_BG $script:C_GRAY_BD $script:C_SUB 7.5
        $rb.Anchor = 'Top, Right'
    }

    $riskText = '低风险'; $riskFg = $script:C_SUB; $riskBg = $script:C_GRAY_BG; $riskBd = $script:C_GRAY_BD
    if ($it.R -eq 'med') { $riskText = '中风险'; $riskFg = $script:C_ORANGE; $riskBg = $script:C_ORANGE_BG; $riskBd = $script:C_ORANGE_BD }
    elseif ($it.R -eq 'high') { $riskText = '高风险'; $riskFg = $script:C_RED; $riskBg = $script:C_RED_BG; $riskBd = $script:C_RED_BD }
    $rk = New-Badge $row $riskText ($rowW - [int](166 * $sc)) ([int](19 * $sc)) ([int](52 * $sc)) ([int](24 * $sc)) $riskBg $riskBd $riskFg 7.5
    $rk.Anchor = 'Top, Right'

    $stText = '待应用'; $stFg = $script:C_ORANGE; $stBg = $script:C_ORANGE_BG; $stBd = $script:C_ORANGE_BD
    if ($si.Status -eq 'ok') { $stText = '已生效'; $stFg = $script:C_GREEN; $stBg = $script:C_GREEN_BG; $stBd = $script:C_GREEN_BD }
    elseif ($si.Status -eq 'na') { $stText = '不适用'; $stFg = $script:C_SUB; $stBg = $script:C_GRAY_BG; $stBd = $script:C_GRAY_BD }
    elseif ($si.Status -eq 'checking') { $stText = '检测中'; $stFg = $script:C_DIM; $stBg = $script:C_GRAY_BG; $stBd = $script:C_GRAY_BD }
    $sb = New-Badge $row $stText ($rowW - [int](102 * $sc)) ([int](19 * $sc)) ([int](86 * $sc)) ([int](24 * $sc)) $stBg $stBd $stFg 8
    $sb.Anchor = 'Top, Right'
    return $row
}

function Update-ItemSummary([int]$shown = -1) {
    try {
        $sel = @($O | Where-Object E).Count
        if ($shown -lt 0) { $shown = $script:UI.ItemsFlow.Controls.Count }
        $script:UI.ItemSummary.Text = "已选 $sel 项 · 显示 $shown / 共 $($O.Count) 项"
        $pend = 0; $ok = 0
        foreach ($it in $O) {
            $si = $script:SnapMap[$it.Id]
            if (-not $si) { continue }
            if ($si.Status -eq 'no') { $pend++ }
            elseif ($si.Status -eq 'ok') { $ok++ }
        }
        if ($script:UI.ItemStatSel) { $script:UI.ItemStatSel.Text = [string]$sel }
        if ($script:UI.ItemStatPend) { $script:UI.ItemStatPend.Text = [string]$pend }
        if ($script:UI.ItemStatOk) { $script:UI.ItemStatOk.Text = [string]$ok }
    } catch {}
}

function Rebuild-Items {
    try {
        $flow = $script:UI.ItemsFlow
        $flow.SuspendLayout()
        while ($flow.Controls.Count -gt 0) {
            $c = $flow.Controls[0]
            $flow.Controls.Remove($c)
            $c.Dispose()
        }
        $searchTxt = (Get-SearchText).ToLowerInvariant()
        $catSel = [string]$script:UI.CatCombo.SelectedItem
        $stSel = [string]$script:UI.StatusCombo.SelectedItem
        $onlyRec = [bool]$script:UI.OnlyRec.Checked
        $sc = [double]$script:UI_SCALE
        $rowW = $flow.ClientSize.Width - [int](24 * $sc)
        if ($rowW -lt [int](400 * $sc)) { $rowW = [int](760 * $sc) }
        $shown = 0
        foreach ($it in $O) {
            $si = Get-ItemSnapshot $it
            if ($catSel -and $catSel -ne '全部分类' -and [string]$it.Cat -ne $catSel) { continue }
            if ($stSel -eq '待应用' -and $si.Status -ne 'no') { continue }
            if ($stSel -eq '已生效' -and $si.Status -ne 'ok') { continue }
            if ($stSel -eq '不适用' -and $si.Status -ne 'na') { continue }
            if ($onlyRec -and $it.R -ne 'low') { continue }
            if ($searchTxt) {
                $hay = ("$($it.Name) $($it.D) $($it.Cat)").ToLowerInvariant()
                if ($hay.IndexOf($searchTxt) -lt 0) { continue }
            }
            $null = New-ItemRow $it $si $rowW
            $shown++
        }
        if ($shown -eq 0) {
            $emptyCard = New-Card $flow 0 0 $rowW ([int](56 * $sc)) 10 $script:C_PANEL $script:C_BORDER
            $emptyCard.Margin = New-Object System.Windows.Forms.Padding -ArgumentList @(0, 0, 0, [int](8 * $sc))
            $null = New-Label $emptyCard '没有匹配的优化项，试试调整分类、状态或搜索关键字' ([int](16 * $sc)) 0 ($rowW - [int](32 * $sc)) ([int](56 * $sc)) 9 $false $script:C_DIM 'MiddleLeft'
        }
        $flow.ResumeLayout()
        Update-ItemSummary $shown
    } catch {
        try { $script:UI.ItemsFlow.ResumeLayout() } catch {}
        Set-Status "优化项列表刷新失败: $($_.Exception.Message)"
    }
}

function Update-Profiles {
    try {
        $c = $script:UI.ProfileCombo
        $cur = [string]$c.SelectedItem
        $c.Items.Clear()
        foreach ($p in @(Get-TxProfiles)) { [void]$c.Items.Add([string]$p.Name) }
        if ($cur) {
            $idx = $c.Items.IndexOf($cur)
            if ($idx -ge 0) { $c.SelectedIndex = $idx; return }
        }
        if ($c.Items.Count -gt 0) { $c.SelectedIndex = 0 }
    } catch {}
}
function Refresh-Profiles([string]$selectName = '') {
    Update-Profiles
    if ($selectName) {
        $idx = $script:UI.ProfileCombo.Items.IndexOf($selectName)
        if ($idx -ge 0) { $script:UI.ProfileCombo.SelectedIndex = $idx }
    }
}

function Select-Recommended {
    foreach ($it in $O) {
        $si = $script:SnapMap[$it.Id]
        $na = $false
        if ($si -and $si.Status -eq 'na') { $na = $true }
        $it.E = ([bool]($it.R -eq 'low') -and -not $na)
    }
    Rebuild-Items
}

function Add-RtLine($rt, [string]$text, $color, [double]$size = 9, [bool]$bold = $false) {
    try {
        if ($rt -is [System.Windows.Forms.ListBox]) {
            $item = New-Object TxUi.LogItem -ArgumentList @([string]$text, $color, [bool]$bold)
            [void]$rt.Items.Add($item)
            return
        }
        $rt.SelectionStart = $rt.TextLength
        $rt.SelectionLength = 0
        $rt.SelectionColor = $color
        $rt.SelectionFont = F $size $bold
        $rt.AppendText($text + "`r`n")
    } catch {}
}

function Show-PreviewDialog($result) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = '变更预览'
    $dlg.Size = New-Object Drawing.Size -ArgumentList @(860, 640)
    $dlg.MinimumSize = New-Object Drawing.Size -ArgumentList @(720, 520)
    $dlg.StartPosition = 'CenterParent'
    $dlg.BackColor = $script:C_BG
    $dlg.ForeColor = $script:C_TEXT
    $dlg.ShowIcon = $false
    $null = New-Label $dlg '变更预览' 24 18 260 30 15 $true $script:C_TEXT
    $null = New-Label $dlg '预览不会写入系统，确认后再应用' 24 48 420 20 9 $false $script:C_SUB
    $rt = New-Object System.Windows.Forms.RichTextBox
    $rt.Location = New-Object Drawing.Point -ArgumentList @(24, 80)
    $rt.Size = New-Object Drawing.Size -ArgumentList @(796, 470)
    $rt.Anchor = 'Top, Bottom, Left, Right'
    $rt.BackColor = $script:C_PANEL
    $rt.ForeColor = $script:C_TEXT
    $rt.BorderStyle = 'None'
    $rt.ReadOnly = $true
    $rt.Font = F 9.5
    $rt.DetectUrls = $false
    $dlg.Controls.Add($rt)

    $pv = @($result.Preview)
    if ($pv.Count -eq 0) {
        Add-RtLine $rt '没有需要变更的项目' $script:C_GREEN 11 $true
        Add-RtLine $rt '' $script:C_DIM 6
        Add-RtLine $rt '所选项目当前均已处于推荐值，无需重复应用。' $script:C_SUB 9.5
    } else {
        Add-RtLine $rt "共 $($pv.Count) 项将被修改" $script:C_CYAN 11 $true
        Add-RtLine $rt '' $script:C_DIM 6
        foreach ($p in $pv) {
            Add-RtLine $rt ("● " + [string]$p.Name) $script:C_TEXT 9.5 $true
            $line = "    当前: $($p.Current)    →    目标: $($p.Target)"
            if ($p.NeedsReboot) { $line += '    [需重启]' }
            Add-RtLine $rt $line $script:C_SUB 9
        }
    }
    if (@($result.Errors).Count -gt 0) {
        Add-RtLine $rt '' $script:C_DIM 6
        Add-RtLine $rt '预览中发现的问题' $script:C_ORANGE 10 $true
        foreach ($er in @($result.Errors)) {
            Add-RtLine $rt ("  - " + [string]$er.Name + ': ' + [string]$er.Message) $script:C_RED 9
        }
    }
    Add-RtLine $rt '' $script:C_DIM 6
    Add-RtLine $rt '* 部分项（HAGS / DRR / 网卡 / 核显 / 独显）需要重启后才能完全生效。' $script:C_DIM 8.5

    $btnCopy = New-Btn $dlg '复制预览' 592 566 100 34 ((TC 24 35 50)) $script:C_TEXT 9
    $btnCopy.Anchor = 'Bottom, Right'
    $btnClose = New-Btn $dlg '关闭' 704 566 116 34 $script:C_CYAN ((TC 4 20 26)) 9
    $btnClose.Anchor = 'Bottom, Right'
    $script:PreviewDlg = $dlg
    $btnClose.Add_Click({ try { $script:PreviewDlg.Close() } catch {} })
    $btnCopy.Add_Click({
        try {
            $txt = @()
            $txt += '变更预览'
            $cpv = @($script:PreviewResult.Preview)
            if ($cpv.Count -eq 0) {
                $txt += '没有需要变更的项目'
                $txt += '所选项目当前均已处于推荐值，无需重复应用。'
            } else {
                foreach ($p in $cpv) {
                    $txt += ("● " + $p.Name)
                    $txt += ("    当前: " + $p.Current + " -> 目标: " + $p.Target)
                }
            }
            [System.Windows.Forms.Clipboard]::SetText(($txt -join "`r`n"))
            Set-Status '预览已复制到剪贴板'
        } catch {}
    })
    $script:PreviewResult = $result
    if ($script:UI_SCALE -gt 1.0001) {
        try {
            $sc = [double]$script:UI_SCALE
            $dlg.Scale((New-Object Drawing.SizeF -ArgumentList @([single]$sc, [single]$sc)))
            $dlg.MinimumSize = New-Object Drawing.Size -ArgumentList @([int](720 * $sc), [int](520 * $sc))
            Set-Round $btnCopy ([int][Math]::Round(10 * $sc))
            Set-Round $btnClose ([int][Math]::Round(10 * $sc))
        } catch {}
    }
    $dlg.ShowDialog($form) | Out-Null
    $dlg.Dispose()
}

function Invoke-PreviewSelected {
    if ($script:UI.Busy) { return }
    $sel = @($O | Where-Object E)
    $note = '已勾选项'
    if (-not $sel.Count) {
        $sel = @($O | Where-Object { $_.R -eq 'low' -and (Get-ItemSnapshot $_).Status -ne 'na' })
        $note = '推荐项（当前没有勾选）'
    }
    if (-not $sel.Count) {
        [System.Windows.Forms.MessageBox]::Show($form, '当前没有可预览的优化项。', '预览', 'OK', 'Information') | Out-Null
        return
    }
    try {
        Set-Status "正在生成预览: $note ..."
        $r = Invoke-TxApply -Items $sel -DryRun
        Show-PreviewDialog $r
        Set-Status '预览完成（未写入系统）'
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '预览失败', 'OK', 'Warning') | Out-Null
        Set-Status '预览失败'
    }
}

function Invoke-ApplyItems($items, [string]$title) {
    if ($script:UI.Busy) { return }
    $sel = @($items)
    if (-not $sel.Count) {
        [System.Windows.Forms.MessageBox]::Show($form, '没有可应用的优化项。', $title, 'OK', 'Information') | Out-Null
        return
    }
    $rp = [bool]$script:UI.RestoreChk.Checked
    $msg = "即将应用 $($sel.Count) 项优化。`n`n改动前会自动生成 JSON 原值备份和 .reg 快照，可在「备份还原」中撤销。"
    if ($rp) { $msg += "`n`n已勾选：应用前创建系统还原点（可能需要 10-30 秒）。" }
    $msg += "`n`n部分项需要重启才能完全生效。是否继续？"
    $ans = [System.Windows.Forms.MessageBox]::Show($form, $msg, $title, 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }

    $script:UI.Busy = $true
    $script:Pump = $true
    $script:UI.BtnItemApply.Enabled = $false
    $script:UI.BtnItemPreview.Enabled = $false
    Set-Status '正在应用优化...'
    $ok = $false
    $summary = ''
    try {
        $r = Invoke-TxApply -Items $sel -Yes -RestorePoint:$rp
        $summary = "成功 $($r.Ok) 项，失败 $($r.Fail) 项"
        if ($r.Backup) { $summary += "`n备份: $($r.Backup)" }
        if ($r.RegDir) { $summary += "`n.reg 快照: $($r.RegDir)" }
        $errText = ''
        if (@($r.Errors).Count -gt 0) {
            $errText = "`n`n失败明细:`n"
            foreach ($er in @($r.Errors | Select-Object -First 6)) {
                $errText += "  - $($er.Name): $($er.Message)`n"
            }
        }
        $ok = ($r.Fail -eq 0)
        try { Refresh-Snapshot } catch {}
        $icon = 'Warning'
        if ($ok) { $icon = 'Information' }
        [System.Windows.Forms.MessageBox]::Show($form, "应用完成：$summary$errText`n提示：HAGS / DRR / 网卡 / 核显 / 独显项需要重启后生效。", "$title - 完成", 'OK', $icon) | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "应用失败:`n$($_.Exception.Message)", $title, 'OK', 'Error') | Out-Null
    } finally {
        $script:UI.Busy = $false
        $script:Pump = $false
        $script:UI.BtnItemApply.Enabled = $true
        $script:UI.BtnItemPreview.Enabled = $true
        Set-Status '就绪'
    }
}

function Invoke-ApplySelected {
    $sel = @($O | Where-Object E)
    Invoke-ApplyItems $sel '应用选中项'
}

function Invoke-QuickOptimize {
    $sel = @($O | Where-Object { $_.R -eq 'low' -and (Get-ItemSnapshot $_).Status -ne 'na' })
    Invoke-ApplyItems $sel '一键优化（推荐项）'
}

# ══════════════════════════════════════════════════════════
# 备份还原页
# ══════════════════════════════════════════════════════════
$bakPage = New-Page 'backup'
$script:UI.BakPage = $bakPage
$bw = $cw - 40
$bakHero = New-PageHero $bakPage 'BACKUP & RESTORE · REVERSIBLE' '备份还原' '原值备份 + .reg 快照 · 单项还原、最近一次撤销或全部回放' @(
    @{ V = '0'; T = '备份数量'; C = $script:C_TEXT },
    @{ V = '无'; T = '最近备份'; C = $script:C_SUB; S = 10 },
    @{ V = '0'; T = '.reg 快照'; C = $script:C_TEXT },
    @{ V = '无记录'; T = '上次应用'; C = $script:C_DIM; S = 10 }
)
$script:UI.BakHero = $bakHero.Card
$script:UI.BakCount = $bakHero.Values[0]
$script:UI.BakLatest = $bakHero.Values[1]
$script:UI.BakRegs = $bakHero.Values[2]
$script:UI.BakLast = $bakHero.Values[3]
$btnBakRestore = New-Btn $bakHero.Card '还原选中' 24 84 104 32 $heroBtnBg2 $script:C_TEXT 9
$btnBakLatest = New-Btn $bakHero.Card '还原最近' 136 84 104 32 $heroBtnBg2 $script:C_TEXT 9
$btnBakAll = New-Btn $bakHero.Card '全部还原' 248 84 104 32 ((TC 46 25 30)) $script:C_RED 9
$btnBakPoint = New-Btn $bakHero.Card '创建还原点' 360 84 112 32 $heroBtnBg2 $script:C_CYAN 9
$btnBakOpen = New-Btn $bakHero.Card '打开备份目录' 480 84 116 32 $heroBtnBg2 $script:C_SUB 9
$btnBakRefresh = New-Btn $bakHero.Card '刷新' 604 84 72 32 $heroBtnBg2 $script:C_SUB 9
$btnBakRestore.Add_Click({ Invoke-RestoreSelected })
$btnBakLatest.Add_Click({ Invoke-RestoreLatest })
$btnBakAll.Add_Click({ Invoke-RestoreAll })
$btnBakPoint.Add_Click({ Invoke-CreatePoint })
$btnBakOpen.Add_Click({ try { Start-Process explorer.exe -ArgumentList $BK } catch {} })
$btnBakRefresh.Add_Click({ Refresh-BackupList; Set-Status '备份列表已刷新' })

function Style-Grid($g) {
    $g.BackgroundColor = $script:C_PANEL
    $g.BorderStyle = 'None'
    $g.EnableHeadersVisualStyles = $false
    $g.ColumnHeadersBorderStyle = 'None'
    $g.ColumnHeadersDefaultCellStyle.BackColor = (TC 22 32 46)
    $g.ColumnHeadersDefaultCellStyle.ForeColor = $script:C_SUB
    $g.ColumnHeadersDefaultCellStyle.Font = F 8.5 $true
    $g.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding -ArgumentList @(6, 0, 6, 0)
    $g.ColumnHeadersHeight = 34
    $g.DefaultCellStyle.BackColor = $script:C_PANEL
    $g.DefaultCellStyle.ForeColor = $script:C_TEXT
    $g.DefaultCellStyle.SelectionBackColor = (TC 30 42 58)
    $g.DefaultCellStyle.SelectionForeColor = $script:C_TEXT
    $g.DefaultCellStyle.Font = F 9
    $g.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding -ArgumentList @(6, 0, 6, 0)
    $g.AlternatingRowsDefaultCellStyle.BackColor = (TC 16 21 31)
    $g.GridColor = (TC 28 38 54)
    $g.RowHeadersVisible = $false
    $g.AllowUserToAddRows = $false
    $g.AllowUserToDeleteRows = $false
    $g.AllowUserToResizeRows = $false
    $g.ReadOnly = $true
    $g.SelectionMode = 'FullRowSelect'
    $g.MultiSelect = $false
    $g.AutoSizeColumnsMode = 'Fill'
    $g.RowTemplate.Height = 30
    $g.CellBorderStyle = 'SingleHorizontal'
    try {
        $pi = [System.Windows.Forms.DataGridView].GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic')
        if ($pi) { $pi.SetValue($g, $true) }
    } catch {}
}

function Add-GridCol($g, [string]$name, [string]$header, [double]$weight, [int]$minW = 60, [string]$align = 'MiddleLeft') {
    $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.Name = $name
    $c.HeaderText = $header
    $c.FillWeight = $weight
    $c.MinimumWidth = $minW
    $c.SortMode = 'NotSortable'
    $c.DefaultCellStyle.Alignment = $align
    [void]$g.Columns.Add($c)
    return $c
}

$bakGrid = New-Object System.Windows.Forms.DataGridView
$bakGrid.Location = New-Object Drawing.Point -ArgumentList @(20, 158)
$bakGrid.Size = New-Object Drawing.Size -ArgumentList @(($cw - 40), 500)
$bakGrid.Anchor = 'Top, Bottom, Left, Right'
$bakPage.Controls.Add($bakGrid)
$script:UI.BakGrid = $bakGrid
Style-Grid $bakGrid
$null = Add-GridCol $bakGrid 'time' '备份时间' 1.15 140
$null = Add-GridCol $bakGrid 'file' '备份文件' 2.2 220
$null = Add-GridCol $bakGrid 'ver' '版本' 0.55 64 'MiddleCenter'
$null = Add-GridCol $bakGrid 'cnt' '记录数' 0.55 64 'MiddleCenter'
$null = Add-GridCol $bakGrid 'size' '大小' 0.6 72 'MiddleRight'
$bakGrid.Add_CellDoubleClick({
    param($s, $e)
    if ($e.RowIndex -ge 0) { Invoke-RestoreSelected }
})

function Refresh-BackupList {
    try {
        $g = $script:UI.BakGrid
        $g.Rows.Clear()
        $fs = @(Get-ChildItem $BK -Filter backup_*.json -EA 0 | Sort-Object LastWriteTime -Descending)
        foreach ($f in $fs) {
            $ver = ''; $cnt = 0
            try {
                $j = Get-Content -Raw -LiteralPath $f.FullName | ConvertFrom-Json
                $ver = [string]$j.Version
                $cnt = @($j.Records).Count
            } catch {}
            if (-not $ver) { $ver = '旧版' }
            $idx = $g.Rows.Add($f.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss'), $f.Name, $ver, $cnt, ("{0:N1} KB" -f ($f.Length / 1KB)))
            $g.Rows[$idx].Tag = $f.FullName
        }
        $script:UI.BakCount.Text = [string]$fs.Count
        if ($fs.Count -gt 0) { $script:UI.BakLatest.Text = $fs[0].LastWriteTime.ToString('MM-dd HH:mm') } else { $script:UI.BakLatest.Text = '无' }
        $regs = @(Get-ChildItem $BK -Directory -Filter 'reg_*' -EA 0).Count
        $script:UI.BakRegs.Text = [string]$regs
        $la = Get-TxPendingState
        if ($la) {
            $t = [string]$la.Time
            try { $t = ([datetime]$t).ToString('MM-dd HH:mm') } catch {}
            $script:UI.BakLast.Text = $t
            $script:UI.BakLast.ForeColor = $script:C_TEXT
        } else {
            $script:UI.BakLast.Text = '无记录'
            $script:UI.BakLast.ForeColor = $script:C_DIM
        }
        $script:UI.BackupDirty = $false
    } catch {
        Set-Status "备份列表读取失败: $($_.Exception.Message)"
    }
}

function Get-SelectedBackup {
    $g = $script:UI.BakGrid
    if ($g.SelectedRows.Count -eq 0) { return $null }
    $p = $g.SelectedRows[0].Tag
    if ($p) { return [string]$p }
    return $null
}

function Invoke-RestoreFile([string]$path, [string]$title) {
    if (-not $path) {
        [System.Windows.Forms.MessageBox]::Show($form, '请先在列表中选择一份备份。', $title, 'OK', 'Information') | Out-Null
        return
    }
    if (-not (Test-Path -LiteralPath $path)) {
        [System.Windows.Forms.MessageBox]::Show($form, "备份文件不存在:`n$path", $title, 'OK', 'Warning') | Out-Null
        return
    }
    $name = Split-Path -Leaf $path
    $ans = [System.Windows.Forms.MessageBox]::Show($form, "将把 $name 中记录的原值写回系统。`n`n还原不覆盖之后手动做的其他改动，但会覆盖同名注册表值。是否继续？", $title, 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    $script:UI.Busy = $true
    $script:Pump = $true
    Set-Status "正在还原 $name ..."
    try {
        $r = Restore-TxBackupFile -Path $path
        $ver = '旧版'; if ($r.Version) { $ver = [string]$r.Version }
        $msg = "还原完成：成功 $($r.Ok) 项，失败 $($r.Fail) 项`n版本: $ver · 记录数: $($r.Records)"
        if (@($r.Errors).Count -gt 0) {
            $msg += "`n`n失败明细:"
            foreach ($er in @($r.Errors | Select-Object -First 6)) { $msg += "`n  - $($er.Id): $($er.Message)" }
        }
        $msg += "`n`n部分项（核显 / DRR / HAGS / 网卡 / 独显）需要重启后才完全恢复。"
        try { Refresh-Snapshot } catch {}
        Refresh-BackupList
        [System.Windows.Forms.MessageBox]::Show($form, $msg, "$title - 完成", 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "还原失败:`n$($_.Exception.Message)", $title, 'OK', 'Error') | Out-Null
    } finally {
        $script:UI.Busy = $false
        $script:Pump = $false
        Set-Status '就绪'
    }
}

function Invoke-RestoreSelected {
    if ($script:UI.Busy) { return }
    Invoke-RestoreFile (Get-SelectedBackup) '还原选中备份'
}

function Invoke-RestoreLatest {
    if ($script:UI.Busy) { return }
    $fs = @(Get-ChildItem $BK -Filter backup_*.json -EA 0 | Sort-Object LastWriteTime -Descending)
    if (-not $fs.Count) {
        [System.Windows.Forms.MessageBox]::Show($form, '当前没有可还原的备份。', '撤销上次优化', 'OK', 'Information') | Out-Null
        return
    }
    Invoke-RestoreFile $fs[0].FullName '撤销上次优化'
}

function Invoke-RestoreAll {
    if ($script:UI.Busy) { return }
    $fs = @(Get-ChildItem $BK -Filter backup_*.json -EA 0 | Sort-Object LastWriteTime -Descending)
    if (-not $fs.Count) {
        [System.Windows.Forms.MessageBox]::Show($form, '当前没有可还原的备份。', '全部还原', 'OK', 'Information') | Out-Null
        return
    }
    $msg = "将按时间倒序回放 $($fs.Count) 份备份，最终回到最早一次应用前的状态。`n`n这会覆盖之后由本工具做过的所有改动。是否继续？"
    $ans = [System.Windows.Forms.MessageBox]::Show($form, $msg, '全部还原', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    $script:UI.Busy = $true
    $script:Pump = $true
    Set-Status '正在回放全部备份...'
    try {
        $r = Restore-TxAll
        $msg = "全部还原完成：$($r.Files) 份备份，成功 $($r.Ok) 项，失败 $($r.Fail) 项"
        if (@($r.Errors).Count -gt 0) {
            $msg += "`n`n失败明细:"
            foreach ($er in @($r.Errors | Select-Object -First 8)) { $msg += "`n  - $($er.Id): $($er.Message)" }
        }
        try { Refresh-Snapshot } catch {}
        Refresh-BackupList
        [System.Windows.Forms.MessageBox]::Show($form, $msg, '全部还原 - 完成', 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "全部还原失败:`n$($_.Exception.Message)", '全部还原', 'OK', 'Error') | Out-Null
    } finally {
        $script:UI.Busy = $false
        $script:Pump = $false
        Set-Status '就绪'
    }
}

function Invoke-CreatePoint {
    if ($script:UI.Busy) { return }
    $script:UI.Busy = $true
    Set-Status '正在创建系统还原点（可能需要 10-30 秒）...'
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $r = New-TxRestorePoint
        if ($r.Ok) {
            [System.Windows.Forms.MessageBox]::Show($form, $r.Msg, '创建还原点', 'OK', 'Information') | Out-Null
        } else {
            [System.Windows.Forms.MessageBox]::Show($form, "未能创建还原点:`n$($r.Msg)", '创建还原点', 'OK', 'Warning') | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '创建还原点', 'OK', 'Warning') | Out-Null
    } finally {
        $script:UI.Busy = $false
        Set-Status '就绪'
    }
}

# ══════════════════════════════════════════════════════════
# 游戏库页
# ══════════════════════════════════════════════════════════
$gamePage = New-Page 'game'
$script:UI.GamePage = $gamePage
$gamePage.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, 710)
$gameHero = New-PageHero $gamePage 'GAME LIBRARY · LOCAL FIRST' '游戏库' '自动识别 Steam / Epic 游戏，为单个游戏保存独立的优先级、核心与显卡偏好 · 只写本机，不联网' @(
    @{ V = '0'; T = '已识别'; C = $script:C_CYAN },
    @{ V = '0'; T = '已配置'; C = $script:C_GREEN },
    @{ V = '0'; T = '路径缺失'; C = $script:C_RED }
)
$script:UI.GameStatAll = $gameHero.Values[0]
$script:UI.GameStatCfg = $gameHero.Values[1]
$script:UI.GameStatBad = $gameHero.Values[2]

$btnGameScan = New-Btn $gameHero.Card '重新扫描' 24 84 96 32 $heroBtnBg2 $script:C_TEXT 9
$btnGameAdd = New-Btn $gameHero.Card '手动添加' 128 84 96 32 $heroBtnBg2 $script:C_TEXT 9
$btnGameFolder = New-Btn $gameHero.Card '打开游戏目录' 232 84 112 32 $heroBtnBg2 $script:C_SUB 9
$btnGameScan.Add_Click({ Refresh-GamePage $true })
$btnGameFolder.Add_Click({
    if (-not $script:GameSel) { return }
    try { Start-Process explorer.exe -ArgumentList ('/select,"' + [string]$script:GameSel.Exe + '"') } catch {}
})

$script:GameData = @()
$script:GameSel = $null
$script:GameSuppress = $false
$script:GameRefreshing = $false
$script:UI.GameDirty = $true
$script:GameCoreCount = 0

function Get-GameConfigText($gd) {
    if (-not $gd -or -not $gd.Profile -or -not $gd.Profile.HasSaved) { return '默认' }
    $a = New-Object System.Collections.ArrayList
    try {
        if ($gd.Profile.Priority -eq 'High') { [void]$a.Add('高优先') }
        elseif ($gd.Profile.Priority -eq 'AboveNormal') { [void]$a.Add('较高优先') }
        if ($gd.Profile.Affinity -eq 'Physical') { [void]$a.Add('限核') }
        if ($gd.Profile.FsOff) { [void]$a.Add('关全屏') }
        if ($gd.Profile.GpuHigh) { [void]$a.Add('独显') }
        if ($gd.Profile.RunAsAdmin) { [void]$a.Add('管理员') }
    } catch {}
    if ($a.Count -eq 0) { return '已记录' }
    return ($a -join ' · ')
}

function Set-GameMsg([string]$text, $color) {
    try {
        $lbl = $script:UI.GameMsg
        $lbl.Text = [string]$text
        if ($null -eq $color) { $color = $script:C_DIM }
        $lbl.ForeColor = $color
    } catch {}
}

function Get-GameProfileFromUi {
    $p = [PSCustomObject]@{
        Priority = 'Normal'; Affinity = 'All'; FsOff = $false; GpuHigh = $false
        RunAsAdmin = $false; Args = ''; HasSaved = $false
    }
    try {
        $pi = $script:UI.GamePrio.SelectedIndex
        if ($pi -eq 1) { $p.Priority = 'AboveNormal' }
        elseif ($pi -eq 2) { $p.Priority = 'High' }
        if ($script:UI.GameAff.SelectedIndex -eq 1) { $p.Affinity = 'Physical' }
        $p.FsOff = [bool]$script:UI.GameFs.Checked
        $p.GpuHigh = [bool]$script:UI.GameGpu.Checked
        $p.RunAsAdmin = [bool]$script:UI.GameAdmin.Checked
        $tb = $script:UI.GameArgs
        if ($tb -and $tb.Tag -and $tb.Tag.Active) { $p.Args = [string]$tb.Text }
    } catch {}
    return $p
}

function Show-GameEmpty {
    try {
        $script:UI.GameSel = $null
        foreach ($c in @($script:UI.GameDetailCtrls)) { try { $c.Visible = $false } catch {} }
        $script:UI.GameEmpty.Visible = $true
        $script:UI.GameEmpty.Text = "左侧选择一个游戏`r`n或点击「重新扫描」识别本机游戏库"
        $script:UI.GameEmpty.ForeColor = $script:C_DIM
    } catch {}
}

function Show-GameDetail($gd) {
    if (-not $gd) { Show-GameEmpty; return }
    $script:GameSel = $gd
    try {
        $script:UI.GameEmpty.Visible = $false
        foreach ($c in @($script:UI.GameDetailCtrls)) { $c.Visible = $true }
        $script:UI.GameName.Text = [string]$gd.Name
        $script:UI.GamePath.Text = [string]$gd.Exe
        $meta = "来源 $($gd.Source)"
        if ($gd.AppId) { $meta += " · AppId $($gd.AppId)" }
        if (-not $gd.Exists) {
            $meta += ' · 文件不存在'
            $script:UI.GameMeta.ForeColor = $script:C_RED
        } else {
            $script:UI.GameMeta.ForeColor = $script:C_SUB
        }
        if ([string]$gd.Source -eq '手动') { $meta += ' · 手动添加' }
        $script:UI.GameMeta.Text = $meta

        $pr = $gd.Profile
        $pi = 0
        if ($pr.Priority -eq 'AboveNormal') { $pi = 1 }
        elseif ($pr.Priority -eq 'High') { $pi = 2 }
        $script:UI.GamePrio.SelectedIndex = $pi
        $script:UI.GameAff.SelectedIndex = $(if ($pr.Affinity -eq 'Physical') { 1 } else { 0 })
        $script:UI.GameFs.Checked = [bool]$pr.FsOff
        $script:UI.GameGpu.Checked = [bool]$pr.GpuHigh
        $script:UI.GameAdmin.Checked = [bool]$pr.RunAsAdmin

        $tb = $script:UI.GameArgs
        $ph = [string]$tb.Tag.Placeholder
        if ([string]$pr.Args) {
            $tb.Tag.Active = $true
            $tb.Text = [string]$pr.Args
            $tb.ForeColor = $script:C_TEXT
        } else {
            $tb.Tag.Active = $false
            $tb.Text = $ph
            $tb.ForeColor = $script:C_DIM
        }

        $script:UI.GameBtnRemove.Visible = [bool]$gd.Manual
        $script:UI.GameBtnLaunch.Enabled = [bool]$gd.Exists
        $script:UI.GameBtnApply.Enabled = [bool]$gd.Exists
        Set-GameMsg '' $script:C_DIM
    } catch {}
}

function Refresh-GamePage([bool]$force) {
    if ($script:GameRefreshing) { return }
    $script:GameRefreshing = $true
    $oldExe = ''
    if ($script:GameSel) { $oldExe = [string]$script:GameSel.Exe }
    try {
        Set-Status '正在扫描本地游戏库...'
        [System.Windows.Forms.Application]::DoEvents()
        $games = @(Get-TxGames -Force:$force)
        $script:GameData = $games
        $script:GameSuppress = $true
        $g = $script:UI.GameGrid
        $g.Rows.Clear()
        foreach ($gd in $games) {
            $cfg = Get-GameConfigText $gd
            if (-not $gd.Exists) { $cfg = '路径缺失' }
            $idx = $g.Rows.Add([string]$gd.Name, [string]$gd.Source, $cfg)
            $g.Rows[$idx].Tag = [string]$gd.Exe
            if (-not $gd.Exists) { $g.Rows[$idx].DefaultCellStyle.ForeColor = $script:C_RED }
        }
        $script:GameSuppress = $false

        $cfgCount = 0; $badCount = 0
        foreach ($gd in $games) {
            if ($gd.Profile.HasSaved) { $cfgCount++ }
            if (-not $gd.Exists) { $badCount++ }
        }
        $script:UI.GameStatAll.Text = [string]$games.Count
        $script:UI.GameStatCfg.Text = [string]$cfgCount
        $script:UI.GameStatBad.Text = [string]$badCount

        if ($script:GameCoreCount -le 0) {
            try {
                $n = 0
                foreach ($cpu in @(Get-CimInstance -ClassName Win32_Processor -ErrorAction SilentlyContinue)) { $n += [int]$cpu.NumberOfCores }
                $script:GameCoreCount = $n
            } catch {}
        }
        try { $script:UI.GameAff.Items[1] = ("仅前 $($script:GameCoreCount) 个逻辑处理器") } catch {}

        $hit = $null
        if ($oldExe) {
            $hit = @($games | Where-Object { ([string]$_.Exe).ToLowerInvariant() -eq $oldExe.ToLowerInvariant() } | Select-Object -First 1)
        }
        if ($hit -and $hit.Count -gt 0) {
            Show-GameDetail $hit[0]
            for ($i = 0; $i -lt $g.Rows.Count; $i++) {
                if (([string]$g.Rows[$i].Tag).ToLowerInvariant() -eq $oldExe.ToLowerInvariant()) {
                    $g.Rows[$i].Selected = $true
                    $g.FirstDisplayedScrollingRowIndex = $i
                    break
                }
            }
        } elseif ($games.Count -gt 0) {
            Show-GameDetail $games[0]
            $g.Rows[0].Selected = $true
        } else {
            Show-GameEmpty
        }
        $script:UI.GameDirty = $false
        if ($games.Count -eq 0) { Set-Status '未识别到游戏，可手动添加可执行文件' }
        else { Set-Status "游戏库已刷新 · $($games.Count) 个游戏" }
    } catch {
        Set-Status "游戏库扫描失败: $($_.Exception.Message)"
        if ($Preview) { Write-Output "game_refresh_error=$($_.Exception.Message) at $($_.InvocationInfo.ScriptLineNumber)" }
    } finally {
        $script:GameSuppress = $false
        $script:GameRefreshing = $false
    }
}

$gameListCard = New-Card $gamePage 20 150 320 540 14 $script:C_PANEL $script:C_BORDER
$gameListCard.Anchor = 'Top, Bottom, Left'
$gameListTitle = New-SectionTitle $gameListCard '本地游戏' 16 14 300 10
$lblGameListSub = New-Label $gameListCard 'Steam · Epic · 手动添加' 16 34 300 18 8 $false $script:C_DIM

$gameGrid = New-Object System.Windows.Forms.DataGridView
$gameGrid.Location = New-Object Drawing.Point -ArgumentList @(16, 62)
$gameGrid.Size = New-Object Drawing.Size -ArgumentList @(288, 460)
$gameGrid.Anchor = 'Top, Bottom, Left, Right'
$gameListCard.Controls.Add($gameGrid)
$script:UI.GameGrid = $gameGrid
Style-Grid $gameGrid
$null = Add-GridCol $gameGrid 'name' '游戏' 2.2 120
$null = Add-GridCol $gameGrid 'src' '来源' 0.7 56 'MiddleCenter'
$null = Add-GridCol $gameGrid 'cfg' '配置' 1.1 70 'MiddleCenter'

$gameGrid.Add_SelectionChanged({
    if ($script:GameSuppress) { return }
    try {
        $g = $script:UI.GameGrid
        if ($g.SelectedRows.Count -eq 0) { Show-GameEmpty; return }
        $exe = [string]$g.SelectedRows[0].Tag
        $hit = @($script:GameData | Where-Object { ([string]$_.Exe) -eq $exe } | Select-Object -First 1)
        if ($hit.Count -gt 0) { Show-GameDetail $hit[0] }
    } catch {}
})

$gameDetailCard = New-Card $gamePage 352 150 ($cw - 372) 540 14 $script:C_PANEL $script:C_BORDER
$gameDetailCard.Anchor = 'Top, Bottom, Left, Right'
$script:UI.GameDetailCard = $gameDetailCard

$script:UI.GameEmpty = New-Label $gameDetailCard '' 30 150 ($cw - 432) 80 11 $false $script:C_DIM 'MiddleCenter'
$script:UI.GameEmpty.Anchor = 'Top, Left, Right'

$script:UI.GameName = New-Label $gameDetailCard '' 24 16 ($cw - 420) 32 15 $true $script:C_TEXT
$script:UI.GameName.Anchor = 'Top, Left, Right'
$script:UI.GamePath = New-Label $gameDetailCard '' 24 50 ($cw - 420) 18 8 $false $script:C_DIM
$script:UI.GamePath.Anchor = 'Top, Left, Right'
$script:UI.GameMeta = New-Label $gameDetailCard '' 24 70 ($cw - 420) 18 8 $false $script:C_SUB
$script:UI.GameMeta.Anchor = 'Top, Left, Right'

$gameComboW = [Math]::Max(140, [Math]::Min(360, ($cw - 550)))
$gameArgsW = $gameComboW
$gameSecRun = New-SectionTitle $gameDetailCard '运行设置' 24 100 200 10
$lblGamePrio = New-Label $gameDetailCard '进程优先级' 24 138 84 26 9 $false $script:C_SUB
$script:UI.GamePrio = New-Combo $gameDetailCard 116 134 $gameComboW
$script:UI.GamePrio.Items.AddRange([string[]]@('正常', '高于正常', '高'))
$script:UI.GamePrio.SelectedIndex = 0
$lblGameAff = New-Label $gameDetailCard '核心亲和性' 24 174 84 26 9 $false $script:C_SUB
$script:UI.GameAff = New-Combo $gameDetailCard 116 170 $gameComboW
$script:UI.GameAff.Items.AddRange([string[]]@('全部核心', '仅前 N 个逻辑处理器'))
$script:UI.GameAff.SelectedIndex = 0

$script:UI.GameFs = New-Check $gameDetailCard '关闭全屏优化（写入 AppCompatFlags）' 24 208 320 26
$script:UI.GameGpu = New-Check $gameDetailCard '优先使用高性能显卡（独显）' 24 238 320 26
$script:UI.GameAdmin = New-Check $gameDetailCard '以管理员身份启动' 24 268 320 26
$lblGameArgs = New-Label $gameDetailCard '启动参数' 24 304 84 22 9 $false $script:C_SUB
$script:UI.GameArgs = New-TextBox $gameDetailCard 116 300 $gameArgsW 30 '可选，例如 -dx11 -novid'
$script:UI.GameArgs.Anchor = 'Top, Left, Right'

$script:UI.GameBtnApply = New-Btn $gameDetailCard '保存并应用' 24 348 104 34 $script:C_GREEN ((TC 6 22 13)) 9
$script:UI.GameBtnLaunch = New-Btn $gameDetailCard '启动游戏' 134 348 88 34 $script:C_PANEL2 $script:C_TEXT 9
$script:UI.GameBtnRestore = New-Btn $gameDetailCard '恢复原值' 228 348 88 34 $script:C_PANEL2 $script:C_SUB 9
$script:UI.GameBtnRemove = New-Btn $gameDetailCard '移除手动添加' 322 348 100 34 $script:C_PANEL2 $script:C_RED 9

$script:UI.GameMsg = New-Label $gameDetailCard '' 24 392 ($cw - 420) 40 8.5 $false $script:C_DIM
$script:UI.GameMsg.Anchor = 'Top, Left, Right'
$lblGameNote = New-Label $gameDetailCard '说明：全屏优化与显卡偏好写入当前用户注册表，点击「恢复原值」会写回首次配置前的状态；优先级与核心亲和性仅在本次启动时生效，不常驻。' 24 436 ($cw - 440) 56 8 $false $script:C_DIM
$lblGameNote.Anchor = 'Top, Left, Right'

$script:UI.GameDetailCtrls = @(
    $script:UI.GameName, $script:UI.GamePath, $script:UI.GameMeta,
    $gameSecRun, $lblGamePrio, $script:UI.GamePrio, $lblGameAff, $script:UI.GameAff,
    $script:UI.GameFs, $script:UI.GameGpu, $script:UI.GameAdmin,
    $lblGameArgs, $script:UI.GameArgs,
    $script:UI.GameBtnApply, $script:UI.GameBtnLaunch, $script:UI.GameBtnRestore, $script:UI.GameBtnRemove,
    $script:UI.GameMsg, $lblGameNote
)
foreach ($c in @($script:UI.GameDetailCtrls)) { try { $c.Visible = $false } catch {} }

$script:UI.GameBtnApply.Add_Click({
    if (-not $script:GameSel) { return }
    try {
        $p = Get-GameProfileFromUi
        $null = Save-TxGameProfile ([string]$script:GameSel.Exe) $p
        $r = Apply-TxGameProfile ([string]$script:GameSel.Exe) $p
        if ($r.Ok) {
            Set-GameMsg ("$($script:GameSel.Name) 的配置已保存并应用 · $(Get-GameConfigText $p)") $script:C_GREEN
            Refresh-GamePage $false
        } else {
            Set-GameMsg "应用失败: $($r.Msg)" $script:C_RED
        }
    } catch { Set-GameMsg "保存失败: $($_.Exception.Message)" $script:C_RED }
})

$script:UI.GameBtnLaunch.Add_Click({
    if (-not $script:GameSel) { return }
    try {
        $p = Get-GameProfileFromUi
        $r = Start-TxGame ([string]$script:GameSel.Exe) $p
        if ($r.Ok) { Set-GameMsg "已启动: $($r.Msg)" $script:C_GREEN }
        else { Set-GameMsg "启动失败: $($r.Msg)" $script:C_RED }
    } catch { Set-GameMsg "启动失败: $($_.Exception.Message)" $script:C_RED }
})

$script:UI.GameBtnRestore.Add_Click({
    if (-not $script:GameSel) { return }
    $ans = [System.Windows.Forms.MessageBox]::Show($form, "将把 $($script:GameSel.Name) 的全屏优化与显卡偏好恢复为首次配置前的值，并删除保存的配置。是否继续？", '恢复原值', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    try {
        $r = Remove-TxGameProfile ([string]$script:GameSel.Exe)
        if ($r.Ok) {
            Set-GameMsg "已恢复: $($r.Msg)" $script:C_GREEN
            Refresh-GamePage $false
        } else { Set-GameMsg "恢复失败: $($r.Msg)" $script:C_RED }
    } catch { Set-GameMsg "恢复失败: $($_.Exception.Message)" $script:C_RED }
})

$script:UI.GameBtnRemove.Add_Click({
    if (-not $script:GameSel -or -not $script:GameSel.Manual) { return }
    $ans = [System.Windows.Forms.MessageBox]::Show($form, "将从游戏库移除手动添加的 $($script:GameSel.Name)，并恢复它已应用的注册表项。是否继续？", '移除游戏', 'YesNo', 'Warning')
    if ($ans -ne 'Yes') { return }
    try {
        $null = Remove-TxGameProfile ([string]$script:GameSel.Exe)
        Remove-TxManualGame ([string]$script:GameSel.Exe)
        Set-GameMsg '已从游戏库移除' $script:C_SUB
        $script:GameSel = $null
        Refresh-GamePage $false
    } catch { Set-GameMsg "移除失败: $($_.Exception.Message)" $script:C_RED }
})

$btnGameAdd.Add_Click({
    try {
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = '选择游戏可执行文件'
        $dlg.Filter = '可执行文件 (*.exe)|*.exe|所有文件 (*.*)|*.*'
        $dlg.CheckFileExists = $true
        if ($dlg.ShowDialog($form) -ne 'OK') { return }
        $exe = [string]$dlg.FileName
        $def = [IO.Path]::GetFileNameWithoutExtension($exe)
        $name = Show-InputDialog '添加到游戏库' '显示名称' $def
        if (-not $name) { $name = $def }
        $null = Add-TxManualGame ([string]$name) $exe
        Refresh-GamePage $true
        Set-Status "已添加游戏: $name"
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "添加失败:`n$($_.Exception.Message)", '游戏库', 'OK', 'Error') | Out-Null
    }
})

Show-GameEmpty

# ══════════════════════════════════════════════════════════
# 诊断报告页
# ══════════════════════════════════════════════════════════
$diagPage = New-Page 'diag'
$script:UI.DiagPage = $diagPage
$diagHero = New-PageHero $diagPage 'SYSTEM DIAGNOSTICS · READ ONLY' '诊断报告' 'VBS/HVCI、内存、PCIe、NVMe、电源与显示链路 · 只读采集，不修改系统' @(
    @{ V = '0'; T = '正常'; C = $script:C_GREEN },
    @{ V = '0'; T = '注意'; C = $script:C_ORANGE },
    @{ V = '0'; T = '风险'; C = $script:C_RED }
)
$script:UI.DiagHero = $diagHero.Card
$btnDiagRefresh = New-Btn $diagHero.Card '刷新诊断' 24 84 104 32 $heroBtnBg2 $script:C_TEXT 9
$btnDiagExport = New-Btn $diagHero.Card '导出报告' 136 84 104 32 $heroBtnBg2 $script:C_CYAN 9
$btnDiagCopy = New-Btn $diagHero.Card '复制全部' 248 84 104 32 $heroBtnBg2 $script:C_SUB 9
$btnDiagBundle = New-Btn $diagHero.Card '导出诊断包' 360 84 118 32 $heroBtnBg2 $script:C_CYAN 9
$btnDiagRefresh.Add_Click({ Refresh-Diag $true })
$btnDiagBundle.Add_Click({
    if ($script:UI.Busy) {
        [System.Windows.Forms.MessageBox]::Show($form, '正在应用或还原，请等待当前操作完成。', '导出诊断包', 'OK', 'Information') | Out-Null
        return
    }
    try {
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Title = '导出诊断包'
        $dlg.Filter = 'ZIP 压缩包 (*.zip)|*.zip'
        $dlg.DefaultExt = 'zip'
        $dlg.AddExtension = $true
        $dlg.FileName = '诊断包_' + (Get-Date).ToString('yyyyMMdd_HHmmss') + '.zip'
        try { if (Test-Path -LiteralPath $TX_DIAG) { $dlg.InitialDirectory = $TX_DIAG } } catch {}
        if ($dlg.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        $script:UI.Busy = $true
        Set-Status '正在生成诊断包（dxdiag 可能需要 10-30 秒）...'
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::WaitCursor
        [System.Windows.Forms.Application]::DoEvents()
        $tmp = Join-Path $env:TEMP ('txdiagui_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        try {
            $zip = Export-TxDiagnosticBundle -OutDir $tmp
            if (-not $zip -or -not (Test-Path -LiteralPath $zip)) { throw '诊断包生成失败' }
            Move-Item -LiteralPath $zip -Destination $dlg.FileName -Force
            Set-Status "诊断包已导出: $($dlg.FileName)"
            $ans = [System.Windows.Forms.MessageBox]::Show($form, "诊断包已导出：`n$($dlg.FileName)`n`n内容包含系统信息、dxdiag、驱动列表、最近 24 小时错误事件、优化状态与本机配置。`n`n是否打开所在文件夹？", '导出诊断包 - 完成', 'YesNo', 'Information')
            if ($ans -eq 'Yes') { try { Start-Process explorer.exe -ArgumentList ('/select,"' + $dlg.FileName + '"') } catch {} }
        } finally {
            try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
            [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
            $script:UI.Busy = $false
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "导出诊断包失败:`n$($_.Exception.Message)", '导出诊断包', 'OK', 'Warning') | Out-Null
        Set-Status '诊断包导出失败'
    } finally {
        [System.Windows.Forms.Cursor]::Current = [System.Windows.Forms.Cursors]::Default
        $script:UI.Busy = $false
    }
})
$btnDiagExport.Add_Click({
    try {
        Set-Status '正在导出报告...'
        [System.Windows.Forms.Application]::DoEvents()
        $p = Export-TxReport
        Set-Status "报告已导出: $p"
        [System.Windows.Forms.MessageBox]::Show($form, "报告已导出:`n$p", '导出报告', 'OK', 'Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, $_.Exception.Message, '导出报告', 'OK', 'Warning') | Out-Null
    }
})
$btnDiagCopy.Add_Click({
    try {
        $t = @()
        foreach ($row in $script:UI.DiagGrid.Rows) {
            if ($row.IsNewRow) { continue }
            $t += ("{0} | {1} | {2} | {3} | {4}" -f $row.Cells[0].Value, $row.Cells[1].Value, $row.Cells[2].Value, $row.Cells[3].Value, $row.Cells[4].Value)
        }
        [System.Windows.Forms.Clipboard]::SetText(($t -join "`r`n"))
        Set-Status '诊断结果已复制到剪贴板'
    } catch {}
})
$script:UI.DiagOk = $diagHero.Values[0]
$script:UI.DiagWarn = $diagHero.Values[1]
$script:UI.DiagBad = $diagHero.Values[2]

$diagGrid = New-Object System.Windows.Forms.DataGridView
$diagGrid.Location = New-Object Drawing.Point -ArgumentList @(20, 158)
$diagGrid.Size = New-Object Drawing.Size -ArgumentList @(($cw - 40), 540)
$diagGrid.Anchor = 'Top, Bottom, Left, Right'
$diagPage.Controls.Add($diagGrid)
$script:UI.DiagGrid = $diagGrid
Style-Grid $diagGrid
$diagGrid.AutoSizeRowsMode = 'AllCellsExceptHeaders'
$diagGrid.DefaultCellStyle.WrapMode = 'True'
$null = Add-GridCol $diagGrid 'grp' '分组' 0.55 66 'MiddleCenter'
$null = Add-GridCol $diagGrid 'name' '项目' 1.5 150
$null = Add-GridCol $diagGrid 'val' '数值' 3.0 220
$null = Add-GridCol $diagGrid 'lvl' '级别' 0.55 60 'MiddleCenter'
$null = Add-GridCol $diagGrid 'hint' '建议' 1.8 160

function Refresh-Diag([bool]$manual = $false) {
    try {
        Set-Status '正在读取诊断信息...'
        [System.Windows.Forms.Application]::DoEvents()
        $diag = @(Get-TxDiagnostics)
        $g = $script:UI.DiagGrid
        $g.Rows.Clear()
        $ok = 0; $warn = 0; $bad = 0
        foreach ($x in $diag) {
            $lvl = '信息'; $cl = $script:C_SUB
            if ($x.Level -eq 'Green') { $lvl = '正常'; $cl = $script:C_GREEN; $ok++ }
            elseif ($x.Level -eq 'Yellow') { $lvl = '注意'; $cl = $script:C_ORANGE; $warn++ }
            elseif ($x.Level -eq 'Red') { $lvl = '风险'; $cl = $script:C_RED; $bad++ }
            $idx = $g.Rows.Add([string]$x.Group, [string]$x.Name, [string]$x.Value, $lvl, [string]$x.Hint)
            $g.Rows[$idx].DefaultCellStyle.ForeColor = $cl
        }
        $script:UI.DiagOk.Text = [string]$ok
        $script:UI.DiagWarn.Text = [string]$warn
        $script:UI.DiagBad.Text = [string]$bad
        $script:UI.DiagDirty = $false
        Set-Status "诊断完成: 正常 $ok / 注意 $warn / 风险 $bad"
    } catch {
        Set-Status "诊断失败: $($_.Exception.Message)"
    }
}

# ══════════════════════════════════════════════════════════
# 启动项页 (只读)
# ══════════════════════════════════════════════════════════
$startupPage = New-Page 'startup'
$script:UI.StartupPage = $startupPage
$startupPage.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, 980)
$startupHero = New-PageHero $startupPage 'STARTUP & BACKGROUND · READ ONLY' '启动项与后台程序' '查看开机自启项和当前占用内存较多的后台进程 · 只读，不提供一键禁用' @(
    @{ V = '0'; T = '启动项'; C = $script:C_CYAN },
    @{ V = '0'; T = '后台进程'; C = $script:C_SUB },
    @{ V = '0'; T = '占用内存 MB'; C = $script:C_ORANGE }
)
$script:UI.StartupStatItems = $startupHero.Values[0]
$script:UI.StartupStatProcs = $startupHero.Values[1]
$script:UI.StartupStatMem = $startupHero.Values[2]
$btnStartupRefresh = New-Btn $startupHero.Card '刷新列表' 24 84 104 32 $script:C_CYAN ((TC 4 20 26)) 9
$btnStartupTask = New-Btn $startupHero.Card '任务管理器' 136 84 104 32 $heroBtnBg2 $script:C_TEXT 9
$btnStartupSettings = New-Btn $startupHero.Card '启动应用设置' 248 84 112 32 $heroBtnBg2 $script:C_SUB 9
$btnStartupRefresh.Add_Click({ Refresh-StartupPage })
$btnStartupTask.Add_Click({ try { Start-Process 'taskmgr.exe' } catch {} })
$btnStartupSettings.Add_Click({ try { Start-Process 'ms-settings:startupapps' } catch {} })

$startupCard = New-Card $startupPage 20 150 ($cw - 40) 320 14 $script:C_PANEL $script:C_BORDER
$startupCard.Anchor = 'Top, Left, Right'
$null = New-SectionTitle $startupCard '开机启动项' 16 14 260 10
$null = New-Label $startupCard '注册表 Run / RunOnce 与启动文件夹 · 只读展示' 16 34 520 18 8 $false $script:C_DIM
$startupGrid = New-Object System.Windows.Forms.DataGridView
$startupGrid.Location = New-Object Drawing.Point -ArgumentList @(16, 58)
$startupGrid.Size = New-Object Drawing.Size -ArgumentList @(($cw - 72), 242)
$startupGrid.Anchor = 'Top, Left, Right'
$startupCard.Controls.Add($startupGrid)
$script:UI.StartupGrid = $startupGrid
Style-Grid $startupGrid
$null = Add-GridCol $startupGrid 'name' '名称' 1.2 140
$null = Add-GridCol $startupGrid 'src' '来源' 0.8 110
$null = Add-GridCol $startupGrid 'cmd' '命令 / 路径' 3.4 320

$backCard = New-Card $startupPage 20 486 ($cw - 40) 360 14 $script:C_PANEL $script:C_BORDER
$backCard.Anchor = 'Top, Left, Right'
$null = New-SectionTitle $backCard '后台进程（按内存排序）' 16 14 300 10
$null = New-Label $backCard '只展示占用内存较高的前 40 个进程 · 结束进程请使用任务管理器' 16 34 560 18 8 $false $script:C_DIM
$backGrid = New-Object System.Windows.Forms.DataGridView
$backGrid.Location = New-Object Drawing.Point -ArgumentList @(16, 58)
$backGrid.Size = New-Object Drawing.Size -ArgumentList @(($cw - 72), 282)
$backGrid.Anchor = 'Top, Left, Right'
$backCard.Controls.Add($backGrid)
$script:UI.BackGrid = $backGrid
Style-Grid $backGrid
$null = Add-GridCol $backGrid 'name' '进程' 1.2 140
$null = Add-GridCol $backGrid 'title' '窗口标题' 2.6 240
$null = Add-GridCol $backGrid 'pid' 'PID' 0.5 64 'MiddleCenter'
$null = Add-GridCol $backGrid 'mem' '内存' 0.6 84 'MiddleRight'

$startupNoteCard = New-Card $startupPage 20 862 ($cw - 40) 86 14 $script:C_PANEL $script:C_BORDER
$startupNoteCard.Anchor = 'Top, Left, Right'
$null = New-SectionTitle $startupNoteCard '为什么不做一键禁用' 16 13 280 10
$null = New-Label $startupNoteCard '· 启动项属于系统配置，不同厂商的启动器与安全软件行为差异很大，误禁用可能导致驱动面板、输入法或同步工具失效。' 16 38 ($cw - 72) 18 8.5 $false $script:C_DIM
$null = New-Label $startupNoteCard '· 需要调整时，请使用 Windows 设置 → 应用 → 启动，或任务管理器 → 启动应用；本页只负责帮你看清现状。' 16 58 ($cw - 72) 18 8.5 $false $script:C_DIM

$script:UI.StartupDirty = $true

function Refresh-StartupPage {
    try {
        Set-Status '正在读取启动项与后台进程...'
        [System.Windows.Forms.Application]::DoEvents()
        $items = @(Get-TxStartupEntries)
        $procs = @(Get-TxBackgroundProcesses -Top 40 | Sort-Object MemMB -Descending)

        $sg = $script:UI.StartupGrid
        $sg.Rows.Clear()
        foreach ($it in $items) {
            $idx = $sg.Rows.Add([string]$it.Name, [string]$it.Source, [string]$it.Command)
            $sg.Rows[$idx].Tag = [string]$it.Location
        }

        $bg = $script:UI.BackGrid
        $bg.Rows.Clear()
        $memSum = 0.0
        foreach ($p in $procs) {
            $memSum += [double]$p.MemMB
            $idx = $bg.Rows.Add([string]$p.Name, [string]$p.Title, [string]$p.Id, ("{0:N0} MB" -f [double]$p.MemMB))
            $bg.Rows[$idx].Tag = [int]$p.Id
            if ($p.Foreground) { $bg.Rows[$idx].Cells[1].Style.ForeColor = $script:C_TEXT }
            else { $bg.Rows[$idx].Cells[1].Style.ForeColor = $script:C_DIM }
        }

        $script:UI.StartupStatItems.Text = [string]$items.Count
        $script:UI.StartupStatProcs.Text = [string]$procs.Count
        $script:UI.StartupStatMem.Text = ("{0:N0}" -f $memSum)
        $script:UI.StartupDirty = $false
        Set-Status "启动项 $($items.Count) 个 · 后台进程 $($procs.Count) 个"
    } catch {
        Set-Status "读取启动项失败: $($_.Exception.Message)"
    }
}

# ══════════════════════════════════════════════════════════
# 运行日志页
# ══════════════════════════════════════════════════════════
$logPage = New-Page 'log'
$script:UI.LogPage = $logPage
$logHero = New-PageHero $logPage 'RUNTIME LOG · LOCAL ONLY' '运行日志' '仅记录本机操作与结果 · 不联网、不上传' @(
    @{ V = '0'; T = '日志行数'; C = $script:C_SUB }
)
$script:UI.LogHero = $logHero.Card
$script:UI.LogTool = $logHero.Card
$script:UI.LogCount = $logHero.Values[0]
$btnLogClear = New-Btn $logHero.Card '清空界面' 24 84 96 32 $heroBtnBg2 $script:C_TEXT 9
$btnLogOpen = New-Btn $logHero.Card '打开日志文件' 128 84 116 32 $heroBtnBg2 $script:C_CYAN 9
$btnLogDir = New-Btn $logHero.Card '打开脚本目录' 252 84 116 32 $heroBtnBg2 $script:C_SUB 9
$btnLogCopy = New-Btn $logHero.Card '复制日志' 376 84 96 32 $heroBtnBg2 $script:C_SUB 9
$chkLogAuto = New-Check $logHero.Card '自动滚动' 484 88 96 24 $true
$script:UI.LogAuto = $chkLogAuto
$btnLogClear.Add_Click({ try { $script:UI.LogBox.Items.Clear(); $script:UI.LogCount.Text = '0' } catch {} })
$btnLogOpen.Add_Click({
    try {
        if (Test-Path -LiteralPath $LOG) { Start-Process $LOG }
        else { Start-Process explorer.exe -ArgumentList $BK }
    } catch {}
})
$btnLogDir.Add_Click({ try { Start-Process explorer.exe -ArgumentList $SD } catch {} })
$btnLogCopy.Add_Click({
    try {
        $t = @($script:UI.LogBox.Items | ForEach-Object { $_.ToString() })
        [System.Windows.Forms.Clipboard]::SetText(($t -join "`r`n"))
        Set-Status '日志已复制到剪贴板'
    } catch {}
})

$logBox = New-Object System.Windows.Forms.ListBox
$logBox.Location = New-Object Drawing.Point -ArgumentList @(20, 158)
$logBox.Size = New-Object Drawing.Size -ArgumentList @(($cw - 40), 540)
$logBox.Anchor = 'Top, Bottom, Left, Right'
$logBox.BackColor = $script:C_PANEL
$logBox.ForeColor = $script:C_TEXT
$logBox.BorderStyle = 'None'
$logBox.DrawMode = 'OwnerDrawFixed'
$logBox.ItemHeight = 22
$logBox.IntegralHeight = $false
$logBox.HorizontalScrollbar = $false
$logBox.Font = New-Object Drawing.Font -ArgumentList @('Consolas', [single]9.5)
$logBox.Add_DrawItem({
    param($s, $e)
    if ($e.Index -lt 0) { return }
    try {
        $it = $s.Items[$e.Index]
        $bg = $script:C_PANEL
        if (($e.Index % 2) -eq 1) { $bg = (TC 15 20 30) }
        if (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0) { $bg = (TC 24 35 50) }
        $br = New-Object Drawing.SolidBrush -ArgumentList @($bg)
        $e.Graphics.FillRectangle($br, $e.Bounds)
        $br.Dispose()
        $sc = [double]$script:UI_SCALE
        $tr = New-Object Drawing.Rectangle -ArgumentList @(($e.Bounds.X + 10 * $sc), $e.Bounds.Y, ($e.Bounds.Width - 12 * $sc), $e.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$it.Text, $s.Font, $tr, $it.Color,
            [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
    } catch {}
})
$logPage.Controls.Add($logBox)
$script:UI.LogBox = $logBox

function Get-LogColor([string]$c) {
    switch ($c) {
        'Green'    { return $script:C_GREEN }
        'Red'      { return $script:C_RED }
        'Yellow'   { return $script:C_ORANGE }
        'Cyan'     { return $script:C_CYAN }
        'White'    { return $script:C_TEXT }
        'DarkGray' { return $script:C_DIM }
        default    { return $script:C_SUB }
    }
}

function Append-LogLine([string]$line, [string]$color) {
    try {
        $lb = $script:UI.LogBox
        if (-not $lb) { return }
        $col = Get-LogColor $color
        $item = New-Object TxUi.LogItem -ArgumentList @([string]$line, $col)
        [void]$lb.Items.Add($item)
        if ($lb.Items.Count -gt 2000) { $lb.Items.RemoveAt(0) }
        if ($script:UI.LogCount) { $script:UI.LogCount.Text = [string]$lb.Items.Count }
        if ($script:UI.LogAuto.Checked) { $lb.TopIndex = [Math]::Max(0, $lb.Items.Count - 1) }
    } catch {}
}

$script:LogSink = {
    param($line, $color)
    Append-LogLine $line $color
    if ($script:UI.Busy) { Set-Status ([string]$line) }
}
foreach ($lb in @($script:LogBuffer)) { Append-LogLine $lb.Line $lb.Color }
Append-LogLine "[引擎] 游戏性能优化脚本 v$($script:AppVersion) 已加载 · 共 $($O.Count) 项优化" 'DarkGray'
$script:GpuShort = (@($script:Snap.Gpus | ForEach-Object { $t = '核显'; if ($_.Dedicated) { $t = '独显' }; if ($_.Basic) { $t = '基础显示' }; "$($_.Name)[$t]" }) -join ' + ')
Append-LogLine "[硬件] $($script:MachineTxt) · $($script:GpuShort)" 'DarkGray'
if ([int]$script:Snap.Summary.Checking -gt 0) {
    Append-LogLine '[状态] 正在检测优化项状态，窗口显示后自动完成...' 'DarkGray'
} else {
    Append-LogLine "[状态] 已生效 $($script:Snap.Summary.Applied) · 待应用 $($script:Snap.Summary.Pending) · 不适用 $($script:Snap.Summary.NotApplicable)" 'DarkGray'
}
Append-LogLine "[界面] 可视化控制台已就绪 · 所有改动均可还原" 'Cyan'

# ══════════════════════════════════════════════════════════
# 关于页
# ══════════════════════════════════════════════════════════
$aboutPage = New-Page 'about'
$script:UI.AboutPage = $aboutPage
$aboutPage.AutoScroll = $false
$aboutHero = New-PageHero $aboutPage 'ABOUT · TIANXI PERFORMANCE LAB' '关于' '核显 / 独显 / 混合显卡 · 本地运行 · 不上传数据'
$script:UI.AboutHero = $aboutHero.Card
$btnAboutUpdate = New-Btn $aboutHero.Card '检查更新' 24 84 110 32 $heroBtnBg2 $script:C_CYAN 9
$script:UI.BtnAboutUpdate = $btnAboutUpdate
$lblAboutVer = New-Label $aboutHero.Card "当前版本 v$($script:AppVersion) · 发布源 GitHub Releases" 146 88 460 24 8.5 $false $script:C_SUB
$btnAboutUpdate.Add_Click({ Invoke-CheckUpdate })
$aboutBadges = @(
    @{ T='核显兼容' },
    @{ T='独显优化' },
    @{ T='混合显卡' },
    @{ T='双重备份' },
    @{ T='只读诊断' },
    @{ T='本地运行' }
)
$bx = 20
foreach ($ab in $aboutBadges) {
    $null = New-Badge $aboutPage $ab.T $bx 150 92 24 $script:C_GRAY_BG $script:C_GRAY_BD $script:C_SUB 8
    $bx += 100
}
$aboutBox = New-Object System.Windows.Forms.ListBox
$aboutBox.Location = New-Object Drawing.Point -ArgumentList @(20, 190)
$aboutBox.Size = New-Object Drawing.Size -ArgumentList @(($cw - 40), 430)
$aboutBox.Anchor = 'Top, Bottom, Left, Right'
$aboutBox.BackColor = $script:C_PANEL
$aboutBox.ForeColor = $script:C_TEXT
$aboutBox.BorderStyle = 'None'
$aboutBox.DrawMode = 'OwnerDrawFixed'
$aboutBox.ItemHeight = 22
$aboutBox.IntegralHeight = $false
$aboutBox.HorizontalScrollbar = $false
$aboutBox.SelectionMode = 'None'
$aboutBox.Font = F 9.2
$script:AboutBoldFont = F 10 $true
$aboutBox.Add_DrawItem({
    param($s, $e)
    if ($e.Index -lt 0) { return }
    try {
        $it = $s.Items[$e.Index]
        $bg = $script:C_PANEL
        if (($e.Index % 2) -eq 1) { $bg = (TC 15 20 30) }
        $br = New-Object Drawing.SolidBrush -ArgumentList @($bg)
        $e.Graphics.FillRectangle($br, $e.Bounds)
        $br.Dispose()
        $f = $s.Font
        if ($it.Bold) { $f = $script:AboutBoldFont }
        $sc = [double]$script:UI_SCALE
        $tr = New-Object Drawing.Rectangle -ArgumentList @(($e.Bounds.X + 8 * $sc), $e.Bounds.Y, ($e.Bounds.Width - 10 * $sc), $e.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$it.Text, $f, $tr, $it.Color,
            [System.Windows.Forms.TextFormatFlags]::NoPrefix -bor [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis)
    } catch {}
})
$aboutPage.Controls.Add($aboutBox)
$script:UI.AboutBox = $aboutBox
function Update-AboutLayout {
    try {
        $p = $script:UI.AboutPage
        if (-not $p) { return }
        $sc = [double]$script:UI_SCALE
        $top = [int][Math]::Round(190 * $sc)
        $bottom = [int][Math]::Round(88 * $sc)
        $h = $p.ClientSize.Height - $top - $bottom
        $minH = [int][Math]::Round(160 * $sc)
        if ($h -lt $minH) { $h = $minH }
        $script:UI.AboutBox.Height = $h
    } catch {}
}
$aboutPage.Add_Resize({
    if ($script:UiScaling) { return }
    Update-AboutLayout
})

# ★ 支持作者: 关于页底部入口, 内置赞赏码查看, 不依赖系统图片关联
$script:SupportImgPath = Join-Path $SD '赞赏码.png'
if (-not (Test-Path -LiteralPath $script:SupportImgPath)) {
    $script:SupportImgPath = Join-Path $PSScriptRoot '赞赏码.png'
}

function Show-SupportDialog {
    try {
        $imgPath = $script:SupportImgPath
        $dw = UiPx 400
        $dh = UiPx 500
        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = '支持作者'
        $dlg.FormBorderStyle = 'FixedDialog'
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $dlg.ShowIcon = $false
        $dlg.ShowInTaskbar = $false
        $dlg.StartPosition = 'CenterParent'
        $dlg.AutoScaleMode = 'None'
        $dlg.ClientSize = New-Object Drawing.Size -ArgumentList @($dw, $dh)
        $dlg.BackColor = $script:C_BG
        $dlg.ForeColor = $script:C_TEXT
        $dlg.Font = F 9
        $dlg.SuspendLayout()

        $null = New-Label $dlg '支持作者' (UiPx 24) (UiPx 20) (UiPx 352) (UiPx 28) 12 $true $script:C_TEXT
        $null = New-Label $dlg '如果这个工具帮到了你，可以扫码请作者喝一杯。' (UiPx 24) (UiPx 52) (UiPx 352) (UiPx 20) 9 $false $script:C_SUB

        $qrPanel = New-Object System.Windows.Forms.Panel
        $qrPanel.Location = New-Object Drawing.Point -ArgumentList @([int](($dw - (UiPx 250)) / 2), (UiPx 86))
        $qrPanel.Size = New-Object Drawing.Size -ArgumentList @((UiPx 250), (UiPx 250))
        $qrPanel.BackColor = [Drawing.Color]::White
        $dlg.Controls.Add($qrPanel)

        if ($null -ne $script:SupportImage) {
            $pb = New-Object System.Windows.Forms.PictureBox
            $pb.Location = New-Object Drawing.Point -ArgumentList @((UiPx 9), (UiPx 9))
            $pb.Size = New-Object Drawing.Size -ArgumentList @((UiPx 232), (UiPx 232))
            $pb.BackColor = [Drawing.Color]::White
            $pb.SizeMode = 'Zoom'
            $pb.Image = $script:SupportImage
            $pb.Cursor = [System.Windows.Forms.Cursors]::Hand
            $pb.Add_Click({ try { Start-Process -FilePath $script:SupportImgPath } catch {} })
            try { (Get-Tip).SetToolTip($pb, '点击打开原图') } catch {}
            $qrPanel.Controls.Add($pb)
        } else {
            $null = New-Label $qrPanel '未找到或无法读取赞赏码.png' (UiPx 0) (UiPx 108) (UiPx 250) (UiPx 24) 9 $false $script:C_DIM 'MiddleCenter'
        }

        $null = New-Label $dlg '微信 / 支付宝扫码支持' (UiPx 24) (UiPx 346) (UiPx 352) (UiPx 20) 9 $false $script:C_DIM 'MiddleCenter'
        $null = New-Label $dlg "赞赏码：$imgPath" (UiPx 24) (UiPx 368) (UiPx 352) (UiPx 18) 8 $false $script:C_DIM 'MiddleCenter'

        $btnOpen = New-Btn $dlg '打开原图' (UiPx 138) (UiPx 404) (UiPx 110) (UiPx 34) ((TC 24 35 50)) $script:C_SUB 9
        $btnClose = New-Btn $dlg '关闭' (UiPx 260) (UiPx 404) (UiPx 110) (UiPx 34) $script:C_CYAN ((TC 4 20 26)) 9
        $btnOpen.Add_Click({ try { Start-Process -FilePath $script:SupportImgPath } catch {} })
        $btnClose.Add_Click({ try { $dlg.Close() } catch {} })
        $dlg.AcceptButton = $btnClose
        $dlg.CancelButton = $btnClose
        $dlg.Add_Shown({ try { [TxUi.Native]::DarkTitle($dlg.Handle) } catch {} })
        $dlg.ResumeLayout($true)
        $dlg.ShowDialog($form) | Out-Null
        $dlg.Dispose()
    } catch {
        try { Start-Process -FilePath $script:SupportImgPath } catch {}
    }
}

$supBar = New-Object System.Windows.Forms.Panel
$supBar.Dock = 'Bottom'
$supBar.Height = 72
$supBar.BackColor = $script:C_PANEL
$aboutPage.Controls.Add($supBar)
$script:UI.SupportBar = $supBar

$supLine = New-Object System.Windows.Forms.Panel
$supLine.Dock = 'Top'
$supLine.Height = 1
$supLine.BackColor = $script:C_BORDER
$supBar.Controls.Add($supLine)

$script:SupportImage = $null
if (Test-Path -LiteralPath $script:SupportImgPath) {
    try { $script:SupportImage = [Drawing.Image]::FromFile($script:SupportImgPath) } catch {}
}

$supQr = New-Object System.Windows.Forms.PictureBox
$supQr.Location = New-Object Drawing.Point -ArgumentList @(20, 11)
$supQr.Size = New-Object Drawing.Size -ArgumentList @(50, 50)
$supQr.BackColor = [Drawing.Color]::White
$supQr.SizeMode = 'Zoom'
$supQr.Cursor = [System.Windows.Forms.Cursors]::Hand
if ($null -ne $script:SupportImage) { $supQr.Image = $script:SupportImage }
$supQr.Add_Click({ Show-SupportDialog })
$supBar.Controls.Add($supQr)
try { (Get-Tip).SetToolTip($supQr, '点击查看赞赏码') } catch {}

$null = New-Label $supBar '支持作者' 82 12 180 22 10 $true $script:C_TEXT
$supHint = New-Label $supBar '扫码请作者喝一杯，感谢支持' 82 36 300 18 8.5 $false $script:C_DIM
$btnSupport = New-Btn $supBar '支持作者' ($supBar.Width - 140) 19 120 34 $script:C_ORANGE_BG $script:C_ORANGE 9
$btnSupport.Anchor = 'Top, Right'
$btnSupport.Add_Click({ Show-SupportDialog })
$script:UI.BtnSupport = $btnSupport

function Fill-About {
    try {
        $rt = $script:UI.AboutBox
        if ($rt -is [System.Windows.Forms.ListBox]) { $rt.Items.Clear() } else { $rt.Clear() }
        $machine = $script:MachineTxt
        $gpuLines = @()
        foreach ($g in @($script:Snap.Gpus)) {
            $tag = '核显'
            if ($g.Basic) { $tag = '基础显示' }
            elseif ($g.Virtual) { $tag = '虚拟' }
            elseif ($g.Dedicated) { $tag = '独显' }
            $vram = [math]::Round($g.VRAM / 1GB, 1)
            $gpuLines += "$($g.Name) [$tag/$($g.Vendor)] 显存 $vram GB"
        }
        $dispLines = @()
        foreach ($d in @($script:Snap.Displays)) {
            $dispLines += "$($d.Device) [$($d.Name)] $($d.Width)x$($d.Height) $($d.Refresh)Hz / 最高 $($d.MaxRefresh)Hz"
        }
        $dgtxt = '未检测到独立显卡（独显专属项自动隐藏，检测到后自动出现）'
        if ($HAS_DGPU) { $dgtxt = '已检测到独立显卡（独显专属优化项已启用）' }

        Add-RtLine $rt '【本机能力】' $script:C_CYAN 10 $true
        Add-RtLine $rt "  机型: $machine" $script:C_TEXT 9
        Add-RtLine $rt "  形态: $(if($IL){'笔记本'}else{'台式机'}) · 供电: $(if($script:Snap.OnAC -eq $true){'已插电'}elseif($script:Snap.OnAC -eq $false){'电池'}else{'未知/台式'})" $script:C_TEXT 9
        foreach ($gl in $gpuLines) { Add-RtLine $rt "  显卡: $gl" $script:C_TEXT 9 }
        foreach ($dl in $dispLines) { Add-RtLine $rt "  显示器: $dl" $script:C_TEXT 9 }
        Add-RtLine $rt "  独显能力: $dgtxt" $script:C_SUB 9
        Add-RtLine $rt '' $script:C_DIM 5

        Add-RtLine $rt '【核心功能】' $script:C_CYAN 10 $true
        Add-RtLine $rt '  · 一键应用推荐项，支持逐项勾选、分类/状态/关键字筛选' $script:C_TEXT 9
        Add-RtLine $rt '  · 应用前自动生成 JSON 原值备份 + 按注册表键导出的 .reg 快照' $script:C_TEXT 9
        Add-RtLine $rt '  · 单项还原、最近一次撤销、全部备份回放；可选创建系统还原点' $script:C_TEXT 9
        Add-RtLine $rt '  · 待重启追踪：重启后自动复核哪些项真正生效' $script:C_TEXT 9
        Add-RtLine $rt '  · 只读诊断：VBS/HVCI、内存 XMP/EXPO、PCIe 链路、NVMe 健康、系统盘、电源' $script:C_TEXT 9
        Add-RtLine $rt '  · 预设方案（推荐 / 全量 / 仅游戏录制后台）与自定义方案保存' $script:C_TEXT 9
        Add-RtLine $rt '  · 报告导出、运行日志、网络进阶项按驱动能力自动生成' $script:C_TEXT 9
        Add-RtLine $rt '' $script:C_DIM 5

        Add-RtLine $rt '【安全与还原】' $script:C_CYAN 10 $true
        Add-RtLine $rt '  · 所有改动都有原值记录；还原按逆序回放，按位修改的项可精确恢复' $script:C_TEXT 9
        Add-RtLine $rt '  · 不修改 Defender、不关闭系统服务、不改 BCD、不超频、不改 DNS/hosts' $script:C_TEXT 9
        Add-RtLine $rt '  · 需要重启的项会在列表与结果中标注；笔记本用电池时请谨慎启用独显常开/核心停车' $script:C_TEXT 9
        Add-RtLine $rt '' $script:C_DIM 5

        Add-RtLine $rt '【兼容性】' $script:C_CYAN 10 $true
        Add-RtLine $rt '  · Intel / NVIDIA / AMD / Qualcomm / Apple 显卡；核显、独显、混合显卡自动识别' $script:C_TEXT 9
        Add-RtLine $rt '  · Intel Arc 1xxT/2xxV 核显、Arc A/B 独显、AMD APU/独显、Microsoft 基本显示、虚拟显卡' $script:C_TEXT 9
        Add-RtLine $rt '  · 没有对应硬件/驱动属性的优化项会自动隐藏或标记为不适用，不会强行写入' $script:C_TEXT 9
        Add-RtLine $rt '' $script:C_DIM 5

        Add-RtLine $rt '【文件位置】' $script:C_CYAN 10 $true
        Add-RtLine $rt "  脚本目录: $SD" $script:C_SUB 8.5
        Add-RtLine $rt "  备份目录: $BK" $script:C_SUB 8.5
        Add-RtLine $rt "  日志文件: $LOG" $script:C_SUB 8.5
        Add-RtLine $rt "  方案文件: $PROFILES" $script:C_SUB 8.5
        Add-RtLine $rt '' $script:C_DIM 5
        Add-RtLine $rt '提示：本工具只做可逆的注册表/电源/显示设置优化，不保证所有游戏都有帧率提升。' $script:C_DIM 8.5
        Add-RtLine $rt '请先保存工作，再应用需要重启的项。' $script:C_DIM 8.5
        if ($rt -is [System.Windows.Forms.ListBox]) { $rt.TopIndex = 0 } else { $rt.SelectionStart = 0; $rt.ScrollToCaret() }
    } catch {}
}

function Invoke-CheckUpdate {
    try {
        Set-Status '正在检查更新...'
        [System.Windows.Forms.Application]::DoEvents()
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
        $url = "https://api.github.com/repos/$($script:RepoSlug)/releases/latest"
        $headers = @{
            'User-Agent' = "TianxiGameOptimizer/$($script:AppVersion)"
            'Accept'     = 'application/vnd.github+json'
        }
        $j = Invoke-RestMethod -Uri $url -Headers $headers -TimeoutSec 12 -ErrorAction Stop
        $tag = [string]$j.tag_name
        if (-not $tag) { throw '发布信息缺少版本号' }
        $latest = $tag.TrimStart('v', 'V')
        $cmp = Compare-TxEngineVersion $latest $script:AppVersion
        if ($cmp -gt 0) {
            $body = [string]$j.body
            try { $body = ($body -replace "`r?`n", "`n").Trim() } catch {}
            if ($body.Length -gt 600) { $body = $body.Substring(0, 600) + '...' }
            $msg = "发现新版本：$tag`n当前版本：v$($script:AppVersion)`n发布时间：$([string]$j.published_at)`n`n$body`n`n是否打开下载页面？"
            $ans = [System.Windows.Forms.MessageBox]::Show($form, $msg, '检查更新', 'YesNo', 'Information')
            if ($ans -eq 'Yes') {
                try { Start-Process ([string]$j.html_url) } catch {}
            }
            Set-Status "发现新版本 $tag"
        } else {
            [System.Windows.Forms.MessageBox]::Show($form, "当前已是最新版本。`n`n当前版本：v$($script:AppVersion)`n最新发布：$tag", '检查更新', 'OK', 'Information') | Out-Null
            Set-Status "已是最新版本 v$($script:AppVersion)"
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "检查更新失败:`n$($_.Exception.Message)`n`n请检查网络连接，或稍后重试。", '检查更新', 'OK', 'Warning') | Out-Null
        Set-Status '检查更新失败'
    }
}

# ══════════════════════════════════════════════════════════
# 分享 / 便携包
# ══════════════════════════════════════════════════════════
function New-ShareReadme([string]$stamp) {
    return @"
游戏性能优化中心 v$($script:AppVersion) · 便携版
========================================

一、快速开始
  1. 先把整个压缩包解压到一个固定文件夹（不要直接在压缩包里双击）。
  2. 双击“启动优化脚本.bat”。
  3. Windows 弹出管理员权限请求时，点“是”。
  4. 打开界面后，先在“概览”查看硬件，再到“优化项”按需勾选，点“应用选中项”。
  5. 概览页的 CPU / GPU / RAM / 显示存储 卡片支持悬停高亮，点击可查看只读详情，并可直接复制或跳转诊断报告。

  启动行为：启动器以隐藏方式运行，不会再停留黑色控制台窗口；
  如果加载期间你切到了别的程序，主窗口不会抢焦点，只会闪烁任务栏图标提示。

二、QQ / Windows 拦截说明
  · 请用“以文件发送”的方式发送 zip；对方收到后先解压再运行。
  · 若出现“Windows 已保护你的电脑”：点“更多信息” → “仍要运行”。
  · 若提示脚本被系统禁止：右键 zip → 属性 → 勾选“解除锁定” → 确定，再重新解压。
  · 启动器会自动执行 Unblock-File，解除从网络下载的脚本锁定。
  · 杀毒软件可能对修改注册表 / 电源计划的脚本报警。本工具不联网、不下载、不修改系统文件，所有改动都有原值备份。

三、它做什么
  · 只读检测 + 可逆的注册表 / 电源 / 显示 / 网卡设置优化。
  · 应用前自动备份原值（backups 文件夹），支持单项还原、最近一次撤销、全部回放。
  · 不修改 Defender、不关闭系统服务、不改 BCD、不超频、不改 DNS/hosts。

四、数据与隐私
  · 设置、备份、日志都保存在解压后的文件夹内，不联网、不上传。
  · 分享包不包含原作者的本机设置、备份和日志。

五、系统要求
  · Windows 10 / 11（64 位）
  · Windows PowerShell 5.1（系统自带）
  · 建议 1920×1080 及以上；高缩放屏幕可在“设置”里开启实验性高 DPI。

六、卸载
  · 直接删除整个文件夹即可；如已应用优化项，请先在“备份还原”里还原。

七、关于启动时的“检测中”
  · 为了让界面更快出现，窗口会先显示出来，此时优化项状态显示为“检测中”；
    约 1 秒后自动补全真实状态，不需要手动刷新或重启。

八、支持作者
  · 如果这个工具帮到了你，可以打开同目录的“赞赏码.png”扫码支持；
    界面里的“关于”页底部也有“支持作者”按钮。

包内文件
  · 游戏性能优化-GUI.ps1   可视化界面
  · 游戏性能优化.ps1       引擎与优化项
  · 启动优化脚本.bat       日常启动器
  · 启动控制台版.bat       界面异常时的备用入口
  · 赞赏码.png             支持作者（可选）
  · 使用说明.txt           本文件
  · SHA256.txt             文件校验值

导出时间: $stamp
"@
}

function Export-SharePackage([string]$zipPath, [switch]$Quiet) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('txshare_' + [Guid]::NewGuid().ToString('N'))
    $payload = Join-Path $tmp "游戏性能优化中心_v$($script:AppVersion)"
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    try {
        $guiPath = $PSCommandPath
        if (-not $guiPath) { $guiPath = Join-Path $PSScriptRoot '游戏性能优化-GUI.ps1' }
        $files = @(
            @{ Src = $guiPath; Name = '游戏性能优化-GUI.ps1' },
            @{ Src = (Join-Path $PSScriptRoot '游戏性能优化.ps1'); Name = '游戏性能优化.ps1' },
            @{ Src = (Join-Path $PSScriptRoot '启动优化脚本.bat'); Name = '启动优化脚本.bat' },
            @{ Src = (Join-Path $PSScriptRoot '启动控制台版.bat'); Name = '启动控制台版.bat' },
            @{ Src = (Join-Path $PSScriptRoot '赞赏码.png'); Name = '赞赏码.png'; Optional = $true }
        )
        foreach ($f in $files) {
            if (-not (Test-Path -LiteralPath $f.Src)) {
                if ($f.Optional) { continue }
                throw "缺少文件: $($f.Name)"
            }
            Copy-Item -LiteralPath $f.Src -Destination (Join-Path $payload $f.Name) -Force
        }

        $stamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        [IO.File]::WriteAllText((Join-Path $payload '使用说明.txt'), (New-ShareReadme $stamp), (New-Object System.Text.UTF8Encoding($true)))

        $hashLines = @()
        foreach ($f in @(Get-ChildItem -LiteralPath $payload -File | Where-Object { $_.Name -ne 'SHA256.txt' } | Sort-Object Name)) {
            $h = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash
            $hashLines += ('{0}  {1}' -f $h, $f.Name)
        }
        [IO.File]::WriteAllText((Join-Path $payload 'SHA256.txt'), (($hashLines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction Stop }
        Compress-Archive -Path $payload -DestinationPath $zipPath -CompressionLevel Optimal

        $script:LastSharePath = $zipPath
        try { $script:UI.SharePath.Text = $zipPath } catch {}
        Set-Status "便携包已导出 · $([IO.Path]::GetFileName($zipPath))"
        if ($Quiet) { return }
        $ans = [System.Windows.Forms.MessageBox]::Show($form,
            "便携包已导出：`n$zipPath`n`n已包含 GUI、引擎、启动器、赞赏码、使用说明与 SHA256 校验。`n已自动排除本机设置、备份和日志。`n`n是否打开所在文件夹？",
            '导出便携包 - 完成', 'YesNo', 'Information')
        if ($ans -eq 'Yes') { Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f $zipPath) }
    } finally {
        try { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } } catch {}
    }
}

# ══════════════════════════════════════════════════════════
# 设置页 (实验性功能)
# ══════════════════════════════════════════════════════════
$setPage = New-Page 'settings'
$script:UI.SettingsPage = $setPage
$setPage.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, 1220)
$setHero = New-PageHero $setPage 'PREFERENCES · LOCAL CONFIG' '设置' '外观、托盘通知、实验性渲染与配置文件 · 所有设置只保存在本机' @(
    @{ V = '深色'; T = '主题'; C = $script:C_CYAN },
    @{ V = '关闭'; T = '高 DPI 渲染'; C = $script:C_DIM },
    @{ V = '关闭'; T = '状态栏渲染信息'; C = $script:C_DIM }
)
$script:UI.SetHero = $setHero.Card
$script:UI.SetStatTheme = $setHero.Values[0]
$script:UI.SetStatDpi = $setHero.Values[1]
$script:UI.SetStatRender = $setHero.Values[2]

$setW = $cw - 40
$appCard = New-Card $setPage 20 150 $setW 196 16 $script:C_PANEL $script:C_BORDER
$appCard.Anchor = 'Top, Left, Right'
$script:UI.AppCard = $appCard
$null = New-SectionTitle $appCard '外观与通知' 20 16 220 12
$null = New-Label $appCard '主题切换需要重启界面；托盘与通知选项立即生效' 20 42 ($setW - 40) 18 8.5 $false $script:C_DIM

$lblTheme = New-Label $appCard '界面主题' 20 76 80 26 9.5 $true $script:C_TEXT
$script:UI.SetThemeCombo = New-Combo $appCard 108 72 170
$script:UI.SetThemeCombo.Items.AddRange([string[]]@('深色', '浅色'))
$script:UI.SetThemeCombo.SelectedIndex = $(if ([string]$script:GuiCfg.Theme -eq 'light') { 1 } else { 0 })
$lblThemeState = New-Label $appCard '' 292 76 360 24 8.5 $false $script:C_DIM
$script:UI.SetThemeState = $lblThemeState

$script:UI.SetTrayCheck = New-Check $appCard '关闭窗口时最小化到托盘，而不是退出' 20 112 380 26 ([bool]$script:GuiCfg.MinimizeToTray)
$null = New-Label $appCard '托盘图标双击可恢复主界面；右键菜单可显示或退出' 44 138 460 18 8 $false $script:C_DIM
$script:UI.SetNotifyCheck = New-Check $appCard '驱动版本变化时发送托盘通知' 20 158 360 26 ([bool]$script:GuiCfg.NotifyDriver)

$btnAppRestart = New-Btn $appCard '重启界面' ($setW - 150) 72 130 34 ((TC 24 35 50)) $script:C_CYAN 9
$btnAppRestart.Anchor = 'Top, Right'
$btnAppRestart.Add_Click({ Restart-Gui })

$expCard = New-Card $setPage 20 362 $setW 350 16 $script:C_PANEL $script:C_BORDER
$expCard.Anchor = 'Top, Left, Right'
$script:UI.ExpCard = $expCard
$null = New-SectionTitle $expCard '实验性功能' 20 16 220 12
$null = New-Label $expCard '仅影响界面渲染，不修改任何系统优化项与注册表' 20 42 520 18 8.5 $false $script:C_DIM

$null = New-Label $expCard '高 DPI 渲染 (PerMonitorV2)' 20 80 420 24 10.5 $true $script:C_TEXT
$null = New-Label $expCard '按主屏实际 DPI 绘制，125% / 150% / 200% 缩放下文字与线条更清晰' 20 106 700 20 8.5 $false $script:C_SUB
$lblDpiState = New-Label $expCard '' 20 128 650 20 8 $false $script:C_DIM
$script:UI.SetDpiState = $lblDpiState
$chkDpi = New-Check $expCard '启用（重启界面生效）' ($setW - 380) 78 210 26 ([bool]$script:GuiCfg.ExperimentalDpi)
$chkDpi.Anchor = 'Top, Right'
$script:UI.SetDpiCheck = $chkDpi
$btnRestart = New-Btn $expCard '重启界面' ($setW - 150) 74 130 34 ((TC 24 35 50)) $script:C_CYAN 9
$btnRestart.Anchor = 'Top, Right'
$script:UI.SetRestart = $btnRestart
$div1 = New-Label $expCard '' 20 168 ($setW - 40) 1 8 $false $script:C_BORDER
$div1.BackColor = $script:C_BORDER

$null = New-Label $expCard '界面渲染（旧版备用界面）' 20 188 420 24 10.5 $true $script:C_TEXT
$null = New-Label $expCard '本界面为 WinForms + GDI+ 旧版备用界面；主界面已迁移到 WinUI 3，仅在原生程序无法启动时使用' 20 214 780 20 8.5 $false $script:C_SUB
$null = New-Label $expCard 'WinUI 3 主程序使用系统原生渲染，本备用界面保持现状，不再继续改造' 20 236 660 20 8 $false $script:C_DIM
$badgeWpf = New-Badge $expCard '旧版 · 备用' ($setW - 270) 192 160 26 $script:C_GRAY_BG $script:C_GRAY_BD $script:C_SUB 8
$badgeWpf.Anchor = 'Top, Right'
$btnWpf = New-Btn $expCard '查看说明' ($setW - 100) 190 80 32 ((TC 24 35 50)) $script:C_TEXT 8.5
$btnWpf.Anchor = 'Top, Right'
$div2 = New-Label $expCard '' 20 266 ($setW - 40) 1 8 $false $script:C_BORDER
$div2.BackColor = $script:C_BORDER

$chkRender = New-Check $expCard '在状态栏显示 DPI / 缩放 / 渲染方式' 20 278 380 26 ([bool]$script:GuiCfg.ShowRenderInfo)
$script:UI.SetRenderCheck = $chkRender
$null = New-Label $expCard '立即生效，仅新增一段状态文字，便于验证实验性 DPI 是否生效' 44 304 640 18 8 $false $script:C_DIM

$script:LastSharePath = ''
$shareCard = New-Card $setPage 20 728 $setW 172 16 $script:C_PANEL $script:C_BORDER
$shareCard.Anchor = 'Top, Left, Right'
$script:UI.ShareCard = $shareCard
$null = New-SectionTitle $shareCard '分享 / 便携包' 20 16 260 12
$null = New-Label $shareCard '一键打包给同学：GUI、引擎、启动器、使用说明与 SHA256 校验' 20 42 640 18 8.5 $false $script:C_SUB
$null = New-Label $shareCard '自动排除本机设置、备份与日志；对方解压后双击“启动优化脚本.bat”即可' 20 64 720 18 8 $false $script:C_DIM
$null = New-Label $shareCard 'GUI · 引擎 · 启动器 · 控制台备用入口 · 使用说明 · SHA256' 20 86 700 18 8 $false $script:C_DIM

$btnShare = New-Btn $shareCard '导出便携包' 20 112 150 36 ((TC 16 40 46)) $script:C_CYAN 9
$script:UI.ShareBtn = $btnShare
$btnShareTip = New-Btn $shareCard '复制分享话术' 182 112 150 36 ((TC 24 35 50)) $script:C_TEXT 9
$script:UI.ShareTipBtn = $btnShareTip
$lblSharePath = New-Label $shareCard '尚未导出便携包' 350 118 ($setW - 370) 20 8 $false $script:C_DIM
$script:UI.SharePath = $lblSharePath

$cfgCard = New-Card $setPage 20 916 $setW 150 16 $script:C_PANEL $script:C_BORDER
$cfgCard.Anchor = 'Top, Left, Right'
$null = New-SectionTitle $cfgCard '配置文件' 20 16 220 12
$lblCfgPath = New-Label $cfgCard $script:GuiSettingsFile 20 48 ($setW - 40) 20 8.5 $false $script:C_SUB
$btnOpenDir = New-Btn $cfgCard '打开脚本目录' 20 96 140 32 ((TC 24 35 50)) $script:C_CYAN 9
$btnReset = New-Btn $cfgCard '恢复默认设置' 172 96 140 32 ((TC 46 32 24)) $script:C_ORANGE 9
$null = New-Label $cfgCard '设置只保存在本机；删除该文件即恢复默认。' 330 100 ($setW - 350) 20 8 $false $script:C_DIM

$noteCard = New-Card $setPage 20 1082 $setW 110 16 $script:C_PANEL $script:C_BORDER
$noteCard.Anchor = 'Top, Left, Right'
$null = New-SectionTitle $noteCard '实验性功能说明' 20 14 240 11
$null = New-Label $noteCard '· 实验性选项可能随系统 / 驱动差异表现不同，默认关闭；关闭后重启即可回到原渲染方式。' 20 42 ($setW - 40) 18 8.5 $false $script:C_DIM
$null = New-Label $noteCard '· 高 DPI 模式按启动时主屏 DPI 布局；拖到不同缩放比例的显示器时建议重启界面。' 20 64 ($setW - 40) 18 8.5 $false $script:C_DIM

$script:SetUiSuppress = $false

function Update-SettingsUi {
    try {
        $want = [bool]$script:GuiCfg.ExperimentalDpi
        $actual = [bool]$script:DPI_ENABLED
        if ($actual) {
            $state = "当前: 已启用 · DPI $($script:DPI_NOW) · 界面缩放 $(([double]$script:UI_SCALE).ToString('0.##'))x"
            $stateColor = $script:C_GREEN
            if (-not $want) { $state += ' · 需要重启界面关闭' }
        } elseif ($want) {
            $state = '当前: 未启用 · 需要重启界面启用；若重启后仍无效，说明当前环境不支持进程级 DPI 感知'
            $stateColor = $script:C_ORANGE
        } else {
            $state = '当前: 未启用 · 使用系统位图缩放（默认）'
            $stateColor = $script:C_DIM
        }
        $script:UI.SetDpiState.Text = $state
        $script:UI.SetDpiState.ForeColor = $stateColor
        $sup0 = $script:SetUiSuppress
        $script:SetUiSuppress = $true
        try {
            $script:UI.SetDpiCheck.Checked = $want
            $script:UI.SetRenderCheck.Checked = [bool]$script:GuiCfg.ShowRenderInfo
            if ($script:UI.SetTrayCheck) { $script:UI.SetTrayCheck.Checked = [bool]$script:GuiCfg.MinimizeToTray }
            if ($script:UI.SetNotifyCheck) { $script:UI.SetNotifyCheck.Checked = [bool]$script:GuiCfg.NotifyDriver }
            if ($script:UI.SetThemeCombo) {
                $script:UI.SetThemeCombo.SelectedIndex = $(if ([string]$script:GuiCfg.Theme -eq 'light') { 1 } else { 0 })
            }
        } finally { $script:SetUiSuppress = $sup0 }
        if ($script:UI.SetThemeState) {
            $cur = [string]$script:ThemeName
            $wantTheme = [string]$script:GuiCfg.Theme
            if ($cur -ne $wantTheme) {
                $curName = $(if ($cur -eq 'light') { '浅色' } else { '深色' })
                $wantName = $(if ($wantTheme -eq 'light') { '浅色' } else { '深色' })
                $script:UI.SetThemeState.Text = "当前: $curName · 重启后切换为 $wantName"
                $script:UI.SetThemeState.ForeColor = $script:C_ORANGE
            } else {
                $curName = $(if ($cur -eq 'light') { '浅色' } else { '深色' })
                $script:UI.SetThemeState.Text = "当前: $curName"
                $script:UI.SetThemeState.ForeColor = $script:C_DIM
            }
        }
        if ($script:UI.SetStatTheme) {
            $isLight = ([string]$script:GuiCfg.Theme -eq 'light')
            $script:UI.SetStatTheme.Text = $(if ($isLight) { '浅色' } else { '深色' })
            $script:UI.SetStatTheme.ForeColor = $(if ($isLight) { $script:C_CYAN } else { $script:C_SUB })
        }
        if ($script:UI.SetStatDpi) {
            $dpiTxt = '关闭'; $dpiColor = $script:C_DIM
            if ($actual) { $dpiTxt = '已启用'; $dpiColor = $script:C_GREEN }
            elseif ($want) { $dpiTxt = '待重启'; $dpiColor = $script:C_ORANGE }
            $script:UI.SetStatDpi.Text = $dpiTxt
            $script:UI.SetStatDpi.ForeColor = $dpiColor
        }
        if ($script:UI.SetStatRender) {
            $on = [bool]$script:GuiCfg.ShowRenderInfo
            $script:UI.SetStatRender.Text = $(if ($on) { '已开启' } else { '关闭' })
            $script:UI.SetStatRender.ForeColor = $(if ($on) { $script:C_CYAN } else { $script:C_DIM })
        }
    } catch {}
}

function Restart-Gui {
    try {
        if ($script:UI.Busy) {
            [System.Windows.Forms.MessageBox]::Show($form, '正在应用或还原，请等待当前操作完成。', '重启界面', 'OK', 'Information') | Out-Null
            return
        }
        $ans = [System.Windows.Forms.MessageBox]::Show($form, "重启界面以应用实验性设置？`n`n当前未保存的勾选会丢失。", '重启界面', 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden',
            '-File', "`"$PSCommandPath`"", '-NoElevate', '-Sid', $Sid)
        Start-Process powershell.exe -ArgumentList $argList | Out-Null
        try { $script:ClockTimer.Stop() } catch {}
        try { $script:LiveTimer.Stop() } catch {}
        Stop-Sampler
        try { $form.Close() } catch {}
        [System.Windows.Forms.Application]::Exit()
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "重启失败:`n$($_.Exception.Message)", '重启界面', 'OK', 'Warning') | Out-Null
    }
}

$chkDpi.Add_CheckedChanged({
    if ($script:SetUiSuppress) { return }
    $script:GuiCfg.ExperimentalDpi = [bool]$script:UI.SetDpiCheck.Checked
    $ok = Save-GuiSettings
    Update-SettingsUi
    if ($ok) { Set-Status '实验性高 DPI 设置已保存 · 需要重启界面生效' }
    else { Set-Status '设置保存失败，目录可能只读；本次仅在当前进程内生效' }
})
$chkRender.Add_CheckedChanged({
    if ($script:SetUiSuppress) { return }
    $script:GuiCfg.ShowRenderInfo = [bool]$script:UI.SetRenderCheck.Checked
    $null = Save-GuiSettings
    Update-RenderInfo
    Set-Status '状态栏渲染信息已更新'
})
$script:UI.SetThemeCombo.Add_SelectedIndexChanged({
    if ($script:SetUiSuppress) { return }
    $want = 'dark'
    if ($script:UI.SetThemeCombo.SelectedIndex -eq 1) { $want = 'light' }
    if ([string]$script:GuiCfg.Theme -eq $want) { return }
    $script:GuiCfg.Theme = $want
    $ok = Save-GuiSettings
    Update-SettingsUi
    if ($ok) { Set-Status '主题设置已保存 · 点击「重启界面」后生效' }
    else { Set-Status '主题设置保存失败，目录可能只读' }
})
$script:UI.SetTrayCheck.Add_CheckedChanged({
    if ($script:SetUiSuppress) { return }
    $script:GuiCfg.MinimizeToTray = [bool]$script:UI.SetTrayCheck.Checked
    $ok = Save-GuiSettings
    if ($ok) { Set-Status '托盘设置已保存' }
    else { Set-Status '托盘设置保存失败，目录可能只读' }
})
$script:UI.SetNotifyCheck.Add_CheckedChanged({
    if ($script:SetUiSuppress) { return }
    $script:GuiCfg.NotifyDriver = [bool]$script:UI.SetNotifyCheck.Checked
    $ok = Save-GuiSettings
    if ($ok) { Set-Status '驱动通知设置已保存' }
    else { Set-Status '驱动通知设置保存失败，目录可能只读' }
})
$btnRestart.Add_Click({ Restart-Gui })
$btnWpf.Add_Click({
    [System.Windows.Forms.MessageBox]::Show($form,
        "这是一个旧版备用界面：`n`n  · 使用 WinForms + GDI+ 绘制`n  · 桌面窗口管理器 (DWM) 在 GPU 上完成窗口合成`n`n主界面已经迁移到 WinUI 3，使用系统原生控件与渲染管线。`n本界面仅在原生程序无法启动时使用，功能与优化数据完全一致，不再继续演进。",
        '界面渲染 / 旧版备用界面', 'OK', 'Information') | Out-Null
})
$btnShare.Add_Click({
    if ($script:UI.Busy) {
        [System.Windows.Forms.MessageBox]::Show($form, '正在应用或还原，请等待当前操作完成。', '导出便携包', 'OK', 'Information') | Out-Null
        return
    }
    try {
        $dlg = New-Object System.Windows.Forms.SaveFileDialog
        $dlg.Title = '导出便携包'
        $dlg.Filter = 'ZIP 压缩包 (*.zip)|*.zip'
        $dlg.DefaultExt = 'zip'
        $dlg.AddExtension = $true
        $dlg.FileName = "游戏性能优化中心_v$($script:AppVersion)_便携版.zip"
        try { $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop') } catch {}
        if ($dlg.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
        Set-Status '正在打包便携包，请稍候...'
        Export-SharePackage $dlg.FileName
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "导出失败:`n$($_.Exception.Message)", '导出便携包', 'OK', 'Warning') | Out-Null
        Set-Status '便携包导出失败'
    }
})
$btnShareTip.Add_Click({
    $tip = @"
游戏性能优化中心 v$($script:AppVersion) 便携版（Windows 10 / 11）

使用步骤：
1. 先解压整个压缩包到固定文件夹，不要直接在压缩包里双击。
2. 双击“启动优化脚本.bat”，管理员权限请求点“是”。
3. 打开界面后先看“概览”，再到“优化项”按需勾选并应用。

如果被系统或 QQ 拦截：
· 压缩包先解压再运行。
· 提示“Windows 已保护你的电脑”：点“更多信息” → “仍要运行”。
· 提示脚本被禁止：右键压缩包 → 属性 → 勾选“解除锁定” → 确定后重新解压。
· 杀毒软件误报时，把解压后的文件夹加入信任区。
· 启动器会自动解除脚本锁定；本工具不联网、不上传、不改系统文件。

所有优化都有原值备份，可以在“备份还原”里撤销。
"@
    try {
        [System.Windows.Forms.Clipboard]::SetText($tip)
        Set-Status '分享话术已复制到剪贴板'
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "复制失败:`n$($_.Exception.Message)", '复制分享话术', 'OK', 'Warning') | Out-Null
    }
})
$btnOpenDir.Add_Click({
    try { Start-Process explorer.exe -ArgumentList ('"' + $PSScriptRoot + '"') } catch {}
})
$btnReset.Add_Click({
    $ans = [System.Windows.Forms.MessageBox]::Show($form, "恢复默认设置？`n`n将恢复深色主题、关闭高 DPI 渲染与状态栏渲染信息、关闭最小化到托盘，并开启驱动通知。`n主题与高 DPI 的变更需要重启界面。", '恢复默认设置', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    $script:GuiCfg.ExperimentalDpi = $false
    $script:GuiCfg.ShowRenderInfo = $false
    $script:GuiCfg.Theme = 'dark'
    $script:GuiCfg.MinimizeToTray = $false
    $script:GuiCfg.NotifyDriver = $true
    $null = Save-GuiSettings
    $script:SetUiSuppress = $true
    try {
        Update-SettingsUi
        Update-RenderInfo
    } finally { $script:SetUiSuppress = $false }
    Set-Status '已恢复默认设置 · 高 DPI 渲染将在重启界面后关闭'
})

$script:SetUiSuppress = $true
try { Update-SettingsUi } finally { $script:SetUiSuppress = $false }

# ══════════════════════════════════════════════════════════
# 数据刷新 / 布局 / 页面切换
# ══════════════════════════════════════════════════════════
$script:UI.Status = $lblStatus
$script:UI.Clock = $lblClock
$script:UI.TopMachine = $lblTopMachine
$script:InitialCw = $cw

function Set-Status([string]$t) {
    try {
        if ($t.Length -gt 120) { $t = $t.Substring(0, 120) + '...' }
        $script:UI.Status.Text = $t
    } catch {}
}

function Update-RenderInfo {
    try {
        if ($script:DPI_ENABLED) {
            $scTxt = ([double]$script:UI_SCALE).ToString('0.##')
            $script:UI.Render.Text = "DPI $($script:DPI_NOW) · PMv2 · 缩放 ${scTxt}x"
        } else {
            $script:UI.Render.Text = '系统缩放 · GDI+'
        }
        $script:UI.Render.Visible = [bool]$script:GuiCfg.ShowRenderInfo
    } catch {}
}

function Apply-DarkScrollbars {
    $apply = {
        param($ctrl)
        if ($null -eq $ctrl) { return }
        try {
            if ($ctrl -is [System.Windows.Forms.DataGridView] -or
                $ctrl -is [System.Windows.Forms.ListBox] -or
                $ctrl -is [System.Windows.Forms.Panel] -or
                $ctrl -is [System.Windows.Forms.FlowLayoutPanel]) {
                if ($ctrl.IsHandleCreated) {
                    [TxUi.Native]::DarkScroll($ctrl.Handle)
                    [TxUi.Native]::DarkChildren($ctrl.Handle)
                }
            }
        } catch {}
        try { foreach ($ch in @($ctrl.Controls)) { & $apply $ch } } catch {}
    }
    try {
        foreach ($k in @('AboutBox', 'LogBox', 'BakGrid', 'DiagGrid', 'DrvFlow')) {
            $c = $script:UI[$k]
            if ($c) { & $apply $c }
        }
        foreach ($pg in @($script:UI.Pages.Values)) { & $apply $pg }
    } catch {}
}

function Get-DiagVal([string]$group, [string]$name) {
    try {
        $x = @($script:Snap.Diagnostics | Where-Object { $_.Group -eq $group -and $_.Name -eq $name } | Select-Object -First 1)
        if ($x.Count -gt 0) { return [string]$x[0].Value }
    } catch {}
    return ''
}

function Get-DiagObj([string]$group, [string]$name) {
    try {
        $x = @($script:Snap.Diagnostics | Where-Object { $_.Group -eq $group -and $_.Name -eq $name } | Select-Object -First 1)
        if ($x.Count -gt 0) { return $x[0] }
    } catch {}
    return $null
}

function Update-Overview {
    try {
        $s = $script:Snap
        $script:UI.TopMachine.Text = [string]$s.Machine
        $script:MachineTxt = [string]$s.Machine

        # CPU
        $cpuRaw = Get-DiagVal '系统' 'CPU'
        $cpuName = $cpuRaw; $cpuSub = ''
        if ($cpuRaw -match '^(.*?)\s*\|\s*(.*)$') { $cpuName = $Matches[1]; $cpuSub = $Matches[2] }
        if (-not $cpuName) { $cpuName = '未知 CPU' }
        $osRaw = Get-DiagVal '系统' '操作系统'
        $osShort = $osRaw -replace 'Microsoft ', ''
        $script:UI.Hw['cpu'].Value.Text = $cpuName
        $script:UI.Hw['cpu'].Sub1.Text = $cpuSub
        $script:UI.Hw['cpu'].Sub2.Text = $osShort

        # GPU
        $gpu = @($s.Gpus | Where-Object { -not $_.Basic -and -not $_.Virtual } | Sort-Object @{ Expression = { $_.Dedicated }; Descending = $true } | Select-Object -First 1)
        if ($gpu.Count -eq 0) { $gpu = @($s.Gpus | Select-Object -First 1) }
        if ($gpu.Count -gt 0) {
            $g = $gpu[0]
            $tag = '核显'
            if ($g.Dedicated) { $tag = '独显' }
            if ($g.Basic) { $tag = '基础显示' }
            if ($g.Virtual) { $tag = '虚拟' }
            $vram = [math]::Round([double]$g.VRAM / 1GB, 1)
            $script:UI.Hw['gpu'].Value.Text = [string]$g.Name
            if ($g.Dedicated) { $script:UI.Hw['gpu'].Sub1.Text = "$tag · $($g.Vendor) · 显存 $vram GB" }
            else { $script:UI.Hw['gpu'].Sub1.Text = "$tag · $($g.Vendor) · 共享/显存 $vram GB" }
            $gd = @($s.Diagnostics | Where-Object { $_.Group -eq '显卡' -and $_.Name -like "$($g.Name)*" } | Select-Object -First 1)
            if ($gd.Count -gt 0) { $script:UI.Hw['gpu'].Sub2.Text = [string]$gd[0].Value } else { $script:UI.Hw['gpu'].Sub2.Text = '驱动信息未知' }
        } else {
            $script:UI.Hw['gpu'].Value.Text = '未检测到显卡'
            $script:UI.Hw['gpu'].Sub1.Text = ''
            $script:UI.Hw['gpu'].Sub2.Text = ''
        }

        # RAM
        $ramRaw = Get-DiagVal '系统' '内存'
        $ramVal = $ramRaw; $ramSub = ''
        if ($ramRaw -match '^(.*?)\s*\|\s*(.*)$') { $ramVal = $Matches[1]; $ramSub = $Matches[2] }
        $freq = Get-DiagVal '系统' '内存频率'
        $script:UI.Hw['ram'].Value.Text = $ramVal
        if ($freq) { $script:UI.Hw['ram'].Sub1.Text = "$ramSub · $freq" } else { $script:UI.Hw['ram'].Sub1.Text = $ramSub }
        if (-not $script:UI.Hw['ram'].Sub2.Text -or $script:UI.Hw['ram'].Sub2.Text -eq '') { $script:UI.Hw['ram'].Sub2.Text = '实时占用见下方监控' }

        # Display / disk
        $disp = @($s.Displays | Select-Object -First 1)
        if ($disp.Count -gt 0) {
            $d = $disp[0]
            $script:UI.Hw['disk'].Value.Text = "$($d.Width)x$($d.Height) @ $($d.Refresh)Hz"
            $script:UI.Hw['disk'].Sub1.Text = "$($d.Device) [$($d.Name)] · 最高 $($d.MaxRefresh)Hz"
        } else {
            $script:UI.Hw['disk'].Value.Text = '未检测到显示器'
            $script:UI.Hw['disk'].Sub1.Text = '可能处于远程桌面或虚拟机'
        }
        $diskFree = Get-DiagVal '存储' '系统盘剩余'
        if ($diskFree) { $script:UI.Hw['disk'].Sub2.Text = "系统盘剩余 $diskFree" } else { $script:UI.Hw['disk'].Sub2.Text = '' }

        # 卡片文字可能因宽度被截断，完整内容放进 tooltip
        try {
            foreach ($k in @('cpu', 'gpu', 'ram')) {
                $lbl = $script:UI.Hw[$k].Value
                $len = ([string]$lbl.Text).Length
                $fs = 10.5
                if ($len -gt 30) { $fs = 8.5 }
                elseif ($len -gt 24) { $fs = 9 }
                elseif ($len -gt 19) { $fs = 9.5 }
                $lbl.Font = F $fs $true
            }
            $script:Tip.SetToolTip($script:UI.Hw['cpu'].Value, ("{0} {1}" -f $cpuName, $cpuSub).Trim())
            $script:Tip.SetToolTip($script:UI.Hw['gpu'].Value, [string]$script:UI.Hw['gpu'].Value.Text)
            $script:Tip.SetToolTip($script:UI.Hw['ram'].Value, ("{0} {1}" -f $ramVal, $ramSub).Trim())
            $script:Tip.SetToolTip($script:UI.Hw['disk'].Sub1, [string]$script:UI.Hw['disk'].Sub1.Text)
        } catch {}

        # 待应用项
        $pend = @($s.Items | Where-Object { $_.Status -eq 'no' })
        $chk = @($s.Items | Where-Object { $_.Status -eq 'checking' })
        if ($chk.Count -gt 0) {
            try { $script:UI.PendTitle.Text = '待应用项 (检测中)' } catch {}
            if ($script:UI.PendLabels.Count -gt 0) {
                $script:UI.PendLabels[0].Text = '• 正在检测优化项状态，完成后自动更新'
                $script:UI.PendLabels[0].ForeColor = $script:C_DIM
            }
            for ($i = 1; $i -lt $script:UI.PendLabels.Count; $i++) { $script:UI.PendLabels[$i].Text = '' }
        } elseif ($pend.Count -eq 0) {
            try { $script:UI.PendTitle.Text = '待应用项 (0)' } catch {}
            if ($script:UI.PendLabels.Count -gt 0) { $script:UI.PendLabels[0].Text = '• 当前没有待应用项，状态良好'; $script:UI.PendLabels[0].ForeColor = $script:C_GREEN }
            for ($i = 1; $i -lt $script:UI.PendLabels.Count; $i++) { $script:UI.PendLabels[$i].Text = '' }
        } else {
            try { $script:UI.PendTitle.Text = "待应用项 ($($pend.Count))" } catch {}
            for ($i = 0; $i -lt $script:UI.PendLabels.Count; $i++) {
                if ($i -lt $pend.Count) {
                    $script:UI.PendLabels[$i].Text = "• [$($pend[$i].Cat)] $($pend[$i].Name)"
                    $script:UI.PendLabels[$i].ForeColor = $script:C_SUB
                } else {
                    $script:UI.PendLabels[$i].Text = ''
                }
            }
        }

        # 系统状态
        $vals = New-Object System.Collections.ArrayList
        $pr = $s.PendingReboot
        if ($pr -and $pr.Pending) { [void]$vals.Add(@{ T = "是 ($(@($pr.Reasons) -join ', '))"; C = $script:C_ORANGE }) }
        else { [void]$vals.Add(@{ T = '否'; C = $script:C_GREEN }) }
        $la = $s.LastApply
        if ($la) {
            $lt = "$($la.Time) · $(@($la.Items).Count) 项"
            if ($la.Checked -and $la.Result) { $lt += " · $($la.Result)" }
            [void]$vals.Add(@{ T = $lt; C = $script:C_TEXT })
        } else {
            [void]$vals.Add(@{ T = '无记录'; C = $script:C_DIM })
        }
        if (-not $s.IsLaptop) { [void]$vals.Add(@{ T = '台式机'; C = $script:C_TEXT }) }
        elseif ($null -eq $s.OnAC) { [void]$vals.Add(@{ T = '笔记本 / 供电未知'; C = $script:C_ORANGE }) }
        elseif ($s.OnAC) { [void]$vals.Add(@{ T = '笔记本 / 已插电'; C = $script:C_GREEN }) }
        else { [void]$vals.Add(@{ T = '笔记本 / 电池供电'; C = $script:C_RED }) }
        $vbs = Get-DiagVal '安全' 'VBS 虚拟化安全'
        $hvci = Get-DiagVal '安全' '内存完整性 HVCI'
        $sec = "$vbs · HVCI $hvci"
        $secColor = $script:C_TEXT
        if ($vbs -match '运行中') { $secColor = $script:C_ORANGE }
        [void]$vals.Add(@{ T = $sec; C = $secColor })
        if (@($s.Nics).Count -gt 0) { [void]$vals.Add(@{ T = (@($s.Nics) -join ', '); C = $script:C_TEXT }) }
        else { [void]$vals.Add(@{ T = '未检测到物理网卡'; C = $script:C_DIM }) }
        $bkCount = @(Get-ChildItem $BK -Filter backup_*.json -EA 0).Count
        [void]$vals.Add(@{ T = "$bkCount 份"; C = $script:C_TEXT })
        [void]$vals.Add(@{ T = "v$($script:AppVersion)"; C = $script:C_CYAN })
        for ($i = 0; $i -lt $script:UI.SysVals.Count; $i++) {
            if ($i -lt $vals.Count) {
                $script:UI.SysVals[$i].Text = [string]$vals[$i].T
                $script:UI.SysVals[$i].ForeColor = $vals[$i].C
            }
        }
        try { $script:UI.Hero.Invalidate() } catch {}
    } catch {}
}

function Layout-Overview {
    try {
        $sc = [double]$script:UI_SCALE
        $p = $script:UI.Ov
        $w = $p.ClientSize.Width
        if ($w -lt [int](600 * $sc)) { return }
        $heroW = $w - [int](40 * $sc)
        $script:UI.Hero.Width = $heroW
        $hwW = [int](($heroW - 36 * $sc) / 4)
        if ($hwW -lt [int](150 * $sc)) { $hwW = [int](150 * $sc) }
        for ($i = 0; $i -lt $script:UI.HwCards.Count; $i++) {
            $c = $script:UI.HwCards[$i]
            $c.Location = New-Object Drawing.Point -ArgumentList @(([int](20 * $sc) + $i * ($hwW + [int](12 * $sc))), [int](160 * $sc))
            $c.Width = $hwW
        }
        foreach ($k in @('cpu', 'gpu', 'ram', 'disk')) {
            $h = $script:UI.Hw[$k]
            $h.Value.Width = $hwW - [int](28 * $sc)
            $h.Sub1.Width = $hwW - [int](28 * $sc)
            $h.Sub2.Width = $hwW - [int](28 * $sc)
        }
        $script:UI.Mon.Width = $heroW
        $inner = $heroW - [int](36 * $sc)
        if ($inner -gt [int](200 * $sc)) {
            $mw = [int](($inner - [int](36 * $sc)) / 4)
            for ($i = 0; $i -lt $script:UI.MeterCtrls.Count; $i++) {
                $mm = $script:UI.MeterCtrls[$i]
                $mm.Location = New-Object Drawing.Point -ArgumentList @(([int](18 * $sc) + $i * ($mw + [int](12 * $sc))), [int](48 * $sc))
                $mm.Width = $mw
            }
        }
        $leftW = [int](($heroW - 12 * $sc) * 0.58)
        $rightW = $heroW - [int](12 * $sc) - $leftW
        $script:UI.PendCard.Location = New-Object Drawing.Point -ArgumentList @([int](20 * $sc), [int](476 * $sc))
        $script:UI.PendCard.Width = $leftW
        $script:UI.SysCard.Location = New-Object Drawing.Point -ArgumentList @(([int](20 * $sc) + $leftW + [int](12 * $sc)), [int](476 * $sc))
        $script:UI.SysCard.Width = $rightW
        foreach ($pl in $script:UI.PendLabels) { $pl.Width = $leftW - [int](32 * $sc) }
        foreach ($sv in $script:UI.SysVals) { $sv.Width = $rightW - [int](96 * $sc) }
        # 窗口从最大化还原后, AutoScroll 可能沿用旧的横向虚拟宽度而多出横向滚动条
        $p.PerformLayout()
    } catch {}
}

function Scale-ControlTree($parent, [double]$sc) {
    foreach ($c in @($parent.Controls)) {
        try {
            if ($c -is [System.Windows.Forms.Button]) {
                Set-Round $c ([int][Math]::Round(10 * $sc))
            } elseif ($c -is [System.Windows.Forms.DataGridView]) {
                $c.RowTemplate.Height = [int][Math]::Round(30 * $sc)
                $c.ColumnHeadersHeight = [int][Math]::Round(34 * $sc)
                $pad = [int][Math]::Round(6 * $sc)
                $c.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding -ArgumentList @($pad, 0, $pad, 0)
                $c.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding -ArgumentList @($pad, 0, $pad, 0)
                foreach ($col in @($c.Columns)) {
                    try { if ($col.MinimumWidth -gt 0) { $col.MinimumWidth = [int][Math]::Round($col.MinimumWidth * $sc) } } catch {}
                }
            } elseif ($c -is [System.Windows.Forms.ListBox]) {
                $c.ItemHeight = [int][Math]::Round(22 * $sc)
            } elseif ($c -is [System.Windows.Forms.ComboBox]) {
                $c.ItemHeight = [int][Math]::Round(22 * $sc)
            }
        } catch {}
        try { if ($c.HasChildren) { Scale-ControlTree $c $sc } } catch {}
    }
}

function Apply-UiScale {
    try {
        $sc = [double]$script:UI_SCALE
        if ($sc -le 1.0001) {
            $script:InitialCw = $content.ClientSize.Width
            Update-RenderInfo
            return
        }
        if ($script:UiScaled) { return }
        $script:UiScaled = $true
        $script:UiScaling = $true
        $form.SuspendLayout()
        try {
            $form.Scale((New-Object Drawing.SizeF -ArgumentList @([single]$sc, [single]$sc)))
            $form.MinimumSize = New-Object Drawing.Size -ArgumentList @([int][Math]::Round($script:MinW * $sc), [int][Math]::Round($script:MinH * $sc))
            Scale-ControlTree $form $sc
            $script:InitialCw = $content.ClientSize.Width
            $script:UI.Ov.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, [int][Math]::Round(720 * $sc))
            $script:UI.SettingsPage.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, [int][Math]::Round(1220 * $sc))
            if ($script:UI.GamePage) { $script:UI.GamePage.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, [int][Math]::Round(710 * $sc)) }
            if ($script:UI.StartupPage) { $script:UI.StartupPage.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, [int][Math]::Round(980 * $sc)) }
        } finally {
            $script:UiScaling = $false
            $form.ResumeLayout($true)
        }
        Layout-Overview
        Update-RenderInfo
        Update-SettingsUi
        Set-Status "高 DPI 渲染已启用 · DPI $($script:DPI_NOW) · 缩放 $($sc.ToString('0.##'))x"
    } catch {
        Set-Status "高 DPI 缩放失败: $($_.Exception.Message)"
    }
}

function Refresh-Snapshot {
    try {
        Set-Status '正在刷新硬件与优化项状态...'
        [System.Windows.Forms.Application]::DoEvents()
        $script:Snap = Get-TxSnapshot
        $script:SnapMap = @{}
        foreach ($x in @($script:Snap.Items)) { $script:SnapMap[$x.Id] = $x }
        Update-Overview
        Rebuild-Items
        Refresh-BackupList
        $script:UI.DiagDirty = $true
        Set-Status '状态已刷新'
    } catch {
        Set-Status "刷新失败: $($_.Exception.Message)"
    }
}

function Show-Page([string]$key) {
    try {
        if (-not $script:UI.Pages.ContainsKey($key)) { return }
        foreach ($k in @($script:UI.Pages.Keys)) {
            $script:UI.Pages[$k].Visible = ($k -eq $key)
        }
        foreach ($k in @($script:UI.NavBtns.Keys)) {
            $b = $script:UI.NavBtns[$k]
            $active = ($k -eq $key)
            try { $b.Tag.Bar.Visible = $active } catch {}
            try {
                $ic = $script:UI.NavIcons[$k]
                if ($null -ne $ic) { $b.Image = $(if ($active) { $ic.On } else { $ic.Off }) }
            } catch {}
            if ($active) {
                $b.BackColor = (TC 22 32 46)
                $b.ForeColor = $script:C_CYAN
                $b.Font = F 10 $true
            } else {
                $b.BackColor = $script:C_PANEL2
                $b.ForeColor = $script:C_SUB
                $b.Font = F 10 $false
            }
        }
        $script:UI.CurrentPage = $key
        switch ($key) {
            'backup' { if ($script:UI.BackupDirty) { Refresh-BackupList } }
            'game'   { if ($script:UI.GameDirty) { Refresh-GamePage $false } }
            'driver' { if ($script:UI.DriverDirty) { Refresh-DriverPage $false } }
            'diag'   { if ($script:UI.DiagDirty) { Refresh-Diag $false } }
            'startup' { if ($script:UI.StartupDirty) { Refresh-StartupPage } }
            'about'  {
                Fill-About
                Update-AboutLayout
            }
            'settings' { Update-SettingsUi }
            'overview' { Update-Overview }
            'items'  { Update-ItemSummary }
        }
        # 页面首次显示后才创建句柄，需在填充数据后重新给滚动条应用暗色主题
        try {
            $pg = $script:UI.Pages[$key]
            if ($pg -and $pg.IsHandleCreated) {
                [TxUi.Native]::DarkScroll($pg.Handle)
                [TxUi.Native]::DarkChildren($pg.Handle)
            }
        } catch {}
        Layout-Overview
    } catch {
        if ($Preview) { Write-Output "show_page_error=$key : $($_.Exception.Message)" }
    }
}

function Show-InputDialog([string]$title, [string]$prompt, [string]$default) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $title
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowIcon = $false
    $dlg.StartPosition = 'CenterParent'
    $dlg.ClientSize = New-Object Drawing.Size -ArgumentList @(440, 170)
    $dlg.BackColor = $script:C_BG
    $dlg.ForeColor = $script:C_TEXT
    $null = New-Label $dlg $prompt 24 24 392 24 9.5 $false $script:C_TEXT
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object Drawing.Point -ArgumentList @(24, 58)
    $tb.Size = New-Object Drawing.Size -ArgumentList @(392, 30)
    $tb.BackColor = $script:C_PANEL2
    $tb.ForeColor = $script:C_TEXT
    $tb.BorderStyle = 'FixedSingle'
    $tb.Font = F 10
    $tb.Text = $default
    $dlg.Controls.Add($tb)
    $btnCancel = New-Btn $dlg '取消' 232 112 88 34 ((TC 24 35 50)) $script:C_SUB 9
    $btnOk = New-Btn $dlg '确定' 328 112 88 34 $script:C_CYAN ((TC 4 20 26)) 9
    $script:DlgInput = $tb
    $script:DlgInputForm = $dlg
    $script:DlgInputResult = $null
    $btnOk.Add_Click({ $script:DlgInputResult = $script:DlgInput.Text; $script:DlgInputForm.Close() })
    $btnCancel.Add_Click({ $script:DlgInputForm.Close() })
    $dlg.AcceptButton = $btnOk
    $dlg.CancelButton = $btnCancel
    $dlg.Add_Shown({ try { $script:DlgInput.Focus(); $script:DlgInput.SelectAll() } catch {} })
    if ($script:UI_SCALE -gt 1.0001) {
        try {
            $sc = [double]$script:UI_SCALE
            $dlg.Scale((New-Object Drawing.SizeF -ArgumentList @([single]$sc, [single]$sc)))
            Set-Round $btnOk ([int][Math]::Round(10 * $sc))
            Set-Round $btnCancel ([int][Math]::Round(10 * $sc))
        } catch {}
    }
    $dlg.ShowDialog($form) | Out-Null
    $r = $script:DlgInputResult
    $dlg.Dispose()
    if ($r -and $r.Trim()) { return $r.Trim() }
    return $null
}

# ── 硬件卡片详情 ─────────────────────────────────────────
function Get-HwDetailRows([string]$key) {
    $rows = New-Object System.Collections.ArrayList
    $add = {
        param($k, $v, $g = '概览')
        if ($null -ne $v -and ([string]$v).Trim().Length -gt 0) {
            [void]$rows.Add(@{ K = [string]$k; V = [string]$v; G = [string]$g })
        }
    }
    try {
        switch ($key) {
            'cpu' {
                $cpu = Get-DiagObj '系统' 'CPU'
                if ($cpu) { & $add '处理器' $cpu.Value '核心信息' }
                $os = Get-DiagObj '系统' '操作系统'
                if ($os) { & $add '操作系统' $os.Value '核心信息' }
                if ($script:Snap.Machine) { & $add '机型' $script:Snap.Machine '核心信息' }
                $mem = Get-DiagObj '系统' '内存'
                if ($mem) { & $add '内存' $mem.Value '内存与运行环境' }
                $freq = Get-DiagObj '系统' '内存频率'
                if ($freq) { & $add '内存频率' $freq.Value '内存与运行环境' }
                $envObj = Get-DiagObj '系统' '运行环境'
                if ($envObj) { & $add '运行环境' $envObj.Value '内存与运行环境' }
                $gm = Get-DiagObj '系统' '游戏模式'
                if ($gm) { & $add '游戏模式' $gm.Value '内存与运行环境' }
                try {
                    if ($script:Live.Updated -and $null -ne $script:Live.Cpu) { & $add '当前负载' ("{0:N0}%（实时）" -f [double]$script:Live.Cpu) '实时状态' }
                    else { & $add '当前负载' '读取中' '实时状态' }
                } catch {}
            }
            'gpu' {
                $idx = 0
                foreach ($g in @($script:Snap.Gpus | Where-Object { -not $_.Basic -and -not $_.Virtual })) {
                    $idx++
                    $tag = '核显'; if ($g.Dedicated) { $tag = '独显' }
                    $vram = [math]::Round([double]$g.VRAM / 1GB, 1)
                    & $add "显卡 $idx" ("$($g.Name) [$tag] · $($g.Vendor) · 显存 $vram GB") '显卡'
                    $gd = @($script:Snap.Diagnostics | Where-Object { $_.Group -eq '显卡' -and $_.Name -like "$($g.Name)*" } | Select-Object -First 1)
                    if ($gd.Count -gt 0) {
                        $dv = [string]$gd[0].Value
                        if ($dv -like '驱动 *') { $dv = $dv.Substring(3) }
                        & $add "驱动 $idx" $dv '驱动与特性'
                    }
                }
                foreach ($p in @($script:Snap.Diagnostics | Where-Object { $_.Group -eq '显卡' -and $_.Name -like '* PCIe' })) {
                    & $add $p.Name $p.Value '驱动与特性'
                }
                $hags = Get-DiagObj '显卡' 'HAGS'
                if ($hags) { & $add 'HAGS 硬件加速' $hags.Value '驱动与特性' }
                $tdr = Get-DiagObj '显卡' 'TDR 超时'
                if ($tdr) { & $add 'TDR 超时' $tdr.Value '驱动与特性' }
                try {
                    if ($script:Live.Updated -and $null -ne $script:Live.Gpu) { & $add '当前 3D 负载' ("{0:N0}%（实时）" -f [double]$script:Live.Gpu) '实时状态' }
                    elseif ([long]$script:Live.GpuAt -gt 0) { & $add '当前 3D 负载' 'N/A（未检测到 3D 引擎）' '实时状态' }
                    else { & $add '当前 3D 负载' '读取中' '实时状态' }
                } catch {}
            }
            'ram' {
                $mem = Get-DiagObj '系统' '内存'
                if ($mem) { & $add '容量 / 通道' $mem.Value '容量与频率' }
                $freq = Get-DiagObj '系统' '内存频率'
                if ($freq) {
                    & $add '运行 / 标称频率' $freq.Value '容量与频率'
                    if ($freq.Hint) { & $add '提示' $freq.Hint '容量与频率' }
                }
                try {
                    if ($script:Live.Updated -and $null -ne $script:Live.RamUsedGB) {
                        & $add '当前占用' ("{0:N1} / {1:N0} GB · {2:N0}%" -f [double]$script:Live.RamUsedGB, [double]$script:Live.RamTotalGB, [double]$script:Live.RamPct) '实时状态'
                    } else { & $add '当前占用' '读取中' '实时状态' }
                } catch {}
                & $add '说明' '内存容量与频率来自系统 SMBIOS；实时占用每 0.25 秒刷新。' '备注'
            }
            'disk' {
                $i = 0
                foreach ($d in @($script:Snap.Displays)) {
                    $i++
                    & $add "显示器 $i" ("$($d.Device) [$($d.Name)] · $($d.Width)x$($d.Height) @ $($d.Refresh)Hz（最高 $($d.MaxRefresh)Hz）") '显示'
                }
                if ($i -eq 0) { & $add '显示器' '未检测到显示器（可能处于远程桌面或虚拟机）' '显示' }
                $drr = Get-DiagObj '显示' 'DRR 动态刷新率'
                if ($drr) { & $add 'DRR 动态刷新率' $drr.Value '显示' }
                $free = Get-DiagObj '存储' '系统盘剩余'
                if ($free) { & $add '系统盘剩余' $free.Value '存储' }
                foreach ($d in @($script:Snap.Diagnostics | Where-Object { $_.Group -eq '存储' -and $_.Name -ne '系统盘剩余' } | Select-Object -First 6)) {
                    & $add $d.Name $d.Value '存储'
                }
            }
            default { & $add '信息' '暂无可用的详细数据' '概览' }
        }
    } catch {
        & $add '错误' $_.Exception.Message '概览'
    }
    if ($rows.Count -eq 0) { & $add '信息' '暂无可用的详细数据' '概览' }
    return @($rows.ToArray())
}

function Get-MixColor($from, $to, [double]$t) {
    if ($t -lt 0) { $t = 0 }
    if ($t -gt 1) { $t = 1 }
    $r = [int][Math]::Round([double]$from.R + ([double]$to.R - [double]$from.R) * $t)
    $g = [int][Math]::Round([double]$from.G + ([double]$to.G - [double]$from.G) * $t)
    $b = [int][Math]::Round([double]$from.B + ([double]$to.B - [double]$from.B) * $t)
    return (TC $r $g $b)
}

function Show-HardwareDetails([string]$key) {
    try {
        $metaMap = @{
            cpu  = @('处理器详情', '处理器、系统与运行环境')
            gpu  = @('显卡详情', '核显 / 独显、驱动与实时负载')
            ram  = @('内存详情', '容量、频率与实时占用')
            disk = @('显示与存储', '显示器、刷新率与磁盘空间')
        }
        $accentMap = @{
            cpu  = $script:C_CYAN
            gpu  = $script:C_PURPLE
            ram  = $script:C_GREEN
            disk = $script:C_ORANGE
        }
        $codeMap = @{ cpu = 'CPU'; gpu = 'GPU'; ram = 'RAM'; disk = 'DISK' }
        $meta = $metaMap[$key]
        if (-not $meta) { $meta = @('硬件详情', '只读信息') }
        $accent = $accentMap[$key]
        if (-not $accent) { $accent = $script:C_CYAN }
        $code = $codeMap[$key]
        if (-not $code) { $code = 'HW' }
        $rows = @(Get-HwDetailRows $key)

        # 分组, 保持数据出现顺序
        $groupOrder = New-Object System.Collections.ArrayList
        $groupRows = @{}
        foreach ($r in $rows) {
            $g = ''
            try { $g = [string]$r.G } catch {}
            if (-not $g) { $g = '概览' }
            if (-not $groupRows.ContainsKey($g)) {
                $groupRows[$g] = New-Object System.Collections.ArrayList
                [void]$groupOrder.Add($g)
            }
            [void]$groupRows[$g].Add($r)
        }

        # 尺寸
        $pad = UiPx 24
        $screenW = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Width
        $screenH = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height
        $dlgW = [Math]::Min((UiPx 720), [int]($screenW * 0.92))
        if ($dlgW -lt (UiPx 480)) { $dlgW = [Math]::Min((UiPx 480), ($screenW - (UiPx 24))) }
        $cardW = $dlgW - $pad * 2
        $titleH = UiPx 40
        $headerTop = $titleH + (UiPx 12)
        $headerH = UiPx 112
        $contentTop = $headerTop + $headerH + (UiPx 16)
        $footBtnH = UiPx 36
        $footBottom = UiPx 20
        $footGap = UiPx 16
        $maxDlgH = [Math]::Min((UiPx 780), [int]($screenH * 0.88))

        $keyW = UiPx 150
        $valX = (UiPx 18) + $keyW + (UiPx 14)
        $valW = $cardW - $valX - (UiPx 18)
        $fMeasure = F 9.5
        $secHeights = @{}
        $secRowHeights = @{}
        $contentNeed = 0
        foreach ($g in $groupOrder) {
            $gr = @($groupRows[$g])
            $secHt = UiPx 42
            $rhs = New-Object System.Collections.ArrayList
            foreach ($r in $gr) {
                $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::NoPrefix
                $sz = [System.Windows.Forms.TextRenderer]::MeasureText([string]$r.V, $fMeasure, (New-Object Drawing.Size -ArgumentList @($valW, 10000)), $flags)
                $rh = [Math]::Max((UiPx 24), ($sz.Height + (UiPx 2)))
                [void]$rhs.Add($rh)
                $secHt += $rh + (UiPx 16)
            }
            $secHt += UiPx 8
            $secHeights[$g] = $secHt
            $secRowHeights[$g] = @($rhs.ToArray())
            $contentNeed += $secHt + (UiPx 12)
        }
        if ($groupOrder.Count -gt 0) { $contentNeed -= UiPx 12 }
        try { $fMeasure.Dispose() } catch {}

        $dlgH = $contentTop + $contentNeed + $footGap + $footBtnH + $footBottom
        if ($dlgH -lt (UiPx 420)) { $dlgH = UiPx 420 }
        if ($dlgH -gt $maxDlgH) { $dlgH = $maxDlgH }
        $footY = $dlgH - $footBottom - $footBtnH
        $boxH = $footY - $footGap - $contentTop
        if ($boxH -lt (UiPx 100)) { $boxH = UiPx 100 }

        $dlg = New-Object System.Windows.Forms.Form
        $dlg.Text = $meta[0]
        $dlg.FormBorderStyle = 'None'
        $dlg.MaximizeBox = $false
        $dlg.MinimizeBox = $false
        $dlg.ShowIcon = $false
        $dlg.ShowInTaskbar = $false
        $dlg.StartPosition = 'CenterParent'
        $dlg.AutoScaleMode = 'None'
        $dlg.ClientSize = New-Object Drawing.Size -ArgumentList @($dlgW, $dlgH)
        $dlg.BackColor = $script:C_BG
        $dlg.ForeColor = $script:C_TEXT
        $dlg.SuspendLayout()

        # ── 自绘标题条 (无边框窗口, 避免系统浅色标题栏) ──
        $tbar = New-Object System.Windows.Forms.Panel
        $tbar.Location = New-Object Drawing.Point -ArgumentList @(0, 0)
        $tbar.Size = New-Object Drawing.Size -ArgumentList @($dlgW, $titleH)
        $tbar.BackColor = $script:C_BG
        $dlg.Controls.Add($tbar)
        $tbarLine = New-Object System.Windows.Forms.Panel
        $tbarLine.Location = New-Object Drawing.Point -ArgumentList @(0, ($titleH - (UiPx 1)))
        $tbarLine.Size = New-Object Drawing.Size -ArgumentList @($dlgW, (UiPx 1))
        $tbarLine.BackColor = $script:C_BORDER
        $tbar.Controls.Add($tbarLine)
        $tdot = New-Badge $tbar '' (UiPx 22) ((($titleH - (UiPx 6)) / 2)) (UiPx 6) (UiPx 6) $accent $accent $accent 3
        $tlabel = New-Label $tbar '游戏性能优化中心 · 硬件详情' (UiPx 34) 0 ($dlgW - (UiPx 150)) $titleH 9 $true $script:C_SUB 'MiddleLeft'
        $tclose = New-Label $tbar '✕' ($dlgW - (UiPx 24) - (UiPx 34)) ((($titleH - (UiPx 26)) / 2)) (UiPx 34) (UiPx 26) 10 $false $script:C_SUB 'MiddleCenter'
        $tclose.BackColor = $script:C_BG
        try { $tclose.Cursor = [System.Windows.Forms.Cursors]::Hand } catch {}
        $drag = {
            param($s, $e)
            if ($e -and $e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
                try { [TxUi.Native]::DragMove($s.FindForm().Handle) } catch {}
            }
        }
        foreach ($c in @($tbar, $tdot, $tlabel)) { $c.Add_MouseDown($drag) }
        $tclose.Add_Click({ param($s, $e) try { $s.FindForm().Close() } catch {} })
        $tclose.Add_MouseEnter({ param($s, $e) try { $s.ForeColor = $script:C_TEXT; $s.BackColor = $script:C_PANEL } catch {} })
        $tclose.Add_MouseLeave({ param($s, $e) try { $s.ForeColor = $script:C_SUB; $s.BackColor = $script:C_BG } catch {} })
        $dlg.Add_Paint({
            param($s, $e)
            try {
                $pw = [single][Math]::Max(1, (UiPx 1))
                $pen = New-Object Drawing.Pen $script:C_BORDER, $pw
                $e.Graphics.DrawRectangle($pen, 0, 0, ($s.Width - 1), ($s.Height - 1))
                $pen.Dispose()
            } catch {}
        })

        # ── 头部卡片 ──────────────────────────────────────
        $hdrFill = Get-MixColor $script:C_PANEL $accent 0.07
        $hdrBd = Get-MixColor $script:C_BORDER $accent 0.40
        $hdr = New-Card $dlg $pad $headerTop $cardW $headerH 14 $hdrFill $hdrBd
        $bar = New-Object System.Windows.Forms.Panel
        $bar.Location = New-Object Drawing.Point -ArgumentList @(0, 0)
        $bar.Size = New-Object Drawing.Size -ArgumentList @($cardW, (UiPx 3))
        $bar.BackColor = $accent
        $hdr.Controls.Add($bar)

        $iconFill = Get-MixColor $script:C_PANEL $accent 0.16
        $iconBd = Get-MixColor $script:C_BORDER $accent 0.62
        $icon = New-Badge $hdr $code (UiPx 20) (UiPx 30) (UiPx 58) (UiPx 58) $iconFill $iconBd $accent 10
        try { $icon.Radius = UiPx 14 } catch {}
        $titleW = $cardW - (UiPx 96) - (UiPx 250)
        $null = New-Label $hdr $meta[0] (UiPx 96) (UiPx 26) $titleW (UiPx 32) 17 $true $script:C_TEXT 'MiddleLeft'
        $null = New-Label $hdr $meta[1] (UiPx 96) (UiPx 60) $titleW (UiPx 22) 9 $false $script:C_SUB 'MiddleLeft'
        $null = New-Badge $hdr '只读信息' ($cardW - (UiPx 112)) (UiPx 30) (UiPx 92) (UiPx 26) $script:C_GRAY_BG $script:C_GRAY_BD $script:C_SUB 8
        $null = New-Label $hdr "游戏性能优化中心 · v$($script:AppVersion)" ($cardW - (UiPx 250)) (UiPx 62) (UiPx 230) (UiPx 18) 8 $false $script:C_DIM 'MiddleRight'

        # ── 内容区 ────────────────────────────────────────
        $scrollW = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
        $boxW = $cardW + $scrollW + (UiPx 2)
        $box = New-Object System.Windows.Forms.Panel
        $box.Location = New-Object Drawing.Point -ArgumentList @($pad, $contentTop)
        $box.Size = New-Object Drawing.Size -ArgumentList @($boxW, $boxH)
        $box.BackColor = $script:C_BG
        $box.AutoScroll = $true
        $dlg.Controls.Add($box)

        $sepColor = (TC 31 41 56)
        $yOff = 0
        foreach ($g in $groupOrder) {
            $secHt = [int]$secHeights[$g]
            $sec = New-Card $box 0 $yOff $cardW $secHt 12 $script:C_PANEL $script:C_BORDER
            $dotColor = $accent
            if ($g -eq '实时状态') { $dotColor = $script:C_GREEN }
            $dot = New-Badge $sec '' (UiPx 18) (UiPx 19) (UiPx 7) (UiPx 7) $dotColor $dotColor $dotColor 6
            try { $dot.Radius = UiPx 4 } catch {}
            $null = New-Label $sec $g (UiPx 33) (UiPx 9) ($cardW - (UiPx 60)) (UiPx 24) 9.5 $true $script:C_SUB

            $gr = @($groupRows[$g])
            $rhs = @($secRowHeights[$g])
            $ry = UiPx 42
            for ($ri = 0; $ri -lt $gr.Count; $ri++) {
                $r = $gr[$ri]
                $rh = [int]$rhs[$ri]
                $valColor = $script:C_TEXT
                if ($g -eq '实时状态') { $valColor = $script:C_GREEN }
                elseif ($g -eq '说明') { $valColor = $script:C_SUB }
                $lk = New-Label $sec $r.K (UiPx 18) ($ry + (UiPx 2)) $keyW $rh 9 $false $script:C_DIM 'TopLeft'
                $lk.AutoEllipsis = $false
                $lk.UseMnemonic = $false
                $lv = New-Label $sec ([string]$r.V) $valX ($ry + (UiPx 1)) $valW ($rh - (UiPx 1)) 9.5 $false $valColor 'TopLeft'
                $lv.AutoEllipsis = $false
                $lv.UseMnemonic = $false
                if ($ri -lt ($gr.Count - 1)) {
                    $sep = New-Object System.Windows.Forms.Panel
                    $sep.Location = New-Object Drawing.Point -ArgumentList @((UiPx 18), ($ry + $rh + (UiPx 8)))
                    $sep.Size = New-Object Drawing.Size -ArgumentList @(($cardW - (UiPx 36)), (UiPx 1))
                    $sep.BackColor = $sepColor
                    $sec.Controls.Add($sep)
                }
                $ry += $rh + (UiPx 16)
            }
            $yOff += $secHt + (UiPx 12)
        }
        $box.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, [Math]::Max($contentNeed, 1))

        # ── 底部操作栏 ────────────────────────────────────
        $footLine = New-Object System.Windows.Forms.Panel
        $footLine.Location = New-Object Drawing.Point -ArgumentList @($pad, ($footY - (UiPx 14)))
        $footLine.Size = New-Object Drawing.Size -ArgumentList @(($cardW + $scrollW), (UiPx 1))
        $footLine.BackColor = $script:C_BORDER
        $dlg.Controls.Add($footLine)

        $btnCloseW = UiPx 84
        $btnDiagW = UiPx 148
        $btnCopyW = UiPx 116
        $gap = UiPx 10
        $btnCloseX = $dlgW - $pad - $btnCloseW
        $btnDiagX = $btnCloseX - $gap - $btnDiagW
        $btnCopyX = $btnDiagX - $gap - $btnCopyW
        $footTextW = $btnCopyX - $pad - (UiPx 12)
        if ($footTextW -lt (UiPx 120)) { $footTextW = UiPx 120 }
        $null = New-Label $dlg '数据来源 · 本机 WMI / 性能计数器 · 只读' $pad ($footY + (UiPx 9)) $footTextW (UiPx 18) 8 $false $script:C_DIM

        $lum = (0.299 * $accent.R + 0.587 * $accent.G + 0.114 * $accent.B) / 255.0
        $onAccent = (TC 10 14 20)
        if ($lum -lt 0.62) { $onAccent = [Drawing.Color]::White }
        $btnCopy = New-Btn $dlg '复制详情' $btnCopyX $footY $btnCopyW $footBtnH $accent $onAccent 9
        try {
            $btnCopy.FlatAppearance.MouseOverBackColor = Get-MixColor $accent ([Drawing.Color]::White) 0.12
            $btnCopy.FlatAppearance.MouseDownBackColor = Get-MixColor $accent ([Drawing.Color]::Black) 0.12
        } catch {}
        $btnDiag = New-Btn $dlg '打开诊断报告' $btnDiagX $footY $btnDiagW $footBtnH (Get-MixColor $script:C_PANEL $accent 0.10) $script:C_TEXT 9
        $btnClose = New-Btn $dlg '关闭' $btnCloseX $footY $btnCloseW $footBtnH $script:C_PANEL2 $script:C_SUB 9
        $dlg.AcceptButton = $btnCopy
        $dlg.CancelButton = $btnClose
        $dlg.Tag = @{ Rows = $rows; Meta = $meta; Box = $box; Accent = $accent }

        $script:HwDetailGoDiag = $false
        $btnClose.Add_Click({ param($s, $e) try { $s.FindForm().Close() } catch {} })
        $btnCopy.Add_Click({
            param($s, $e)
            try {
                $f = $s.FindForm()
                $tg = $f.Tag
                $body = New-Object System.Collections.ArrayList
                $lastG = ''
                foreach ($r in @($tg.Rows)) {
                    $g = ''
                    try { $g = [string]$r.G } catch {}
                    if ($g -ne $lastG) {
                        if ($lastG -ne '') { [void]$body.Add('') }
                        [void]$body.Add("[$g]")
                        $lastG = $g
                    }
                    [void]$body.Add("$($r.K): $($r.V)")
                }
                $text = $tg.Meta[0] + " · 游戏性能优化中心 v$($script:AppVersion)" + "`r`n" +
                        ('=' * 44) + "`r`n" + ($body -join "`r`n") +
                        "`r`n`r`n导出时间: " + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
                [System.Windows.Forms.Clipboard]::SetText($text)
                $s.Text = '已复制'
            } catch {}
        })
        $btnDiag.Add_Click({
            param($s, $e)
            $script:HwDetailGoDiag = $true
            try { $s.FindForm().Close() } catch {}
        })

        $dlg.Add_Shown({
            param($s, $e)
            try {
                [TxUi.Native]::RoundCorners($s.Handle)
                try { [TxUi.Native]::SetWindowTheme($s.Handle, 'DarkMode_Explorer', $null) } catch {}
                $b = $s.Tag.Box
                if ($b) { [TxUi.Native]::DarkScroll($b.Handle) }
            } catch {}
        })
        $dlg.ResumeLayout($true)
        [void]$dlg.ShowDialog($form)
        if ($script:HwDetailGoDiag) {
            $script:HwDetailGoDiag = $false
            Show-Page 'diag'
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show($form, "无法打开硬件详情:`n$($_.Exception.Message)", '硬件详情', 'OK', 'Warning') | Out-Null
    }
}

# ══════════════════════════════════════════════════════════
# 实时监控 (后台 Runspace)
# ══════════════════════════════════════════════════════════
$script:Live = [hashtable]::Synchronized(@{
    Stop = $false; Cpu = $null; Gpu = $null; RamPct = $null
    RamUsedGB = $null; RamTotalGB = $null; NetDown = $null; NetUp = $null; Updated = $null; Ticks = 0
    CpuAt = 0; GpuAt = 0; RamAt = 0; NetAt = 0
})

# 快速采样 (250ms): CPU 走 GetSystemTimes / 内存走 GlobalMemoryStatusEx,
# 均为进程内 API 调用, 单轮开销 < 1ms
$script:FastSamplerCode = @'
param($State)
$ErrorActionPreference = 'SilentlyContinue'
$prevCpu = $null
while (-not $State.Stop) {
    try {
        $cs = [TxUi.Perf]::GetCpuSample()
        if ($cs) {
            if ($prevCpu) {
                $dIdle = [double]($cs.Idle - $prevCpu.Idle)
                $dTotal = [double](($cs.Kernel - $prevCpu.Kernel) + ($cs.User - $prevCpu.User))
                if ($dTotal -gt 0) {
                    $pct = (1.0 - $dIdle / $dTotal) * 100.0
                    if ($pct -lt 0) { $pct = 0 } elseif ($pct -gt 100) { $pct = 100 }
                    $State.Cpu = [math]::Round($pct, 1)
                    $State.CpuAt = [DateTime]::UtcNow.Ticks
                }
            }
            $prevCpu = $cs
        }
    } catch {}
    try {
        $ms = [TxUi.Perf]::GetMemSample()
        if ($ms -and $ms.Total -gt 0) {
            $tot = [double]$ms.Total / 1GB
            $avail = [double]$ms.Avail / 1GB
            $State.RamTotalGB = [math]::Round($tot, 1)
            $State.RamUsedGB = [math]::Round($tot - $avail, 1)
            $State.RamPct = [math]::Round(($tot - $avail) / $tot * 100, 1)
            $State.RamAt = [DateTime]::UtcNow.Ticks
        }
    } catch {}
    $State.Updated = [DateTime]::Now.ToString('HH:mm:ss')
    $State.Ticks = [int]$State.Ticks + 1
    for ($i = 0; $i -lt 5 -and -not $State.Stop; $i++) { Start-Sleep -Milliseconds 50 }
}
'@

# 网络采样: 单独线程。部分网卡驱动 (如 USB/Remote NDIS) 的统计调用可能阻塞
# 1-2 秒, 放在独立线程可避免拖慢 CPU/内存/GPU 指标
$script:NetSamplerCode = @'
param($State)
$ErrorActionPreference = 'SilentlyContinue'
$nics = $null
$lastNet = $null
$lastT = [DateTime]::UtcNow
$cycles = 0
while (-not $State.Stop) {
    try {
        if (-not $nics -or ($cycles % 15) -eq 0) {
            $nics = @([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
                Where-Object {
                    $_.OperationalStatus -eq 'Up' -and
                    [string]$_.NetworkInterfaceType -ne 'Loopback' -and
                    [string]$_.NetworkInterfaceType -ne 'Tunnel'
                })
        }
        $now = [DateTime]::UtcNow
        $rx = 0.0; $tx = 0.0
        foreach ($ni in $nics) {
            try {
                $st = $ni.GetIPStatistics()
                $rx += [double]$st.BytesReceived
                $tx += [double]$st.BytesSent
            } catch {}
        }
        if ($null -ne $lastNet) {
            $dt = ($now - $lastT).TotalSeconds
            if ($dt -gt 0.2) {
                $d = [math]::Max(0, ($rx - $lastNet.Rx) / $dt)
                $u = [math]::Max(0, ($tx - $lastNet.Tx) / $dt)
                $dn = $d / 1KB; $up = $u / 1KB
                if ($null -ne $State.NetDown) {
                    $dn = [double]$State.NetDown * 0.5 + $dn * 0.5
                    $up = [double]$State.NetUp * 0.5 + $up * 0.5
                }
                $State.NetDown = [math]::Round($dn, 1)
                $State.NetUp = [math]::Round($up, 1)
                $State.NetAt = $now.Ticks
            }
        }
        $lastNet = @{ Rx = $rx; Tx = $tx }
        $lastT = $now
        $cycles++
    } catch {}
    for ($i = 0; $i -lt 10 -and -not $State.Stop; $i++) { Start-Sleep -Milliseconds 100 }
}
'@

# GPU 采样: 服务端过滤 + 属性投影, 单轮约 0.4s; 独立线程, 不阻塞 CPU/内存/网络
$script:GpuSamplerCode = @'
param($State)
$ErrorActionPreference = 'SilentlyContinue'
while (-not $State.Stop) {
    $v = $null
    try {
        $g = @(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -Filter "Name LIKE '%engtype_3D%'" -Property Name,UtilizationPercentage -ErrorAction SilentlyContinue)
        $sum = 0.0
        foreach ($x in $g) { $sum += [double]$x.UtilizationPercentage }
        if ($sum -gt 100) { $sum = 100 }
        if ($sum -lt 0) { $sum = 0 }
        $v = [math]::Round($sum, 1)
    } catch { $v = $null }
    $State.Gpu = $v
    $State.GpuAt = [DateTime]::UtcNow.Ticks
    for ($i = 0; $i -lt 5 -and -not $State.Stop; $i++) { Start-Sleep -Milliseconds 100 }
}
'@

$script:FastPS = $null; $script:FastRS = $null; $script:FastHandle = $null
$script:GpuPS = $null; $script:GpuRS = $null; $script:GpuHandle = $null
$script:NetPS = $null; $script:NetRS = $null; $script:NetHandle = $null

function Start-Sampler {
    try {
        $script:Live.Stop = $false

        $script:FastRS = [runspacefactory]::CreateRunspace()
        $script:FastRS.ApartmentState = 'MTA'
        $script:FastRS.ThreadOptions = 'ReuseThread'
        $script:FastRS.Open()
        $script:FastPS = [powershell]::Create()
        $script:FastPS.Runspace = $script:FastRS
        [void]$script:FastPS.AddScript($script:FastSamplerCode).AddParameter('State', $script:Live)
        $script:FastHandle = $script:FastPS.BeginInvoke()

        $script:GpuRS = [runspacefactory]::CreateRunspace()
        $script:GpuRS.ApartmentState = 'MTA'
        $script:GpuRS.ThreadOptions = 'ReuseThread'
        $script:GpuRS.Open()
        $script:GpuPS = [powershell]::Create()
        $script:GpuPS.Runspace = $script:GpuRS
        [void]$script:GpuPS.AddScript($script:GpuSamplerCode).AddParameter('State', $script:Live)
        $script:GpuHandle = $script:GpuPS.BeginInvoke()

        $script:NetRS = [runspacefactory]::CreateRunspace()
        $script:NetRS.ApartmentState = 'MTA'
        $script:NetRS.ThreadOptions = 'ReuseThread'
        $script:NetRS.Open()
        $script:NetPS = [powershell]::Create()
        $script:NetPS.Runspace = $script:NetRS
        [void]$script:NetPS.AddScript($script:NetSamplerCode).AddParameter('State', $script:Live)
        $script:NetHandle = $script:NetPS.BeginInvoke()
    } catch {
        Set-Status "实时监控不可用: $($_.Exception.Message)"
    }
}

function Stop-Sampler {
    try { $script:Live.Stop = $true } catch {}
    foreach ($ps in @($script:FastPS, $script:GpuPS, $script:NetPS)) {
        try { if ($ps) { $ps.Stop(); $ps.Dispose() } } catch {}
    }
    foreach ($rs in @($script:FastRS, $script:GpuRS, $script:NetRS)) {
        try { if ($rs) { $rs.Close(); $rs.Dispose() } } catch {}
    }
    $script:FastPS = $null; $script:FastRS = $null; $script:FastHandle = $null
    $script:GpuPS = $null; $script:GpuRS = $null; $script:GpuHandle = $null
    $script:NetPS = $null; $script:NetRS = $null; $script:NetHandle = $null
}

function Update-Meters {
    try {
        $L = $script:Live
        $nowT = [DateTime]::UtcNow.Ticks
        $stale = [TimeSpan]::FromSeconds(5).Ticks

        $mc = $script:UI.Meters['cpu']
        if ($null -ne $L.Cpu -and ($nowT - [long]$L.CpuAt) -lt $stale) {
            $mc.Value = [double]$L.Cpu; $mc.ValueText = ("{0:N0}%" -f [double]$L.Cpu)
        } elseif (-not $L.Updated) { $mc.ValueText = '读取中' }
        else { $mc.ValueText = '--' }

        $mg = $script:UI.Meters['gpu']
        if ($null -ne $L.Gpu -and ($nowT - [long]$L.GpuAt) -lt ([TimeSpan]::FromSeconds(8).Ticks)) {
            $mg.Value = [double]$L.Gpu; $mg.ValueText = ("{0:N0}%" -f [double]$L.Gpu)
        } elseif ([long]$L.GpuAt -gt 0) { $mg.Value = 0; $mg.ValueText = 'N/A' }
        else { $mg.ValueText = '读取中' }

        $mr = $script:UI.Meters['ram']
        if ($null -ne $L.RamPct -and ($nowT - [long]$L.RamAt) -lt $stale) {
            $mr.Value = [double]$L.RamPct
            $mr.ValueText = ("{0:N1} / {1:N0} GB" -f [double]$L.RamUsedGB, [double]$L.RamTotalGB)
            try { $script:UI.Hw['ram'].Sub2.Text = ("已用 {0:N1} GB ({1:N0}%)" -f [double]$L.RamUsedGB, [double]$L.RamPct) } catch {}
        } elseif (-not $L.Updated) { $mr.ValueText = '读取中' }
        else { $mr.ValueText = '--' }

        $mn = $script:UI.Meters['net']
        if ($null -ne $L.NetDown -and $null -ne $L.NetUp -and ($nowT - [long]$L.NetAt) -lt ([TimeSpan]::FromSeconds(10).Ticks)) {
            $rate = [double]$L.NetDown + [double]$L.NetUp
            $mn.Value = [math]::Round([math]::Min(1.0, ($rate / 51200.0)) * 100, 1)
            if ([double]$L.NetDown -ge 1024 -or [double]$L.NetUp -ge 1024) {
                $mn.ValueText = ("↓{0:N1} ↑{1:N1} MB/s" -f ([double]$L.NetDown / 1024), ([double]$L.NetUp / 1024))
            } else {
                $mn.ValueText = ("↓{0:N0} ↑{1:N0} KB/s" -f [double]$L.NetDown, [double]$L.NetUp)
            }
        } elseif ($L.Updated) { $mn.ValueText = '--' }
        else { $mn.ValueText = '读取中' }
    } catch {}
}

$clockTimer = New-Object System.Windows.Forms.Timer
$clockTimer.Interval = 1000
$clockTimer.Add_Tick({
    try { $script:UI.Clock.Text = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') } catch {}
})
$script:ClockTimer = $clockTimer

$liveTimer = New-Object System.Windows.Forms.Timer
$liveTimer.Interval = 250
$liveTimer.Add_Tick({ Update-Meters })
$script:LiveTimer = $liveTimer

# ══════════════════════════════════════════════════════════
# 托盘 / 关闭处理 / 预览 / 自检
# ══════════════════════════════════════════════════════════
$script:Tray = $null
$script:TrayIcon = $null
$script:TrayExit = $false
$script:TrayTipShown = $false

function Restore-FromTray {
    try {
        $f = $script:UI.Form
        if (-not $f) { return }
        $f.Show()
        $f.ShowInTaskbar = $true
        if ($f.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
            $f.WindowState = [System.Windows.Forms.FormWindowState]::Normal
        }
        $f.Activate()
        $f.BringToFront()
    } catch {}
}

function Show-TrayBalloon([string]$title, [string]$text, [string]$kind = 'Info') {
    try {
        if (-not $script:Tray) { return }
        $ti = [System.Windows.Forms.ToolTipIcon]::Info
        if ($kind -eq 'Warning') { $ti = [System.Windows.Forms.ToolTipIcon]::Warning }
        elseif ($kind -eq 'Error') { $ti = [System.Windows.Forms.ToolTipIcon]::Error }
        $script:Tray.BalloonTipTitle = [string]$title
        $script:Tray.BalloonTipText = [string]$text
        $script:Tray.BalloonTipIcon = $ti
        $script:Tray.ShowBalloonTip(6000)
    } catch {}
}

if (-not $Preview -and -not $SelfTest) {
    try {
        $trayBmp = New-Object Drawing.Bitmap -ArgumentList @(32, 32)
        $trayG = [Drawing.Graphics]::FromImage($trayBmp)
        $trayG.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $trayG.Clear([Drawing.Color]::Transparent)
        $trayBr = New-Object Drawing.SolidBrush -ArgumentList @([Drawing.Color]::FromArgb(0, 132, 158))
        $trayG.FillEllipse($trayBr, 1, 1, 30, 30)
        $trayBr.Dispose()
        $trayFont = New-Object Drawing.Font -ArgumentList @('Segoe UI', [single]13, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
        $trayTb = New-Object Drawing.SolidBrush -ArgumentList @([Drawing.Color]::White)
        $traySf = New-Object Drawing.StringFormat
        $traySf.Alignment = [Drawing.StringAlignment]::Center
        $traySf.LineAlignment = [Drawing.StringAlignment]::Center
        $trayG.DrawString('TX', $trayFont, $trayTb, (New-Object Drawing.RectangleF -ArgumentList @(0, 0, 32, 32)), $traySf)
        $trayTb.Dispose(); $trayFont.Dispose(); $traySf.Dispose(); $trayG.Dispose()
        $trayH = $trayBmp.GetHicon()
        $script:TrayIcon = [Drawing.Icon]::FromHandle($trayH)
        $trayBmp.Dispose()
    } catch { $script:TrayIcon = [Drawing.SystemIcons]::Application }

    try {
        $tray = New-Object System.Windows.Forms.NotifyIcon
        $tray.Icon = $script:TrayIcon
        $tray.Text = '游戏性能优化中心'
        $tray.Visible = $true
        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $miShow = $menu.Items.Add('显示主界面')
        $miExit = $menu.Items.Add('退出')
        $miShow.Add_Click({ Restore-FromTray })
        $miExit.Add_Click({
            $script:TrayExit = $true
            try { $script:Tray.Visible = $false } catch {}
            try { $script:UI.Form.Close() } catch {}
            try { [System.Windows.Forms.Application]::Exit() } catch {}
        })
        $tray.ContextMenuStrip = $menu
        $tray.Add_MouseDoubleClick({ Restore-FromTray })
        $tray.Add_BalloonTipClicked({ Restore-FromTray })
        $script:Tray = $tray
    } catch {}
}

$form.Add_FormClosing({
    param($s, $e)
    if ($script:UI.Busy) {
        $e.Cancel = $true
        [System.Windows.Forms.MessageBox]::Show($script:UI.Form, '正在应用或还原，请等待当前操作完成。', '请稍候', 'OK', 'Information') | Out-Null
        return
    }
    if ([bool]$script:GuiCfg.MinimizeToTray -and -not $script:TrayExit -and -not $Preview -and -not $SelfTest) {
        $e.Cancel = $true
        try { $script:UI.Form.Hide(); $script:UI.Form.ShowInTaskbar = $false } catch {}
        if (-not $script:TrayTipShown) {
            $script:TrayTipShown = $true
            Show-TrayBalloon '仍在后台运行' '已最小化到托盘，双击图标可恢复主界面。' 'Info'
        }
        return
    }
    try { $script:ClockTimer.Stop() } catch {}
    try { $script:LiveTimer.Stop() } catch {}
    try { if ($script:Tray) { $script:Tray.Visible = $false } } catch {}
    Stop-Sampler
})

function Save-FormPng([string]$path) {
    $bmp = New-Object Drawing.Bitmap -ArgumentList @($script:UI.Form.ClientSize.Width, $script:UI.Form.ClientSize.Height)
    $rect = New-Object Drawing.Rectangle -ArgumentList @(0, 0, $bmp.Width, $bmp.Height)
    $script:UI.Form.DrawToBitmap($bmp, $rect)
    $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

function Wait-Live([int]$ms = 8000) {
    $end = (Get-Date).AddMilliseconds($ms)
    while ((Get-Date) -lt $end) {
        [System.Windows.Forms.Application]::DoEvents()
        $L = $script:Live
        if ($L.Updated -and [int]$L.Ticks -ge 2 -and $null -ne $L.Cpu -and $null -ne $L.RamPct) { return $true }
        Start-Sleep -Milliseconds 120
    }
    return $false
}

# 初始化数据
Apply-UiScale
Update-Profiles
Update-Overview
Rebuild-Items
Refresh-BackupList
Fill-About
Show-Page 'overview'
Layout-Overview
Update-ItemSummary
$clockTimer.Start()
$liveTimer.Start()
Start-Sampler
try { Close-Splash } catch {}

if ($Preview) {
    $dir = $Preview
    try { if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } } catch {}
    $form.ShowInTaskbar = $false
    $form.Location = New-Object Drawing.Point -ArgumentList @(-10000, -10000)
    $form.Show()
    try { [TxUi.Native]::DarkTitle($form.Handle) } catch {}
    [System.Windows.Forms.Application]::DoEvents()
    Apply-DarkScrollbars
    Start-Sleep -Milliseconds 200
    $null = Wait-Live 9000
    Refresh-Snapshot
    $pageList = @('overview', 'driver', 'game', 'items', 'backup', 'diag', 'startup', 'log', 'settings', 'about')
    if ($PreviewPage -and $PreviewPage -ne 'all') {
        if ($pageList -contains $PreviewPage) { $pageList = @($PreviewPage) }
    }
    foreach ($pk in $pageList) {
        try {
            Show-Page $pk
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 350
            # 驱动页是逐个补全的: 预览时等补全跑完再截图
            if ($pk -eq 'driver') {
                try {
                    $deadline = (Get-Date).AddSeconds(20)
                    while ($script:DrvEnrichQueue -and $script:DrvEnrichQueue.Count -gt 0 -and (Get-Date) -lt $deadline) {
                        [System.Windows.Forms.Application]::DoEvents()
                        Start-Sleep -Milliseconds 15
                    }
                    [System.Windows.Forms.Application]::DoEvents()
                    Start-Sleep -Milliseconds 150
                } catch {}
            }
            try { Update-Meters } catch {}
            $pg = $script:UI.Pages[$pk]
            Write-Output "page=$pk bounds=$($pg.Bounds) content=$($content.ClientSize)"
            if ($pk -eq 'about') { $ab = $script:UI.AboutBox; Write-Output "  about visible=$($ab.Visible) bounds=$($ab.Bounds) count=$($ab.Items.Count)" }
            if ($pk -eq 'log') { $lb = $script:UI.LogBox; Write-Output "  log visible=$($lb.Visible) bounds=$($lb.Bounds) count=$($lb.Items.Count)" }
            if ($pk -eq 'items') {
                Write-Output "  tool=$($script:UI.ItemsTool.Bounds) preview=$($script:UI.BtnItemPreview.Bounds) apply=$($script:UI.BtnItemApply.Bounds) search=$($script:UI.Search.Bounds)"
                Write-Output "  search_font=$($script:UI.Search.Font.Height) item_font=$($script:UI.ItemSummary.Font.Height) nav_font=$($script:UI.NavBtns['items'].Font.Height)"
            }
            if ($pk -eq 'settings') { Write-Output "  restart=$($script:UI.SetRestart.Bounds) card=$($script:UI.ExpCard.Bounds) check=$($script:UI.SetDpiCheck.Bounds)" }
            if ($pk -eq 'driver') {
                $dv = $script:UI.DrvFlow
                Write-Output "  drv_flow count=$($dv.Controls.Count) scroll=$($dv.VerticalScroll.Value) auto=$($dv.AutoScrollPosition) bounds=$($dv.Bounds) enriched=$($script:DrvEnrichDone)/$($script:DrvEnrichTotal)"
            }
            if ($pk -eq 'driver') {
                # 预览窗口被移到屏幕外时可能收到杂散滚轮消息, 截图前归零, 保证预览稳定
                try { $script:UI.DrvFlow.AutoScrollPosition = New-Object Drawing.Point(0, 0) } catch {}
            }
            $out = Join-Path $dir ("gui_$pk.png")
            Save-FormPng $out
            Write-Output "preview=$out"
        } catch {
            Write-Output "preview_error=$pk : $($_.Exception.Message)"
        }
    }
    try { $form.Close() } catch {}
    Stop-Sampler
    exit 0
}

if ($SelfTest) {
    $form.ShowInTaskbar = $false
    $form.Location = New-Object Drawing.Point -ArgumentList @(-10000, -10000)
    $form.Show()
    try { [TxUi.Native]::DarkTitle($form.Handle) } catch {}
    [System.Windows.Forms.Application]::DoEvents()
    Apply-DarkScrollbars
    Refresh-Snapshot
    Refresh-BackupList
    Refresh-Diag $false
    Fill-About
    Show-Page 'overview'
    Layout-Overview
    $lines = @()
    $lines += 'gui_selftest=True'
    $lines += "version=v$($script:AppVersion)"
    $lines += "items=$($O.Count)"
    $lines += "snapshot_items=$(@($script:Snap.Items).Count)"
    $lines += "snapmap=$($script:SnapMap.Count)"
    $lines += "pages=$($script:UI.Pages.Count)"
    $lines += "nav=$($script:UI.NavBtns.Count)"
    $lines += "meter_count=$($script:UI.MeterCtrls.Count)"
    $lines += "item_rows=$($script:UI.ItemsFlow.Controls.Count)"
    $lines += "backup_rows=$($script:UI.BakGrid.Rows.Count)"
    $lines += "diag_rows=$($script:UI.DiagGrid.Rows.Count)"
    $lines += "has_dgpu=$HAS_DGPU"
    $lines += "has_igpu=$HAS_IGPU"
    $lines += "dpi_now=$($script:DPI_NOW) dpi_aware=$($script:DPI_AWARE) dpi_enabled=$($script:DPI_ENABLED) ui_scale=$($script:UI_SCALE)"
    $lines += "settings_file=$($script:GuiSettingsFile) settings_dpi=$($script:GuiCfg.ExperimentalDpi) settings_render=$($script:GuiCfg.ShowRenderInfo)"
    $lines += "hint=$($lblDgpuHint.Text)"
    $lines += "backup_count=$($script:UI.BakCount.Text)"
    $lines += "diag_summary=$($script:UI.DiagOk.Text) / $($script:UI.DiagWarn.Text) / $($script:UI.DiagBad.Text)"
    try {
        $tItem = @($O | Where-Object Id -eq 'gamedvr' | Select-Object -First 1)
        if ($tItem.Count -eq 0) { $tItem = @($O | Where-Object { $_.R -eq 'low' } | Select-Object -First 1) }
        $dr = Invoke-TxApply -Items $tItem -DryRun
        $lines += "dryrun_ok=$($dr.Ok) dryrun_preview=$(@($dr.Preview).Count) dryrun_errors=$(@($dr.Errors).Count) dryrun_backup=$([bool]$dr.Backup)"
    } catch { $lines += "dryrun_error=$($_.Exception.Message)" }
    $ab = $script:UI.AboutBox
    $lines += "about_len=$($ab.Items.Count) about_visible=$($ab.Visible) about_bounds=$($ab.Bounds) about_parent=$($ab.Parent.ClientSize)"
    try { $lines += "about_support=$($script:UI.SupportBar.Bounds) support_visible=$($script:UI.SupportBar.Visible) support_page=$($script:UI.AboutPage.ClientSize)" } catch {}
    try { $lines += "support_img=$([bool]$script:SupportImage) support_path=$($script:SupportImgPath)" } catch {}
    $lg = $script:UI.LogBox
    $lines += "log_len=$($lg.Items.Count) log_visible=$($lg.Visible) log_bounds=$($lg.Bounds)"
    $lines += "nav_visible=$($script:UI.NavBtns['overview'].Parent.Visible) nav_bounds=$($script:UI.NavBtns['overview'].Parent.Bounds)"
    $lines += "content_bounds=$($content.Bounds) hero_bounds=$($script:UI.Hero.Bounds)"
    $lines += "diag_cols=$($script:UI.DiagGrid.Columns.Count) diag_grid=$($script:UI.DiagGrid.Bounds)"
    foreach ($col in @($script:UI.DiagGrid.Columns)) { $lines += "  diag_col $($col.Name) w=$($col.Width) vis=$($col.Visible)" }
    $lines += "diag_ok=$($script:UI.DiagOk.Bounds) diag_warn=$($script:UI.DiagWarn.Bounds) diag_bad=$($script:UI.DiagBad.Bounds)"
    $text = ($lines -join "`r`n")
    if ($script:GuiOutFile) { $text | Out-File -FilePath $script:GuiOutFile -Encoding UTF8 }
    else { Write-Output $text }
    try { $form.Close() } catch {}
    Stop-Sampler
    exit 0
}

# ★ v5.1 首屏显示后再补齐优化项真实状态, 避免阻塞启动
$script:BootTimer = New-Object System.Windows.Forms.Timer
$script:BootTimer.Interval = 120
$script:BootTimer.Add_Tick({
    $script:BootTimer.Stop()
    try { $script:BootTimer.Dispose() } catch {}
    try {
        Set-Status '正在检测优化项状态...'
        [System.Windows.Forms.Application]::DoEvents()
        Refresh-Snapshot
        Set-Status '就绪 · 所有改动均可还原'
    } catch {
        Set-Status "状态检测失败: $($_.Exception.Message)"
    }
})

$form.Add_Shown({
    try {
        $script:UiShownAt = [DateTime]::UtcNow
        [TxUi.Native]::DarkTitle($script:UI.Form.Handle)
        Apply-DarkScrollbars
        Layout-Overview
        # 不调用 Activate(): 窗口显示后遵循系统前台规则, 不抢其他程序的焦点
        if ($script:UI.Form.QuietShow) {
            # 用户已切到别的程序: 只闪任务栏提示, 不把窗口拉到前台
            try { [TxUi.Boot]::FlashTaskbar($script:UI.Form.Handle) } catch {}
        }
        Set-Status '就绪 · 界面已显示，正在补齐优化项状态...'
        # 提前编译音频保护辅助类, 避免首次切换驱动时临时编译造成停顿
        try { $null = Initialize-TxAudioGuard } catch {}
        $script:BootTimer.Start()
    } catch {}
})


[System.Windows.Forms.Application]::Run($form)
Stop-Sampler

