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
    private void OnAppWindowClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (!App.Services.Settings.MinimizeToTray) return;
        args.Cancel = true;
        try
        {
            AppWindow.Hide();
            _tray?.Show();
            PauseMetrics();
        }
        catch (Exception ex)
        {
            AppLog.Write("最小化到托盘失败: " + ex.Message);
        }
    }

    private void RestoreFromTray()
    {
        try
        {
            _tray?.Hide();
            AppWindow.Show();
            Activate();
            ResumeMetrics();
        }
        catch (Exception ex)
        {
            AppLog.Write("从托盘恢复失败: " + ex.Message);
        }
    }

    private void PauseMetrics()
    {
        if (_metricsPaused) return;
        _metricsPaused = true;
        _metricsTimer.Stop();
    }

    private void ResumeMetrics()
    {
        if (!_metricsPaused) return;
        _metricsPaused = false;
        _metricsTick = 0;
        _metricsTimer.Start();
        _ = SampleMetricsAsync();
    }

    private void OpenFromTray(string tag)
    {
        RestoreFromTray();
        NavigateTo(tag);
    }

    private async void RefreshFromTray()
    {
        RestoreFromTray();
        try
        {
            await App.Services.State.EnsureSnapshotAsync(force: true);
            ShowInfo("状态已刷新", "优化项状态与硬件快照已更新。", InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowError("刷新失败", ex.Message);
        }
    }

    private async void ExitFromTray()
    {
        try { _tray?.Dispose(); } catch { }
        try { await App.Services.Engine.DisposeAsync(); } catch { }
        Environment.Exit(0);
    }

    private async void OnClosed(object sender, WindowEventArgs args)
    {
        try { _tray?.Dispose(); } catch { }
        try { await App.Services.Engine.DisposeAsync(); } catch { }
    }
}
