using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Animation;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using GamePerfCenter.Helpers;

namespace GamePerfCenter.Pages;

public sealed partial class OverviewPage : Page, IThemeAware, ILanguageAware
{
    private bool? _gpuWasAvailable;
    private string _lastStamp = "";
    private readonly NumberRoll _cpuRoll;
    private readonly NumberRoll _gpuRoll;
    private readonly NumberRoll _ramRoll;
    private Storyboard? _pulse;
    private MainWindow? _shell;
    /// <summary>主按钮当前是“一键应用”还是“查看待优化项”，由推荐项数量决定。</summary>
    private bool _applyMode;

    public OverviewPage()
    {
        InitializeComponent();
        _cpuRoll = new NumberRoll(CpuValue);
        _gpuRoll = new NumberRoll(GpuValue);
        _ramRoll = new NumberRoll(RamValue);
        NavigationCacheMode = Microsoft.UI.Xaml.Navigation.NavigationCacheMode.Required;
        App.Services.State.Changed += OnStateChanged;
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        Responsive.Watch(this, 1180, ApplyWidth);
        Responsive.Watch(this, 900, ApplyBottom);
    }

    /// <summary>宽屏三列；窄窗口下硬件与状态并排，实时资源独占一行，避免三块互相挤压。</summary>
    private void ApplyWidth(bool narrow)
    {
        if (narrow)
        {
            HeroGrid.ColumnDefinitions[0].Width = new GridLength(320);
            HeroGrid.ColumnDefinitions[1].Width = new GridLength(1, GridUnitType.Star);
            HeroGrid.ColumnDefinitions[2].Width = new GridLength(0);
            HeroGrid.RowSpacing = 16;

            Grid.SetRow(HardwareCard, 0);
            Grid.SetColumn(HardwareCard, 0);
            Grid.SetColumnSpan(HardwareCard, 1);

            Grid.SetRow(StatusCard, 0);
            Grid.SetColumn(StatusCard, 1);
            Grid.SetColumnSpan(StatusCard, 1);

            Grid.SetRow(ResourceCard, 1);
            Grid.SetColumn(ResourceCard, 0);
            Grid.SetColumnSpan(ResourceCard, 2);

            // 资源卡整行铺开，四项改为并排四列，保持与宽屏一致的读数距离。
            for (var i = 0; i < 4; i++)
                GaugeGrid.ColumnDefinitions[i].Width = new GridLength(1, GridUnitType.Star);
            GaugeGrid.ColumnSpacing = 24;
            GaugeGrid.RowDefinitions[1].Height = new GridLength(0);
            GaugeGrid.RowDefinitions[2].Height = new GridLength(0);
            GaugeGrid.RowDefinitions[3].Height = new GridLength(0);
            PlaceGauge(CpuGauge, 0, 0);
            PlaceGauge(GpuGauge, 0, 1);
            PlaceGauge(RamGauge, 0, 2);
            PlaceGauge(NetGauge, 0, 3);
            SetGaugeGaps(0);
        }
        else
        {
            HeroGrid.ColumnDefinitions[0].Width = new GridLength(300);
            HeroGrid.ColumnDefinitions[1].Width = new GridLength(1, GridUnitType.Star);
            HeroGrid.ColumnDefinitions[2].Width = new GridLength(290);
            // 宽屏只用第 0 行；空行间距会白白撑高整块，所以关掉。
            HeroGrid.RowSpacing = 0;

            Grid.SetRow(HardwareCard, 0);
            Grid.SetColumn(HardwareCard, 0);
            Grid.SetColumnSpan(HardwareCard, 1);

            Grid.SetRow(StatusCard, 0);
            Grid.SetColumn(StatusCard, 1);
            Grid.SetColumnSpan(StatusCard, 1);

            Grid.SetRow(ResourceCard, 0);
            Grid.SetColumn(ResourceCard, 2);
            Grid.SetColumnSpan(ResourceCard, 1);

            GaugeGrid.ColumnDefinitions[0].Width = new GridLength(1, GridUnitType.Star);
            GaugeGrid.ColumnDefinitions[1].Width = new GridLength(0);
            GaugeGrid.ColumnDefinitions[2].Width = new GridLength(0);
            GaugeGrid.ColumnDefinitions[3].Width = new GridLength(0);
            // 零宽列之间仍会算列间距，宽屏必须清零，否则卡片右侧被白白吃掉宽度。
            GaugeGrid.ColumnSpacing = 0;
            GaugeGrid.RowDefinitions[1].Height = GridLength.Auto;
            GaugeGrid.RowDefinitions[2].Height = GridLength.Auto;
            GaugeGrid.RowDefinitions[3].Height = GridLength.Auto;
            PlaceGauge(CpuGauge, 0, 0);
            PlaceGauge(GpuGauge, 1, 0);
            PlaceGauge(RamGauge, 2, 0);
            PlaceGauge(NetGauge, 3, 0);
            SetGaugeGaps(16);
        }
    }

