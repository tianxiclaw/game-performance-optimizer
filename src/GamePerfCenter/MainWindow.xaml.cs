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

namespace GamePerfCenter;

public sealed partial class MainWindow : Window
{
    private readonly Microsoft.UI.Dispatching.DispatcherQueue _dispatcher;
    private readonly SemaphoreSlim _engineReportLock = new(1, 1);
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _metricsTimer;
    private TrayIcon? _tray;
    private bool _initialized;
    private bool _metricsBusy;
    private bool _metricsPaused;
    private int _metricsTick;
    private bool _sizedOnActivate;
    private EngineFailure? _shownFailure;
    private double _starWidth;
    private double _starHeight;
    private string _currentTag = "overview";
    private bool _inspectorOpen;
    private bool _narrowTitleBar;
    private string? _pendingItemFocus;
    private List<GameInfo>? _paletteGames;
    private DateTime _paletteGamesAt;
    private bool _paletteGamesLoading;

    /// <summary>最近一次实时采样。概览页进入时先拿这里的数据，不用等下一个采样周期。</summary>
    public LiveMetrics? LatestMetrics { get; private set; }

    /// <summary>外壳统一采样，页面只订阅结果，避免同一时刻跑多份 CPU / WMI 查询。</summary>
    public event Action<LiveMetrics>? MetricsUpdated;

