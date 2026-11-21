using System.Diagnostics;
using GamePerfCenter.Helpers;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.Windows.Storage.Pickers;
using Windows.ApplicationModel.DataTransfer;

namespace GamePerfCenter.Pages;

public sealed partial class SettingsPage : Page, IThemeAware
{
    private bool _loading;
    private bool _exporting;
    private string? _lastExportPath;

    public SettingsPage()
    {
        InitializeComponent();
        Loaded += OnLoaded;
        Responsive.Watch(this, 900, ApplyWidth);
    }

    private void ApplyWidth(bool narrow)
    {
        if (narrow)
        {
            Grid.SetColumn(LeftColumn, 0);
            Grid.SetColumnSpan(LeftColumn, 2);
            Grid.SetRow(LeftColumn, 0);

            Grid.SetColumn(RightColumn, 0);
            Grid.SetColumnSpan(RightColumn, 2);
            Grid.SetRow(RightColumn, 1);
            RightColumn.Margin = new Thickness(0, 16, 0, 0);
        }
        else
        {
            Grid.SetColumn(LeftColumn, 0);
            Grid.SetColumnSpan(LeftColumn, 1);
            Grid.SetRow(LeftColumn, 0);

            Grid.SetColumn(RightColumn, 1);
            Grid.SetColumnSpan(RightColumn, 1);
            Grid.SetRow(RightColumn, 0);
            RightColumn.Margin = new Thickness(0);
        }
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        LoadIntoUi();
        BaseDirText.Text = AppPaths.BaseDir;
        ConfigPathText.Text = AppPaths.SettingsPath;
        ToolTipService.SetToolTip(BaseDirText, AppPaths.BaseDir);
        ToolTipService.SetToolTip(ConfigPathText, AppPaths.SettingsPath);
        VersionText.Text = $"游戏性能优化中心 v{AppPaths.Version}";
    }

    private void LoadIntoUi()
    {
        _loading = true;
        ThemeService.RefreshHighContrast();
        try
        {
            var settings = App.Services.Settings;
            DarkOption.IsChecked = settings.Theme == "dark";
            LightOption.IsChecked = settings.Theme == "light";
            SystemOption.IsChecked = settings.Theme == "system";
            var material = MaterialService.Normalize(settings.Material);
            var highContrast = ThemeService.IsHighContrast;
            var micaSupported = MaterialService.IsSupported("mica");
            var micaAltSupported = MaterialService.IsSupported("mica-alt");
            var glassSupported = MaterialService.IsSupported("glass");
            // 配置可能来自另一台机器；本机不支持时窗口已回退深空，选项也要显示真实状态。
            if ((material == "mica" && !micaSupported) ||
                (material == "mica-alt" && !micaAltSupported) ||
                (material == "glass" && !glassSupported))
                material = "deep";
            if (highContrast) material = "deep";
            UpdateMaterialTiles(material);
            MaterialMicaOption.IsEnabled = micaSupported && !highContrast;
            MaterialMicaAltOption.IsEnabled = micaAltSupported && !highContrast;
            MaterialGlassOption.IsEnabled = glassSupported && !highContrast;
            ToolTipService.SetToolTip(MaterialMicaOption,
                highContrast ? "高对比度开启时停用窗口材质"
                : MaterialMicaOption.IsEnabled ? "使用 Windows 11 云母背景" : "当前系统不支持云母材质");
            ToolTipService.SetToolTip(MaterialMicaAltOption,
                highContrast ? "高对比度开启时停用窗口材质"
                : MaterialMicaAltOption.IsEnabled ? "Mica Alt：比云母更深的底色，文字与卡片对比更稳" : "当前系统不支持云母材质");
            ToolTipService.SetToolTip(MaterialGlassOption,
                highContrast ? "高对比度开启时停用窗口材质"
                : MaterialGlassOption.IsEnabled ? "使用系统亚克力与高光层模拟液态玻璃" : "当前系统不支持液态玻璃");
            TraySwitch.IsOn = settings.MinimizeToTray;
            DriverNotifySwitch.IsOn = settings.NotifyDriver;
            ReduceMotionSwitch.IsOn = settings.ReduceMotion;
            MotionStateText.Text = Motion.Describe(settings.ReduceMotion);
            HighContrastText.Text = highContrast
                ? "已开启：界面改用 Windows 系统色，窗口材质停用。"
                : "跟随 Windows 高对比度设置；开启时使用系统色并停用窗口材质。";
        }
        finally
        {
            _loading = false;
        }
    }

