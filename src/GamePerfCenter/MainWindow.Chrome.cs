using System.Diagnostics;
using System.Numerics;
using System.Text.Json;
using Microsoft.UI;
using Microsoft.UI.Composition;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Navigation;
using Windows.Graphics;
using Windows.System;
using GamePerfCenter.Controls;
using GamePerfCenter.Helpers;
using GamePerfCenter.Models;
using GamePerfCenter.Pages;
using GamePerfCenter.Services;
using Rectangle = Microsoft.UI.Xaml.Shapes.Rectangle;
using Ellipse = Microsoft.UI.Xaml.Shapes.Ellipse;

namespace GamePerfCenter;

public sealed partial class MainWindow
{
    private void SizeWindow()
    {
        try
        {
            var display = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
            var work = display.WorkArea;
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            var dpi = GetDpiForWindow(hwnd);
            // 构造期窗口尚未激活，GetDpiForWindow 可能先返回 96；直接问所在显示器要真实 DPI，
            // 否则 200% 缩放下窗口第一次出现只有应有尺寸的一半。
            var monitor = MonitorFromWindow(hwnd, 2 /* MONITOR_DEFAULTTONEAREST */);
            if (monitor != IntPtr.Zero &&
                GetDpiForMonitor(monitor, 0 /* MDT_EFFECTIVE_DPI */, out var monitorDpi, out _) == 0 &&
                monitorDpi > 0)
            {
                dpi = monitorDpi;
            }
            if (dpi == 0) dpi = 96;
            var scale = dpi / 96.0;

            // 以 DIP 为单位计算目标尺寸，再换算成物理像素，避免高 DPI 下窗口“缩水”。
            // 同时必须受工作区约束：200% 缩放的 1440×900 屏幕只有约 720×430 DIP，
            // 如果此处保底取 960 DIP，窗口会比屏幕还宽，右侧内容被推到屏幕外。
            var availWidth = work.Width / scale;
            var availHeight = work.Height / scale;
            var widthDip = Math.Min(1380, Math.Max(480, availWidth - 24));
            var heightDip = Math.Min(900, Math.Max(320, availHeight - 24));
            var width = (int)Math.Round(widthDip * scale);
            var height = (int)Math.Round(heightDip * scale);
            var x = work.X + (work.Width - width) / 2;
            var y = work.Y + (work.Height - height) / 2;
            AppLog.Write($"窗口尺寸: dpi={dpi} work={work.Width}x{work.Height} -> {width}x{height}");
            AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
        }
        catch { }
    }

    private void ApplyTheme()
    {
        ThemeService.RefreshHighContrast();
        var theme = App.Services.Settings.Theme;
        ThemeService.Apply(RootGrid, theme);
        UpdateThemeSegments();
        UpdateCaptionButtons();
        UpdateEngineBadge(App.Services.Engine.IsRunning);
        RefreshDockVisuals();
        ApplyMaterial();
        BuildTechGrid(force: true);
    }

    private void UpdateThemeSegments()
    {
        var current = App.Services.Settings.Theme;
        foreach (var button in new[] { ThemeLightButton, ThemeDarkButton, ThemeSystemButton })
        {
            var active = string.Equals(button.Tag as string, current, StringComparison.Ordinal);
            button.Background = active
                ? ThemeResources.Get("AccentSoftBrush")
                : new SolidColorBrush(Colors.Transparent);
            button.Foreground = ThemeResources.Get(active ? "AccentBrush" : "SubTextBrush");
        }
    }