    public MainWindow()
    {
        InitializeComponent();
        _dispatcher = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();

        ExtendsContentIntoTitleBar = true;
        SetTitleBar(TitleBarDrag);
        Title = "游戏性能优化中心";
        try { AppWindow.Title = "游戏性能优化中心"; } catch { }
        try { AppWindow.SetIcon(Path.Combine(AppPaths.BaseDir, "Assets", "AppIcon.ico")); } catch { }

        ApplyTheme();
        SizeWindow();

        Activated += OnWindowActivated;

        App.Services.State.StatusChanged += OnStatusChanged;
        App.Services.State.Changed += OnStateChanged;
        App.Services.Engine.Crashed += OnEngineCrashed;
        Palette.CommandInvoked += OnCommandInvoked;
        ContentFrame.Navigated += OnFrameNavigated;

        var paletteAccelerator = new KeyboardAccelerator
        {
            Key = VirtualKey.K,
            Modifiers = VirtualKeyModifiers.Control
        };
        paletteAccelerator.Invoked += (_, args) =>
        {
            args.Handled = true;
            ToggleCommandPalette();
        };
        RootGrid.KeyboardAccelerators.Add(paletteAccelerator);

        DockBar.Loaded += Nav_Loaded;
        // Button 内部会把 PointerEntered 标记为已处理，普通订阅收不到；
        // 必须用 handledEventsToo 才能驱动 Dock 的悬浮标签。
        foreach (var button in EnumerateDockItems())
        {
            button.AddHandler(UIElement.PointerEnteredEvent,
                new PointerEventHandler(DockButton_PointerEntered), handledEventsToo: true);
            button.AddHandler(UIElement.PointerExitedEvent,
                new PointerEventHandler(DockButton_PointerExited), handledEventsToo: true);
        }

        // 图标型按钮统一加悬浮放大 / 按下收缩；按钮布局尺寸不变，只动图标本身。
        foreach (var button in EnumerateIconButtons())
        {
            button.AddHandler(UIElement.PointerEnteredEvent,
                new PointerEventHandler(IconButton_PointerEntered), handledEventsToo: true);
            button.AddHandler(UIElement.PointerExitedEvent,
                new PointerEventHandler(IconButton_PointerExited), handledEventsToo: true);
            button.AddHandler(UIElement.PointerPressedEvent,
                new PointerEventHandler(IconButton_PointerPressed), handledEventsToo: true);
            button.AddHandler(UIElement.PointerReleasedEvent,
                new PointerEventHandler(IconButton_PointerReleased), handledEventsToo: true);
            // 拖拽、窗口失焦、UAC 抢占等情况下收不到 PointerExited，图标会卡在放大状态。
            button.AddHandler(UIElement.PointerCanceledEvent,
                new PointerEventHandler(IconButton_PointerCanceled), handledEventsToo: true);
            button.AddHandler(UIElement.PointerCaptureLostEvent,
                new PointerEventHandler(IconButton_PointerCanceled), handledEventsToo: true);
        }

        // 加速键挂在 RootGrid 上时，WinUI 会在指针 hover 时自动弹一个 "Ctrl+K" 提示，
        // 与 Dock 自定义标签冲突。这里关掉自动提示，快捷键说明交给 Dock 标签。
        RootGrid.KeyboardAcceleratorPlacementMode = KeyboardAcceleratorPlacementMode.Hidden;
        Responsive.Watch(RootGrid, 1120, ApplyShellWidth);
        Responsive.Watch(RootGrid, 900, ApplyTitleBar);
        Responsive.Watch(RootGrid, 760, ApplyDockCompact);
        RootGrid.SizeChanged += (_, e) => ApplyInspectorWidth(e.NewSize.Width);
        StarLayer.Loaded += (_, _) => BuildTechGrid();
        StarLayer.SizeChanged += (_, _) => BuildTechGrid();
        AppWindow.Closing += OnAppWindowClosing;
        Activated += OnFirstActivated;
        Closed += OnClosed;

        _metricsTimer = _dispatcher.CreateTimer();
        _metricsTimer.Interval = TimeSpan.FromMilliseconds(250);
        _metricsTimer.Tick += async (_, _) => await SampleMetricsAsync();
        _metricsTimer.Start();
        _ = SampleMetricsAsync();

        try { VersionText.Text = $"v{AppPaths.Version}"; } catch { }

        try
        {
            _tray = new TrayIcon(Path.Combine(AppPaths.BaseDir, "Assets", "AppIcon.ico"));
            _tray.OnOpen = RestoreFromTray;
            _tray.OnItems = () => OpenFromTray("items");
            _tray.OnGames = () => OpenFromTray("games");
            _tray.OnRefresh = RefreshFromTray;
            _tray.OnExit = ExitFromTray;
        }
        catch (Exception ex)
        {
            AppLog.Write("托盘初始化失败: " + ex.Message);
        }
    }

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

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);

    [System.Runtime.InteropServices.DllImport("Shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr monitor, int dpiType, out uint dpiX, out uint dpiY);

    /// <summary>
    /// 构造期窗口还没落到真实显示器上，GetDpiForWindow 可能先返回 96，
    /// 在 200% 缩放下会让窗口只有应有尺寸的一半。首次激活后再按真实 DPI 校正一次。
    /// </summary>
    private async void OnFirstActivated(object sender, WindowActivatedEventArgs args)
    {
        if (_sizedOnActivate || args.WindowActivationState == WindowActivationState.Deactivated) return;
        _sizedOnActivate = true;
        await Task.Delay(120);
        SizeWindow();
    }

    /// <summary>
    /// 系统高对比度切换不会经过本进程的消息循环，回到窗口时重新读一次标志。
    /// 变化时重跑主题与材质；设置页缓存在 Frame 里，也要同步它的状态文案。
    /// </summary>
    private void OnWindowActivated(object sender, WindowActivatedEventArgs args)
    {
        if (args.WindowActivationState == WindowActivationState.Deactivated)
        {
            ResetIconScales();
            return;
        }
        var before = ThemeService.IsHighContrast;
        ThemeService.RefreshHighContrast();
        if (before != ThemeService.IsHighContrast)
        {
            ApplyTheme();
        }
        else if (ContentFrame.Content is SettingsPage settingsPage)
        {
            settingsPage.OnAccessibilityChanged();
        }
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

    /// <summary>顶栏主题图标（日 / 月 / 系统）：当前项用强调底与强调字，其余保持中性。</summary>
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

    /// <summary>
    /// 窗口材质：深空沿用自带渐变，云母与液态玻璃交给 Windows 11 合成层。
    /// 卡片仍是实色，材质只出现在窗口背景、导航与留白处，保证正文对比度。
    /// 三种材质都保留技术网格，切换时只改变底色与网格强度。
    /// </summary>
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

    /// <summary>
    /// 深空材质用实色顶栏；云母与液态玻璃让顶栏透明，避免半透明栏叠在根底色上二次加深。
    /// 底部 Dock 区始终透明，由 Dock 自身的浮层底承担分隔。
    /// </summary>
    private void ApplyChrome(bool unified)
    {
        var clear = new SolidColorBrush(Colors.Transparent);
        TitleBarDrag.Background = unified ? clear : ThemeResources.Get("PaneBrush");
        StatusBar.Background = clear;
    }

    public void RefreshMaterial() => ApplyMaterial();

    /// <summary>
    /// 内容区底纹：76px 间距的 1px 技术网格，给切角面板提供可读的坐标参照。
    /// 只在尺寸真正变化或主题切换时重建，避免每次采样都重绘。
    /// </summary>
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

    private void Nav_Loaded(object sender, RoutedEventArgs e)
    {
        if (_initialized) return;
        _initialized = true;
        SelectNav("overview", navigate: true);
        _ = InitializeAsync();
    }

    /// <summary>窄窗口收起品牌文字与底部次要状态，Dock 保持完整可点。</summary>
    private void ApplyShellWidth(bool narrow)
    {
        BrandText.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        StatusRing.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        StatusText.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        StatusSecureDivider.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        StatusSecureText.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
    }

    /// <summary>窗口继续收窄时压缩 Dock 尺寸，避免它和右侧状态在 480 DIP 附近重叠。</summary>
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

    /// <summary>
    /// 窄窗口顶栏只保留当前页名：面包屑前缀与 LOCAL MODE 徽标会和右侧的
    /// 待优化按钮、主题切换争位置，导致文字被压住半截。
    /// </summary>
    private void ApplyTitleBar(bool narrow)
    {
        _narrowTitleBar = narrow;
        CrumbRoot.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        CrumbSlash.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        LocalModeGroup.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        RepoButton.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        if (narrow)
        {
            PendingButton.Visibility = Visibility.Collapsed;
        }
        else
        {
            UpdateShellInfo();
        }
    }

    /// <summary>Dock 覆盖在内容上，窄屏时让右侧控制台贴近可用宽度，但它本身仍是覆盖层。</summary>
    private void ApplyInspectorWidth(double width)
    {
        InspectorPanel.Width = width < 700 ? Math.Max(260, width - 24) : 320;
    }

    private Button[] EnumerateDockItems() => new[]
    {
        DockOverview, DockItems, DockDiagnostics, DockStartup,
        DockGames, DockDriver, DockBackup, DockLog, DockSettings, DockAbout
    };

    /// <summary>Dock 与顶栏中“只有图标”的按钮；文字按钮不参与缩放，避免整块文字抖动。</summary>
    private Button[] EnumerateIconButtons() => new[]
    {
        DockOverview, DockItems, DockDiagnostics, DockStartup,
        DockGames, DockDriver, DockBackup, DockLog, DockSettings, DockAbout, DockCommand,
        ThemeLightButton, ThemeDarkButton, ThemeSystemButton,
        InspectorToggleButton, RepoButton
    };

    private static FrameworkElement? IconOf(object sender)
        => sender is Button { Content: FrameworkElement icon } ? icon : null;

    private float IconScaleFor(object sender)
        => ReferenceEquals(sender, DockCommand) ? 1.15f : 1.22f;

    private bool _motionTraceLogged;

    /// <summary>首次真正执行缩放时写一条日志，便于确认动效在提权后的进程里同样生效。</summary>
    private void TraceMotionOnce(float scale)
    {
        if (_motionTraceLogged) return;
        _motionTraceLogged = true;
        AppLog.Write($"动效生效: 图标 1.00 -> {scale:0.00}，Windows 动画={(Motion.SystemEnabled ? "开" : "关")}");
    }

    private void IconButton_PointerEntered(object sender, PointerRoutedEventArgs e)
    {
        var scale = IconScaleFor(sender);
        TraceMotionOnce(scale);
        Motion.IconHover(IconOf(sender), true, scale);
    }

    private void IconButton_PointerExited(object sender, PointerRoutedEventArgs e)
        => Motion.IconHover(IconOf(sender), false);

    private void IconButton_PointerPressed(object sender, PointerRoutedEventArgs e)
        => Motion.IconPress(IconOf(sender), true, IconScaleFor(sender));

    private void IconButton_PointerReleased(object sender, PointerRoutedEventArgs e)
        => Motion.IconPress(IconOf(sender), false, IconScaleFor(sender));

    private void IconButton_PointerCanceled(object sender, PointerRoutedEventArgs e)
    {
        var hover = sender is Button { IsPointerOver: true };
        Motion.IconHover(IconOf(sender), hover, IconScaleFor(sender));
    }

    /// <summary>窗口失焦时指针必然已经离开，统一复位，避免图标停留在放大或按下状态。</summary>
    private void ResetIconScales()
    {
        foreach (var button in EnumerateIconButtons())
        {
            Motion.IconHover(IconOf(button), false);
        }
    }

    private void RefreshDockVisuals()
    {
        var selectedFill = ThemeResources.Get("AccentSoftBrush");
        var clear = new SolidColorBrush(Colors.Transparent);
        foreach (var button in EnumerateDockItems())
        {
            var active = string.Equals(button.Tag as string, _currentTag, StringComparison.Ordinal);
            button.Background = active ? selectedFill : clear;
            button.Foreground = ThemeResources.Get(active ? "AccentBrush" : "SubTextBrush");
        }
        DockCommand.Background = ThemeResources.Get("AccentSoftBrush");
        DockCommand.Foreground = ThemeResources.Get("AccentBrush");
    }

    private void DockItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string tag })
        {
            SelectNav(tag, navigate: true);
        }
        HideDockHint();
    }

    private string DockLabel(Button button)
    {
        if (ReferenceEquals(button, DockCommand)) return "命令面板 · Ctrl K";
        return (button.Tag as string) switch
        {
            "overview" => "概览",
            "items" => "优化项",
            "diagnostics" => "诊断报告",
            "startup" => "启动项与后台",
            "games" => "游戏库",
            "driver" => "驱动中心",
            "backup" => "备份还原",
            "log" => "运行日志",
            "settings" => "设置",
            "about" => "关于与支持",
            _ => ""
        };
    }

    private void DockButton_PointerEntered(object sender, PointerRoutedEventArgs e)
    {
        if (sender is not Button button) return;
        var label = DockLabel(button);
        if (string.IsNullOrEmpty(label)) return;

        DockHintText.Text = label;
        DockHintHost.Visibility = Visibility.Visible;
        // 先让提示按内容完成一次布局，才能拿到真实宽度做居中；此前用 Measure 得到的是脏值。
        DockHintHost.UpdateLayout();
        var hintWidth = DockHintHost.ActualWidth > 0 ? DockHintHost.ActualWidth : 72;
        var origin = button.TransformToVisual(StatusBar)
            .TransformPoint(new Windows.Foundation.Point(0, 0));
        var x = origin.X + (button.ActualWidth - hintWidth) / 2;
        x = Math.Clamp(x, 8, Math.Max(8, StatusBar.ActualWidth - hintWidth - 8));
        DockHintHost.Margin = new Thickness(x, 0, 0, 0);
        AnimateOpacity(DockHintHost, 1, 120);
    }

    private void DockButton_PointerExited(object sender, PointerRoutedEventArgs e) => HideDockHint();

    private void HideDockHint()
    {
        if (DockHintHost.Visibility != Visibility.Visible) return;
        AnimateOpacity(DockHintHost, 0, 100, collapse: true);
    }

    private static void AnimateOpacity(UIElement element, double to, int milliseconds, bool collapse = false)
    {
        if (!Motion.Enabled)
        {
            element.Opacity = to;
            if (collapse) element.Visibility = Visibility.Collapsed;
            return;
        }
        var storyboard = new Storyboard();
        var animation = new DoubleAnimation
        {
            To = to,
            Duration = new Duration(TimeSpan.FromMilliseconds(milliseconds)),
            EnableDependentAnimation = true
        };
        Storyboard.SetTarget(animation, element);
        Storyboard.SetTargetProperty(animation, "Opacity");
        storyboard.Children.Add(animation);
        if (collapse)
        {
            storyboard.Completed += (_, _) =>
            {
                if (element.Opacity <= 0.01) element.Visibility = Visibility.Collapsed;
            };
        }
        storyboard.Begin();
    }

    private void InspectorToggle_Click(object sender, RoutedEventArgs e) => SetInspectorOpen(!_inspectorOpen);
    private void InspectorClose_Click(object sender, RoutedEventArgs e) => SetInspectorOpen(false);

    private void SetInspectorOpen(bool open)
    {
        if (_inspectorOpen == open) return;
        _inspectorOpen = open;
        InspectorToggleButton.Background = open
            ? ThemeResources.Get("AccentSoftBrush")
            : new SolidColorBrush(Colors.Transparent);
        InspectorToggleButton.Foreground = ThemeResources.Get(open ? "AccentBrush" : "SubTextBrush");
        AutomationProperties.SetName(InspectorToggleButton, open ? "收起控制台" : "展开控制台");
        ToolTipService.SetToolTip(InspectorToggleButton, open ? "收起控制台" : "展开控制台");

        if (open)
        {
            InspectorPanel.Visibility = Visibility.Visible;
            InspectorSlide.X = 24;
            InspectorPanel.Opacity = 0;
            AnimateInspector(0, 1);
        }
        else
        {
            AnimateInspector(24, 0, collapse: true);
        }
    }

    private void AnimateInspector(double x, double opacity, bool collapse = false)
    {
        if (!Motion.Enabled)
        {
            InspectorSlide.X = x;
            InspectorPanel.Opacity = opacity;
            if (collapse) InspectorPanel.Visibility = Visibility.Collapsed;
            return;
        }
        var storyboard = new Storyboard();
        var slide = new DoubleAnimation
        {
            To = x,
            Duration = new Duration(TimeSpan.FromMilliseconds(180)),
            EnableDependentAnimation = true,
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        Storyboard.SetTarget(slide, InspectorSlide);
        Storyboard.SetTargetProperty(slide, "X");
        var fade = new DoubleAnimation
        {
            To = opacity,
            Duration = new Duration(TimeSpan.FromMilliseconds(150)),
            EnableDependentAnimation = true
        };
        Storyboard.SetTarget(fade, InspectorPanel);
        Storyboard.SetTargetProperty(fade, "Opacity");
        storyboard.Children.Add(slide);
        storyboard.Children.Add(fade);
        if (collapse)
        {
            storyboard.Completed += (_, _) =>
            {
                if (InspectorPanel.Opacity <= 0.01) InspectorPanel.Visibility = Visibility.Collapsed;
            };
        }
        storyboard.Begin();
    }

    private void DrawerRefresh_Click(object sender, RoutedEventArgs e) => RefreshFromTray();
    private void DrawerDataDir_Click(object sender, RoutedEventArgs e) => OpenDirectory(AppPaths.DataDir);
    private void DrawerBackupDir_Click(object sender, RoutedEventArgs e) => OpenDirectory(AppPaths.BackupDir);

    private void SelectNav(string tag, bool navigate)
    {
        _currentTag = tag;
        TopBreadcrumb.Text = PageName(tag);
        DrawerPageTitle.Text = PageName(tag);
        DrawerPageDesc.Text = PageDescription(tag);
        RefreshDockVisuals();
        if (navigate) Navigate(tag);
    }

    private static string PageDescription(string tag) => tag switch
    {
        "items" => "按分类筛选并应用可还原的系统优化。",
        "diagnostics" => "只读检查 VBS、内存、PCIe、NVMe 与显示链路。",
        "startup" => "查看开机自启项与内存占用较高的后台进程。",
        "games" => "识别本地游戏并保存独立运行配置。",
        "driver" => "显卡驱动版本、厂商工具与回退记录。",
        "backup" => "原值备份、单项还原与全部回放。",
        "log" => "本机操作与引擎输出，不上传。",
        "settings" => "外观、托盘与配置文件。",
        "about" => "版本信息、赞赏码与项目链接。",
        _ => "实时负载、优化进度与硬件摘要。"
    };

    private static string PageName(string tag) => tag switch
    {
        "items" => "优化项",
        "diagnostics" => "诊断报告",
        "startup" => "启动项与后台",
        "games" => "游戏库",
        "driver" => "驱动中心",
        "backup" => "备份还原",
        "log" => "运行日志",
        "settings" => "设置",
        "about" => "关于与支持",
        _ => "概览"
    };

    private async Task InitializeAsync()
    {
        try
        {
            SetStatus("正在连接优化引擎...", true);
            PaneEngineText.Text = "正在连接优化引擎";
            await App.Services.Engine.StartAsync();
            EngineStateText.Text = "引擎已连接";
            UpdateEngineBadge(true);
            SetStatus("正在读取硬件信息...", true);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            UpdateShellInfo();
            SetStatus("就绪", false);
        }
        catch (Exception ex)
        {
            EngineStateText.Text = "引擎连接失败";
            UpdateEngineBadge(false);
            SetStatus("引擎连接失败", false);
            AppLog.Write("初始化失败: " + ex);
            await ShowEngineFailureAsync(App.Services.Engine.LastFailure, ex);
        }
    }

    /// <summary>引擎进程意外退出时由 EngineBridge 触发，整理报告并弹出可操作的故障说明。</summary>
    private void OnEngineCrashed(EngineFailure failure)
    {
        _dispatcher.TryEnqueue(() =>
        {
            EngineStateText.Text = "引擎已断开";
            UpdateEngineBadge(false);
            SetStatus("引擎连接中断，正在整理故障报告...", true);
            _ = ShowEngineFailureAsync(failure, null);
        });
    }

    /// <summary>
    /// 同一时间只允许一个故障弹窗。用户点“重新连接”后若仍失败，就地把新报告再展示一次，
    /// 而不是叠出第二个 ContentDialog。
    /// </summary>
    private async Task ShowEngineFailureAsync(EngineFailure? failure, Exception? error)
    {
        if (!_engineReportLock.Wait(0)) return;
        try
        {
            failure ??= App.Services.Engine.LastFailure;
            // Exited 事件比管道关闭稍晚，等一小会儿才能拿到退出代码与 stderr。
            for (var i = 0; i < 10 && failure is null; i++)
            {
                await Task.Delay(100);
                failure = App.Services.Engine.LastFailure;
            }
            if (failure is not null && ReferenceEquals(failure, _shownFailure)) return;
            _shownFailure = failure;

            var result = await ShowReportAsync(failure, error);
            while (result == ContentDialogResult.Primary)
            {
                if (await ReconnectEngineAsync()) return;
                failure = App.Services.Engine.LastFailure;
                error = null;
                result = await ShowReportAsync(failure, error);
            }

            EngineStateText.Text = App.Services.Engine.IsRunning ? "引擎已连接" : "引擎未连接";
            UpdateEngineBadge(App.Services.Engine.IsRunning);
            SetStatus(App.Services.Engine.IsRunning ? "就绪" : "引擎未连接", false);
        }
        finally
        {
            _engineReportLock.Release();
        }
    }

    private async Task<ContentDialogResult> ShowReportAsync(EngineFailure? failure, Exception? error)
    {
        EngineReport report;
        try
        {
            report = await EngineDiagnostics.BuildAsync(failure, error);
        }
        catch (Exception ex)
        {
            AppLog.Write("故障报告生成失败: " + ex);
            report = new EngineReport
            {
                Summary = failure?.Summary ?? "优化引擎没有正常工作",
                Cause = error?.Message ?? failure?.Summary ?? ex.Message,
                Suggestions = new[]
                {
                    "点击“重新连接”会重启引擎。",
                    "仍失败时，到“运行日志”页查看最近输出。"
                },
                Details = "故障报告生成失败：" + ex
            };
        }

        SetStatus("引擎异常，请查看故障报告", false);
        if (RootGrid.XamlRoot is null) return ContentDialogResult.None;
        return await EngineErrorDialog.ShowAsync(RootGrid.XamlRoot, report);
    }

    private async Task<bool> ReconnectEngineAsync()
    {
        EngineStateText.Text = "正在重连...";
        SetStatus("正在重新连接优化引擎...", true);
        try
        {
            await App.Services.Engine.RestartAsync();
            SetStatus("正在读取硬件信息...", true);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            EngineStateText.Text = "引擎已连接";
            UpdateEngineBadge(true);
            UpdateShellInfo();
            SetStatus("就绪", false);
            _shownFailure = null;
            AppLog.Write("引擎重新连接成功");
            return true;
        }
        catch (Exception ex)
        {
            EngineStateText.Text = "引擎连接失败";
            AppLog.Write("重新连接失败: " + ex);
            return false;
        }
    }

    private void OnStatusChanged(string text)
    {
        _dispatcher.TryEnqueue(() => SetStatus(text, App.Services.State.IsBusy));
    }

    private void OnStateChanged()
    {
        _dispatcher.TryEnqueue(() =>
        {
            StatusRing.IsActive = App.Services.State.IsBusy;
            UpdateShellInfo();
        });
    }

    /// <summary>外壳常驻采样：左侧实时负载与概览页共用同一份结果。</summary>
    private async Task SampleMetricsAsync()
    {
        if (_metricsBusy) return;
        _metricsBusy = true;
        try
        {
            var m = await Task.Run(() => App.Services.Metrics.Sample());
            LatestMetrics = m;

            // 侧栏只是常驻摘要，1 秒一次足够；概览页仍按 250ms 拿实时数据。
            if (++_metricsTick % 4 == 1)
            {
                PaneCpuValue.Text = m.Cpu.ToString("0") + "%";
                PaneCpuBar.Value = m.Cpu;
                var gpuAvailable = App.Services.Metrics.GpuAvailable;
                PaneGpuValue.Text = gpuAvailable ? m.Gpu.ToString("0") + "%" : "--";
                PaneGpuBar.Value = gpuAvailable ? m.Gpu : 0;
                PaneRamValue.Text = m.RamPercent.ToString("0") + "%";
                PaneRamBar.Value = m.RamPercent;
            }

            MetricsUpdated?.Invoke(m);
        }
        catch (Exception ex)
        {
            AppLog.Write("实时采样失败: " + ex.Message);
        }
        finally
        {
            _metricsBusy = false;
        }
    }

    /// <summary>设备名与待优化数量。状态变化频繁，这里保持廉价，只改文本与可见性。</summary>
    private void UpdateShellInfo()
    {
        var snap = App.Services.State.Snapshot;
        if (snap is not null && !string.IsNullOrWhiteSpace(snap.Machine))
        {
            PaneDeviceName.Text = snap.Machine;
            ToolTipService.SetToolTip(PaneDeviceName, snap.Machine);
        }

        var pending = snap?.Summary.Pending ?? 0;
        TopPendingText.Text = $"待优化 {pending} 项";
        PendingButton.Visibility = pending > 0 && !_narrowTitleBar
            ? Visibility.Visible
            : Visibility.Collapsed;
        PendingButton.IsEnabled = pending > 0;
        DrawerPendingText.Text = pending > 0 ? $"{pending} 项待应用" : "暂无待应用项";
        DrawerPendingButton.Visibility = pending > 0 ? Visibility.Visible : Visibility.Collapsed;

        var kind = snap is null ? "" : snap.IsLaptop ? "笔记本" : "台式机";
        var engine = App.Services.Engine.IsRunning ? "引擎已连接" : "引擎未连接";
        PaneEngineText.Text = string.IsNullOrEmpty(kind) ? engine : $"{kind} · {engine}";
    }

    private void UpdateEngineBadge(bool connected)
    {
        try
        {
            var brush = ThemeResources.Get(connected ? "OkBrush" : "WarnBrush");
            PaneEngineDot.Fill = brush;
            StatusEngineDot.Fill = brush;
        }
        catch { }
    }

    private void PendingButton_Click(object sender, RoutedEventArgs e) => NavigateTo("items");

    private void SetStatus(string text, bool busy)
    {
        StatusText.Text = text;
        StatusRing.IsActive = busy;
    }

    public void ShowError(string title, string message)
    {
        EngineInfoBar.Title = title;
        EngineInfoBar.Message = message;
        EngineInfoBar.Severity = InfoBarSeverity.Error;
        EngineInfoBar.IsOpen = true;
    }

    public void ShowInfo(string title, string message, InfoBarSeverity severity = InfoBarSeverity.Success)
    {
        EngineInfoBar.Title = title;
        EngineInfoBar.Message = message;
        EngineInfoBar.Severity = severity;
        EngineInfoBar.IsOpen = true;
    }

    /// <summary>设置页修改主题后调用，刷新标题栏与当前页面。</summary>
    public void RefreshTheme()
    {
        ApplyTheme();
        if (ContentFrame.Content is Page page && page is IThemeAware aware)
            aware.OnThemeChanged();
    }

    /// <summary>供页面内部跳转使用，同时同步左侧导航的选中项。</summary>
    public void NavigateTo(string tag)
    {
        SelectNav(tag, navigate: true);
    }

    private void Navigate(string tag)
    {
        Type pageType = tag switch
        {
            "items" => typeof(ItemsPage),
            "driver" => typeof(DriverPage),
            "backup" => typeof(BackupPage),
            "games" => typeof(GamesPage),
            "diagnostics" => typeof(DiagnosticsPage),
            "startup" => typeof(StartupPage),
            "log" => typeof(LogPage),
            "settings" => typeof(SettingsPage),
            "about" => typeof(AboutPage),
            _ => typeof(OverviewPage)
        };
        TopBreadcrumb.Text = PageName(tag);
        if (ContentFrame.CurrentSourcePageType == pageType) return;
        ContentFrame.Navigate(pageType, null, new SuppressNavigationTransitionInfo());
    }

    /// <summary>页面本身不带动画，由外壳统一做 180ms 淡入 + 位移，切页节奏一致。</summary>
    private void OnFrameNavigated(object sender, NavigationEventArgs e)
    {
        AnimateFrameIn();
        if (e.Content is Page page && _pageFeedbackHooked.Add(page))
            page.Loaded += (_, _) => AttachPageIconFeedback(page);
        if (_pendingItemFocus is { } id && ContentFrame.Content is ItemsPage itemsPage)
        {
            _pendingItemFocus = null;
            DispatcherQueue.TryEnqueue(() => itemsPage.FocusItem(id));
        }
    }

    /// <summary>页面内带图标的按钮同样获得悬浮反馈，只缩放图标，不缩放文字。</summary>
    private readonly HashSet<Button> _pageIconButtons = new();
    private readonly HashSet<Page> _pageFeedbackHooked = new();

    private void AttachPageIconFeedback(DependencyObject root)
    {
        foreach (var child in Descendants(root))
        {
            if (child is not Button button || _pageIconButtons.Contains(button)) continue;
            if (FindIcon(button, 0) is null) continue;
            _pageIconButtons.Add(button);
            button.AddHandler(UIElement.PointerEnteredEvent,
                new PointerEventHandler(PageIcon_PointerEntered), handledEventsToo: true);
            button.AddHandler(UIElement.PointerExitedEvent,
                new PointerEventHandler(PageIcon_PointerExited), handledEventsToo: true);
            button.AddHandler(UIElement.PointerPressedEvent,
                new PointerEventHandler(PageIcon_PointerPressed), handledEventsToo: true);
            button.AddHandler(UIElement.PointerReleasedEvent,
                new PointerEventHandler(PageIcon_PointerReleased), handledEventsToo: true);
        }
    }

    private static IEnumerable<DependencyObject> Descendants(DependencyObject root)
    {
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < count; i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            yield return child;
            foreach (var nested in Descendants(child)) yield return nested;
        }
    }

    private static FontIcon? FindIcon(DependencyObject root, int depth)
    {
        if (root is FontIcon icon) return icon;
        if (depth >= 4) return null;
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < count; i++)
        {
            if (FindIcon(VisualTreeHelper.GetChild(root, i), depth + 1) is { } found) return found;
        }
        return null;
    }

    private void PageIcon_PointerEntered(object sender, PointerRoutedEventArgs e)
        => Motion.IconHover(sender is Button b ? FindIcon(b, 0) : null, true, 1.14f, -1f);

    private void PageIcon_PointerExited(object sender, PointerRoutedEventArgs e)
        => Motion.IconHover(sender is Button b ? FindIcon(b, 0) : null, false);

    private void PageIcon_PointerPressed(object sender, PointerRoutedEventArgs e)
        => Motion.IconPress(sender is Button b ? FindIcon(b, 0) : null, true, 1.14f);

    private void PageIcon_PointerReleased(object sender, PointerRoutedEventArgs e)
        => Motion.IconPress(sender is Button b ? FindIcon(b, 0) : null, false, 1.14f);

    private void AnimateFrameIn()
    {
        if (!Motion.Enabled) return;
        try
        {
            var visual = ElementCompositionPreview.GetElementVisual(ContentFrame);
            var compositor = visual.Compositor;
            visual.Opacity = 0f;
            visual.Offset = new Vector3(0, 10, 0);

            var ease = compositor.CreateCubicBezierEasingFunction(new Vector2(0.2f, 0f), new Vector2(0f, 1f));
            var duration = TimeSpan.FromMilliseconds(180);

            var fade = compositor.CreateScalarKeyFrameAnimation();
            fade.InsertKeyFrame(0f, 0f);
            fade.InsertKeyFrame(1f, 1f, ease);
            fade.Duration = duration;

            var slide = compositor.CreateVector3KeyFrameAnimation();
            slide.InsertKeyFrame(0f, new Vector3(0, 10, 0));
            slide.InsertKeyFrame(1f, Vector3.Zero, ease);
            slide.Duration = duration;

            var batch = compositor.CreateScopedBatch(CompositionBatchTypes.Animation);
            visual.StartAnimation("Opacity", fade);
            visual.StartAnimation("Offset", slide);
            batch.Completed += (_, _) =>
            {
                try
                {
                    visual.Opacity = 1f;
                    visual.Offset = Vector3.Zero;
                }
                catch { }
            };
            batch.End();
        }
        catch { }
    }

    private void CommandButton_Click(object sender, RoutedEventArgs e) => ToggleCommandPalette();

    private void ToggleCommandPalette()
    {
        if (Palette.IsOpen)
        {
            Palette.Close();
            return;
        }
        Palette.Open(BuildCommands(), App.Services.Settings.CommandRecents);
        _ = LoadGamesForPaletteAsync();
    }

    private void OnCommandInvoked(CommandItem item)
    {
        App.Services.Settings.RecordCommand(item.Id);
        App.Services.Settings.Save();
        try { item.Invoke?.Invoke(); }
        catch (Exception ex)
        {
            AppLog.Write("命令执行失败: " + ex);
            ShowError("命令执行失败", ex.Message);
        }
    }

    private List<CommandItem> BuildCommands()
    {
        var commands = new List<CommandItem>();
        void Page(string tag, string title, string glyph, string detail, string keywords)
        {
            commands.Add(new CommandItem
            {
                Id = "page:" + tag,
                Title = title,
                Detail = detail,
                Glyph = glyph,
                Group = "页面",
                Keywords = tag + " " + keywords,
                Invoke = () => NavigateTo(tag)
            });
        }

        Page("overview", "概览", "\uE80F", "实时负载、优化进度与硬件摘要", "home dashboard 首页 工作台");
        Page("items", "优化项", "\uE9D9", "按分类筛选并应用可还原的系统优化", "optimize items 优化 项目 应用");
        Page("diagnostics", "诊断报告", "\uE9D5", "只读检查 VBS、内存、PCIe、NVMe 与显示链路", "diagnostics report 诊断 报告");
        Page("startup", "启动项与后台", "\uE7C4", "查看开机自启项与内存占用较高的后台进程", "startup background 启动 后台");
        Page("games", "游戏库", "\uE7FC", "识别本地游戏并保存独立运行配置", "games library 游戏 库 steam epic");
        Page("driver", "驱动中心", "\uE7F8", "显卡驱动版本、厂商工具与回退记录", "driver gpu 驱动 显卡");
        Page("backup", "备份还原", "\uE777", "原值备份、单项还原与全部回放", "backup restore 备份 还原 回滚");
        Page("log", "运行日志", "\uE8A5", "本机操作与引擎输出，不上传", "log 日志 输出");
        Page("settings", "设置", "\uE713", "外观、托盘与配置文件", "settings 设置 配置 主题 材质");
        Page("about", "关于与支持", "\uE946", "版本信息、赞赏码与项目链接", "about version support 关于 版本");

        commands.Add(new CommandItem
        {
            Id = "action:refresh",
            Title = "刷新硬件与优化项",
            Detail = "重新采样 CPU、GPU、内存与本机状态",
            Glyph = "\uE72C",
            Group = "操作",
            Keywords = "refresh snapshot 刷新 状态 采样",
            Invoke = () => _ = RefreshSnapshotAsync()
        });
        commands.Add(new CommandItem
        {
            Id = "action:open-base",
            Title = "打开程序目录",
            Detail = AppPaths.BaseDir,
            Glyph = "\uE838",
            Group = "操作",
            Keywords = "open folder 打开 目录 程序",
            Invoke = () => OpenDirectory(AppPaths.BaseDir)
        });
        commands.Add(new CommandItem
        {
            Id = "action:open-backups",
            Title = "打开备份目录",
            Detail = AppPaths.BackupDir,
            Glyph = "\uE777",
            Group = "操作",
            Keywords = "open backup folder 打开 备份 目录",
            Invoke = () => OpenDirectory(AppPaths.BackupDir)
        });
        commands.Add(new CommandItem
        {
            Id = "action:open-data",
            Title = "打开数据目录",
            Detail = AppPaths.DataDir,
            Glyph = "\uE8A5",
            Group = "操作",
            Keywords = "open data log folder 打开 数据 日志 目录",
            Invoke = () => OpenDirectory(AppPaths.DataDir)
        });
        commands.Add(new CommandItem
        {
            Id = "action:open-settings",
            Title = "打开配置文件",
            Detail = AppPaths.SettingsPath,
            Glyph = "\uE713",
            Group = "操作",
            Keywords = "open settings json 打开 配置 文件",
            Invoke = () => OpenFile(AppPaths.SettingsPath)
        });

        var material = MaterialService.Normalize(App.Services.Settings.Material);
        void Material(string key, string title, string detail, string glyph)
        {
            var supported = MaterialService.IsSupported(key);
            commands.Add(new CommandItem
            {
                Id = "material:" + key,
                Title = title,
                Detail = (material == key ? "当前材质 · " : "") + detail +
                         (supported ? "" : " · 当前系统不支持，会回退深空"),
                Glyph = glyph,
                Group = "材质",
                Keywords = "material theme 材质 外观 " + key,
                Invoke = () => SetMaterial(key, title.Replace("材质：", ""))
            });
        }
        Material("deep", "材质：深空", "自带渐变背景，不依赖系统合成层", "\uE790");
        Material("mica", "材质：云母", "Windows 11 Mica，桌面颜色直接透出", "\uE790");
        Material("mica-alt", "材质：云母 Alt", "Mica Alt 底色更深，适合深色桌面与高对比内容", "\uE790");
        Material("glass", "材质：液态玻璃", "Acrylic 半透明，适合浅色桌面", "\uE790");

        var theme = App.Services.Settings.Theme;
        void Theme(string key, string title)
        {
            commands.Add(new CommandItem
            {
                Id = "theme:" + key,
                Title = title,
                Detail = theme == key ? "当前主题" : "切换后立即生效",
                Glyph = "\uE793",
                Group = "操作",
                Keywords = "theme 主题 外观 " + key,
                Invoke = () => SetTheme(key, title.Replace("主题：", ""))
            });
        }
        Theme("dark", "主题：深色");
        Theme("light", "主题：浅色");
        Theme("system", "主题：跟随系统");

        foreach (var item in App.Services.State.Items)
        {
            if (string.IsNullOrWhiteSpace(item.Id)) continue;
            commands.Add(new CommandItem
            {
                Id = "item:" + item.Id,
                Title = item.Name ?? item.Id,
                Detail = $"{item.Cat} · {item.StatusText}",
                Glyph = "\uE9D9",
                Group = "优化项",
                Keywords = $"{item.Id} {item.Cat} {item.Desc} {item.StatusText}",
                Invoke = () => FocusItem(item.Id)
            });
        }

        if (_paletteGames is not null)
        {
            foreach (var game in _paletteGames)
            {
                if (string.IsNullOrWhiteSpace(game.Exe)) continue;
                commands.Add(new CommandItem
                {
                    Id = "game:" + game.Exe,
                    Title = string.IsNullOrWhiteSpace(game.Name) ? Path.GetFileNameWithoutExtension(game.Exe) : game.Name!,
                    Detail = $"{game.SourceText} · {game.ProfileText}",
                    Glyph = "\uE7FC",
                    Group = "游戏",
                    Keywords = $"{game.Exe} {game.SourceText} 游戏 启动 launch play",
                    Invoke = () => _ = LaunchGameFromPaletteAsync(game)
                });
            }
        }

        return commands;
    }

    private async Task RefreshSnapshotAsync()
    {
        try
        {
            SetStatus("正在刷新硬件与优化项...", true);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            UpdateShellInfo();
            SetStatus("就绪", false);
            ShowInfo("刷新完成", "硬件与优化项状态已更新。");
        }
        catch (Exception ex)
        {
            SetStatus("刷新失败", false);
            ShowError("刷新失败", ex.Message);
        }
    }

    private void OpenDirectory(string path)
    {
        try
        {
            Directory.CreateDirectory(path);
            Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true });
        }
        catch (Exception ex)
        {
            ShowError("打开目录失败", ex.Message);
        }
    }

    private void OpenFile(string path)
    {
        try
        {
            if (!File.Exists(path)) File.WriteAllText(path, "{}", new System.Text.UTF8Encoding(true));
            Process.Start(new ProcessStartInfo { FileName = path, UseShellExecute = true });
        }
        catch (Exception ex)
        {
            ShowError("打开文件失败", ex.Message);
        }
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

    private void FocusItem(string? id)
    {
        if (string.IsNullOrWhiteSpace(id)) return;
        _pendingItemFocus = id;
        NavigateTo("items");
        if (ContentFrame.Content is ItemsPage page)
        {
            _pendingItemFocus = null;
            page.FocusItem(id);
        }
    }

    private async Task LoadGamesForPaletteAsync()
    {
        if (_paletteGamesLoading) return;
        if (_paletteGames is not null && DateTime.Now - _paletteGamesAt < TimeSpan.FromMinutes(5)) return;

        _paletteGamesLoading = true;
        try
        {
            _paletteGames = await App.Services.State.GetGamesAsync(false);
            _paletteGamesAt = DateTime.Now;
        }
        catch (Exception ex)
        {
            AppLog.Write("命令面板游戏库读取失败: " + ex.Message);
            return;
        }
        finally
        {
            _paletteGamesLoading = false;
        }

        if (Palette.IsOpen) Palette.SetCommands(BuildCommands());
    }

    private async Task LaunchGameFromPaletteAsync(GameInfo game)
    {
        try
        {
            SetStatus("正在启动游戏...", true);
            var result = await App.Services.State.StartGameAsync(game.Exe ?? "", game.Profile);
            var ok = !result.TryGetProperty("Ok", out var okEl) || okEl.ValueKind != JsonValueKind.False;
            var message = result.TryGetProperty("Message", out var msg) ? msg.ToString() : "";
            ShowInfo(ok ? "已启动" : "启动失败",
                string.IsNullOrEmpty(message) ? (game.Name ?? "游戏") + " 已交给系统启动。" : message,
                ok ? InfoBarSeverity.Success : InfoBarSeverity.Error);
        }
        catch (Exception ex)
        {
            ShowError("启动失败", ex.Message);
        }
        finally
        {
            SetStatus("就绪", false);
        }
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

    private async void RepoButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "https://github.com/tianxiclaw/game-performance-optimizer",
                UseShellExecute = true
            });
        }
        catch { }
        await Task.CompletedTask;
    }

    private void OnAppWindowClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (!App.Services.Settings.MinimizeToTray) return;
        args.Cancel = true;
        try
        {
            AppWindow.Hide();
            _tray?.Show();
            PauseMetrics();
        }
        catch (Exception ex)
        {
            AppLog.Write("最小化到托盘失败: " + ex.Message);
        }
    }

    private void RestoreFromTray()
    {
        try
        {
            _tray?.Hide();
            AppWindow.Show();
            Activate();
            ResumeMetrics();
        }
        catch (Exception ex)
        {
            AppLog.Write("从托盘恢复失败: " + ex.Message);
        }
    }

    /// <summary>窗口隐藏到托盘后没有可见的实时数据，停掉采样避免空转。</summary>
    private void PauseMetrics()
    {
        if (_metricsPaused) return;
        _metricsPaused = true;
        _metricsTimer.Stop();
    }

    private void ResumeMetrics()
    {
        if (!_metricsPaused) return;
        _metricsPaused = false;
        _metricsTick = 0;
        _metricsTimer.Start();
        _ = SampleMetricsAsync();
    }

    /// <summary>托盘快捷入口：先恢复窗口，再切到目标页面。</summary>
    private void OpenFromTray(string tag)
    {
        RestoreFromTray();
        NavigateTo(tag);
    }

    private async void RefreshFromTray()
    {
        RestoreFromTray();
        try
        {
            await App.Services.State.EnsureSnapshotAsync(force: true);
            ShowInfo("状态已刷新", "优化项状态与硬件快照已更新。", InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowError("刷新失败", ex.Message);
        }
    }

    private async void ExitFromTray()
    {
        try { _tray?.Dispose(); } catch { }
        try { await App.Services.Engine.DisposeAsync(); } catch { }
        Environment.Exit(0);
    }

    private async void OnClosed(object sender, WindowEventArgs args)
    {
        try { _tray?.Dispose(); } catch { }
        try { await App.Services.Engine.DisposeAsync(); } catch { }
    }
}

public interface IThemeAware
{
    void OnThemeChanged();
}
