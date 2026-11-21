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
    private void RegisterIconButtons(IEnumerable<Button> buttons)
    {
        foreach (var button in buttons)
        {
            if (!_iconButtons.Add(button)) continue;
            button.AddHandler(UIElement.PointerEnteredEvent,
                new PointerEventHandler(IconButton_PointerEntered), handledEventsToo: true);
            button.AddHandler(UIElement.PointerExitedEvent,
                new PointerEventHandler(IconButton_PointerExited), handledEventsToo: true);
            button.AddHandler(UIElement.PointerPressedEvent,
                new PointerEventHandler(IconButton_PointerPressed), handledEventsToo: true);
            button.AddHandler(UIElement.PointerReleasedEvent,
                new PointerEventHandler(IconButton_PointerReleased), handledEventsToo: true);
            button.AddHandler(UIElement.PointerCanceledEvent,
                new PointerEventHandler(IconButton_PointerCanceled), handledEventsToo: true);
            button.AddHandler(UIElement.PointerCaptureLostEvent,
                new PointerEventHandler(IconButton_PointerCanceled), handledEventsToo: true);
        }
    }

    private void SetIconHover(Button button, bool hover)
    {
        if (hover)
        {
            if (!_hoveredIcons.Add(button)) return;
            var scale = IconScaleFor(button);
            if (!_motionTraceLogged)
            {
                _motionTraceLogged = true;
                AppLog.Write($"动效生效: 图标 1.00 -> {scale:0.00}，Windows 动画={(Motion.SystemEnabled ? "开" : "关")}");
            }
            Motion.IconHover(IconTarget(button), true, scale);
            return;
        }

        if (!_hoveredIcons.Remove(button)) return;
        if (!_motionResetLogged)
        {
            _motionResetLogged = true;
            AppLog.Write("动效复位: 图标 -> 1.00");
        }
        Motion.IconHover(IconTarget(button), false);
    }

    private void IconButton_PointerEntered(object sender, PointerRoutedEventArgs e)
    {
        if (sender is Button button) SetIconHover(button, true);
    }

    private void IconButton_PointerExited(object sender, PointerRoutedEventArgs e)
    {
        if (sender is Button button) SetIconHover(button, false);
    }

    private void IconButton_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (sender is Button button) Motion.IconPress(IconTarget(button), true, IconScaleFor(button));
    }

    private void IconButton_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        if (sender is Button button) Motion.IconPress(IconTarget(button), false, IconScaleFor(button));
    }

    private void IconButton_PointerCanceled(object sender, PointerRoutedEventArgs e)
    {
        if (sender is Button button) SetIconHover(button, button.IsPointerOver);
    }

    private void RootGrid_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (_hoveredIcons.Count == 0) return;
        Button? hit = null;
        try
        {
            var point = e.GetCurrentPoint(RootGrid).Position;
            foreach (var element in VisualTreeHelper.FindElementsInHostCoordinates(point, RootGrid))
            {
                if (element is Button button && _iconButtons.Contains(button))
                {
                    hit = button;
                    break;
                }
            }
        }
        catch { }

        foreach (var button in _hoveredIcons.ToArray())
        {
            if (!ReferenceEquals(button, hit)) SetIconHover(button, false);
        }
        if (hit is not null) SetIconHover(hit, true);
    }

    private void RootGrid_PointerExited(object sender, PointerRoutedEventArgs e)
    {
        ResetIconScales();
        HideDockHint();
    }

    private void ResetIconScales()
    {
        _hoveredIcons.Clear();
        foreach (var button in _iconButtons)
        {
            Motion.IconHover(IconTarget(button), false);
        }
    }

    private void DockButton_PointerEntered(object sender, PointerRoutedEventArgs e)
    {
        if (sender is not Button button) return;
        var label = Localization.T(DockLabel(button));
        if (string.IsNullOrEmpty(label)) return;

        DockHintText.Text = label;
        DockHintHost.Visibility = Visibility.Visible;
        // 先让提示按内容完成一次布局，才能拿到真实宽度做居中；此前用 Measure 得到的是脏值。
        DockHintHost.UpdateLayout();
        var hintWidth = DockHintHost.ActualWidth > 0 ? DockHintHost.ActualWidth : 72;
        var origin = button.TransformToVisual(StatusBar)
            .TransformPoint(new Windows.Foundation.Point(0, 0));
        var x = origin.X + (button.ActualWidth - hintWidth) / 2;
        x = Math.Clamp(x, 8, Math.Max(8, StatusBar.ActualWidth - hintWidth - 8));
        DockHintHost.Margin = new Thickness(x, 0, 0, 0);
        AnimateOpacity(DockHintHost, 1, 120);
    }

    private void DockButton_PointerExited(object sender, PointerRoutedEventArgs e) => HideDockHint();

    private void HideDockHint()
    {
        if (DockHintHost.Visibility != Visibility.Visible) return;
        AnimateOpacity(DockHintHost, 0, 100, collapse: true);
    }

    private static void AnimateOpacity(UIElement element, double to, int milliseconds, bool collapse = false)
    {
        if (!Motion.Enabled)
        {
            element.Opacity = to;
            if (collapse) element.Visibility = Visibility.Collapsed;
            return;
        }
        var storyboard = new Storyboard();
        var animation = new DoubleAnimation
        {
            To = to,
            Duration = new Duration(TimeSpan.FromMilliseconds(milliseconds)),
            EnableDependentAnimation = true
        };
        Storyboard.SetTarget(animation, element);
        Storyboard.SetTargetProperty(animation, "Opacity");
        storyboard.Children.Add(animation);
        if (collapse)
        {
            storyboard.Completed += (_, _) =>
            {
                if (element.Opacity <= 0.01) element.Visibility = Visibility.Collapsed;
            };
        }
        storyboard.Begin();
    }
}
