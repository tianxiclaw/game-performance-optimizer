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

public sealed partial class MainWindow : Window
{
    private readonly Microsoft.UI.Dispatching.DispatcherQueue _dispatcher;
    private readonly SemaphoreSlim _engineReportLock = new(1, 1);
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _metricsTimer;
    private TrayIcon? _tray;
    private bool _initialized;
    private bool _metricsBusy;
    private bool _metricsPaused;
    private Func<string> _statusRender = () => "";
    private string _lastEngineStateZh = "引擎未连接";
    private string _lastInfoTitle = "";
    private string _lastInfoMessage = "";
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
        Title = Localization.T("游戏性能优化中心");
        try { AppWindow.Title = Localization.T("游戏性能优化中心"); } catch { }
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
        RegisterIconButtons(EnumerateIconButtons());
        InitPendingTip();

        // 兜底复位：指针只要还在窗口内移动，就用实时命中结果校正悬浮状态。
        // 只依赖按钮的 PointerExited 时，快速划出或提示层抢占会漏事件，
        // 图标就会永久停在放大位置。
        RootGrid.AddHandler(UIElement.PointerMovedEvent,
            new PointerEventHandler(RootGrid_PointerMoved), handledEventsToo: true);
        RootGrid.AddHandler(UIElement.PointerExitedEvent,
            new PointerEventHandler(RootGrid_PointerExited), handledEventsToo: true);

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

        // 静态文案先按当前语言替换一次；页面在导航完成后再处理。
        Localization.Apply(RootGrid);
        UpdateLanguageButton();

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

    /// <summary>顶栏主题图标（日 / 月 / 系统）：当前项用强调底与强调字，其余保持中性。</summary>
    /// <summary>
    /// 窗口材质：深空沿用自带渐变，云母与液态玻璃交给 Windows 11 合成层。
    /// 卡片仍是实色，材质只出现在窗口背景、导航与留白处，保证正文对比度。
    /// 三种材质都保留技术网格，切换时只改变底色与网格强度。
    /// </summary>
    /// <summary>
    /// 深空材质用实色顶栏；云母与液态玻璃让顶栏透明，避免半透明栏叠在根底色上二次加深。
    /// 底部 Dock 区始终透明，由 Dock 自身的浮层底承担分隔。
    /// </summary>
    /// <summary>
    /// 内容区底纹：76px 间距的 1px 技术网格，给切角面板提供可读的坐标参照。
    /// 只在尺寸真正变化或主题切换时重建，避免每次采样都重绘。
    /// </summary>
    private void Nav_Loaded(object sender, RoutedEventArgs e)
    {
        if (_initialized) return;
        _initialized = true;
        SelectNav("overview", navigate: true);
        _ = InitializeAsync();
    }

    /// <summary>窄窗口收起品牌文字与底部次要状态，Dock 保持完整可点。</summary>
    /// <summary>窗口继续收窄时压缩 Dock 尺寸，避免它和右侧状态在 480 DIP 附近重叠。</summary>
    /// <summary>
    /// 窄窗口顶栏只保留当前页名：面包屑前缀、待优化按钮与外部链接
    /// 会和右侧工具组争位置，导致文字被压住半截。
    /// “本地运行”状态已在底部状态栏常驻，顶栏不再重复。
    /// </summary>
    /// <summary>Dock 覆盖在内容上，窄屏时让右侧控制台贴近可用宽度，但它本身仍是覆盖层。</summary>
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
        InspectorToggleButton, RepoButton, PendingButton
    };

    /// <summary>
    /// 待优化按钮折叠成感叹号后，悬浮就要能看到具体项目。
    /// 清单直接放在窗口内（而非 ToolTip 弹出层），这样能跟随应用主题，
    /// 也能在离屏截图里被渲染到。
    /// </summary>
    private Microsoft.UI.Dispatching.DispatcherQueueTimer? _pendingHideTimer;

#if DEBUG
    /// <summary>离屏截图专用：不用真实鼠标悬浮也能看到清单展开态。</summary>
