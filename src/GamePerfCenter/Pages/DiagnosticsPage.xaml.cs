using System.Collections.ObjectModel;
using System.Diagnostics;
using GamePerfCenter.Helpers;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Pages;

public sealed partial class DiagnosticsPage : Page, IThemeAware, ILanguageAware
{
    private readonly ObservableCollection<DiagGroup> _groups = new();
    private readonly List<DiagEntry> _entries = new();
    private string _level = "all";
    private string _query = "";
    private string? _lastExport;
    private bool _loaded;
    private bool _running;
    private bool _memoryBusy;
    private MemorySnapshot? _memory;

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
        await Task.WhenAll(RunDiagnosticsAsync(), RefreshMemoryAsync());
    }

    /// <summary>只读采样内存构成；WMI 查询放后台线程，避免首次进入诊断页时卡住界面。</summary>
    private async Task RefreshMemoryAsync()
    {
        if (_memoryBusy) return;
        _memoryBusy = true;
        MemoryRefreshButton.IsEnabled = false;
        MemoryStamp.Text = Localization.T("正在读取内存构成...");
        try
        {
            _memory = await Task.Run(MemoryDiagnosticsService.Sample);
            RenderMemory();
        }
        catch (Exception ex)
        {
            MemoryStamp.Text = Localization.F("内存构成读取失败: {0}", ex.Message);
        }
        finally
        {
            _memoryBusy = false;
            MemoryRefreshButton.IsEnabled = true;
        }
    }

    private void RenderMemory()
    {
        if (_memory is not { } m) return;

        MemUsedValue.Text = $"{m.UsedGb:0.0} / {m.TotalGb:0.0} GB";
        MemAvailableValue.Text = $"{m.AvailableGb:0.0} GB";
        MemStandbyValue.Text = $"{m.StandbyGb:0.0} GB";
        MemCommittedValue.Text = $"{m.CommittedGb:0.0} / {m.CommitLimitGb:0.0} GB";
        MemPagedPoolValue.Text = $"{m.PagedPoolGb:0.00} GB";
        MemNonPagedPoolValue.Text = $"{m.NonPagedPoolGb:0.00} GB";
        MemFreeValue.Text = $"{m.FreeGb:0.0} GB";
        MemProcessTotalValue.Text = $"{m.ProcessTotalGb:0.0} GB";

        MemoryProcessList.ItemsSource = m.Processes;
        MemoryEmpty.Text = Localization.T("暂无进程数据");
        MemoryEmpty.Visibility = m.Processes.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        MemoryStamp.Text = Localization.F("更新于 {0}", m.UpdatedAt.ToString("HH:mm:ss"));
    }

    private async void MemoryRefresh_Click(object sender, RoutedEventArgs e) => await RefreshMemoryAsync();

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

    FilterAll.Content = Localization.F("全部 {0}", _entries.Count);
    FilterAttention.Content = Localization.F("需关注 {0}", bad + warn);
    FilterOk.Content = Localization.F("正常 {0}", ok);
    DiagSummary.Text = Localization.F("{0} 项警告 · {1} 项注意 · {2} 项正常", bad, warn, ok);
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
            Name = GroupLabel(group.Key),
            Hint = bad > 0
                ? Localization.F("{0} 项需关注", bad)
                : warn > 0
                    ? Localization.F("{0} 项提示", warn)
                    : Localization.F("{0} 项正常", items.Count),
            Items = items
        });
    }

    var hasAny = _entries.Count > 0;
    var hasResult = filtered.Count > 0;
    ResultsCard.Visibility = hasResult ? Visibility.Visible : Visibility.Collapsed;
    EmptyHint.Visibility = hasResult ? Visibility.Collapsed : Visibility.Visible;
    EmptyTitle.Text = Localization.T(hasAny
        ? "没有匹配的诊断项"
        : _running ? "正在执行诊断" : "还没有诊断结果");
    EmptyDetail.Text = Localization.T(hasAny
        ? "换个关键词，或切换到“全部”查看完整结果。"
        : _running
            ? "正在读取硬件、电源与服务状态，通常需要几秒。"
            : "运行一次诊断，确认当前系统的风险与可优化项。");
    EmptyAction.Visibility = hasAny || _running ? Visibility.Collapsed : Visibility.Visible;
}

/// <summary>引擎分组名是中文数据，英文界面单独映射，避免污染通用词表的反向还原。</summary>
private static string GroupLabel(string name) => !Localization.IsEnglish ? name : name switch
{
    "系统" => "System",
    "内存" => "Memory",
    "显卡" => "GPU",
    "网络" => "Network",
    "供电" => "Power",
    "其他" => "Other",
    _ => name
};

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

    /// <summary>重建分组视图，让 x:Bind 的等级文案按新语言重新求值。</summary>
    public void OnLanguageChanged()
    {
        UpdateSummary();
        ApplyFilter();
        if (_memory is null) MemoryStamp.Text = Localization.T("正在读取内存构成...");
        else RenderMemory();
    }
}