    private void ApplyMaterial()
    {
        var material = MaterialService.Normalize(App.Services.Settings.Material);
        // 高对比度下系统要求不透明高反差，材质透出背景会破坏可读性，统一回退深空。
        if (ThemeService.IsHighContrast) material = "deep";
        if (!MaterialService.IsSupported(material)) material = "deep";

        // 卡片底色跟随窗口材质：液态玻璃下压到半透明，让 Acrylic 真正透上来。
        ThemeService.ApplyGlassSurfaces(material == "glass");

        try
        {
            SystemBackdrop = null;
            switch (material)
            {
                case "mica":
                    SystemBackdrop = new MicaBackdrop();
                    RootGrid.Background = ThemeResources.Get("MicaTintBrush");
                    SheenLayer.Background = ThemeResources.Get("MicaSheenBrush");
                    SheenLayer.Opacity = 0.55;
                    ApplyChrome(unified: true);
                    // 材质模式不再叠加星空网格：网格会盖住 Mica 的细微噪点与明暗层次。
                    StarLayer.Opacity = 0;
                    break;
                case "mica-alt":
                    SystemBackdrop = new MicaBackdrop { Kind = MicaKind.BaseAlt };
                    RootGrid.Background = ThemeResources.Get("MicaTintBrush");
                    SheenLayer.Background = ThemeResources.Get("MicaSheenBrush");
                    SheenLayer.Opacity = 0.35;
                    ApplyChrome(unified: true);
                    StarLayer.Opacity = 0;
                    break;
                case "glass":
                    SystemBackdrop = new DesktopAcrylicBackdrop();
                    RootGrid.Background = ThemeResources.Get("GlassTintBrush");
                    SheenLayer.Background = ThemeResources.Get("GlassSheenBrush");
                    SheenLayer.Opacity = 0.85;
                    ApplyChrome(unified: true);
                    StarLayer.Opacity = 0;
                    break;
                default:
                    RootGrid.Background = ThemeResources.Get("AppBackdropBrush");
                    SheenLayer.Opacity = 0;
                    ApplyChrome(unified: false);
                    StarLayer.Opacity = ThemeService.IsHighContrast ? 0 : (ThemeService.IsDark ? 1 : 0.55);
                    break;
            }
        }
        catch (Exception ex)
        {
            AppLog.Write("窗口材质应用失败: " + ex.Message);
            SystemBackdrop = null;
            ThemeService.ApplyGlassSurfaces(false);
            RootGrid.Background = ThemeResources.Get("AppBackdropBrush");
            SheenLayer.Opacity = 0;
            ApplyChrome(unified: false);
            StarLayer.Opacity = ThemeService.IsHighContrast ? 0 : (ThemeService.IsDark ? 1 : 0.55);
        }
    }

    private void ApplyChrome(bool unified)
    {
        var clear = new SolidColorBrush(Colors.Transparent);
        TitleBarDrag.Background = unified ? clear : ThemeResources.Get("PaneBrush");
        StatusBar.Background = clear;
    }

    public void RefreshMaterial() => ApplyMaterial();

    private void BuildTechGrid(bool force = false)
    {
        try
        {
            var width = StarLayer.ActualWidth;
            var height = StarLayer.ActualHeight;
            if (width < 240 || height < 240) return;
            if (!force && Math.Abs(width - _starWidth) < 2 && Math.Abs(height - _starHeight) < 2) return;

            _starWidth = width;
            _starHeight = height;
            StarLayer.Children.Clear();

            var brush = ThemeResources.Get("TechGridBrush");
            const double step = 76;

            // 按设备像素对齐：1 DIP 的线在 125%/150% 缩放下会被重采样成两条半透明线，
            // 看起来像脏点。这里换算成 1 物理像素宽，并把起点吸附到整像素。
            var scale = 1.0;
            try { scale = StarLayer.XamlRoot?.RasterizationScale ?? 1.0; } catch { }
            if (scale <= 0) scale = 1.0;
            var thickness = 1.0 / scale;

            for (var x = step; x < width; x += step)
            {
                var line = new Rectangle
                {
                    Width = thickness,
                    Height = height,
                    Fill = brush
                };
                Canvas.SetLeft(line, Math.Round(x * scale) / scale);
                Canvas.SetTop(line, 0);
                StarLayer.Children.Add(line);
            }
            for (var y = step; y < height; y += step)
            {
                var line = new Rectangle
                {
                    Width = width,
                    Height = thickness,
                    Fill = brush
                };
                Canvas.SetLeft(line, 0);
                Canvas.SetTop(line, Math.Round(y * scale) / scale);
                StarLayer.Children.Add(line);
            }
        }
        catch { }
    }

