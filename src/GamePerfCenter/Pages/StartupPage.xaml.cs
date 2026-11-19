using System.Collections.ObjectModel;
using System.Diagnostics;
using GamePerfCenter.Helpers;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Pages;

public sealed partial class StartupPage : Page, IThemeAware
{
    private const int TopProcesses = 14;

    private readonly ObservableCollection<StartupEntry> _startup = new();
    private readonly ObservableCollection<BackgroundProc> _background = new();
    private bool _loaded;

    public StartupPage()
    {
        InitializeComponent();
        StartupList.ItemsSource = _startup;
        BackgroundList.ItemsSource = _background;
        Loaded += OnLoaded;
        // 窄窗口两张卡片改为上下排列，各自内部滚动。
        Responsive.Watch(this, 900, ApplyWidth);
    }

    private void ApplyWidth(bool narrow)
    {
        ContentGrid.ColumnDefinitions[0].Width = new GridLength(1, GridUnitType.Star);
        ContentGrid.ColumnDefinitions[1].Width = narrow
            ? new GridLength(0)
            : new GridLength(1, GridUnitType.Star);
        ContentGrid.RowDefinitions[0].Height = new GridLength(1, GridUnitType.Star);
        ContentGrid.RowDefinitions[1].Height = narrow
            ? new GridLength(1, GridUnitType.Star)
            : new GridLength(0);

        if (narrow)
        {
            Grid.SetRow(BackgroundCard, 1);
            Grid.SetColumn(BackgroundCard, 0);
            Grid.SetColumnSpan(BackgroundCard, 2);
        }
        else
        {
            Grid.SetRow(BackgroundCard, 0);
            Grid.SetColumn(BackgroundCard, 1);
            Grid.SetColumnSpan(BackgroundCard, 1);
        }

        // 卡片变窄后标题与右侧计数会挤在一起，只保留标题。
        BackgroundHint.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible;
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
            var backgroundTask = App.Services.State.GetBackgroundAsync(TopProcesses);
            await Task.WhenAll(startupTask, backgroundTask);

            _startup.Clear();
            foreach (var entry in await startupTask) _startup.Add(entry);

            _background.Clear();
            var procs = (await backgroundTask)
                .OrderByDescending(p => p.MemMB)
                .Take(TopProcesses)
                .ToList();
            var max = procs.Count > 0 ? Math.Max(1, procs[0].MemMB) : 1;
            foreach (var proc in procs)
            {
                proc.Share = Math.Clamp(proc.MemMB / max * 100, 1.5, 100);
                _background.Add(proc);
            }

            StartupHint.Text = _startup.Count == 0 ? "" : $"{_startup.Count} 项";
            BackgroundHint.Text = _background.Count == 0 ? "" : $"共 {_background.Count} 个";
            StartupCountText.Text = _startup.Count.ToString();
            BackgroundCountText.Text = _background.Count.ToString();
            BackgroundTotalText.Text = FormatMemory(_background.Sum(p => p.MemMB));

            StartupEmpty.Visibility = _startup.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
            BackgroundEmpty.Visibility = _background.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
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

    private static string FormatMemory(double mb) =>
        mb >= 1024 ? $"{mb / 1024:0.0} GB" : $"{mb:0} MB";

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
        PageInfo.Title = Localization.T(title);
        PageInfo.Message = Localization.T(message);
        PageInfo.Severity = severity;
        PageInfo.IsOpen = true;
    }

    public void OnThemeChanged() { }
}