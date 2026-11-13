using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Foundation;
using Windows.UI.ViewManagement;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using GamePerfCenter.Helpers;

namespace GamePerfCenter.Pages;

public sealed partial class OverviewPage : Page, IThemeAware
{
    private const int HistoryLimit = 45;
    private const double RadarCenter = 132;
    private readonly List<double> _cpuHistory = new();
    private Storyboard? _sweep;
    private MainWindow? _shell;

    public OverviewPage()
    {
        InitializeComponent();
        NavigationCacheMode = Microsoft.UI.Xaml.Navigation.NavigationCacheMode.Required;
        App.Services.State.Changed += OnStateChanged;
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        Responsive.Watch(this, 1020, ApplyWidth);
        Responsive.Watch(this, 760, ApplyCompact);
        Responsive.Watch(this, 900, ApplyBottom);
    }

    /// <summary>窄窗口时把优化进度移到仪表下方，避免横向挤压。</summary>
    private void ApplyWidth(bool narrow)
    {
        // 优化进度移走后，右侧两列不再需要占位；否则固定的 264 + 300 会把
        // 中间的自适应列压成 0，窄窗口下雷达与遥测被裁掉一截。
        HeroGrid.ColumnDefinitions[2].Width = narrow ? new GridLength(0) : new GridLength(1);
        HeroGrid.ColumnDefinitions[3].Width = narrow ? new GridLength(0) : new GridLength(300);

        if (narrow)
        {
            Grid.SetRow(PendingDivider, 3);
            Grid.SetColumn(PendingDivider, 0);
            Grid.SetColumnSpan(PendingDivider, 4);
            PendingDivider.Width = double.NaN;
            PendingDivider.Height = 1;
            PendingDivider.Margin = new Thickness(0, 18, 0, 0);

            Grid.SetRow(PendingPanel, 4);
            Grid.SetColumn(PendingPanel, 0);
            Grid.SetColumnSpan(PendingPanel, 4);
            PendingPanel.Width = double.NaN;
            PendingPanel.Margin = new Thickness(0, 16, 0, 0);
        }
        else
        {
            Grid.SetRow(PendingDivider, 1);
            Grid.SetColumn(PendingDivider, 2);
            Grid.SetColumnSpan(PendingDivider, 1);
            PendingDivider.Width = 1;
            PendingDivider.Height = double.NaN;
            PendingDivider.Margin = new Thickness(0, 2, 0, 2);

            Grid.SetRow(PendingPanel, 1);
            Grid.SetColumn(PendingPanel, 3);
            Grid.SetColumnSpan(PendingPanel, 1);
            PendingPanel.Width = 300;
            PendingPanel.Margin = new Thickness(0);
        }
    }

    /// <summary>更窄时把遥测列移到雷达下方。</summary>
    private void ApplyCompact(bool compact)
    {
        // 遥测列移到雷达下方后，第一列接管整行宽度，雷达仍保持 264 的固定尺寸。
        HeroGrid.ColumnDefinitions[0].Width = compact
            ? new GridLength(1, GridUnitType.Star)
            : new GridLength(264);
        HeroGrid.ColumnDefinitions[1].Width = compact
            ? new GridLength(0)
            : new GridLength(1, GridUnitType.Star);

        if (compact)
        {
            Grid.SetRow(LiveStats, 2);
            Grid.SetColumn(LiveStats, 0);
            Grid.SetColumnSpan(LiveStats, 2);
            LiveStats.MinWidth = 0;
            LiveStats.Margin = new Thickness(0, 18, 0, 0);
        }
        else
        {
            Grid.SetRow(LiveStats, 1);
            Grid.SetColumn(LiveStats, 1);
            Grid.SetColumnSpan(LiveStats, 1);
            LiveStats.MinWidth = 190;
            LiveStats.Margin = new Thickness(4, 0, 0, 0);
        }
    }

    /// <summary>窄窗口时硬件与安全改为上下排列。</summary>
    private void ApplyBottom(bool narrow)
    {
        if (narrow)
        {
            Grid.SetRow(SecurityCard, 1);
            Grid.SetColumn(SecurityCard, 0);
            Grid.SetColumnSpan(SecurityCard, 2);
            SecurityCard.Margin = new Thickness(0, 14, 0, 0);
        }
        else
        {
            Grid.SetRow(SecurityCard, 0);
            Grid.SetColumn(SecurityCard, 1);
            Grid.SetColumnSpan(SecurityCard, 1);
            SecurityCard.Margin = new Thickness(0);
        }
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        BuildRadarTicks();
        StartRadarSweep();
        RefreshUi();
        SubscribeMetrics();
        if (_shell?.LatestMetrics is { } latest) OnMetrics(latest);
        _ = EnsureDataAsync();
    }

