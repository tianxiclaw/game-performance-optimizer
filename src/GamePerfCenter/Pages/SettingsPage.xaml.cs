using System.Diagnostics;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Storage.Pickers;

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
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        LoadIntoUi();
        BaseDirText.Text = AppPaths.BaseDir;
        ConfigPathText.Text = AppPaths.SettingsPath;
        VersionText.Text = $"游戏性能优化中心 v{AppPaths.Version}";
    }

    private void LoadIntoUi()
    {
        _loading = true;
        try
        {
            var settings = App.Services.Settings;
            DarkOption.IsChecked = settings.Theme == "dark";
            LightOption.IsChecked = settings.Theme == "light";
            SystemOption.IsChecked = settings.Theme == "system";
            TraySwitch.IsOn = settings.MinimizeToTray;
            DriverNotifySwitch.IsOn = settings.NotifyDriver;
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

    private void Setting_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading || TraySwitch is null || DriverNotifySwitch is null) return;
        var settings = App.Services.Settings;
        settings.MinimizeToTray = TraySwitch.IsOn;
        settings.NotifyDriver = DriverNotifySwitch.IsOn;
        Save();
    }

    private void Save()
    {
        if (!App.Services.Settings.Save())
            ShowInfo("保存失败", "无法写入 gui-settings.json，请检查目录权限。", InfoBarSeverity.Warning);
    }

    private void OpenConfig_Click(object sender, RoutedEventArgs e) => OpenFolder(AppPaths.BaseDir);

    private async void Export_Click(object sender, RoutedEventArgs e)
    {
        if (_exporting) return;

        var picker = new FileSavePicker
        {
            SuggestedStartLocation = PickerLocationId.Desktop,
            SuggestedFileName = $"游戏性能优化中心_v{AppPaths.Version}_便携版"
        };
        picker.FileTypeChoices.Add("ZIP 压缩包", new List<string> { ".zip" });
        if (App.MainWindow is not null)
            WinRT.Interop.InitializeWithWindow.Initialize(picker,
                WinRT.Interop.WindowNative.GetWindowHandle(App.MainWindow));

        Windows.Storage.StorageFile? file;
        try
        {
            file = await picker.PickSaveFileAsync();
        }
        catch (Exception ex)
        {
            ShowInfo("无法选择保存位置", ex.Message, InfoBarSeverity.Error);
            return;
        }
        if (file is null) return;
        if (string.IsNullOrWhiteSpace(file.Path))
        {
            ShowInfo("无法导出", "请选择一个本地文件夹作为保存位置。", InfoBarSeverity.Warning);
            return;
        }

        _exporting = true;
        ExportButton.IsEnabled = false;
        OpenExportButton.IsEnabled = false;
        ExportStatus.Text = "正在导出，请稍候…";
        try
        {
            var (count, bytes) = await PortableExportService.ExportAsync(file.Path);
            _lastExportPath = file.Path;
            ExportStatus.Text = $"已导出 {count} 个文件（{bytes / 1024.0 / 1024.0:0.0} MB）：{file.Path}";
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
                Text = "将外观与行为设置恢复为默认值（深色主题、关闭托盘、开启驱动提醒）。\n\n备份、日志与游戏库不会受影响。",
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
        settings.MinimizeToTray = false;
        settings.NotifyDriver = true;
        Save();
        LoadIntoUi();
        if (App.MainWindow is MainWindow main) main.RefreshTheme();
        ShowInfo("已恢复默认设置", "外观与行为设置已重置。", InfoBarSeverity.Success);
    }

    private void ShowInfo(string title, string message, InfoBarSeverity severity)
    {
        PageInfo.Title = title;
        PageInfo.Message = message;
        PageInfo.Severity = severity;
        PageInfo.IsOpen = true;
    }

    public void OnThemeChanged() { }
}