    /// <summary>宽屏四项上下排列，需要行间留白；窄屏并排时不再加底部外边距。</summary>
    private void SetGaugeGaps(double gap)
    {
        CpuGauge.Margin = new Thickness(0, 0, 0, gap);
        GpuGauge.Margin = new Thickness(0, 0, 0, gap);
        RamGauge.Margin = new Thickness(0, 0, 0, gap);
    }

    private static void PlaceGauge(FrameworkElement gauge, int row, int column)
    {
        Grid.SetRow(gauge, row);
        Grid.SetColumn(gauge, column);
        Grid.SetColumnSpan(gauge, 1);
    }

    /// <summary>窄窗口时底部两张卡改为上下排列。</summary>
    private void ApplyBottom(bool narrow)
    {
        if (narrow)
        {
            Grid.SetRow(SecurityCard, 1);
            Grid.SetColumn(SecurityCard, 0);
            Grid.SetColumnSpan(SecurityCard, 2);
            BottomGrid.RowSpacing = 14;
        }
        else
        {
            Grid.SetRow(SecurityCard, 0);
            Grid.SetColumn(SecurityCard, 1);
            Grid.SetColumnSpan(SecurityCard, 1);
            BottomGrid.RowSpacing = 0;
        }
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        StartLivePulse();
        RefreshUi();
        SubscribeMetrics();
        if (_shell?.LatestMetrics is { } latest) OnMetrics(latest);
        _ = EnsureDataAsync();
    }

    /// <summary>LIVE 呼吸点：只表达采样在运行，不承载信息。</summary>
    private void StartLivePulse()
    {
        if (_pulse is not null || !Motion.Enabled) return;
        try
        {
            var animation = new DoubleAnimation
            {
                From = 1,
                To = 0.3,
                Duration = new Duration(TimeSpan.FromMilliseconds(1100)),
                RepeatBehavior = RepeatBehavior.Forever,
                AutoReverse = true
            };
            Storyboard.SetTarget(animation, LivePulseDot);
            Storyboard.SetTargetProperty(animation, "Opacity");
            _pulse = new Storyboard();
            _pulse.Children.Add(animation);
            _pulse.Begin();
        }
        catch { }
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        UnsubscribeMetrics();
        _pulse?.Stop();
        _pulse = null;
        LivePulseDot.Opacity = 1;
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
            StatusHeadline.Text = Localization.T("正在读取本机状态...");
            StatusDetail.Text = string.IsNullOrWhiteSpace(App.Services.State.StatusText)
                ? Localization.T("正在采集硬件与优化项状态，通常需要几秒。")
                : App.Services.State.StatusText;
            PendingCount.Text = "--";
            StatusRing.Value = 0;
            AppliedText.Text = Localization.T("已生效 -- 项");
            RebootText.Text = Localization.T("重启状态：读取中");
            SecurityText.Text = Localization.T("正在检查...");
            LastApplyText.Text = Localization.T("正在读取优化记录...");
            ApplyRecommendedButton.Content = Localization.T("一键优化推荐项");
            ApplyRecommendedButton.IsEnabled = false;
            PreviewButton.IsEnabled = false;
            _applyMode = false;
            MachineLine.Text = Localization.T("正在读取设备...");
            CpuFactValue.Text = Localization.T("读取中...");
            CpuFactSub.Text = "CPU";
            GpuFactValue.Text = Localization.T("读取中...");
            GpuFactSub.Text = "GPU";
            RamFactValue.Text = Localization.T("读取中...");
            RamFactSub.Text = "RAM";
            DisplayFactValue.Text = Localization.T("读取中...");
            DisplayFactSub.Text = Localization.T("显示输出");
            return;
        }

        var recommended = GetRecommendedIds();
        var s = snap.Summary;
        PendingCount.Text = s.Pending.ToString();
        UpdateCompletion(s.Applied, s.Total, s.NotApplicable, s.Checking);