    /// <summary>雷达扫描扇区：系统关闭动画时停在固定角度，避免无意义的循环重绘。</summary>
    private void StartRadarSweep()
    {
        if (_sweep is not null) return;
        try
        {
            if (!new UISettings().AnimationsEnabled)
            {
                RadarSweepRotate.Angle = 42;
                return;
            }
        }
        catch { }

        var animation = new DoubleAnimation
        {
            From = 0,
            To = 360,
            Duration = new Duration(TimeSpan.FromSeconds(8)),
            RepeatBehavior = RepeatBehavior.Forever
        };
        Storyboard.SetTarget(animation, RadarSweepRotate);
        Storyboard.SetTargetProperty(animation, "Angle");
        _sweep = new Storyboard();
        _sweep.Children.Add(animation);
        _sweep.Begin();
    }

    /// <summary>雷达外圈的 36 根刻度，9 根一组加长，用主题描边色绘制。</summary>
    private void BuildRadarTicks()
    {
        RadarTicks.Children.Clear();
        var brush = ThemeResources.Get("BorderStrongBrush");
        const double center = RadarCenter;
        for (var i = 0; i < 36; i++)
        {
            var angle = i * Math.PI / 18;
            var major = i % 9 == 0;
            var inner = major ? 118 : 122;
            RadarTicks.Children.Add(new Microsoft.UI.Xaml.Shapes.Line
            {
                X1 = center + Math.Cos(angle) * inner,
                Y1 = center + Math.Sin(angle) * inner,
                X2 = center + Math.Cos(angle) * 126,
                Y2 = center + Math.Sin(angle) * 126,
                Stroke = brush,
                StrokeThickness = major ? 1 : 0.75,
                Opacity = major ? 0.9 : 0.5
            });
        }
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        UnsubscribeMetrics();
        _sweep?.Stop();
        _sweep = null;
    }

    private void SubscribeMetrics()
    {
        if (App.MainWindow is not MainWindow shell) return;
        _shell = shell;
        shell.MetricsUpdated -= OnMetrics;
        shell.MetricsUpdated += OnMetrics;
    }

    private void UnsubscribeMetrics()
    {
        if (_shell is not null) _shell.MetricsUpdated -= OnMetrics;
        _shell = null;
    }

    private void OnStateChanged()
    {
        DispatcherQueue.TryEnqueue(RefreshUi);
    }

    private async Task EnsureDataAsync()
    {
        try { await App.Services.State.EnsureSnapshotAsync(); }
        catch (Exception ex) { ShowAction("状态读取失败", ex.Message, InfoBarSeverity.Error); }
        RefreshUi();
    }

