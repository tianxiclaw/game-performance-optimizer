using System.Collections.ObjectModel;
using System.Diagnostics;
using GamePerfCenter.Helpers;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Pages;

public sealed partial class DiagnosticsPage : Page, IThemeAware
{
    private readonly ObservableCollection<DiagGroup> _groups = new();
    private readonly List<DiagEntry> _entries = new();
    private string _level = "all";
    private string _query = "";
    private string? _lastExport;
    private bool _loaded;
    private bool _running;

    public DiagnosticsPage()
    {
        InitializeComponent();
        GroupList.ItemsSource = _groups;
        // 首次进入、诊断尚未返回时也要有可见状态，而不是一片空白。
        ApplyFilter();
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
        _running = true;
        ApplyFilter();
        try
        {
            App.Services.State.SetStatus("正在执行系统诊断...");
            var entries = await App.Services.State.GetDiagnosticsAsync();
            _entries.Clear();
            _entries.AddRange(entries);
            UpdateSummary();
        }
        catch (Exception ex)
        {
            ShowInfo("诊断失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            _running = false;
            ApplyFilter();
            App.Services.State.SetStatus("就绪");
        }
    }

    private void UpdateSummary()
{
    var bad = _entries.Count(e => IsBad(e.Level));
    var warn = _entries.Count(e => IsWarn(e.Level));
    var ok = _entries.Count(e => IsOk(e.Level));

    FilterAll.Content = $"全部 {_entries.Count}";
    FilterAttention.Content = $"需关注 {bad + warn}";
    FilterOk.Content = $"正常 {ok}";
    DiagSummary.Text = $"{bad} 项警告 · {warn} 项注意 · {ok} 项正常";
    PaintChips();
}

/// <summary>筛选只改变视图，不重新诊断；计数始终来自完整结果。</summary>
private void ApplyFilter()
{
    var query = _query.Trim();
    var filtered = _entries
        .Where(e => MatchLevel(e) && MatchQuery(e, query))
        .ToList();

    _groups.Clear();
    foreach (var group in filtered.GroupBy(e => e.Group ?? "其他"))
    {
        var items = group.ToList();
        var warn = items.Count(e => IsWarn(e.Level));
        var bad = items.Count(e => IsBad(e.Level));
        _groups.Add(new DiagGroup
        {
            Name = group.Key,
            Hint = bad > 0 ? $"{bad} 项需关注" : warn > 0 ? $"{warn} 项提示" : $"{items.Count} 项正常",
            Items = items
        });
    }

    var hasAny = _entries.Count > 0;
    var hasResult = filtered.Count > 0;
    ResultsCard.Visibility = hasResult ? Visibility.Visible : Visibility.Collapsed;
    EmptyHint.Visibility = hasResult ? Visibility.Collapsed : Visibility.Visible;
    EmptyTitle.Text = hasAny
        ? "没有匹配的诊断项"
        : _running ? "正在执行诊断" : "还没有诊断结果";
    EmptyDetail.Text = hasAny
        ? "换个关键词，或切换到“全部”查看完整结果。"
        : _running
            ? "正在读取硬件、电源与服务状态，通常需要几秒。"
            : "运行一次诊断，确认当前系统的风险与可优化项。";
    EmptyAction.Visibility = hasAny || _running ? Visibility.Collapsed : Visibility.Visible;
}

private bool MatchLevel(DiagEntry entry) => _level switch
{
    "attention" => IsBad(entry.Level) || IsWarn(entry.Level),
    "ok" => IsOk(entry.Level),
    _ => true
};

private static bool MatchQuery(DiagEntry entry, string query)
{
    if (query.Length == 0) return true;
    return Contains(entry.Name, query) || Contains(entry.Value, query) ||
           Contains(entry.Hint, query) || Contains(entry.Group, query);
}

private static bool Contains(string? value, string query) =>
    value is not null && value.Contains(query, StringComparison.OrdinalIgnoreCase);

private static bool IsBad(string? level) =>
    string.Equals(level, "bad", StringComparison.OrdinalIgnoreCase) ||
    string.Equals(level, "error", StringComparison.OrdinalIgnoreCase) ||
    string.Equals(level, "red", StringComparison.OrdinalIgnoreCase);

private static bool IsWarn(string? level) =>
    string.Equals(level, "warn", StringComparison.OrdinalIgnoreCase) ||
    string.Equals(level, "yellow", StringComparison.OrdinalIgnoreCase);

private static bool IsOk(string? level) =>
    string.Equals(level, "ok", StringComparison.OrdinalIgnoreCase) ||
    string.Equals(level, "green", StringComparison.OrdinalIgnoreCase);

private void PaintChips()
{
    PaintChip(FilterAll, _level == "all");
    PaintChip(FilterAttention, _level == "attention");
    PaintChip(FilterOk, _level == "ok");
}

private static void PaintChip(Button chip, bool active)
{
    chip.Background = ThemeResources.Get(active ? "AccentSoftBrush" : "Surface2Brush");
    chip.Foreground = ThemeResources.Get(active ? "AccentBrush" : "SubTextBrush");
    chip.BorderBrush = ThemeResources.Get(active ? "AccentDimBrush" : "Surface2Brush");
}

private void SetFilter(string level)
{
    _level = level;
    PaintChips();
    ApplyFilter();
}

private void FilterAll_Click(object sender, RoutedEventArgs e) => SetFilter("all");

private void FilterAttention_Click(object sender, RoutedEventArgs e) => SetFilter("attention");

private void FilterOk_Click(object sender, RoutedEventArgs e) => SetFilter("ok");

private void Search_TextChanged(object sender, TextChangedEventArgs e)
{
    _query = DiagSearch.Text ?? "";
    ApplyFilter();
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
        PageInfo.Title = Localization.T(title);
        PageInfo.Message = Localization.T(message);
        PageInfo.Severity = severity;
        PageInfo.IsOpen = true;
    }

    public void OnThemeChanged() { }
}
