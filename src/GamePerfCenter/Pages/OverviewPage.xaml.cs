using System.Diagnostics;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using GamePerfCenter.Helpers;

namespace GamePerfCenter.Pages;

public sealed partial class OverviewPage : Page, IThemeAware
{
    private readonly DispatcherQueueTimer _timer;
    private readonly LiveMetricsService _metrics = new();
    private bool _sampling;

    public OverviewPage()
    {
        InitializeComponent();
        NavigationCacheMode = Microsoft.UI.Xaml.Navigation.NavigationCacheMode.Required;
        _timer = DispatcherQueue.CreateTimer();
        _timer.Interval = TimeSpan.FromSeconds(2);
        _timer.Tick += async (_, _) => await SampleAsync();
        App.Services.State.Changed += OnStateChanged;
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        Responsive.Watch(this, 880, ApplyWidth);
    }

    private void ApplyWidth(bool narrow)
    {
        if (narrow)
        {
            Grid.SetColumnSpan(StatusMain, 3);
            StatusDivider.Visibility = Visibility.Collapsed;
            Grid.SetColumn(StatusIdentity, 0);
            Grid.SetColumnSpan(StatusIdentity, 3);
            Grid.SetRow(StatusIdentity, 2);
            StatusIdentity.Margin = new Thickness(0, 16, 0, 0);
            StatusIdentity.MinWidth = 0;

            Grid.SetColumnSpan(HardwareCard, 2);
            Grid.SetColumnSpan(SecurityCard, 2);
            Grid.SetColumn(SecurityCard, 0);
            Grid.SetRow(SecurityCard, 1);
            SecurityCard.Margin = new Thickness(0, 16, 0, 0);
        }
        else
        {
            Grid.SetColumnSpan(StatusMain, 1);
            StatusDivider.Visibility = Visibility.Visible;
            Grid.SetColumn(StatusIdentity, 2);
            Grid.SetColumnSpan(StatusIdentity, 1);
            Grid.SetRow(StatusIdentity, 0);
            StatusIdentity.Margin = new Thickness(0);
            StatusIdentity.MinWidth = 220;

            Grid.SetColumnSpan(HardwareCard, 1);
            Grid.SetColumnSpan(SecurityCard, 1);
            Grid.SetColumn(SecurityCard, 1);
            Grid.SetRow(SecurityCard, 0);
            SecurityCard.Margin = new Thickness(0);
        }
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        RefreshUi();
        _timer.Start();
        _ = EnsureDataAsync();
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        _timer.Stop();
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
            AppliedText.Text = "已生效 -- 项";
            return;
        }

        var recommended = GetRecommendedIds();
        var s = snap.Summary;
        PendingCount.Text = s.Pending.ToString();
        AppliedText.Text = $"已生效 {s.Applied} / {s.Total} 项";
        StatusHeadline.Text = s.Pending == 0 ? "当前没有待优化项" : "还有可应用的优化项";
        StatusDetail.Text = s.Pending == 0
            ? "推荐项均已生效。可以打开优化项手动复查，或预览当前配置。"
            : $"{recommended.Count} 项低风险推荐项可直接应用；应用前自动备份原值，可在「备份还原」中撤销。";
        ApplyRecommendedButton.Content = recommended.Count > 0 ? $"应用 {recommended.Count} 项" : "暂无推荐项";
        ApplyRecommendedButton.IsEnabled = recommended.Count > 0;

        var machine = string.IsNullOrWhiteSpace(snap.Machine) ? "本机" : snap.Machine;
        var gpus = snap.Gpus.Where(g => !g.Basic && !g.Virtual).Select(g => g.Name).Where(n => !string.IsNullOrWhiteSpace(n)).ToList();
        var os = snap.Diagnostics.FirstOrDefault(d => d.Name == "操作系统")?.Value;
        IdentityDevice.Text = $"{machine} · {(snap.IsLaptop ? "笔记本" : "台式机")}";
        IdentityGpu.Text = gpus.Count > 0 ? string.Join(" + ", gpus) : "未识别到显卡";
        IdentityOs.Text = string.IsNullOrWhiteSpace(os) ? "未检测到" : os;

        PendingBar.IsOpen = snap.PendingReboot?.Pending == true;
        if (snap.PendingReboot?.Pending == true)
            PendingBar.Message = "检测到系统等待重启：" + string.Join("、", snap.PendingReboot.Reasons) +
                                 "。部分优化需要重启后才会生效。";

        HardwareList.ItemsSource = snap.Diagnostics
            .Where(d => d.Group is "系统" or "显卡")
            .Take(9)
            .ToList();
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

    private async Task SampleAsync()
    {
        if (_sampling) return;
        _sampling = true;
        try
        {
            var m = await Task.Run(() => _metrics.Sample());
            CpuValue.Text = m.Cpu.ToString("0");
            CpuBar.Value = m.Cpu;
            GpuValue.Text = _metrics.GpuAvailable ? m.Gpu.ToString("0") : "--";
            GpuBar.Value = m.Gpu;
            GpuHint.Text = _metrics.GpuAvailable ? "3D 引擎负载" : "当前驱动未提供 GPU 计数器";
            RamValue.Text = m.RamPercent.ToString("0");
            RamBar.Value = m.RamPercent;
            RamHint.Text = $"{m.RamUsedGb:0.0} / {m.RamTotalGb:0.0} GB";
            NetValue.Text = m.NetDownKbps >= 1024 ? (m.NetDownKbps / 1024).ToString("0.0") : m.NetDownKbps.ToString("0");
            NetBar.Value = Math.Min(1000, m.NetDownKbps);
            NetHint.Text = $"下行 {FormatRate(m.NetDownKbps)} · 上行 {FormatRate(m.NetUpKbps)}";
        }
        catch (Exception ex)
        {
            AppLog.Write("实时采样失败: " + ex.Message);
        }
        finally { _sampling = false; }
    }

    private static string FormatRate(double kbps)
    {
        if (kbps >= 1024) return $"{kbps / 1024:0.0} MB/s";
        return $"{kbps:0} KB/s";
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

    public void OnThemeChanged()
    {
        if (App.Services.State.Snapshot is { } snap)
        {
            HardwareList.ItemsSource = null;
            DiagList.ItemsSource = null;
            HardwareList.ItemsSource = snap.Diagnostics.Where(d => d.Group is "系统" or "显卡").Take(9).ToList();
            DiagList.ItemsSource = snap.Diagnostics.Where(d => d.Group is "安全" or "存储").Take(8).ToList();
        }
    }
}