    private void RefreshUi()
    {
        var snap = App.Services.State.Snapshot;
        if (snap is null)
        {
            StatusHeadline.Text = "正在读取本机状态...";
            StatusDetail.Text = string.IsNullOrWhiteSpace(App.Services.State.StatusText)
                ? "正在采集硬件与优化项状态。"
                : App.Services.State.StatusText;
            PendingCount.Text = "--";
            CompletionBar.Value = 0;
            AppliedText.Text = "已生效 -- 项";
            RecoText.Text = "低风险推荐 -- 项";
            RebootText.Text = "重启状态：读取中";
            SecurityText.Text = "安全与存储：读取中";
            ApplyRecommendedButton.Content = "应用推荐项";
            ApplyRecommendedButton.IsEnabled = false;
            HardwareSubtitle.Text = "正在读取设备信息...";
            SignalPower.Text = "—";
            SignalGpu.Text = "—";
            SignalApply.Text = "—";
            return;
        }

        var recommended = GetRecommendedIds();
        var s = snap.Summary;
        PendingCount.Text = s.Pending.ToString();
        UpdateCompletion(s.Applied, s.Total, s.NotApplicable, s.Checking);
        StatusHeadline.Text = s.Pending == 0 ? "当前没有待优化项" : "还有可应用的优化项";
        StatusDetail.Text = s.Pending == 0
            ? "推荐项均已生效。可以打开优化项手动复查，或预览当前配置。"
            : $"{recommended.Count} 项低风险推荐项可直接应用；应用前自动备份原值，可在「备份还原」中撤销。";
        RecoText.Text = recommended.Count > 0
            ? $"低风险推荐 {recommended.Count} 项可应用"
            : "低风险推荐：暂无待应用项";
        ApplyRecommendedButton.Content = recommended.Count > 0 ? $"应用 {recommended.Count} 项" : "暂无推荐项";
        ApplyRecommendedButton.IsEnabled = recommended.Count > 0;

        RebootText.Text = snap.PendingReboot?.Pending == true
            ? "重启状态：等待重启后生效"
            : "重启状态：无需重启";
        var issues = snap.Diagnostics.Count(d =>
            d.Group is "安全" or "存储" && d.Level is "Red" or "Yellow");
        SecurityText.Text = issues == 0 ? "安全与存储：未见异常" : $"安全与存储：{issues} 项提示";

        var machine = string.IsNullOrWhiteSpace(snap.Machine) ? "本机" : snap.Machine;
        var gpus = snap.Gpus.Where(g => !g.Basic && !g.Virtual)
            .Select(g => g.Name)
            .Where(n => !string.IsNullOrWhiteSpace(n))
            .ToList();
        LiveDeviceLine.Text = gpus.Count > 0 ? "显示设备 · " + string.Join(" + ", gpus) : "未识别到显示设备";
        HardwareSubtitle.Text = $"{machine} · {(snap.IsLaptop ? "笔记本" : "台式机")}";
        SignalPower.Text = snap.OnAC switch { true => "交流供电", false => "电池供电", _ => "未知" };
        SignalGpu.Text = App.Services.Metrics.GpuAvailable ? "可用 · 2 秒采样" : "不可用";
        SignalApply.Text = snap.LastApply is null
            ? "暂无记录"
            : $"{snap.LastApply.Items.Count} 项 · {ShortTime(snap.LastApply.Time)}";

        PendingBar.IsOpen = snap.PendingReboot?.Pending == true;
        if (snap.PendingReboot?.Pending == true)
            PendingBar.Message = "检测到系统等待重启：" + string.Join("、", snap.PendingReboot.Reasons) +
                                 "。部分优化需要重启后才会生效。";

        HardwareList.ItemsSource = HardwareSummary(snap.Diagnostics);
        var extra = new List<DiagEntry>();
        if (snap.LastApply is not null)
        {
            extra.Add(new DiagEntry
            {
                Group = "记录",
                Name = "上次应用",
                Value = string.IsNullOrWhiteSpace(snap.LastApply.Result)
                    ? $"{snap.LastApply.Items.Count} 项 · {snap.LastApply.Time}"
                    : snap.LastApply.Result,
                Level = snap.LastApply.Errors.Count > 0 ? "Yellow" : "Green"
            });
        }
        DiagList.ItemsSource = snap.Diagnostics
            .Where(d => d.Group is "安全" or "存储")
            .Concat(extra)
            .Take(8)
            .ToList();
        HardwareUpdated.Text = $"更新于 {snap.Time?.Replace('T', ' ')}";
    }

    /// <summary>完成度只画一条细进度条，仪表位置留给实时负载。</summary>
    private void UpdateCompletion(int applied, int total, int notApplicable, int checking)
    {
        var effective = Math.Max(0, total - notApplicable);
        var fraction = effective > 0 ? Math.Clamp((double)applied / effective, 0d, 1d) : 0d;
        CompletionBar.Value = fraction * 100;

        var line = effective > 0 ? $"已生效 {applied} / {effective} 项可优化" : "已生效 -- 项";
        if (notApplicable > 0) line += $" · {notApplicable} 项不适用";
        if (checking > 0) line += $" · {checking} 项检测中";
        AppliedText.Text = line;
        ToolTipService.SetToolTip(CompletionBar,
            effective > 0 ? $"优化完成度 {fraction:P0}" : "优化完成度：正在读取本机状态");
    }

