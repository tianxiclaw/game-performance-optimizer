using System.Diagnostics;
using System.Numerics;
using System.Text.Json;
using Microsoft.UI;
using Microsoft.UI.Composition;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Navigation;
using Windows.Graphics;
using Windows.System;
using GamePerfCenter.Controls;
using GamePerfCenter.Helpers;
using GamePerfCenter.Models;
using GamePerfCenter.Pages;
using GamePerfCenter.Services;
using Rectangle = Microsoft.UI.Xaml.Shapes.Rectangle;
using Ellipse = Microsoft.UI.Xaml.Shapes.Ellipse;

namespace GamePerfCenter;

public sealed partial class MainWindow
{
    private void OnStatusChanged()
    {
        _dispatcher.TryEnqueue(() =>
        {
            // 状态文案可能带参数，交给 AppState 按当前语言重新渲染，避免缓存住英文结果。
            _statusRender = () => App.Services.State.StatusText;
            StatusText.Text = _statusRender();
            StatusRing.IsActive = App.Services.State.IsBusy;
        });
    }

    private void OnStateChanged()
    {
        _dispatcher.TryEnqueue(() =>
        {
            StatusRing.IsActive = App.Services.State.IsBusy;
            UpdateShellInfo();
        });
    }

    private async Task SampleMetricsAsync()
    {
        if (_metricsBusy) return;
        _metricsBusy = true;
        try
        {
            var m = await Task.Run(() => App.Services.Metrics.Sample());
            LatestMetrics = m;

            // 侧栏只是常驻摘要，1 秒一次足够；概览页仍按 250ms 拿实时数据。
            if (++_metricsTick % 4 == 1)
            {
                PaneCpuValue.Text = m.Cpu.ToString("0") + "%";
                PaneCpuBar.Value = m.Cpu;
                var gpuAvailable = App.Services.Metrics.GpuAvailable;
                PaneGpuValue.Text = gpuAvailable ? m.Gpu.ToString("0") + "%" : "--";
                PaneGpuBar.Value = gpuAvailable ? m.Gpu : 0;
                PaneRamValue.Text = m.RamPercent.ToString("0") + "%";
                PaneRamBar.Value = m.RamPercent;
            }

            MetricsUpdated?.Invoke(m);
        }
        catch (Exception ex)
        {
            AppLog.Write("实时采样失败: " + ex.Message);
        }
        finally
        {
            _metricsBusy = false;
        }
    }

    private void UpdateShellInfo()
    {
        var snap = App.Services.State.Snapshot;
        if (snap is not null && !string.IsNullOrWhiteSpace(snap.Machine))
        {
            PaneDeviceName.Text = snap.Machine;
            ToolTipService.SetToolTip(PaneDeviceName, snap.Machine);
        }

        var pending = snap?.Summary.Pending ?? 0;
        UpdatePendingTip(snap);
        PendingButton.Visibility = pending > 0 && !_narrowTitleBar
            ? Visibility.Visible
            : Visibility.Collapsed;
        PendingButton.IsEnabled = pending > 0;
        AutomationProperties.SetName(PendingButton, Localization.F("待优化项：{0}", pending));
        DrawerPendingText.Text = pending > 0
            ? (Localization.IsEnglish ? $"{pending} to apply" : $"{pending} 项待应用")
            : Localization.T("暂无待应用项");
        DrawerPendingButton.Visibility = pending > 0 ? Visibility.Visible : Visibility.Collapsed;

        var kind = snap is null ? "" : Localization.T(snap.IsLaptop ? "笔记本" : "台式机");
        var engine = Localization.T(App.Services.Engine.IsRunning ? "引擎已连接" : "引擎未连接");
        PaneEngineText.Text = string.IsNullOrEmpty(kind) ? engine : $"{kind} · {engine}";
    }

    private void UpdatePendingTip(SnapshotInfo? snap)
    {
        var total = snap?.Summary.Pending ?? 0;
        var names = snap?.Items
            .Where(i => i.Status == "no")
            .Select(i => string.IsNullOrWhiteSpace(i.Name) ? i.Id : i.Name)
            .Where(n => !string.IsNullOrWhiteSpace(n))
            .Take(6)
            .ToList() ?? new List<string?>();

        PendingTipTitle.Foreground = ThemeResources.Get("WarnBrush");
        PendingTipHint.Foreground = ThemeResources.Get("SubTextBrush");
        PendingTipTitle.Text = Localization.F("还有 {0} 项待优化", total);
        PendingTipHint.Text = Localization.F("单击查看全部 {0} 项", total);
        if (total <= 0) HidePendingTip();

        PendingTipList.Children.Clear();
        var dot = ThemeResources.Get("WarnBrush");
        var text = ThemeResources.Get("TextBrush");
        foreach (var name in names)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
            row.Children.Add(new Ellipse
            {
                Width = 4,
                Height = 4,
                Fill = dot,
                VerticalAlignment = VerticalAlignment.Center
            });
            row.Children.Add(new TextBlock
            {
                Text = name,
                FontSize = 12,
                Foreground = text,
                MaxWidth = 260,
                TextTrimming = TextTrimming.CharacterEllipsis,
                TextWrapping = TextWrapping.NoWrap
            });
            PendingTipList.Children.Add(row);
        }

        if (names.Count > 0 && total > names.Count)
        {
            PendingTipList.Children.Add(new TextBlock
            {
                Text = Localization.F("以及另外 {0} 项", total - names.Count),
                FontSize = 11.5,
                Foreground = ThemeResources.Get("SubTextBrush"),
                Margin = new Thickness(10, 2, 0, 0)
            });
        }
    }

    private void UpdateEngineBadge(bool connected)
    {
        try
        {
            var brush = ThemeResources.Get(connected ? "OkBrush" : "WarnBrush");
            PaneEngineDot.Fill = brush;
            StatusEngineDot.Fill = brush;
        }
        catch { }
    }

    private void PendingButton_Click(object sender, RoutedEventArgs e)
    {
        HidePendingTip();
        NavigateTo("items");
    }

    private void SetStatus(string text, bool busy)
    {
        _statusRender = () => Localization.T(text);
        StatusText.Text = _statusRender();
        StatusRing.IsActive = busy;
    }

    private void SetEngineState(string zh)
    {
        _lastEngineStateZh = zh;
        EngineStateText.Text = Localization.T(zh);
    }

    public void ShowError(string title, string message)
    {
        _lastInfoTitle = title;
        _lastInfoMessage = message;
        InfoBarPresenter.Show(EngineInfoBar,
            Localization.T(title), Localization.T(message), InfoBarSeverity.Error);
    }

    public void ShowInfo(string title, string message, InfoBarSeverity severity = InfoBarSeverity.Success)
    {
        _lastInfoTitle = title;
        _lastInfoMessage = message;
        InfoBarPresenter.Show(EngineInfoBar,
            Localization.T(title), Localization.T(message), severity);
    }
}
