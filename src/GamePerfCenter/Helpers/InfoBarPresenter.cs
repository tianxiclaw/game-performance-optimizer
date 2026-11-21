using System.Runtime.CompilerServices;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Helpers;

/// <summary>
/// InfoBar 只切 <see cref="InfoBar.IsOpen"/> 时，父级 Auto 行可能保留旧的 0 高度，
/// 提示条会以完整高度压在页面标题上。这里统一先切可见性迫使父级重新测量。
/// </summary>
internal static class InfoBarPresenter
{
    private static readonly ConditionalWeakTable<InfoBar, object> Subscribed = new();

    public static void Show(InfoBar bar, string title, string message, InfoBarSeverity severity)
    {
        bar.Title = title;
        bar.Message = message;
        bar.Severity = severity;
        SetOpen(bar, true);
    }

    public static void SetOpen(InfoBar bar, bool open)
    {
        if (!open)
        {
            bar.IsOpen = false;
            bar.Visibility = Visibility.Collapsed;
            return;
        }

        CollapseOnClose(bar);
        if (bar.Visibility != Visibility.Visible) bar.Visibility = Visibility.Visible;
        bar.IsOpen = true;
        bar.InvalidateMeasure();
        if (bar.Parent is UIElement parent) parent.InvalidateMeasure();
    }

    private static void CollapseOnClose(InfoBar bar)
    {
        if (!Subscribed.TryAdd(bar, new object())) return;
        bar.Closed += (sender, _) =>
        {
            if (sender is InfoBar closed) closed.Visibility = Visibility.Collapsed;
        };
    }
}