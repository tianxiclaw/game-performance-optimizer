using System.Diagnostics;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
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
    private EngineFailure? _shownFailure;
    private double _starWidth;
    private double _starHeight;

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

        App.Services.State.StatusChanged += OnStatusChanged;
        App.Services.State.Changed += OnStateChanged;
        App.Services.Engine.Crashed += OnEngineCrashed;
        NavEntriesPanel.Loaded += Nav_Loaded;
        Responsive.Watch(RootGrid, 1120, ApplyShellWidth);
        Responsive.Watch(RootGrid, 900, ApplyTitleBar);
        StarLayer.Loaded += (_, _) => BuildTechGrid();
        StarLayer.SizeChanged += (_, _) => BuildTechGrid();
        AppWindow.Closing += OnAppWindowClosing;
        Closed += OnClosed;

        _metricsTimer = _dispatcher.CreateTimer();
        _metricsTimer.Interval = TimeSpan.FromSeconds(2);
        _metricsTimer.Tick += async (_, _) => await SampleMetricsAsync();
        _metricsTimer.Start();
        _ = SampleMetricsAsync();

        try { VersionText.Text = $"v{AppPaths.Version}"; } catch { }

        try
        {
            _tray = new TrayIcon(Path.Combine(AppPaths.BaseDir, "Assets", "AppIcon.ico"));
            _tray.OnOpen = RestoreFromTray;
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
            AppWindow.MoveAndResize(new RectInt32(x, y, width, height));
        }
        catch { }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr hwnd);

    private void ApplyTheme()
    {
        var theme = App.Services.Settings.Theme;
        ThemeService.Apply(RootGrid, theme);
        UpdateThemeSegments();
        UpdateCaptionButtons();
        UpdateEngineBadge(App.Services.Engine.IsRunning);
        foreach (var item in EnumerateNavItems()) item.RefreshVisuals();
        ApplyMaterial();
        BuildTechGrid(force: true);
    }

    /// <summary>顶栏三段主题选择：当前项用强调底与强调字，其余保持中性。</summary>
    private void UpdateThemeSegments()
    {
        var current = App.Services.Settings.Theme;
        foreach (var button in new[] { ThemeDarkButton, ThemeLightButton, ThemeSystemButton })
        {
            var active = string.Equals(button.Tag as string, current, StringComparison.Ordinal);
            button.Background = active
                ? ThemeResources.Get("AccentSoftBrush")
                : new SolidColorBrush(Colors.Transparent);
            button.Foreground = ThemeResources.Get(active ? "AccentBrush" : "SubTextBrush");
            button.FontWeight = active
                ? Microsoft.UI.Text.FontWeights.SemiBold
                : Microsoft.UI.Text.FontWeights.Normal;
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
        if (!MaterialService.IsSupported(material)) material = "deep";

        try
        {
            SystemBackdrop = null;
            switch (material)
            {
                case "mica":
                    SystemBackdrop = new MicaBackdrop();
                    RootGrid.Background = ThemeResources.Get("MicaTintBrush");
                    ApplyChrome(unified: true);
                    StarLayer.Opacity = ThemeService.IsDark ? 0.7 : 0.5;
                    break;
                case "glass":
                    SystemBackdrop = new DesktopAcrylicBackdrop();
                    RootGrid.Background = ThemeResources.Get("GlassTintBrush");
                    ApplyChrome(unified: true);
                    StarLayer.Opacity = ThemeService.IsDark ? 0.5 : 0.35;
                    break;
                default:
                    RootGrid.Background = ThemeResources.Get("AppBackdropBrush");
                    ApplyChrome(unified: false);
                    StarLayer.Opacity = ThemeService.IsDark ? 1 : 0.55;
                    break;
            }
        }
        catch (Exception ex)
        {
            AppLog.Write("窗口材质应用失败: " + ex.Message);
            SystemBackdrop = null;
            RootGrid.Background = ThemeResources.Get("AppBackdropBrush");
            ApplyChrome(unified: false);
            StarLayer.Opacity = ThemeService.IsDark ? 1 : 0.55;
        }
    }

    /// <summary>
    /// 深空材质用实色分区；云母与液态玻璃共用一层根底色，
    /// 否则半透明栏叠在根底色上会二次加深，顶栏变成一条突兀的黑带。
    /// </summary>
    private void ApplyChrome(bool unified)
    {
        var clear = unified ? new SolidColorBrush(Colors.Transparent) : null;
        Rail.Background = clear ?? ThemeResources.Get("NavBgBrush");
        TitleBarDrag.Background = clear ?? ThemeResources.Get("PaneBrush");
        StatusBar.Background = clear ?? ThemeResources.Get("NavBgBrush");
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

    /// <summary>窄窗口收起为图标栏，保留全部导航能力。</summary>
    private void ApplyShellWidth(bool narrow)
    {
        RailColumn.Width = new GridLength(narrow ? 64 : 236);
        BrandText.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        RailDeviceBlock.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        RailTelemetry.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        NavGroupA.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        NavGroupB.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;

        Grid.SetColumnSpan(BrandMark, narrow ? 2 : 1);
        BrandMark.HorizontalAlignment = narrow ? HorizontalAlignment.Center : HorizontalAlignment.Left;

        foreach (var item in EnumerateNavItems())
        {
            item.IsCompact = narrow;
        }
    }

    /// <summary>
    /// 窄窗口顶栏只保留当前页名：面包屑前缀与 LOCAL MODE 徽标会和右侧的
    /// 待优化按钮、主题切换争位置，导致文字被压住半截。
    /// </summary>
    private void ApplyTitleBar(bool narrow)
    {
        CrumbRoot.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        CrumbSlash.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
        LocalModeGroup.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
    }

    private IEnumerable<NavItem> EnumerateNavItems()
    {
        foreach (var child in NavEntriesPanel.Children)
        {
            if (child is NavItem item) yield return item;
        }
        foreach (var child in RailFooter.Children)
        {
            if (child is NavItem item) yield return item;
        }
    }

    private void NavItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is NavItem { Tag: string tag })
        {
            SelectNav(tag, navigate: true);
        }
    }

    private void SelectNav(string tag, bool navigate)
    {
        foreach (var item in EnumerateNavItems())
        {
            item.IsSelected = string.Equals(item.Tag as string, tag, StringComparison.Ordinal);
        }
        TopBreadcrumb.Text = PageName(tag);
        if (navigate) Navigate(tag);
    }

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

            PaneCpuValue.Text = m.Cpu.ToString("0") + "%";
            PaneCpuBar.Value = m.Cpu;
            var gpuAvailable = App.Services.Metrics.GpuAvailable;
            PaneGpuValue.Text = gpuAvailable ? m.Gpu.ToString("0") + "%" : "--";
            PaneGpuBar.Value = gpuAvailable ? m.Gpu : 0;
            PaneRamValue.Text = m.RamPercent.ToString("0") + "%";
            PaneRamBar.Value = m.RamPercent;

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
        PendingButton.Visibility = pending > 0 ? Visibility.Visible : Visibility.Collapsed;
        PendingButton.IsEnabled = pending > 0;

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
        ContentFrame.Navigate(pageType, null, new Microsoft.UI.Xaml.Media.Animation.EntranceNavigationTransitionInfo());
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
        }
        catch (Exception ex)
        {
            AppLog.Write("从托盘恢复失败: " + ex.Message);
        }
    }

    private void ExitFromTray()
    {
        try { _tray?.Dispose(); } catch { }
        try { _ = App.Services.Engine.DisposeAsync(); } catch { }
        Environment.Exit(0);
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        try { _tray?.Dispose(); } catch { }
        try { _ = App.Services.Engine.DisposeAsync(); } catch { }
    }
}

public interface IThemeAware
{
    void OnThemeChanged();
}