    private void Theme_Checked(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        var theme = ReferenceEquals(sender, LightOption) ? "light"
            : ReferenceEquals(sender, SystemOption) ? "system" : "dark";
        if (App.Services.Settings.Theme == theme) return;
        App.Services.Settings.Theme = theme;
        Save();
        if (App.MainWindow is MainWindow main) main.RefreshTheme();
        ShowInfo("主题已切换", ThemeService.DisplayName(theme) + " 已应用。", InfoBarSeverity.Success);
    }

    private void MaterialOption_Click(object sender, RoutedEventArgs e)
    {
        if (_loading || sender is not Button { Tag: string material }) return;
        if (App.Services.Settings.Material == material) return;

        if (ThemeService.IsHighContrast && material != "deep")
        {
            ShowInfo("高对比度已开启", "系统高对比度要求不透明高反差，窗口材质已停用。", InfoBarSeverity.Warning);
            UpdateMaterialTiles("deep");
            return;
        }

        if (!MaterialService.IsSupported(material))
        {
            ShowInfo("当前系统不支持", "云母、云母 Alt 与液态玻璃需要 Windows 11 的系统合成层，已保留当前材质。",
                InfoBarSeverity.Warning);
            UpdateMaterialTiles(App.Services.Settings.Material);
            return;
        }

        App.Services.Settings.Material = material;
        Save();
        UpdateMaterialTiles(material);
        if (App.MainWindow is MainWindow main) main.RefreshMaterial();
        ShowInfo("材质已切换", MaterialService.DisplayName(material) + " 已应用。", InfoBarSeverity.Success);
    }

    private void UpdateMaterialTiles(string material)
    {
        foreach (var (tile, tag) in new[]
                 {
                     (MaterialDeepOption, "deep"),
                     (MaterialMicaOption, "mica"),
                     (MaterialMicaAltOption, "mica-alt"),
                     (MaterialGlassOption, "glass")
                 })
        {
            var active = string.Equals(material, tag, StringComparison.Ordinal);
            tile.Background = ThemeResources.Get(active ? "AccentSoftBrush" : "Surface2Brush");
            tile.BorderBrush = ThemeResources.Get(active ? "AccentBrush" : "BorderBrush");
            tile.BorderThickness = new Thickness(active ? 1.5 : 1);
        }
    }