    private void UpdateCaptionButtons()
    {
        try
        {
            var bar = AppWindow.TitleBar;
            bar.ButtonBackgroundColor = Colors.Transparent;
            bar.ButtonInactiveBackgroundColor = Colors.Transparent;
            var fg = ThemeService.IsDark
                ? Windows.UI.Color.FromArgb(255, 230, 237, 247)
                : Windows.UI.Color.FromArgb(255, 15, 23, 42);
            var hover = ThemeService.IsDark
                ? Windows.UI.Color.FromArgb(255, 26, 36, 54)
                : Windows.UI.Color.FromArgb(255, 238, 243, 250);
            bar.ButtonForegroundColor = fg;
            bar.ButtonInactiveForegroundColor = fg;
            bar.ButtonHoverBackgroundColor = hover;
            bar.ButtonHoverForegroundColor = fg;
            bar.ButtonPressedBackgroundColor = hover;
            bar.ButtonPressedForegroundColor = fg;
        }
        catch { }
    }

    private void ApplyShellWidth(bool narrow)
    {
        BrandText.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        StatusRing.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        StatusText.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        StatusSecureDivider.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        StatusSecureText.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
    }

    private void ApplyDockCompact(bool compact)
    {
        var size = compact ? 34d : 42d;
        foreach (var button in EnumerateDockItems())
        {
            button.Width = size;
            button.Height = compact ? 34 : 38;
        }
        DockBar.Padding = compact ? new Thickness(5, 4, 5, 4) : new Thickness(7, 5, 7, 5);
        DockBar.CornerRadius = new CornerRadius(compact ? 12 : 16);
        StatusRight.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        foreach (var separator in new[] { DockSep1, DockSep2, DockSep3 })
        {
            separator.Margin = compact ? new Thickness(2, 0, 2, 0) : new Thickness(5, 0, 5, 0);
            separator.Height = compact ? 18 : 22;
        }
    }

    private void ApplyTitleBar(bool narrow)
    {
        _narrowTitleBar = narrow;
        CrumbRoot.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        CrumbSlash.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        RepoButton.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        if (narrow)
        {
            PendingButton.Visibility = Visibility.Collapsed;
            HidePendingTip();
        }
        else
        {
            UpdateShellInfo();
        }
    }

    private void ApplyInspectorWidth(double width)
    {
        InspectorPanel.Width = width < 700 ? Math.Max(260, width - 24) : 320;
    }

    private void SetMaterial(string key, string label)
    {
        if (ThemeService.IsHighContrast && key != "deep")
        {
            ShowInfo("高对比度已开启", "系统高对比度要求不透明高反差，窗口材质已停用。", InfoBarSeverity.Warning);
            return;
        }
        if (!MaterialService.IsSupported(key))
        {
            ShowInfo("系统不支持该材质", "已回退为深空材质。", InfoBarSeverity.Warning);
            return;
        }
        App.Services.Settings.Material = key;
        App.Services.Settings.Save();
        ApplyMaterial();
        var detail = key == "glass"
            ? "卡片同步降为半透明，让桌面与窗口背后真正透上来。"
            : "卡片保持实色，材质只作用于窗口背景与留白。";
        ShowInfo("材质已切换", $"当前材质：{label}。{detail}");
    }

    private void SetTheme(string key, string label)
    {
        App.Services.Settings.Theme = key;
        App.Services.Settings.Save();
        RefreshTheme();
        ShowInfo("主题已切换", $"当前主题：{label}。");
    }

    private void ThemeSegment_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string theme }) return;
        App.Services.Settings.Theme = theme;
        App.Services.Settings.Save();
        ApplyTheme();

        // 主题资源切换后通知当前页面重新计算依赖主题的徽标颜色
        if (ContentFrame.Content is Page page && page is IThemeAware aware)
            aware.OnThemeChanged();
    }

    public void RefreshTheme()
    {
        ApplyTheme();
        // 悬浮清单的标题与项目文字是代码里赋 brushes 的，换主题后需要重新取色。
        UpdatePendingTip(App.Services.State.Snapshot);
        if (ContentFrame.Content is Page page && page is IThemeAware aware)
            aware.OnThemeChanged();
    }
}
