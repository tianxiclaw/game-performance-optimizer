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
    private void InspectorToggle_Click(object sender, RoutedEventArgs e) => SetInspectorOpen(!_inspectorOpen);

    private void InspectorClose_Click(object sender, RoutedEventArgs e) => SetInspectorOpen(false);

    private void SetInspectorOpen(bool open)
    {
        if (_inspectorOpen == open) return;
        _inspectorOpen = open;
        InspectorToggleButton.Background = open
            ? ThemeResources.Get("AccentSoftBrush")
            : new SolidColorBrush(Colors.Transparent);
        InspectorToggleButton.Foreground = ThemeResources.Get(open ? "AccentBrush" : "SubTextBrush");
        AutomationProperties.SetName(InspectorToggleButton, open ? "收起控制台" : "展开控制台");
        ToolTipService.SetToolTip(InspectorToggleButton, open ? "收起控制台" : "展开控制台");

        if (open)
        {
            InspectorPanel.Visibility = Visibility.Visible;
            InspectorSlide.X = 24;
            InspectorPanel.Opacity = 0;
            AnimateInspector(0, 1);
        }
        else
        {
            AnimateInspector(24, 0, collapse: true);
        }
    }

    private void AnimateInspector(double x, double opacity, bool collapse = false)
    {
        if (!Motion.Enabled)
        {
            InspectorSlide.X = x;
            InspectorPanel.Opacity = opacity;
            if (collapse) InspectorPanel.Visibility = Visibility.Collapsed;
            return;
        }
        var storyboard = new Storyboard();
        var slide = new DoubleAnimation
        {
            To = x,
            Duration = new Duration(TimeSpan.FromMilliseconds(180)),
            EnableDependentAnimation = true,
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
        };
        Storyboard.SetTarget(slide, InspectorSlide);
        Storyboard.SetTargetProperty(slide, "X");
        var fade = new DoubleAnimation
        {
            To = opacity,
            Duration = new Duration(TimeSpan.FromMilliseconds(150)),
            EnableDependentAnimation = true
        };
        Storyboard.SetTarget(fade, InspectorPanel);
        Storyboard.SetTargetProperty(fade, "Opacity");
        storyboard.Children.Add(slide);
        storyboard.Children.Add(fade);
        if (collapse)
        {
            storyboard.Completed += (_, _) =>
            {
                if (InspectorPanel.Opacity <= 0.01) InspectorPanel.Visibility = Visibility.Collapsed;
            };
        }
        storyboard.Begin();
    }

    private void InitPendingTip()
    {
        // 离开按钮后留 160ms 缓冲：鼠标向下移进清单时不会被立刻收起。
        _pendingHideTimer = _dispatcher.CreateTimer();
        _pendingHideTimer.Interval = TimeSpan.FromMilliseconds(160);
        _pendingHideTimer.IsRepeating = false;
        _pendingHideTimer.Tick += (_, _) => HidePendingTip();

        PendingButton.AddHandler(UIElement.PointerEnteredEvent,
            new PointerEventHandler((_, _) =>
            {
                _pendingHideTimer?.Stop();
                ShowPendingTip();
            }), handledEventsToo: true);
        PendingButton.AddHandler(UIElement.PointerExitedEvent,
            new PointerEventHandler((_, _) => SchedulePendingHide()), handledEventsToo: true);
        PendingTipCard.PointerEntered += (_, _) => _pendingHideTimer?.Stop();
        PendingTipCard.PointerExited += (_, _) => SchedulePendingHide();
    }

    private void SchedulePendingHide()
    {
        _pendingHideTimer?.Stop();
        _pendingHideTimer?.Start();
    }

    private void ShowPendingTip()
    {
        if (PendingButton.Visibility != Visibility.Visible) return;
        if (RootGrid.ActualWidth <= 0) return;

        _pendingHideTimer?.Stop();

        PendingTipCard.Visibility = Visibility.Visible;
        PendingTipCard.UpdateLayout();
        try
        {
            var origin = PendingButton.TransformToVisual(RootGrid)
                .TransformPoint(new Windows.Foundation.Point(0, 0));
            var cardWidth = PendingTipCard.ActualWidth > 0 ? PendingTipCard.ActualWidth : 200;
            // 右边缘对齐感叹号，再夹在窗口左右各 12px 的安全区内。
            var left = origin.X + PendingButton.ActualWidth - cardWidth;
            left = Math.Max(12, Math.Min(left, RootGrid.ActualWidth - cardWidth - 12));
            // 悬浮卡落在顶栏下沿之外，不压住顶栏自身的分隔线。
            var top = Math.Max(origin.Y + PendingButton.ActualHeight + 6,
                TitleBarDrag.ActualHeight + 6);
            PendingTipCard.Margin = new Thickness(left, top, 0, 0);
        }
        catch
        {
            // 布局尚未完成时按默认位置显示，不影响功能。
        }
    }

    private void HidePendingTip()
    {
        _pendingHideTimer?.Stop();
        PendingTipCard.Visibility = Visibility.Collapsed;
    }

    internal void QaShowPendingTip() => ShowPendingTip();

    private void DrawerRefresh_Click(object sender, RoutedEventArgs e) => RefreshFromTray();

    private void DrawerDataDir_Click(object sender, RoutedEventArgs e) => OpenDirectory(AppPaths.DataDir);

    private void DrawerBackupDir_Click(object sender, RoutedEventArgs e) => OpenDirectory(AppPaths.BackupDir);
}
