using System.Collections.ObjectModel;
using System.Diagnostics;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Pages;

public sealed partial class DiagnosticsPage : Page, IThemeAware
{
    private readonly ObservableCollection<DiagGroup> _groups = new();
    private string? _lastExport;
    private bool _loaded;

    public DiagnosticsPage()
    {
        InitializeComponent();
        GroupList.ItemsSource = _groups;
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_loaded) return;
        _loaded = true;
        await RunDiagnosticsAsync();
    }

    private async Task RunDiagnosticsAsync()
    {
        try
        {
            App.Services.State.SetStatus("正在执行系统诊断...");
            var entries = await App.Services.State.GetDiagnosticsAsync();
            _groups.Clear();
            foreach (var group in entries.GroupBy(e => e.Group ?? "其他"))
            {
                var items = group.ToList();
                var warn = items.Count(e => string.Equals(e.Level, "warn", StringComparison.OrdinalIgnoreCase));
                var bad = items.Count(e => string.Equals(e.Level, "bad", StringComparison.OrdinalIgnoreCase)
                                          || string.Equals(e.Level, "error", StringComparison.OrdinalIgnoreCase));
                _groups.Add(new DiagGroup
                {
                    Name = group.Key,
                    Hint = bad > 0 ? $"{bad} 项需关注" : warn > 0 ? $"{warn} 项提示" : $"{items.Count} 项正常",
                    Items = items
                });
            }
            EmptyHint.Visibility = _groups.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }
        catch (Exception ex)
        {
            ShowInfo("诊断失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            App.Services.State.SetStatus("就绪");
        }
    }

    private async void Run_Click(object sender, RoutedEventArgs e) => await RunDiagnosticsAsync();

    private async void ExportReport_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            App.Services.State.SetStatus("正在生成诊断报告...");
            var path = await App.Services.State.ExportReportAsync();
            SetExport("诊断报告已生成", path);
            ShowInfo("导出完成", "报告已保存：" + path, InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowInfo("导出失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            App.Services.State.SetStatus("就绪");
        }
    }

    private async void ExportBundle_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            App.Services.State.SetStatus("正在打包诊断信息...");
            var path = await App.Services.State.ExportBundleAsync();
            SetExport("诊断包已生成", path);
            ShowInfo("打包完成", "诊断包已保存：" + path, InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowInfo("打包失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            App.Services.State.SetStatus("就绪");
        }
    }

    private void SetExport(string title, string? path)
    {
        _lastExport = path;
        LastExportTitle.Text = title;
        LastExportPath.Text = string.IsNullOrEmpty(path) ? "路径未知" : path;
        ToolTipService.SetToolTip(LastExportPath, path);
        OpenExportButton.IsEnabled = !string.IsNullOrEmpty(path) && File.Exists(path);
    }

    private void OpenExport_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrEmpty(_lastExport) || !File.Exists(_lastExport)) return;
        try
        {
            Process.Start(new ProcessStartInfo { FileName = _lastExport, UseShellExecute = true });
        }
        catch (Exception ex)
        {
            ShowInfo("无法打开文件", ex.Message, InfoBarSeverity.Error);
        }
    }

    private void OpenFolder_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.DiagnosticsDir);
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"\"{AppPaths.DiagnosticsDir}\"",
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            ShowInfo("无法打开目录", ex.Message, InfoBarSeverity.Error);
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
