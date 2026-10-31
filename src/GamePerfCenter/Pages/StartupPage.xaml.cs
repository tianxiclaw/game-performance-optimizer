using System.Collections.ObjectModel;
using System.Diagnostics;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Pages;

public sealed partial class StartupPage : Page, IThemeAware
{
    private readonly ObservableCollection<StartupEntry> _startup = new();
    private readonly ObservableCollection<BackgroundProc> _background = new();
    private bool _loaded;

    public StartupPage()
    {
        InitializeComponent();
        StartupList.ItemsSource = _startup;
        BackgroundList.ItemsSource = _background;
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_loaded) return;
        _loaded = true;
        await LoadAsync();
    }

    private async Task LoadAsync()
    {
        try
        {
            App.Services.State.SetStatus("正在读取启动项与进程...");
            var startupTask = App.Services.State.GetStartupAsync();
            var backgroundTask = App.Services.State.GetBackgroundAsync(14);
            await Task.WhenAll(startupTask, backgroundTask);

            _startup.Clear();
            foreach (var entry in await startupTask) _startup.Add(entry);
            _background.Clear();
            foreach (var proc in (await backgroundTask).OrderByDescending(p => p.MemMB)) _background.Add(proc);

            StartupHint.Text = $"来自注册表 Run 与启动文件夹 · {_startup.Count} 项";
            BackgroundHint.Text = $"共 {_background.Count} 个高占用进程";
            StartupEmpty.Visibility = _startup.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }
        catch (Exception ex)
        {
            ShowInfo("读取失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            App.Services.State.SetStatus("就绪");
        }
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e) => await LoadAsync();

    private void OpenTaskManager_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo { FileName = "taskmgr.exe", UseShellExecute = true });
        }
        catch (Exception ex)
        {
            ShowInfo("无法打开任务管理器", ex.Message, InfoBarSeverity.Error);
        }
    }

    private void OpenStartupFolder_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var folder = Environment.GetFolderPath(Environment.SpecialFolder.Startup);
            Process.Start(new ProcessStartInfo { FileName = "explorer.exe", Arguments = $"\"{folder}\"", UseShellExecute = true });
        }
        catch (Exception ex)
        {
            ShowInfo("无法打开启动文件夹", ex.Message, InfoBarSeverity.Error);
        }
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