        StatusHeadline.Text = Localization.T(s.Pending == 0
            ? "整体状态良好"
            : "还有可优化空间");
        StatusDetail.Text = s.Pending == 0
            ? Localization.T("推荐项都已生效，可以放心开游戏。")
            : recommended.Count > 0
                ? Localization.F("其中 {0} 项低风险推荐，点一下就能应用，应用前自动备份。", recommended.Count)
                : Localization.F("共 {0} 项待处理，部分项目需要确认后再决定。", s.Pending);

        // 有低风险推荐才给“一键优化”；否则主按钮转为“查看待优化项”，不留死路。
        _applyMode = recommended.Count > 0;
        PreviewButton.Visibility = _applyMode ? Visibility.Visible : Visibility.Collapsed;
        if (_applyMode)
        {
            ApplyRecommendedButton.Content = Localization.F("一键优化 {0} 项", recommended.Count);
            ApplyRecommendedButton.IsEnabled = true;
            ToolTipService.SetToolTip(ApplyRecommendedButton, Localization.T("应用全部低风险推荐项，应用前自动备份原值"));
        }
        else if (s.Pending > 0)
        {
            ApplyRecommendedButton.Content = Localization.F("查看这 {0} 项", s.Pending);
            ApplyRecommendedButton.IsEnabled = true;
            ToolTipService.SetToolTip(ApplyRecommendedButton, Localization.T("打开优化项列表，逐项确认后再应用"));
        }
        else
        {
            ApplyRecommendedButton.Content = Localization.T("全部已优化");
            ApplyRecommendedButton.IsEnabled = false;
            ToolTipService.SetToolTip(ApplyRecommendedButton, Localization.T("当前没有待优化项"));
        }

        RebootText.Text = Localization.T(snap.PendingReboot?.Pending == true
            ? "重启状态：等待重启后生效"
            : "重启状态：无需重启");
        var issues = snap.Diagnostics.Count(d =>
            d.Group is "安全" or "存储" && d.Level is "Red" or "Yellow");
        SecurityText.Text = issues == 0
            ? Localization.T("未发现需要处理的异常。")
            : Localization.F("有 {0} 项提示，建议查看诊断报告。", issues);

        var machine = string.IsNullOrWhiteSpace(snap.Machine) ? "本机" : snap.Machine;
        MachineLine.Text = Localization.F("{0} · {1}", machine, Localization.T(snap.IsLaptop ? "笔记本" : "台式机"));

        // 左侧只保留四件用户真正关心的事：处理器、显卡、内存、显示器。
        var cpu = snap.Diagnostics.FirstOrDefault(d => d.Group == "系统" && d.Name == "CPU");
        var cpuFact = SplitFact(cpu?.Value, "处理器");
        CpuFactValue.Text = FriendlyName(cpuFact.Main);
        CpuFactSub.Text = cpuFact.Sub;
        ToolTipService.SetToolTip(CpuFactValue, cpuFact.Main);

        var gpu = snap.Gpus
            .Where(g => !g.Basic && !g.Virtual)
            .OrderByDescending(g => g.Dedicated)
            .FirstOrDefault();
        if (gpu is not null && !string.IsNullOrWhiteSpace(gpu.Name))
        {
            GpuFactValue.Text = FriendlyName(gpu.Name);
            ToolTipService.SetToolTip(GpuFactValue, gpu.Name);
            var kind = Localization.T(gpu.Dedicated ? "独立显卡" : "集成显卡");
            var vram = gpu.VRAM is > 0
                ? Localization.F("{0} GB 显存", (gpu.VRAM.Value / 1073741824.0).ToString("0.#"))
                : Localization.T("共享内存");
            GpuFactSub.Text = $"{kind} · {vram}";
        }
        else
        {
            GpuFactValue.Text = Localization.T("未识别到显卡");
            GpuFactSub.Text = "GPU";
        }

        var ram = snap.Diagnostics.FirstOrDefault(d => d.Group == "系统" && d.Name == "内存");
        var ramFact = SplitFact(ram?.Value, "内存");
        RamFactValue.Text = ramFact.Main;
        var freq = snap.Diagnostics.FirstOrDefault(d => d.Group == "系统" && d.Name == "内存频率");
        RamFactSub.Text = freq is null ? ramFact.Sub : MemorySpeed(freq.Value, ramFact.Sub);

