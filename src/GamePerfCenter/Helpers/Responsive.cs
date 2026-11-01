using Microsoft.UI.Xaml;

namespace GamePerfCenter.Helpers;

/// <summary>
/// 按页面实际宽度切换布局。WinUI 的 AdaptiveTrigger 依赖窗口上下文，
/// 在部分宿主下不会触发，这里直接用 SizeChanged 保证窄窗口行为可预期。
/// </summary>
public static class Responsive
{
    public static void Watch(FrameworkElement page, double breakpoint, Action<bool> apply)
    {
        bool? last = null;

        void Update()
        {
            if (page.ActualWidth <= 0) return;
            var narrow = page.ActualWidth < breakpoint;
            if (last == narrow) return;
            last = narrow;
            apply(narrow);
        }

        page.Loaded += (_, _) => Update();
        page.SizeChanged += (_, e) =>
        {
            if (e.NewSize.Width > 0) Update();
        };
    }
}