#endif

    private static FrameworkElement? IconTarget(Button button)
    {
        // Dock 与顶栏按钮直接以 FontIcon 作为 Content；页面按钮可能是
        // “图标 + 文字”的容器，只取里面的图标，避免文字跟着缩放。
        if (button.Content is FontIcon icon) return icon;
        return FindIcon(button, 0) ?? button.Content as FrameworkElement;
    }

    private float IconScaleFor(Button button)
        => ReferenceEquals(button, DockCommand) ? 1.15f
            : ReferenceEquals(button, PendingButton) ? 1.12f
            : _pageIconButtons.Contains(button) ? 1.14f
            : 1.22f;

    private readonly HashSet<Button> _iconButtons = new();
    private readonly HashSet<Button> _hoveredIcons = new();
    private bool _motionTraceLogged;
    private bool _motionResetLogged;

    /// <summary>唯一的悬浮状态入口：进和出都走这里，避免重复动画和状态失配。</summary>
    /// <summary>
    /// 以实时命中结果为准校正悬浮状态。只在有图标处于悬浮时执行，
    /// 正常浏览时没有额外开销。
    /// </summary>
    /// <summary>统一复位所有图标，覆盖失焦、指针离开窗口、页面切换等场景。</summary>
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

    private void SelectNav(string tag, bool navigate)
    {
        _currentTag = tag;
        TopBreadcrumb.Text = Localization.T(PageName(tag));
        DrawerPageTitle.Text = Localization.T(PageName(tag));
        DrawerPageDesc.Text = Localization.T(PageDescription(tag));
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
            PaneEngineText.Text = Localization.T("正在连接优化引擎");
            await App.Services.Engine.StartAsync();
            SetEngineState("引擎已连接");
            UpdateEngineBadge(true);
            SetStatus("正在读取硬件信息...", true);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            UpdateShellInfo();
            SetStatus("就绪", false);
        }
        catch (Exception ex)
        {
            SetEngineState("引擎连接失败");
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
            SetEngineState("引擎已断开");
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

            SetEngineState(App.Services.Engine.IsRunning ? "引擎已连接" : "引擎未连接");
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
        SetEngineState("正在重连...");
        SetStatus("正在重新连接优化引擎...", true);
        try
        {
            await App.Services.Engine.RestartAsync();
            SetStatus("正在读取硬件信息...", true);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            SetEngineState("引擎已连接");
            UpdateEngineBadge(true);
            UpdateShellInfo();
            SetStatus("就绪", false);
            _shownFailure = null;
            AppLog.Write("引擎重新连接成功");
            return true;
        }
        catch (Exception ex)
        {
            SetEngineState("引擎连接失败");
            AppLog.Write("重新连接失败: " + ex);
            return false;
        }
    }

    /// <summary>外壳常驻采样：左侧实时负载与概览页共用同一份结果。</summary>
    /// <summary>设备名与待优化数量。状态变化频繁，这里保持廉价，只改文本与可见性。</summary>
    /// <summary>
    /// 待优化按钮折叠成感叹号后，悬浮清单负责回答“还剩哪些”。
    /// 只取引擎快照里状态为待优化的项，最多列 6 条，其余用一行汇总。
    /// </summary>
    /// <summary>引擎状态文字统一入口：切语言时按最后一次状态重新翻译。</summary>
    /// <summary>设置页修改主题后调用，刷新标题栏与当前页面。</summary>
    /// <summary>供页面内部跳转使用，同时同步左侧导航的选中项。</summary>
    public void NavigateTo(string tag)
    {
        SelectNav(tag, navigate: true);
    }

    /// <summary>离屏截图等自检流程读取当前页面实例，避免暴露 ContentFrame。</summary>
    internal object? CurrentPage => ContentFrame.Content;

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
        TopBreadcrumb.Text = Localization.T(PageName(tag));
        if (ContentFrame.CurrentSourcePageType == pageType) return;
        ContentFrame.Navigate(pageType, null, new SuppressNavigationTransitionInfo());
    }

    /// <summary>页面本身不带动画，由外壳统一做 180ms 淡入 + 位移，切页节奏一致。</summary>
    private void OnFrameNavigated(object sender, NavigationEventArgs e)
    {
        // 旧页面即将被丢弃，把它的按钮从追踪表里移除，避免集合随切页持续增长。
        foreach (var button in _pageIconButtons)
        {
            _iconButtons.Remove(button);
            _hoveredIcons.Remove(button);
        }
        _pageIconButtons.Clear();

        AnimateFrameIn();
        if (e.Content is Page page)
        {
            // 缓存页再次导航时也要按当前语言刷一遍静态文案。
            Localization.Apply(page);
            if (page is ILanguageAware languageAware) languageAware.OnLanguageChanged();
            if (_pageFeedbackHooked.Add(page))
            {
                page.Loaded += (_, _) =>
                {
                    AttachPageIconFeedback(page);
                    Localization.Apply(page);
                    if (page is ILanguageAware loadedAware) loadedAware.OnLanguageChanged();
                };
            }
        }
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
        var found = new List<Button>();
        foreach (var child in Descendants(root))
        {
            if (child is not Button button || _pageIconButtons.Contains(button)) continue;
            if (FindIcon(button, 0) is null) continue;
            _pageIconButtons.Add(button);
            found.Add(button);
        }
        // 与 Dock / 顶栏共用同一套进出手柄，命中检测兜底才能覆盖页面控件。
        RegisterIconButtons(found);
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

    /// <summary>顶栏语言图标：中英切换，保存后立即重刷外壳与当前页面。</summary>
    // 仅供内置语言回归检查使用：不写设置，只切换界面。
    /// <summary>切换语言并重刷所有运行期改写的文案。</summary>
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
        catch (Exception ex)
        {
            AppLog.Write("打开项目主页失败: " + ex.Message);
        }
        await Task.CompletedTask;
    }

    /// <summary>窗口隐藏到托盘后没有可见的实时数据，停掉采样避免空转。</summary>
    /// <summary>托盘快捷入口：先恢复窗口，再切到目标页面。</summary>
}