        var display = snap.Displays.FirstOrDefault();
        if (display is not null && display.Width > 0 && display.Height > 0)
        {
            DisplayFactValue.Text = $"{display.Width} × {display.Height}";
            var hz = display.Refresh > 0 ? $"{display.Refresh} Hz" : Localization.T("刷新率未知");
            if (display.MaxRefresh > display.Refresh && display.Refresh > 0)
                hz += Localization.F(" · 最高 {0} Hz", display.MaxRefresh);
            DisplayFactSub.Text = hz;
        }
        else
        {
            DisplayFactValue.Text = Localization.T("未检测到显示器");
            DisplayFactSub.Text = Localization.T("显示输出");
        }

        var gpus = snap.Gpus.Where(g => !g.Basic && !g.Virtual)
            .Select(g => g.Name)
            .Where(n => !string.IsNullOrWhiteSpace(n))
            .ToList();
        ToolTipService.SetToolTip(LiveStamp, gpus.Count > 0
            ? Localization.T("显示设备 · ") + string.Join(" + ", gpus)
            : Localization.T("未识别到显示设备"));

        LastApplyText.Text = snap.LastApply is null
            ? Localization.T("还没有优化记录。")
            : Localization.F("{0} 项优化 · {1}", snap.LastApply.Items.Count, ShortTime(snap.LastApply.Time));

