using System.Diagnostics;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;
using GamePerfCenter.Pages;
using GamePerfCenter.Services;

namespace GamePerfCenter;

public sealed partial class MainWindow : Window
{
    private readonly Microsoft.UI.Dispatching.DispatcherQueue _dispatcher;
    private TrayIcon? _tray;
    private bool _initialized;

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
        Nav.Loaded += Nav_Loaded;
        AppWindow.Closing += OnAppWindowClosing;
        Closed += OnClosed;

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
        ThemeIcon.Glyph = theme switch
        {
            "light" => "\uE706",
            "system" => "\uE793",
            _ => "\uE708"
        };
        ToolTipService.SetToolTip(ThemeButton, $"当前：{ThemeService.DisplayName(theme)}，点击切换");
        UpdateCaptionButtons();
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
        if (Nav.SelectedItem is null && Nav.MenuItems.Count > 0 && Nav.MenuItems[0] is NavigationViewItem first)
            Nav.SelectedItem = first;
        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        try
        {
            SetStatus("正在连接优化引擎...", true);
            await App.Services.Engine.StartAsync();
            EngineStateText.Text = "引擎已连接";
            SetStatus("正在读取硬件信息...", true);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            SetStatus("就绪", false);
        }
        catch (Exception ex)
        {
            EngineStateText.Text = "引擎连接失败";
            SetStatus("引擎连接失败", false);
            ShowError("无法连接优化引擎", ex.Message);
            AppLog.Write("初始化失败: " + ex);
        }
    }

    private void OnStatusChanged(string text)
    {
        _dispatcher.TryEnqueue(() => SetStatus(text, App.Services.State.IsBusy));
    }

    private void OnStateChanged()
    {
        _dispatcher.TryEnqueue(() => StatusRing.IsActive = App.Services.State.IsBusy);
    }

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

    private void Nav_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is not NavigationViewItem item) return;
        if (item.Tag is not string tag) return;
        Navigate(tag);
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
        foreach (var item in Nav.MenuItems)
        {
            if (item is NavigationViewItem navItem && navItem.Tag is string itemTag && itemTag == tag)
            {
                Nav.SelectedItem = navItem;
                Navigate(tag);
                return;
            }
        }
        foreach (var item in Nav.FooterMenuItems)
        {
            if (item is NavigationViewItem navItem && navItem.Tag is string itemTag && itemTag == tag)
            {
                Nav.SelectedItem = navItem;
                Navigate(tag);
                return;
            }
        }
        Navigate(tag);
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
        if (ContentFrame.CurrentSourcePageType == pageType) return;
        ContentFrame.Navigate(pageType, null, new Microsoft.UI.Xaml.Media.Animation.EntranceNavigationTransitionInfo());
    }

    private async void ThemeButton_Click(object sender, RoutedEventArgs e)
    {
        var next = ThemeService.Next(App.Services.Settings.Theme);
        App.Services.Settings.Theme = next;
        App.Services.Settings.Save();
        ApplyTheme();

        // 主题资源切换后通知当前页面重新计算依赖主题的徽标颜色
        if (ContentFrame.Content is Page page && page is IThemeAware aware)
            aware.OnThemeChanged();
        await Task.CompletedTask;
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