    private void OnMetrics(LiveMetrics m)
    {
        CpuValue.Text = m.Cpu.ToString("0");
        UpdateRing(CpuRing, m.Cpu, RadarCenter, 108);
        PushHistory(_cpuHistory, m.Cpu);
        RenderSpark(CpuSparkLine, _cpuHistory);

        var gpuAvailable = App.Services.Metrics.GpuAvailable;
        GpuValue.Text = gpuAvailable ? m.Gpu.ToString("0") : "--";
        GpuRingLabel.Text = gpuAvailable ? "GPU 3D" : "GPU 未提供";
        SignalGpu.Text = gpuAvailable ? "可用 · 2 秒采样" : "不可用";
        GpuRing.Opacity = gpuAvailable ? 0.85 : 0.25;
        UpdateRing(GpuRing, gpuAvailable ? m.Gpu : 0, RadarCenter, 90);
        GpuBar.Value = gpuAvailable ? m.Gpu : 0;

        RamValue.Text = m.RamPercent.ToString("0") + "%";
        RamBar.Value = m.RamPercent;
        RamHint.Text = $"{m.RamUsedGb:0.0} / {m.RamTotalGb:0.0} GB 已用";

        NetValue.Text = "↓ " + FormatRate(m.NetDownKbps);
        NetHint.Text = "↑ " + FormatRate(m.NetUpKbps);
        LiveStamp.Text = $"更新于 {DateTime.Now:HH:mm:ss} · 2 秒采样";
    }

    private static void UpdateRing(Microsoft.UI.Xaml.Shapes.Path ring, double value, double center, double radius)
    {
        var fraction = Math.Clamp(value, 0, 100) / 100.0;
        if (fraction <= 0.004)
        {
            ring.Data = null;
            return;
        }
        if (fraction >= 0.996)
        {
            ring.Data = new EllipseGeometry
            {
                Center = new Point(center, center),
                RadiusX = radius,
                RadiusY = radius
            };
            return;
        }

        var radians = (fraction * 360 - 90) * Math.PI / 180;
        var figure = new PathFigure
        {
            StartPoint = new Point(center, center - radius),
            IsClosed = false,
            IsFilled = false
        };
        figure.Segments.Add(new ArcSegment
        {
            Point = new Point(center + radius * Math.Cos(radians), center + radius * Math.Sin(radians)),
            Size = new Size(radius, radius),
            SweepDirection = SweepDirection.Clockwise,
            IsLargeArc = fraction > 0.5
        });
        var geometry = new PathGeometry();
        geometry.Figures.Add(figure);
        ring.Data = geometry;
    }

    private static void PushHistory(List<double> history, double value)
    {
        history.Add(value);
        if (history.Count > HistoryLimit) history.RemoveRange(0, history.Count - HistoryLimit);
    }

    private static void RenderSpark(Microsoft.UI.Xaml.Shapes.Polyline line, IReadOnlyList<double> values)
    {
        const double width = 264;
        const double height = 28;
        if (values.Count < 2)
        {
            line.Points.Clear();
            return;
        }

        var points = new PointCollection();
        for (var i = 0; i < values.Count; i++)
        {
            var x = i * width / (values.Count - 1);
            var y = height - 2 - Math.Clamp(values[i], 0, 100) / 100 * (height - 4);
            points.Add(new Point(x, y));
        }
        line.Points = points;
    }

    private static string FormatRate(double kbps)
    {
        if (kbps >= 1024) return $"{kbps / 1024:0.0} MB/s";
        return $"{kbps:0} KB/s";
    }