    private void Setting_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading || TraySwitch is null || DriverNotifySwitch is null) return;
        var settings = App.Services.Settings;
        settings.MinimizeToTray = TraySwitch.IsOn;
        settings.NotifyDriver = DriverNotifySwitch.IsOn;
        Save();
    }

    private void ReduceMotion_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        var reduce = ReduceMotionSwitch.IsOn;
        App.Services.Settings.ReduceMotion = reduce;
        Motion.Configure(reduce);
        MotionStateText.Text = Motion.Describe(reduce);
        Save();
        ShowInfo("动效已更新",
            reduce ? "已关闭界面动效，数值与列表直接跳到最终状态。" : "已启用界面动效：控件悬浮放大、按下回弹与数值滚动。",
            InfoBarSeverity.Success);
    }

    private void OpenContrast_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "ms-settings:easeofaccess-highcontrast",
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            ShowInfo("无法打开系统设置", ex.Message, InfoBarSeverity.Error);
        }
    }

    private void Save()
    {
        if (!App.Services.Settings.Save())
            ShowInfo("保存失败", "无法写入 gui-settings.json，请检查目录权限。", InfoBarSeverity.Warning);
    }

    private void OpenConfig_Click(object sender, RoutedEventArgs e) => OpenFolder(AppPaths.BaseDir);

    private void CopyPath_Click(object sender, RoutedEventArgs e)
    {
        var text = ReferenceEquals(sender, CopyConfigButton) ? AppPaths.SettingsPath : AppPaths.BaseDir;
        try
        {
            var package = new DataPackage();
            package.SetText(text);
            Clipboard.SetContent(package);
            Clipboard.Flush();
            ShowInfo("已复制路径", text, InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowInfo("复制失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async void Export_Click(object sender, RoutedEventArgs e)
    {
        if (_exporting) return;

        var targetPath = await PickExportPathAsync();
        if (string.IsNullOrWhiteSpace(targetPath)) return;

        _exporting = true;
        ExportButton.IsEnabled = false;
        OpenExportButton.IsEnabled = false;
        ExportStatus.Text = "正在导出，请稍候…";
        try
        {
            var (count, bytes) = await PortableExportService.ExportAsync(targetPath);
            _lastExportPath = targetPath;
            ExportStatus.Text = $"已导出 {count} 个文件（{bytes / 1024.0 / 1024.0:0.0} MB）：{targetPath}";
            OpenExportButton.IsEnabled = true;
            ShowInfo("导出完成", "便携包已生成，可以直接发送给他人。", InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ExportStatus.Text = "导出失败：" + ex.Message;
            ShowInfo("导出失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            _exporting = false;
            ExportButton.IsEnabled = true;
        }
    }

    // 程序以管理员权限运行，Windows.Storage.Pickers 在提权进程里不会弹出对话框，
    // 必须使用 Windows App SDK 1.8 提供的 Microsoft.Windows.Storage.Pickers。
    private async Task<string?> PickExportPathAsync()
    {
        var fileName = $"游戏性能优化中心_v{AppPaths.Version}_便携版";
        if (App.MainWindow is null) return DesktopExportPath(fileName);

        try
        {
            var picker = new FileSavePicker(App.MainWindow.AppWindow.Id)
            {
                SuggestedStartLocation = PickerLocationId.Desktop,
                SuggestedFileName = fileName,
                DefaultFileExtension = ".zip",
                CommitButtonText = "保存"
            };
            picker.FileTypeChoices.Add("ZIP 压缩包", new List<string> { ".zip" });

            var result = await picker.PickSaveFileAsync();
            return string.IsNullOrWhiteSpace(result?.Path) ? null : result.Path;
        }
        catch (Exception ex)
        {
            AppLog.Write("打开便携包保存对话框失败: " + ex.Message);
            var fallback = DesktopExportPath(fileName);
            ShowInfo("无法打开保存对话框", $"已改为导出到桌面：{fallback}", InfoBarSeverity.Warning);
            return fallback;
        }
    }

    private static string DesktopExportPath(string fileName)
    {
        var desktop = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
        return Path.Combine(desktop, fileName + ".zip");
    }

    private void OpenExport_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(_lastExportPath)) return;
        var folder = Path.GetDirectoryName(_lastExportPath);
        if (!string.IsNullOrEmpty(folder)) OpenFolder(folder);
    }

    private void OpenData_Click(object sender, RoutedEventArgs e) => OpenFolder(AppPaths.DataDir);

    private void OpenBackup_Click(object sender, RoutedEventArgs e) => OpenFolder(AppPaths.BackupDir);

    private static void OpenFolder(string path)
    {
        try
        {
            Directory.CreateDirectory(path);
            Process.Start(new ProcessStartInfo { FileName = "explorer.exe", Arguments = $"\"{path}\"", UseShellExecute = true });
        }
        catch { }
    }

    private void OpenRepo_Click(object sender, RoutedEventArgs e)
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
            ShowInfo("无法打开主页", ex.Message, InfoBarSeverity.Error);
        }
    }

    private void CheckUpdate_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "https://github.com/tianxiclaw/game-performance-optimizer/releases/latest",
                UseShellExecute = true
            });
            ShowInfo("已打开更新页面", "请在浏览器中查看最新版本说明。", InfoBarSeverity.Informational);
        }
        catch (Exception ex)
        {
            ShowInfo("无法打开更新页面", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async void Reset_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "恢复默认设置",
            Content = new TextBlock
            {
                Text = "将外观与行为设置恢复为默认值（深色主题、深空材质、关闭托盘、开启驱动提醒、关闭减弱动效）。\n\n备份、日志与游戏库不会受影响。",
                TextWrapping = TextWrapping.Wrap,
                LineHeight = 22
            },
            PrimaryButtonText = "恢复默认",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;

        var settings = App.Services.Settings;
        settings.Theme = "dark";
        settings.Material = "deep";
        settings.MinimizeToTray = false;
        settings.NotifyDriver = true;
        settings.ReduceMotion = false;
        Motion.Configure(false);
        Save();
        LoadIntoUi();
        if (App.MainWindow is MainWindow main) main.RefreshTheme();
        ShowInfo("已恢复默认设置", "外观与行为设置已重置。", InfoBarSeverity.Success);
    }

    private void ShowInfo(string title, string message, InfoBarSeverity severity)
        => InfoBarPresenter.Show(PageInfo,
            Localization.T(title), Localization.T(message), severity);

    // 顶栏也能切换主题；回到本页时同步单选项，避免界面显示与已保存设置不一致。
    public void OnThemeChanged() => LoadIntoUi();

    /// <summary>系统高对比度可能在窗口失焦期间变化，窗口激活时由外壳通知本页重读状态。</summary>
    public void OnAccessibilityChanged() => LoadIntoUi();
}
