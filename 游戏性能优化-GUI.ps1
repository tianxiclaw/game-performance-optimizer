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
# 游戏性能优化中心 · 可视化控制台 v5.0
# 引擎、控制台、CLI、GUI 共用 游戏性能优化.ps1 的同一套逻辑
# ══════════════════════════════════════════════════════════

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

# ── 界面设置 (实验性功能) ─────────────────────────────────
# 设置文件默认放在脚本目录; TX_GUI_SETTINGS 仅用于测试时指向临时文件
$script:GuiSettingsFile = Join-Path $PSScriptRoot 'gui-settings.json'
if ($env:TX_GUI_SETTINGS) { $script:GuiSettingsFile = [string]$env:TX_GUI_SETTINGS }
$script:GuiCfg = [ordered]@{
    ExperimentalDpi = $false
    ShowRenderInfo  = $false
}

function Load-GuiSettings {
    try {
        if (-not (Test-Path -LiteralPath $script:GuiSettingsFile)) { return }
        $j = Get-Content -Raw -LiteralPath $script:GuiSettingsFile | ConvertFrom-Json
        if ($null -ne $j.ExperimentalDpi) { $script:GuiCfg.ExperimentalDpi = [bool]$j.ExperimentalDpi }
        if ($null -ne $j.ShowRenderInfo)  { $script:GuiCfg.ShowRenderInfo  = [bool]$j.ShowRenderInfo }
    } catch {}
}