    /// <summary>上次应用时间只保留“月-日 时:分”，完整时间在备份页可查。</summary>
    private static string ShortTime(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "时间未知";
        var text = value.Replace('T', ' ');
        return text.Length >= 16 && text[4] == '-' ? text.Substring(5, 11) : text;
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            ShowAction("正在刷新", "重新读取硬件与优化项状态...", InfoBarSeverity.Informational);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            ShowAction("刷新完成", "硬件与优化项状态已更新。", InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowAction("刷新失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private void OpenItems_Click(object sender, RoutedEventArgs e)
    {
        if (App.MainWindow is MainWindow main) main.NavigateTo("items");
    }

    private List<string> GetRecommendedIds()
    {
        return App.Services.State.Items
            .Where(i => i.Risk == "low" && i.Status is "no" or "checking")
            .Select(i => i.Id)
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id!)
            .ToList();
    }

    private async void ApplyRecommended_Click(object sender, RoutedEventArgs e)
    {
        var ids = GetRecommendedIds();
        if (ids.Count == 0)
        {
            ShowAction("无需优化", "当前没有处于待优化状态的低风险项目。", InfoBarSeverity.Success);
            return;
        }
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "应用推荐优化",
            Content = new TextBlock
            {
                Text = $"将应用 {ids.Count} 项低风险优化。\n\n应用前会自动生成 JSON 原值备份与 .reg 快照，可在「备份还原」中撤销。",
                TextWrapping = TextWrapping.Wrap,
                LineHeight = 22
            },
            PrimaryButtonText = $"应用 {ids.Count} 项",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        await RunApplyAsync(ids, dryRun: false);
    }

    private async void Preview_Click(object sender, RoutedEventArgs e)
    {
        var ids = GetRecommendedIds();
        if (ids.Count == 0)
        {
            ShowAction("无需预览", "当前没有处于待优化状态的低风险项目。", InfoBarSeverity.Informational);
            return;
        }
        await RunApplyAsync(ids, dryRun: true);
    }

    private async Task RunApplyAsync(List<string> ids, bool dryRun)
    {
        try
        {
            ActionInfo.IsOpen = false;
            var result = await App.Services.State.ApplyAsync(ids, dryRun);
            if (dryRun)
            {
                await ShowPreviewAsync(result);
            }
            else
            {
                var msg = $"成功 {result.Ok} 项 · 失败 {result.Fail} 项";
                if (!string.IsNullOrWhiteSpace(result.Backup)) msg += $"\n备份：{result.Backup}";
                ShowAction(result.Fail == 0 ? "优化已应用" : "部分项目失败", msg,
                    result.Fail == 0 ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
                await App.Services.State.EnsureSnapshotAsync(force: true);
            }
        }
        catch (Exception ex)
        {
            ShowAction("操作失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async Task ShowPreviewAsync(ApplyResult result)
    {
        var panel = new StackPanel { Spacing = 10 };
        if (result.Preview.Count == 0)
        {
            panel.Children.Add(new TextBlock
            {
                Text = "所选项目均已处于推荐值，无需变更。",
                TextWrapping = TextWrapping.Wrap
            });
        }
        else
        {
            panel.Children.Add(new TextBlock
            {
                Text = $"共 {result.Preview.Count} 项将发生变更（预览不会写入系统）：",
                TextWrapping = TextWrapping.Wrap,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            foreach (var item in result.Preview)
            {
                var row = new StackPanel { Spacing = 2, Margin = new Thickness(0, 2, 0, 6) };
                row.Children.Add(new TextBlock { Text = item.Name, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
                row.Children.Add(new TextBlock
                {
                    Text = $"当前：{item.Current}  →  目标：{item.Target}" + (item.NeedsReboot ? "  · 需重启" : ""),
                    Opacity = 0.78,
                    FontSize = 12.5,
                    TextWrapping = TextWrapping.Wrap
                });
                panel.Children.Add(row);
            }
        }
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "变更预览",
            Content = new ScrollViewer
            {
                Content = panel,
                MaxHeight = 460,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            },
            CloseButtonText = "关闭"
        };
        await dialog.ShowAsync();
    }

    private void ShowAction(string title, string message, InfoBarSeverity severity)
    {
        ActionInfo.Title = title;
        ActionInfo.Message = message;
        ActionInfo.Severity = severity;
        ActionInfo.IsOpen = true;
    }

    /// <summary>
    /// 概览只保留回答“这台机器是什么”的四行：系统、CPU、内存、显卡。
    /// 完整清单在诊断报告页，避免首屏被九行硬件信息撑出折叠线。
    /// </summary>
    private static List<DiagEntry> HardwareSummary(IEnumerable<DiagEntry> diagnostics)
    {
        var all = diagnostics.Where(d => d.Group is "系统" or "显卡").ToList();
        var picked = new List<DiagEntry>();
        foreach (var name in new[] { "操作系统", "CPU", "内存" })
        {
            var entry = all.FirstOrDefault(d => string.Equals(d.Name, name, StringComparison.Ordinal));
            if (entry is not null) picked.Add(entry);
        }

        var gpu = all.FirstOrDefault(d => d.Group == "显卡");
        if (gpu is not null) picked.Add(gpu);

        foreach (var entry in all)
        {
            if (picked.Count >= 4) break;
            if (!picked.Contains(entry)) picked.Add(entry);
        }
        return picked;
    }

    private void OpenDiagnostics_Click(object sender, RoutedEventArgs e)
    {
        if (App.MainWindow is MainWindow main) main.NavigateTo("diagnostics");
    }

    public void OnThemeChanged()
    {
        BuildRadarTicks();
        if (App.Services.State.Snapshot is { } snap)
        {
            HardwareList.ItemsSource = null;
            DiagList.ItemsSource = null;
            HardwareList.ItemsSource = HardwareSummary(snap.Diagnostics);
            DiagList.ItemsSource = snap.Diagnostics.Where(d => d.Group is "安全" or "存储").Take(8).ToList();
        }
    }
}