        var pendingReboot = snap.PendingReboot;
        if (pendingReboot?.Pending == true)
            PendingBar.Message = Localization.F("检测到系统等待重启：{0}。部分优化需要重启后才会生效。",
                string.Join(Localization.IsEnglish ? ", " : "、", pendingReboot.Reasons));
        InfoBarPresenter.SetOpen(PendingBar, pendingReboot?.Pending == true);
    }

    /// <summary>诊断值形如“32.0 GB | 2 根”，拆成主值与说明两部分。</summary>
    private static (string Main, string Sub) SplitFact(string? value, string fallbackSub)
    {
        var text = (value ?? "").Trim();
        if (text.Length == 0) return (Localization.T("未检测到"), fallbackSub);
        var parts = text.Split('|', 2, StringSplitOptions.TrimEntries);
        return parts.Length == 2 ? (parts[0], parts[1]) : (text, fallbackSub);
    }

    /// <summary>去掉“(R)/(TM)”与显存括注，让硬件名在窄卡片里保持一行。</summary>
    private static string FriendlyName(string? name)
    {
        var text = (name ?? "").Trim();
        if (text.Length == 0) return "";
        text = System.Text.RegularExpressions.Regex.Replace(text, @"\((?:R|TM)\)", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        text = System.Text.RegularExpressions.Regex.Replace(text, @"\s*\([^)]*\d+\s*GB[^)]*\)", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        text = System.Text.RegularExpressions.Regex.Replace(text, @"\s{2,}", " ");
        return text.Trim();
    }

    /// <summary>“配置 8533 MT/s / 标称 8533 MT/s”只保留运行频率。</summary>
    private static string MemorySpeed(string? value, string fallback)
    {
        var match = System.Text.RegularExpressions.Regex.Match(value ?? "", @"配置\s*(\d+)\s*MT/s");
        return match.Success ? $"{match.Groups[1].Value} MT/s" : fallback;
    }

    /// <summary>圆环只表达优化完成度，数字留给待优化项数量。</summary>
    private void UpdateCompletion(int applied, int total, int notApplicable, int checking)
    {
        var effective = Math.Max(0, total - notApplicable);
        var fraction = effective > 0 ? Math.Clamp((double)applied / effective, 0d, 1d) : 0d;
        StatusRing.Value = fraction * 100;

        var line = effective > 0
            ? Localization.F("已生效 {0} / {1} 项", applied, effective)
            : Localization.T("已生效 -- 项");
        if (checking > 0) line += " · " + Localization.F("{0} 项检测中", checking);
        AppliedText.Text = line;
        ToolTipService.SetToolTip(StatusRing, effective > 0
            ? Localization.F("优化完成度 {0}", fraction.ToString("P0"))
            : Localization.T("优化完成度：正在读取本机状态"));
    }

    private void OnMetrics(LiveMetrics m)
    {
        _cpuRoll.To(m.Cpu);
        CpuBar.Value = m.Cpu;

        var gpuAvailable = App.Services.Metrics.GpuAvailable;
        if (gpuAvailable) _gpuRoll.To(m.Gpu);
        else _gpuRoll.SetLiteral("—");
        if (_gpuWasAvailable != gpuAvailable)
        {
            _gpuWasAvailable = gpuAvailable;
            GpuRingLabel.Text = Localization.T(gpuAvailable ? "显卡 3D 负载" : "GPU 数据不可用");
        }
        GpuBar.Value = gpuAvailable ? m.Gpu : 0;

        _ramRoll.To(m.RamPercent, "0");
        RamBar.Value = m.RamPercent;
        RamHint.Text = Localization.F("{0} / {1} GB 已用", m.RamUsedGb.ToString("0.0"), m.RamTotalGb.ToString("0.0"));

        NetValue.Text = "↓ " + FormatRate(m.NetDownKbps);
        NetHint.Text = "↑ " + FormatRate(m.NetUpKbps);
        var stamp = Localization.F("更新于 {0}", DateTime.Now.ToString("HH:mm:ss"));
        if (stamp != _lastStamp)
        {
            _lastStamp = stamp;
            LiveStamp.Text = stamp;
        }
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
        // 没有低风险推荐时，主按钮是“查看待优化项”，直接跳到列表逐项确认。
        if (!_applyMode)
        {
            if (App.MainWindow is MainWindow main) main.NavigateTo("items");
            return;
        }
        var ids = GetRecommendedIds();
        if (ids.Count == 0)
        {
            ShowAction("无需优化", "当前没有处于待优化状态的低风险项目。", InfoBarSeverity.Success);
            return;
        }
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = Localization.T("应用推荐优化"),
            Content = new TextBlock
            {
                Text = Localization.F("将应用 {0} 项低风险优化。\n\n应用前会自动生成 JSON 原值备份与 .reg 快照，可在「备份还原」中撤销。", ids.Count),
                TextWrapping = TextWrapping.Wrap,
                LineHeight = 22
            },
            PrimaryButtonText = Localization.F("应用 {0} 项", ids.Count),
            CloseButtonText = Localization.T("取消"),
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
                var msg = Localization.F("成功 {0} 项 · 失败 {1} 项", result.Ok, result.Fail);
                if (!string.IsNullOrWhiteSpace(result.Backup)) msg += "\n" + Localization.F("备份：{0}", result.Backup);
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
                Text = Localization.T("所选项目均已处于推荐值，无需变更。"),
                TextWrapping = TextWrapping.Wrap
            });
        }
        else
        {
            panel.Children.Add(new TextBlock
            {
                Text = Localization.F("共 {0} 项将发生变更（预览不会写入系统）：", result.Preview.Count),
                TextWrapping = TextWrapping.Wrap,
                FontWeight = Microsoft.UI.Text.FontWeights.SemiBold
            });
            foreach (var item in result.Preview)
            {
                var row = new StackPanel { Spacing = 2, Margin = new Thickness(0, 2, 0, 6) };
                row.Children.Add(new TextBlock { Text = item.Name, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold });
                row.Children.Add(new TextBlock
                {
                    Text = Localization.F(item.NeedsReboot
                            ? "当前：{0}  →  目标：{1}  · 需重启"
                            : "当前：{0}  →  目标：{1}", item.Current, item.Target),
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
            Title = Localization.T("变更预览"),
            Content = new ScrollViewer
            {
                Content = panel,
                MaxHeight = 460,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            },
            CloseButtonText = Localization.T("关闭")
        };
        await dialog.ShowAsync();
    }

    private void ShowAction(string title, string message, InfoBarSeverity severity)
    {
        ActionInfo.Title = Localization.T(title);
        ActionInfo.Message = Localization.T(message);
        ActionInfo.Severity = severity;
        ActionInfo.Visibility = Visibility.Visible;
        ActionInfo.IsOpen = true;
    }

    /// <summary>关闭后彻底折叠，避免空 InfoBar 在首屏占一条高度。</summary>
    private void ActionInfo_Closed(InfoBar sender, InfoBarClosedEventArgs args)
        => ActionInfo.Visibility = Visibility.Collapsed;

    private void OpenBackup_Click(object sender, RoutedEventArgs e)
    {
        if (App.MainWindow is MainWindow main) main.NavigateTo("backup");
    }

    private void OpenDiagnostics_Click(object sender, RoutedEventArgs e)
    {
        if (App.MainWindow is MainWindow main) main.NavigateTo("diagnostics");
    }

    public void OnThemeChanged()
    {
        // 概览全部使用主题资源绑定；切主题时不需要重建任何列表。
        RefreshUi();
    }

    public void OnLanguageChanged() => RefreshUi();
}