function Save-GuiSettings {
    try {
        $obj = [ordered]@{
            Version         = 1
            ExperimentalDpi = [bool]$script:GuiCfg.ExperimentalDpi
            ShowRenderInfo  = [bool]$script:GuiCfg.ShowRenderInfo
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
$script:C_BG      = [Drawing.Color]::FromArgb(11,14,20)
$script:C_PANEL   = [Drawing.Color]::FromArgb(18,23,34)
$script:C_PANEL2  = [Drawing.Color]::FromArgb(14,19,28)
$script:C_BORDER  = [Drawing.Color]::FromArgb(38,49,68)
$script:C_TEXT    = [Drawing.Color]::FromArgb(230,237,243)
$script:C_SUB     = [Drawing.Color]::FromArgb(143,163,184)
$script:C_DIM     = [Drawing.Color]::FromArgb(100,116,139)
$script:C_CYAN    = [Drawing.Color]::FromArgb(0,229,255)
$script:C_GREEN   = [Drawing.Color]::FromArgb(0,230,118)
$script:C_ORANGE  = [Drawing.Color]::FromArgb(255,179,0)
$script:C_RED     = [Drawing.Color]::FromArgb(255,82,82)
$script:C_PURPLE  = [Drawing.Color]::FromArgb(124,77,255)
$script:C_BLUE    = [Drawing.Color]::FromArgb(41,121,255)
$script:C_GREEN_BG  = [Drawing.Color]::FromArgb(18,53,40)
$script:C_GREEN_BD  = [Drawing.Color]::FromArgb(31,107,74)
$script:C_ORANGE_BG = [Drawing.Color]::FromArgb(42,33,19)
$script:C_ORANGE_BD = [Drawing.Color]::FromArgb(122,90,24)
$script:C_GRAY_BG   = [Drawing.Color]::FromArgb(26,33,48)
$script:C_GRAY_BD   = [Drawing.Color]::FromArgb(51,65,85)

$script:FF = 'Microsoft YaHei UI'
try { $null = New-Object Drawing.FontFamily -ArgumentList $script:FF } catch { $script:FF = 'Microsoft YaHei' }

function F([double]$size, [bool]$bold = $false) {
    $st = [Drawing.FontStyle]::Regular
    if ($bold) { $st = [Drawing.FontStyle]::Bold }
    return New-Object Drawing.Font -ArgumentList @([string]$script:FF, [single]$size, $st)
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

function New-Check($parent, $text, [int]$x, [int]$y, [int]$w, [int]$h, [bool]$checked = $false) {
    $c = New-Object TxUi.Check
    $c.Text = [string]$text
    $c.Location = New-Object Drawing.Point -ArgumentList @($x, $y)
    $c.Size = New-Object Drawing.Size -ArgumentList @($w, $h)
    $c.ForeColor = $script:C_TEXT
    $c.BackColor = [Drawing.Color]::Transparent
    $c.Font = F 9
    $c.UiScale = [single]$script:UI_SCALE
    $c.Checked = $checked
    $parent.Controls.Add($c)
    return $c
}

function New-Combo($parent, [int]$x, [int]$y, [int]$w) {
    $c = New-Object System.Windows.Forms.ComboBox
    $c.Location = New-Object Drawing.Point -ArgumentList @($x, $y)
    $c.Size = New-Object Drawing.Size -ArgumentList @($w, 28)
    $c.DropDownStyle = 'DropDownList'
    $c.FlatStyle = 'Flat'
    $c.BackColor = $script:C_PANEL2
    $c.ForeColor = $script:C_TEXT
    $c.Font = F 9
    $c.DrawMode = 'OwnerDrawFixed'
    $c.ItemHeight = [int][Math]::Round(22 * $script:UI_SCALE)
    $c.Add_DrawItem({
        param($s, $e)
        if ($e.Index -lt 0) { return }
        $sc = [double]$script:UI_SCALE
        $bg = $script:C_PANEL2
        if (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0) { $bg = [Drawing.Color]::FromArgb(30,42,58) }
        $br = New-Object Drawing.SolidBrush -ArgumentList @($bg)
        $e.Graphics.FillRectangle($br, $e.Bounds)
        $br.Dispose()
        $tb = New-Object Drawing.SolidBrush -ArgumentList @($script:C_TEXT)
        $txt = $s.Items[$e.Index].ToString()
        $e.Graphics.DrawString($txt, $s.Font, $tb, ($e.Bounds.X + 6 * $sc), ($e.Bounds.Y + 3 * $sc))
        $tb.Dispose()
    })
    $parent.Controls.Add($c)
    return $c
}

function New-TextBox($parent, [int]$x, [int]$y, [int]$w, [int]$h, [string]$placeholder) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object Drawing.Point -ArgumentList @($x, $y)
    $t.Size = New-Object Drawing.Size -ArgumentList @($w, $h)
    $t.BorderStyle = 'FixedSingle'
    $t.BackColor = $script:C_PANEL2
    $t.ForeColor = $script:C_DIM
    $t.Font = F 9
    $t.Text = $placeholder
    $t.Tag = @{ Placeholder = $placeholder; Active = $false }
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
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace TxUi
{
    public static class Native
    {
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
            try { SetWindowTheme(h, "DarkMode_Explorer", null); } catch { }
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
            using (SolidBrush bg = new SolidBrush(BackColor)) g.FillRectangle(bg, ClientRectangle);
            using (Font f1 = new Font("Microsoft YaHei UI", 9f))
            {
                using (SolidBrush br = new SolidBrush(Color.FromArgb(143, 163, 184))) g.DrawString(Caption, f1, br, 0, 0);
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
                    using (SolidBrush br2 = new SolidBrush(Color.FromArgb(235, 241, 248))) g.DrawString(ValueText, f2, br2, Width - sz.Width - sc, -sc);
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
            using (SolidBrush b = new SolidBrush(Color.FromArgb(30, 39, 54))) g.FillPath(b, p);
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

    public class SplashForm : Form
    {
        private Label _sub;
        private Label _close;
        private ProgressBar _bar;
        private int _radius = 18;
        public bool UserClosed = false;

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
            TopMost = true;
            DoubleBuffered = true;
            Font = new Font("Microsoft YaHei UI", 9f);

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

            _bar = new ProgressBar();
            _bar.SetBounds(32, 112, 396, 7);
            _bar.Style = ProgressBarStyle.Marquee;
            _bar.MarqueeAnimationSpeed = 26;
            Controls.Add(_bar);

            Label ver = new Label();
            ver.Text = "v5.0 · 硬件兼容版 · 所有改动均可还原";
            ver.Font = new Font("Microsoft YaHei UI", 8f);
            ver.ForeColor = Color.FromArgb(100, 116, 139);
            ver.BackColor = Color.Transparent;
            ver.SetBounds(32, 142, 396, 20);
            Controls.Add(ver);

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

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x84)
            {
                base.WndProc(ref m);
                if ((int)m.Result == 1)
                {
                    int lp = m.LParam.ToInt32();
                    Point pt = PointToClient(new Point((short)(lp & 0xFFFF), (short)((lp >> 16) & 0xFFFF)));
                    if (!_close.Bounds.Contains(pt)) m.Result = (IntPtr)2;
                }
                return;
            }
            base.WndProc(ref m);
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

# 高 DPI 状态已在脚本入口处确定 (必须先于 GDI+ 初始化)

# ── 启动画面 (独立 STA 线程, 加载期间仍可拖动/关闭) ───────
$script:SplashState = [hashtable]::Synchronized(@{
    Ready = $false; Closed = $false; Done = $false; Form = $null; Error = $null
    Scale = [double]$script:UI_SCALE
})
$script:SplashScript = @'
param($State)
$ErrorActionPreference = 'SilentlyContinue'
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $f = New-Object TxUi.SplashForm -ArgumentList @([single]$State.Scale)
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
$form = New-Object System.Windows.Forms.Form
$form.Text = '游戏性能优化中心 v5.0'
$form.BackColor = $script:C_BG
$form.ForeColor = $script:C_TEXT
$form.Font = F 9
$form.FormBorderStyle = 'Sizable'
$form.MaximizeBox = $true
$form.MinimizeBox = $true
$form.StartPosition = 'CenterScreen'
$form.ShowIcon = $false
$form.AutoScaleMode = 'None'
$wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
# WorkingArea 在 PerMonitorV2 下是物理像素, 先换算回 96-DPI 逻辑尺寸
$maxW = [int]($wa.Width / $script:UI_SCALE) - 40
$maxH = [int]($wa.Height / $script:UI_SCALE) - 40
if ($maxW -lt 900) { $maxW = 900 }
if ($maxH -lt 560) { $maxH = 560 }
$fw = [Math]::Min(1240, $maxW)
$fh = [Math]::Min(800, $maxH)
if ($fw -lt 1080) { $fw = [Math]::Min(1080, $maxW) }
if ($fh -lt 660)  { $fh = [Math]::Min(660, $maxH) }
$script:MinW = [Math]::Min(1080, $fw)
$script:MinH = [Math]::Min(660, $fh)
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
$null = New-Label $top '天禧 · 性能优化中心' 70 33 240 18 8 $false $script:C_DIM
$machineTxt = '未知机型'
if ($script:Snap.Machine) { $machineTxt = [string]$script:Snap.Machine }
$script:MachineTxt = $machineTxt
$lblTopMachine = New-Label $top $machineTxt ($fw - 640) 19 300 22 9 $false $script:C_SUB 'MiddleRight'
$lblTopMachine.Anchor = 'Top, Right'
$adminTxt = '管理员'
if (-not $isAdmin) { $adminTxt = '非管理员' }
$badgeAdmin = New-Badge $top $adminTxt ($fw - 326) 18 72 24 $script:C_GREEN_BG $script:C_GREEN_BD $script:C_GREEN 8
if (-not $isAdmin) { $badgeAdmin.Fill = $script:C_ORANGE_BG; $badgeAdmin.BorderColor = $script:C_ORANGE_BD; $badgeAdmin.ForeColor = $script:C_ORANGE }
$badgeAdmin.Anchor = 'Top, Right'
$lblClock = New-Label $top '' ($fw - 244) 19 224 22 9 $false $script:C_SUB 'MiddleRight'
$lblClock.Anchor = 'Top, Right'
$topLine = New-Object System.Windows.Forms.Panel
$topLine.Dock = 'Bottom'
$topLine.Height = 1
$topLine.BackColor = $script:C_BORDER
$top.Controls.Add($topLine)

# 左侧导航
$nav = New-Object System.Windows.Forms.Panel
$nav.Dock = 'Left'
$nav.Width = 200
$nav.BackColor = $script:C_PANEL2
$form.Controls.Add($nav)
$null = New-Label $nav '功能导航' 20 16 160 20 8 $true $script:C_DIM
$navDefs = @(
    @{ Key='overview'; Text='概览';     Glyph='01' },
    @{ Key='items';    Text='优化项';   Glyph='02' },
    @{ Key='backup';   Text='备份还原'; Glyph='03' },
    @{ Key='diag';     Text='诊断报告'; Glyph='04' },
    @{ Key='log';      Text='运行日志'; Glyph='05' },
    @{ Key='settings'; Text='设置';     Glyph='06' },
    @{ Key='about';    Text='关于';     Glyph='07' }
)
$ny = 46
foreach ($nd in $navDefs) {
    $nb = New-Object System.Windows.Forms.Button
    $nb.Text = "  $($nd.Glyph)   $($nd.Text)"
    $nb.Location = New-Object Drawing.Point -ArgumentList @(12, $ny)
    $nb.Size = New-Object Drawing.Size -ArgumentList @(176, 42)
    $nb.FlatStyle = 'Flat'
    $nb.FlatAppearance.BorderSize = 0
    $nb.TextAlign = 'MiddleLeft'
    $nb.Padding = New-Object System.Windows.Forms.Padding -ArgumentList @(8, 0, 0, 0)
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
    $nb.Tag = @{ Page = $nd.Key; Bar = $bar }
    $nb.Add_Click({
        param($s, $e)
        Show-Page $s.Tag.Page
    })
    $nb.Add_MouseEnter({
        param($s, $e)
        try {
            if ($script:UI.CurrentPage -ne $s.Tag.Page) {
                $s.BackColor = [Drawing.Color]::FromArgb(24, 33, 48)
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
    $ny += 50
}
$navFoot = New-Label $nav "v5.0`n核显 / 独显 / 混合显卡`n本地运行 · 不上传数据" 20 ($fh - 200) 164 64 8 $false $script:C_DIM
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
$lblStatusR = New-Label $statusBar "v5.0 · $statusMode" ($fw - 280) 3 260 20 8.5 $false $script:C_DIM 'MiddleRight'
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
$ov.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, 720)

$hero = New-Card $ov 24 20 ($cw - 48) 156 16 $script:C_PANEL $script:C_BORDER
$script:UI.Hero = $hero
$script:HF = @{
    Tag = F 8 $true
    Title = F 24 $true
    Sub = F 10
    Stat = F 26 $true
    StatLabel = F 8
    Small = F 8
}
$hero.Add_Paint({
    param($s, $e)
    $sc = [double]$script:UI_SCALE
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $r = New-Object Drawing.Rectangle -ArgumentList @(0, 0, ($s.Width - 1), ($s.Height - 1))
    $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @($r, [Drawing.Color]::FromArgb(12, 38, 52), [Drawing.Color]::FromArgb(30, 26, 72), [single](12 * $sc))
    $g.FillRectangle($lg, $r)
    $lg.Dispose()
    $accentRect = New-Object Drawing.Rectangle -ArgumentList @(0, 1, $s.Width, [int](3 * $sc))
    $ag = New-Object System.Drawing.Drawing2D.LinearGradientBrush -ArgumentList @($accentRect, $script:C_CYAN, $script:C_PURPLE, [single]0)
    $g.FillRectangle($ag, $accentRect)
    $ag.Dispose()
    $glow1 = New-Object Drawing.SolidBrush -ArgumentList @([Drawing.Color]::FromArgb(16, 0, 229, 255))
    $g.FillEllipse($glow1, ($s.Width - 240 * $sc), (-90 * $sc), (260 * $sc), (260 * $sc))
    $glow1.Dispose()
    $glow2 = New-Object Drawing.SolidBrush -ArgumentList @([Drawing.Color]::FromArgb(14, 124, 77, 255))
    $g.FillEllipse($glow2, ($s.Width - 430 * $sc), (70 * $sc), (240 * $sc), (200 * $sc))
    $glow2.Dispose()
    $bTag = New-Object Drawing.SolidBrush -ArgumentList @($script:C_CYAN)
    $g.DrawString('TIANXI PERFORMANCE LAB · V5.0', $script:HF.Tag, $bTag, (32 * $sc), (18 * $sc))
    $bTag.Dispose()
    $bTitle = New-Object Drawing.SolidBrush -ArgumentList @($script:C_TEXT)
    $g.DrawString('游戏性能优化中心', $script:HF.Title, $bTitle, (30 * $sc), (36 * $sc))
    $bTitle.Dispose()
    $sub = '正在读取硬件信息'
    try {
        $gs = @($script:Snap.Gpus | ForEach-Object { $t = '核显'; if ($_.Dedicated) { $t = '独显' }; if ($_.Basic) { $t = '基础显示' }; if ($_.Virtual) { $t = '虚拟'; }; "$($_.Name) [$t]" })
        $sub = "$($script:MachineTxt) · $($gs -join ' + ') · $(if($isAdmin){'管理员模式'}else{'非管理员模式'})"
        if (@($script:Snap.Gpus | Where-Object Dedicated).Count -eq 0) { $sub += ' · 未检测到独显' }
    } catch {}
    $bSub = New-Object Drawing.SolidBrush -ArgumentList @([Drawing.Color]::FromArgb(168, 199, 216))
    $g.DrawString($sub, $script:HF.Sub, $bSub, (32 * $sc), (82 * $sc))
    $bSub.Dispose()
    $chk = 0
    try { $chk = [int]$script:Snap.Summary.Checking } catch {}
    $stats = @(
        @{ V = $(if ($chk -gt 0) { '--' } else { $script:Snap.Summary.Applied });      T = '已生效'; C = $script:C_GREEN },
        @{ V = $(if ($chk -gt 0) { '--' } else { $script:Snap.Summary.Pending });      T = '待应用'; C = $script:C_ORANGE },
        @{ V = $(if ($chk -gt 0) { '--' } else { $script:Snap.Summary.NotApplicable });T = '不适用'; C = $script:C_DIM }
    )
    $sx = $s.Width - 330 * $sc
    foreach ($st in $stats) {
        $bV = New-Object Drawing.SolidBrush -ArgumentList @($st.C)
        $g.DrawString([string]$st.V, $script:HF.Stat, $bV, $sx, (40 * $sc))
        $bV.Dispose()
        $bL = New-Object Drawing.SolidBrush -ArgumentList @([Drawing.Color]::FromArgb(143, 163, 184))
        $g.DrawString($st.T, $script:HF.StatLabel, $bL, ($sx + 3 * $sc), (88 * $sc))
        $bL.Dispose()
        $sx += 100 * $sc
    }
    $hp = New-Object Drawing.Pen -ArgumentList @([Drawing.Color]::FromArgb(52, 72, 95), 1)
    $g.DrawRectangle($hp, 0, 0, $s.Width - 1, $s.Height - 1)
    $hp.Dispose()
})
$btnQuick = New-Btn $hero '一键优化' 32 110 118 34 $script:C_GREEN ([Drawing.Color]::FromArgb(6, 22, 13))
$btnQuick.Add_Click({ Invoke-QuickOptimize })
$btnPreview = New-Btn $hero '预览变更' 158 110 110 34 ([Drawing.Color]::FromArgb(22, 48, 62)) ([Drawing.Color]::FromArgb(207, 232, 245))
$btnPreview.Add_Click({ Invoke-PreviewSelected })
$btnRestoreLatest = New-Btn $hero '撤销上次优化' 276 110 128 34 ([Drawing.Color]::FromArgb(22, 36, 50)) ([Drawing.Color]::FromArgb(190, 210, 225))
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
            $card.Fill = [Drawing.Color]::FromArgb(24, 31, 45)
            $card.BorderColor = [Drawing.Color]::FromArgb(130, $accent.R, $accent.G, $accent.B)
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
$hwW = [int](($cw - 48 - 36) / 4)
$hwDefs = @(
    @{ Key='cpu';  Label='CPU';  Accent=$script:C_CYAN },
    @{ Key='gpu';  Label='GPU';  Accent=$script:C_PURPLE },
    @{ Key='ram';  Label='RAM';  Accent=$script:C_GREEN },
    @{ Key='disk'; Label='显示 / 存储'; Accent=$script:C_ORANGE }
)
$script:UI.HwCards = @()
$script:UI.Hw = @{}
$hx = 24
foreach ($hd in $hwDefs) {
    $card = New-Card $ov $hx 192 $hwW 118 12 $script:C_PANEL $script:C_BORDER
    $card.Anchor = 'Top, Left'
    $null = New-Badge $card $hd.Label 14 12 52 22 $script:C_GRAY_BG $script:C_GRAY_BD $hd.Accent 8
    $v = New-Label $card '--' 14 38 ($hwW - 28) 28 11 $true $script:C_TEXT
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
$mon = New-Card $ov 24 322 ($cw - 48) 170 12 $script:C_PANEL $script:C_BORDER
$script:UI.Mon = $mon
$null = New-Label $mon '实时监控' 18 12 160 22 11 $true $script:C_TEXT
$null = New-Label $mon '每 0.25 秒刷新 · 仅本机读取' 112 15 260 18 8 $false $script:C_DIM
$script:UI.Meters = @{}
$meterDefs = @(
    @{ Key='cpu'; Caption='CPU 使用率'; Accent=$script:C_CYAN },
    @{ Key='gpu'; Caption='GPU 3D 负载'; Accent=$script:C_PURPLE },
    @{ Key='ram'; Caption='内存占用';   Accent=$script:C_GREEN },
    @{ Key='net'; Caption='网络'; Accent=$script:C_ORANGE }
)
$script:UI.MeterCtrls = @()
foreach ($md in $meterDefs) {
    $m = New-Object TxUi.Meter
    $m.Caption = $md.Caption
    $m.ValueText = '--'
    $m.Accent = $md.Accent
    $m.BackColor = $script:C_PANEL
    $m.UiScale = [single]$script:UI_SCALE
    $m.Height = 58
    $mon.Controls.Add($m)
    $script:UI.Meters[$md.Key] = $m
    $script:UI.MeterCtrls += $m
}
$innerMon = [int](($cw - 48 - 36 - 36) / 4)
for ($i = 0; $i -lt 4; $i++) {
    $script:UI.MeterCtrls[$i].Location = New-Object Drawing.Point -ArgumentList @((18 + $i * ($innerMon + 12)), 48)
    $script:UI.MeterCtrls[$i].Width = $innerMon
}
$null = New-Label $mon '数据来源: 系统内核计数器 / CIM · 不联网、不上传' 18 140 420 18 8 $false $script:C_DIM

# 待应用项
$leftW = [int](($cw - 48 - 12) * 0.58)
$pendCard = New-Card $ov 24 506 $leftW 180 12 $script:C_PANEL $script:C_BORDER
$script:UI.PendCard = $pendCard
$script:UI.PendTitle = New-Label $pendCard '待应用项' 16 12 220 22 11 $true $script:C_TEXT
$btnGoItems = New-Btn $pendCard '查看全部' ($leftW - 92) 12 76 24 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_CYAN 8 $false
$btnGoItems.Anchor = 'Top, Right'
$btnGoItems.Add_Click({ Show-Page 'items' })
$script:UI.PendLabels = @()
for ($i = 0; $i -lt 5; $i++) {
    $pl = New-Label $pendCard '' 16 (44 + $i * 24) ($leftW - 32) 22 9 $false $script:C_SUB
    $script:UI.PendLabels += $pl
}

# 系统状态
$rightW = $cw - 48 - $leftW - 12
$sysCard = New-Card $ov (24 + $leftW + 12) 506 $rightW 180 12 $script:C_PANEL $script:C_BORDER
$script:UI.SysCard = $sysCard
$null = New-Label $sysCard '系统状态' 16 12 160 22 11 $true $script:C_TEXT
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
# 优化项页
# ══════════════════════════════════════════════════════════
$script:SnapMap = @{}
foreach ($x in @($script:Snap.Items)) { $script:SnapMap[$x.Id] = $x }

$itPage = New-Page 'items'
$script:UI.ItemsPage = $itPage
$tw = $cw - 40
$tool = New-Card $itPage 20 16 $tw 104 12 $script:C_PANEL $script:C_BORDER
$tool.Anchor = 'Top, Left, Right'
$script:UI.ItemsTool = $tool

$search = New-TextBox $tool 16 14 230 30 '搜索优化项名称或说明...'
$script:UI.Search = $search
$search.Add_TextChanged({ Rebuild-Items })
$catCombo = New-Combo $tool 258 15 120
$script:UI.CatCombo = $catCombo
[void]$catCombo.Items.Add('全部分类')
foreach ($cat in @($O.Cat | Select-Object -Unique)) { [void]$catCombo.Items.Add([string]$cat) }
$catCombo.SelectedIndex = 0
$catCombo.Add_SelectedIndexChanged({ Rebuild-Items })
$statusCombo = New-Combo $tool 390 15 110
$script:UI.StatusCombo = $statusCombo
foreach ($st in @('全部状态','待应用','已生效','不适用')) { [void]$statusCombo.Items.Add($st) }
$statusCombo.SelectedIndex = 0
$statusCombo.Add_SelectedIndexChanged({ Rebuild-Items })
$onlyRec = New-Check $tool '仅推荐项' 512 18 88 24
$script:UI.OnlyRec = $onlyRec
$onlyRec.Add_CheckedChanged({ Rebuild-Items })
$btnSelRec = New-Btn $tool '全选推荐' 610 14 90 30 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_GREEN 8
$btnSelNone = New-Btn $tool '全不选' 708 14 72 30 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_SUB 8
$btnSelRec.Add_Click({ Select-Recommended })
$btnSelNone.Add_Click({
    foreach ($it in $O) { $it.E = $false }
    Rebuild-Items
    Set-Status '已取消全部勾选'
})

$profileCombo = New-Combo $tool 16 60 160
$script:UI.ProfileCombo = $profileCombo
$btnPLoad = New-Btn $tool '载入方案' 184 60 76 30 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_CYAN 8
$btnPSave = New-Btn $tool '保存方案' 268 60 76 30 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_SUB 8
$restoreChk = New-Check $tool '应用前创建还原点' 352 62 150 24
$script:UI.RestoreChk = $restoreChk
$btnItemPreview = New-Btn $tool '预览变更' ($tw - 268) 60 120 30 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_TEXT 9
$btnItemPreview.Anchor = 'Top, Right'
$btnItemApply = New-Btn $tool '应用选中项' ($tw - 136) 60 120 30 $script:C_GREEN ([Drawing.Color]::FromArgb(6, 22, 13)) 9
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

$lblItemSummary = New-Label $itPage '已选 0 项' 24 128 360 22 9 $false $script:C_SUB
$script:UI.ItemSummary = $lblItemSummary
if ($HAS_DGPU) {
    $hintText = '已检测到独立显卡：独显专属优化项已加入列表'
} else {
    $hintText = '核显机型：独显专属项已隐藏（检测到独显后会自动出现）'
}
$lblDgpuHint = New-Label $itPage $hintText ($cw - 480) 128 456 22 8.5 $false $script:C_DIM 'MiddleRight'
$lblDgpuHint.Anchor = 'Top, Right'

$itemsFlow = New-Object TxUi.Flow
$itemsFlow.Location = New-Object Drawing.Point -ArgumentList @(20, 156)
$itemsFlow.Size = New-Object Drawing.Size -ArgumentList @(($cw - 40), 500)
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
        $script:UI.ItemsFlow.Height = $s.ClientSize.Height - [int](176 * $sc)
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
    $tgt = New-Label $row ("目标: " + [string]$it.TL) ($rowW - [int](436 * $sc)) ([int](30 * $sc)) ([int](118 * $sc)) ([int](20 * $sc)) 8 $false $script:C_CYAN 'MiddleRight'
    $tgt.Anchor = 'Top, Right'

    $catColor = $script:C_GRAY_BG
    $catBorder = $script:C_GRAY_BD
    $catBadge = New-Badge $row ([string]$it.Cat) ($rowW - [int](312 * $sc)) ([int](19 * $sc)) ([int](72 * $sc)) ([int](24 * $sc)) $catColor $catBorder $script:C_SUB 7.5
    $catBadge.Anchor = 'Top, Right'

    if ($si.NeedsReboot) {
        $rb = New-Badge $row '需重启' ($rowW - [int](238 * $sc)) ([int](19 * $sc)) ([int](64 * $sc)) ([int](24 * $sc)) ([Drawing.Color]::FromArgb(35, 26, 58)) ([Drawing.Color]::FromArgb(91, 61, 148)) ([Drawing.Color]::FromArgb(196, 181, 253)) 7.5
        $rb.Anchor = 'Top, Right'
    }

    $riskText = '低风险'; $riskFg = $script:C_GREEN; $riskBg = $script:C_GREEN_BG; $riskBd = $script:C_GREEN_BD
    if ($it.R -eq 'med') { $riskText = '中风险'; $riskFg = $script:C_ORANGE; $riskBg = $script:C_ORANGE_BG; $riskBd = $script:C_ORANGE_BD }
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

    $btnCopy = New-Btn $dlg '复制预览' 592 566 100 34 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_TEXT 9
    $btnCopy.Anchor = 'Bottom, Right'
    $btnClose = New-Btn $dlg '关闭' 704 566 116 34 $script:C_CYAN ([Drawing.Color]::FromArgb(4, 20, 26)) 9
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
$bakTool = New-Card $bakPage 20 16 $bw 64 12 $script:C_PANEL $script:C_BORDER
$bakTool.Anchor = 'Top, Left, Right'
$script:UI.BakTool = $bakTool
$btnBakRestore = New-Btn $bakTool '还原选中' 16 16 104 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_TEXT 9
$btnBakLatest = New-Btn $bakTool '还原最近' 128 16 104 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_TEXT 9
$btnBakAll = New-Btn $bakTool '全部还原' 240 16 104 32 ([Drawing.Color]::FromArgb(46, 25, 30)) $script:C_RED 9
$btnBakPoint = New-Btn $bakTool '创建还原点' 352 16 112 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_CYAN 9
$btnBakOpen = New-Btn $bakTool '打开备份目录' 472 16 116 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_SUB 9
$btnBakRefresh = New-Btn $bakTool '刷新' 596 16 72 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_SUB 9
$btnBakRestore.Add_Click({ Invoke-RestoreSelected })
$btnBakLatest.Add_Click({ Invoke-RestoreLatest })
$btnBakAll.Add_Click({ Invoke-RestoreAll })
$btnBakPoint.Add_Click({ Invoke-CreatePoint })
$btnBakOpen.Add_Click({ try { Start-Process explorer.exe -ArgumentList $BK } catch {} })
$btnBakRefresh.Add_Click({ Refresh-BackupList; Set-Status '备份列表已刷新' })

$bakStats = New-Card $bakPage 20 92 $bw 72 12 $script:C_PANEL $script:C_BORDER
$bakStats.Anchor = 'Top, Left, Right'
$script:UI.BakStats = $bakStats
$statW = [int](($bw - 32) / 4)
$script:UI.BakCount = New-Label $bakStats '0' 16 10 $statW 26 13 $true $script:C_TEXT
$null = New-Label $bakStats 'JSON 备份数量' 16 38 $statW 18 8 $false $script:C_DIM
$script:UI.BakLatest = New-Label $bakStats '无' (16 + $statW) 10 $statW 26 11 $true $script:C_TEXT
$null = New-Label $bakStats '最近一次备份' (16 + $statW) 38 $statW 18 8 $false $script:C_DIM
$script:UI.BakRegs = New-Label $bakStats '0' (16 + $statW * 2) 10 $statW 26 13 $true $script:C_TEXT
$null = New-Label $bakStats '.reg 快照目录' (16 + $statW * 2) 38 $statW 18 8 $false $script:C_DIM
$script:UI.BakLast = New-Label $bakStats '无记录' (16 + $statW * 3) 10 $statW 26 10 $true $script:C_TEXT
$null = New-Label $bakStats '上次应用记录' (16 + $statW * 3) 38 $statW 18 8 $false $script:C_DIM

function Style-Grid($g) {
    $g.BackgroundColor = $script:C_PANEL
    $g.BorderStyle = 'None'
    $g.EnableHeadersVisualStyles = $false
    $g.ColumnHeadersBorderStyle = 'None'
    $g.ColumnHeadersDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(22, 32, 46)
    $g.ColumnHeadersDefaultCellStyle.ForeColor = $script:C_SUB
    $g.ColumnHeadersDefaultCellStyle.Font = F 8.5 $true
    $g.ColumnHeadersDefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding -ArgumentList @(6, 0, 6, 0)
    $g.ColumnHeadersHeight = 34
    $g.DefaultCellStyle.BackColor = $script:C_PANEL
    $g.DefaultCellStyle.ForeColor = $script:C_TEXT
    $g.DefaultCellStyle.SelectionBackColor = [Drawing.Color]::FromArgb(30, 42, 58)
    $g.DefaultCellStyle.SelectionForeColor = $script:C_TEXT
    $g.DefaultCellStyle.Font = F 9
    $g.DefaultCellStyle.Padding = New-Object System.Windows.Forms.Padding -ArgumentList @(6, 0, 6, 0)
    $g.AlternatingRowsDefaultCellStyle.BackColor = [Drawing.Color]::FromArgb(16, 21, 31)
    $g.GridColor = [Drawing.Color]::FromArgb(28, 38, 54)
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
$bakGrid.Location = New-Object Drawing.Point -ArgumentList @(20, 180)
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
            $script:UI.BakLast.Text = "$($la.Time) · $(@($la.Items).Count) 项"
        } else {
            $script:UI.BakLast.Text = '无记录'
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
# 诊断报告页
# ══════════════════════════════════════════════════════════
$diagPage = New-Page 'diag'
$script:UI.DiagPage = $diagPage
$dgTool = New-Card $diagPage 20 16 ($cw - 40) 64 12 $script:C_PANEL $script:C_BORDER
$dgTool.Anchor = 'Top, Left, Right'
$script:UI.DiagTool = $dgTool
$btnDiagRefresh = New-Btn $dgTool '刷新诊断' 16 16 104 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_TEXT 9
$btnDiagExport = New-Btn $dgTool '导出报告' 128 16 104 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_CYAN 9
$btnDiagCopy = New-Btn $dgTool '复制全部' 240 16 104 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_SUB 9
$btnDiagRefresh.Add_Click({ Refresh-Diag $true })
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
$lblDiagOk = New-Label $dgTool '正常 0' ($cw - 340) 20 80 24 9 $true $script:C_GREEN 'MiddleRight'
$lblDiagOk.Anchor = 'Top, Right'
$lblDiagWarn = New-Label $dgTool '注意 0' ($cw - 250) 20 80 24 9 $true $script:C_ORANGE 'MiddleRight'
$lblDiagWarn.Anchor = 'Top, Right'
$lblDiagBad = New-Label $dgTool '风险 0' ($cw - 160) 20 80 24 9 $true $script:C_RED 'MiddleRight'
$lblDiagBad.Anchor = 'Top, Right'
$script:UI.DiagOk = $lblDiagOk
$script:UI.DiagWarn = $lblDiagWarn
$script:UI.DiagBad = $lblDiagBad

$diagGrid = New-Object System.Windows.Forms.DataGridView
$diagGrid.Location = New-Object Drawing.Point -ArgumentList @(20, 96)
$diagGrid.Size = New-Object Drawing.Size -ArgumentList @(($cw - 40), 580)
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
        $script:UI.DiagOk.Text = "正常 $ok"
        $script:UI.DiagWarn.Text = "注意 $warn"
        $script:UI.DiagBad.Text = "风险 $bad"
        $script:UI.DiagDirty = $false
        Set-Status "诊断完成: 正常 $ok / 注意 $warn / 风险 $bad"
    } catch {
        Set-Status "诊断失败: $($_.Exception.Message)"
    }
}

# ══════════════════════════════════════════════════════════
# 运行日志页
# ══════════════════════════════════════════════════════════
$logPage = New-Page 'log'
$script:UI.LogPage = $logPage
$lgTool = New-Card $logPage 20 16 ($cw - 40) 56 12 $script:C_PANEL $script:C_BORDER
$lgTool.Anchor = 'Top, Left, Right'
$script:UI.LogTool = $lgTool
$btnLogClear = New-Btn $lgTool '清空界面' 16 12 96 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_TEXT 9
$btnLogOpen = New-Btn $lgTool '打开日志文件' 120 12 116 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_CYAN 9
$btnLogDir = New-Btn $lgTool '打开脚本目录' 244 12 116 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_SUB 9
$btnLogCopy = New-Btn $lgTool '复制日志' 368 12 96 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_SUB 9
$chkLogAuto = New-Check $lgTool '自动滚动' 480 16 96 24 $true
$script:UI.LogAuto = $chkLogAuto
$btnLogClear.Add_Click({ try { $script:UI.LogBox.Items.Clear() } catch {} })
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
$logBox.Location = New-Object Drawing.Point -ArgumentList @(20, 88)
$logBox.Size = New-Object Drawing.Size -ArgumentList @(($cw - 40), 560)
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
        if (($e.Index % 2) -eq 1) { $bg = [Drawing.Color]::FromArgb(15, 20, 30) }
        if (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0) { $bg = [Drawing.Color]::FromArgb(24, 35, 50) }
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
        if ($script:UI.LogAuto.Checked) { $lb.TopIndex = [Math]::Max(0, $lb.Items.Count - 1) }
    } catch {}
}

$script:LogSink = {
    param($line, $color)
    Append-LogLine $line $color
    if ($script:UI.Busy) { Set-Status ([string]$line) }
}
foreach ($lb in @($script:LogBuffer)) { Append-LogLine $lb.Line $lb.Color }
Append-LogLine "[引擎] 游戏性能优化脚本 v5.0 已加载 · 共 $($O.Count) 项优化" 'DarkGray'
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
$null = New-Label $aboutPage '游戏性能优化中心' 24 18 420 32 16 $true $script:C_TEXT
$null = New-Label $aboutPage '可视化控制台 · 引擎 / 控制台 / CLI 共用同一套逻辑' 24 50 620 20 9 $false $script:C_SUB
$aboutBadges = @(
    @{ T='核显兼容'; C=$script:C_CYAN },
    @{ T='独显优化'; C=$script:C_PURPLE },
    @{ T='混合显卡'; C=$script:C_BLUE },
    @{ T='双重备份'; C=$script:C_GREEN },
    @{ T='只读诊断'; C=$script:C_ORANGE },
    @{ T='本地运行'; C=$script:C_SUB }
)
$bx = 24
foreach ($ab in $aboutBadges) {
    $null = New-Badge $aboutPage $ab.T $bx 78 92 24 $script:C_GRAY_BG $script:C_GRAY_BD $ab.C 8
    $bx += 100
}
$aboutBox = New-Object System.Windows.Forms.ListBox
$aboutBox.Location = New-Object Drawing.Point -ArgumentList @(24, 116)
$aboutBox.Size = New-Object Drawing.Size -ArgumentList @(($cw - 48), 500)
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
        if (($e.Index % 2) -eq 1) { $bg = [Drawing.Color]::FromArgb(15, 20, 30) }
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

# ★ 支持作者: 关于页底部入口, 打开包内赞赏码图片
$supBar = New-Object System.Windows.Forms.Panel
$supBar.Dock = 'Bottom'
$supBar.Height = 66
$supBar.BackColor = $script:C_BG
$aboutPage.Controls.Add($supBar)
$supHint = New-Label $supBar '如果这个工具帮到了你，可以扫码请作者喝一杯。' 24 24 400 20 9 $false $script:C_DIM
$btnSupport = New-Btn $supBar '支持作者' 440 16 120 34 $script:C_ORANGE_BG $script:C_ORANGE 9
$btnSupport.Add_Click({
    try {
        $img = Join-Path $SD '赞赏码.png'
        if (Test-Path -LiteralPath $img) {
            Start-Process -FilePath $img
            Set-Status '已打开赞赏码图片'
        } else {
            [System.Windows.Forms.MessageBox]::Show($form,
                "未找到赞赏码图片：`n$img`n`n请确认 赞赏码.png 与本程序在同一个文件夹。",
                '支持作者', 'OK', 'Information') | Out-Null
        }
    } catch {
        try { Start-Process explorer.exe -ArgumentList ('/select,"{0}"' -f (Join-Path $SD '赞赏码.png')) } catch {}
    }
})

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

# ══════════════════════════════════════════════════════════
# 分享 / 便携包
# ══════════════════════════════════════════════════════════
function New-ShareReadme([string]$stamp) {
    return @"
游戏性能优化中心 v5.0 · 便携版
========================================

一、快速开始
  1. 先把整个压缩包解压到一个固定文件夹（不要直接在压缩包里双击）。
  2. 双击“启动优化脚本.bat”。
  3. Windows 弹出管理员权限请求时，点“是”。
  4. 打开界面后，先在“概览”查看硬件，再到“优化项”按需勾选，点“应用选中项”。
  5. 概览页的 CPU / GPU / RAM / 显示存储 卡片支持悬停高亮，点击可查看只读详情，并可直接复制或跳转诊断报告。

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
    $payload = Join-Path $tmp '游戏性能优化中心_v5.0'
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
$setPage.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, 940)
$null = New-Label $setPage '设置' 24 18 300 32 16 $true $script:C_TEXT
$null = New-Label $setPage '实验性功能、渲染选项与配置文件 · 所有设置只保存在本机' 24 50 760 20 9 $false $script:C_SUB

$setW = $cw - 48
$expCard = New-Card $setPage 24 88 $setW 350 16 $script:C_PANEL $script:C_BORDER
$expCard.Anchor = 'Top, Left, Right'
$script:UI.ExpCard = $expCard
$null = New-Label $expCard '实验性功能' 20 16 220 24 12 $true $script:C_TEXT
$null = New-Label $expCard '仅影响界面渲染，不修改任何系统优化项与注册表' 20 42 520 18 8.5 $false $script:C_DIM

$null = New-Label $expCard '高 DPI 渲染 (PerMonitorV2)' 20 80 420 24 10.5 $true $script:C_TEXT
$null = New-Label $expCard '按主屏实际 DPI 绘制，125% / 150% / 200% 缩放下文字与线条更清晰' 20 106 700 20 8.5 $false $script:C_SUB
$lblDpiState = New-Label $expCard '' 20 128 650 20 8 $false $script:C_DIM
$script:UI.SetDpiState = $lblDpiState
$chkDpi = New-Check $expCard '启用（重启界面生效）' ($setW - 380) 78 210 26 ([bool]$script:GuiCfg.ExperimentalDpi)
$chkDpi.Anchor = 'Top, Right'
$script:UI.SetDpiCheck = $chkDpi
$btnRestart = New-Btn $expCard '重启界面' ($setW - 150) 74 130 34 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_CYAN 9
$btnRestart.Anchor = 'Top, Right'
$script:UI.SetRestart = $btnRestart
$div1 = New-Label $expCard '' 20 168 ($setW - 40) 1 8 $false $script:C_BORDER
$div1.BackColor = $script:C_BORDER

$null = New-Label $expCard 'GPU 渲染加速 / WPF 后端' 20 188 420 24 10.5 $true $script:C_TEXT
$null = New-Label $expCard '当前使用 WinForms + GDI+ 绘制，由 DWM 在 GPU 上合成；完整 GPU 渲染需迁移 WPF / Direct2D' 20 214 780 20 8.5 $false $script:C_SUB
$null = New-Label $expCard '评估结论：改造成本高于收益，暂不启用，保留为实验记录' 20 236 660 20 8 $false $script:C_DIM
$badgeWpf = New-Badge $expCard '已评估 · 未启用' ($setW - 270) 192 160 26 $script:C_GRAY_BG $script:C_GRAY_BD $script:C_SUB 8
$badgeWpf.Anchor = 'Top, Right'
$btnWpf = New-Btn $expCard '查看说明' ($setW - 100) 190 80 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_TEXT 8.5
$btnWpf.Anchor = 'Top, Right'
$div2 = New-Label $expCard '' 20 266 ($setW - 40) 1 8 $false $script:C_BORDER
$div2.BackColor = $script:C_BORDER

$chkRender = New-Check $expCard '在状态栏显示 DPI / 缩放 / 渲染方式' 20 278 380 26 ([bool]$script:GuiCfg.ShowRenderInfo)
$script:UI.SetRenderCheck = $chkRender
$null = New-Label $expCard '立即生效，仅新增一段状态文字，便于验证实验性 DPI 是否生效' 44 304 640 18 8 $false $script:C_DIM

$script:LastSharePath = ''
$shareCard = New-Card $setPage 24 454 $setW 172 16 $script:C_PANEL $script:C_BORDER
$shareCard.Anchor = 'Top, Left, Right'
$script:UI.ShareCard = $shareCard
$null = New-Label $shareCard '分享 / 便携包' 20 16 260 24 12 $true $script:C_TEXT
$null = New-Label $shareCard '一键打包给同学：GUI、引擎、启动器、使用说明与 SHA256 校验' 20 42 640 18 8.5 $false $script:C_SUB
$null = New-Label $shareCard '自动排除本机设置、备份与日志；对方解压后双击“启动优化脚本.bat”即可' 20 64 720 18 8 $false $script:C_DIM
$null = New-Label $shareCard 'GUI · 引擎 · 启动器 · 控制台备用入口 · 使用说明 · SHA256' 20 86 700 18 8 $false $script:C_DIM

$btnShare = New-Btn $shareCard '导出便携包' 20 112 150 36 ([Drawing.Color]::FromArgb(16, 40, 46)) $script:C_CYAN 9
$script:UI.ShareBtn = $btnShare
$btnShareTip = New-Btn $shareCard '复制分享话术' 182 112 150 36 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_TEXT 9
$script:UI.ShareTipBtn = $btnShareTip
$lblSharePath = New-Label $shareCard '尚未导出便携包' 350 118 ($setW - 370) 20 8 $false $script:C_DIM
$script:UI.SharePath = $lblSharePath

$cfgCard = New-Card $setPage 24 640 $setW 150 16 $script:C_PANEL $script:C_BORDER
$cfgCard.Anchor = 'Top, Left, Right'
$null = New-Label $cfgCard '配置文件' 20 16 220 24 12 $true $script:C_TEXT
$lblCfgPath = New-Label $cfgCard $script:GuiSettingsFile 20 48 ($setW - 40) 20 8.5 $false $script:C_SUB
$btnOpenDir = New-Btn $cfgCard '打开脚本目录' 20 96 140 32 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_CYAN 9
$btnReset = New-Btn $cfgCard '恢复默认设置' 172 96 140 32 ([Drawing.Color]::FromArgb(46, 32, 24)) $script:C_ORANGE 9
$null = New-Label $cfgCard '设置只保存在本机；删除该文件即恢复默认。' 330 100 ($setW - 350) 20 8 $false $script:C_DIM

$noteCard = New-Card $setPage 24 806 $setW 110 16 $script:C_PANEL $script:C_BORDER
$noteCard.Anchor = 'Top, Left, Right'
$null = New-Label $noteCard '实验性功能说明' 20 14 240 22 11 $true $script:C_TEXT
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
        $script:UI.SetDpiCheck.Checked = $want
        $script:UI.SetRenderCheck.Checked = [bool]$script:GuiCfg.ShowRenderInfo
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
$btnRestart.Add_Click({ Restart-Gui })
$btnWpf.Add_Click({
    [System.Windows.Forms.MessageBox]::Show($form,
        "当前界面的渲染路径：`n`n  · WinForms + GDI+ 负责绘制`n  · 桌面窗口管理器 (DWM) 在 GPU 上完成窗口合成`n`n已评估的方案：`n  · WPF 嵌入：可获得 GPU 合成，但需要重写控件与布局，混合自绘控件时容易引入 DPI、焦点和性能问题。`n  · Direct2D 自绘：需要额外 P/Invoke 与大量渲染代码，维护成本更高。`n`n结论：改造成本高于收益，暂不启用。现有优化集中在数据采集速度与刷新频率上。",
        'GPU 渲染 / WPF 后端', 'OK', 'Information') | Out-Null
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
        $dlg.FileName = '游戏性能优化中心_v5.0_便携版.zip'
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
    $tip = @'
游戏性能优化中心 v5.0 便携版（Windows 10 / 11）

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
'@
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
    $ans = [System.Windows.Forms.MessageBox]::Show($form, "恢复默认设置？`n`n将关闭高 DPI 渲染和状态栏渲染信息；高 DPI 的关闭需要重启界面。", '恢复默认设置', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    $script:GuiCfg.ExperimentalDpi = $false
    $script:GuiCfg.ShowRenderInfo = $false
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
    try {
        foreach ($k in @('AboutBox', 'LogBox', 'BakGrid', 'DiagGrid')) {
            $c = $script:UI[$k]
            if ($c) { [TxUi.Native]::DarkScroll($c.Handle) }
        }
        foreach ($pg in @($script:UI.Pages.Values)) {
            if ($pg -and $pg.IsHandleCreated) { [TxUi.Native]::DarkScroll($pg.Handle) }
        }
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
        [void]$vals.Add(@{ T = 'v5.0'; C = $script:C_CYAN })
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
        $heroW = $w - [int](48 * $sc)
        $script:UI.Hero.Width = $heroW
        $hwW = [int](($heroW - 36 * $sc) / 4)
        if ($hwW -lt [int](150 * $sc)) { $hwW = [int](150 * $sc) }
        for ($i = 0; $i -lt $script:UI.HwCards.Count; $i++) {
            $c = $script:UI.HwCards[$i]
            $c.Location = New-Object Drawing.Point -ArgumentList @(([int](24 * $sc) + $i * ($hwW + [int](12 * $sc))), [int](192 * $sc))
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
        $script:UI.PendCard.Location = New-Object Drawing.Point -ArgumentList @([int](24 * $sc), [int](506 * $sc))
        $script:UI.PendCard.Width = $leftW
        $script:UI.SysCard.Location = New-Object Drawing.Point -ArgumentList @(([int](24 * $sc) + $leftW + [int](12 * $sc)), [int](506 * $sc))
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
            $script:UI.SettingsPage.AutoScrollMinSize = New-Object Drawing.Size -ArgumentList @(0, [int][Math]::Round(940 * $sc))
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
            if ($active) {
                $b.BackColor = [Drawing.Color]::FromArgb(22, 32, 46)
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
            'diag'   { if ($script:UI.DiagDirty) { Refresh-Diag $false } }
            'about'  { Fill-About }
            'settings' { Update-SettingsUi }
            'overview' { Update-Overview }
            'items'  { Update-ItemSummary }
        }
        Layout-Overview
    } catch {}
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
    $btnCancel = New-Btn $dlg '取消' 232 112 88 34 ([Drawing.Color]::FromArgb(24, 35, 50)) $script:C_SUB 9
    $btnOk = New-Btn $dlg '确定' 328 112 88 34 $script:C_CYAN ([Drawing.Color]::FromArgb(4, 20, 26)) 9
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
    return [Drawing.Color]::FromArgb($r, $g, $b)
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
        $null = New-Label $hdr '游戏性能优化中心 · v5.0' ($cardW - (UiPx 250)) (UiPx 62) (UiPx 230) (UiPx 18) 8 $false $script:C_DIM 'MiddleRight'

        # ── 内容区 ────────────────────────────────────────
        $scrollW = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
        $boxW = $cardW + $scrollW + (UiPx 2)
        $box = New-Object System.Windows.Forms.Panel
        $box.Location = New-Object Drawing.Point -ArgumentList @($pad, $contentTop)
        $box.Size = New-Object Drawing.Size -ArgumentList @($boxW, $boxH)
        $box.BackColor = $script:C_BG
        $box.AutoScroll = $true
        $dlg.Controls.Add($box)

        $sepColor = [Drawing.Color]::FromArgb(31, 41, 56)
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
        $onAccent = [Drawing.Color]::FromArgb(10, 14, 20)
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
                $text = $tg.Meta[0] + ' · 游戏性能优化中心 v5.0' + "`r`n" +
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
# 关闭处理 / 预览 / 自检
# ══════════════════════════════════════════════════════════
$form.Add_FormClosing({
    param($s, $e)
    if ($script:UI.Busy) {
        $e.Cancel = $true
        [System.Windows.Forms.MessageBox]::Show($script:UI.Form, '正在应用或还原，请等待当前操作完成。', '请稍候', 'OK', 'Information') | Out-Null
        return
    }
    try { $script:ClockTimer.Stop() } catch {}
    try { $script:LiveTimer.Stop() } catch {}
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
    $pageList = @('overview', 'items', 'backup', 'diag', 'log', 'settings', 'about')
    if ($PreviewPage -and $PreviewPage -ne 'all') {
        if ($pageList -contains $PreviewPage) { $pageList = @($PreviewPage) }
    }
    foreach ($pk in $pageList) {
        try {
            Show-Page $pk
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 350
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
    $lines += "version=v5.0"
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
        $script:UI.Form.Activate()
        Set-Status '就绪 · 界面已显示，正在补齐优化项状态...'
        $script:BootTimer.Start()
    } catch {}
})


[System.Windows.Forms.Application]::Run($form)
Stop-Sampler

