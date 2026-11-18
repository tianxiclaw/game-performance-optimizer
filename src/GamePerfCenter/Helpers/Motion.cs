using System.Diagnostics;
using Microsoft.UI.Composition;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Windows.UI.ViewManagement;
using System.Numerics;

namespace GamePerfCenter.Helpers;

/// <summary>
/// 动效统一入口：系统关闭动画时全部降级为直接切换。
/// 工具类界面只做状态表达，不做入场编排。
/// </summary>
public static class Motion
{
    public static bool Enabled { get; } = Detect();

    private static bool Detect()
    {
        try { return new UISettings().AnimationsEnabled; }
        catch { return true; }
    }

    /// <summary>透明度 + 垂直位移的入场，200ms 以内，只用于容器出现。</summary>
    public static void FadeSlideIn(UIElement element, double fromY = 8, int milliseconds = 190)
    {
        if (!Enabled || element is null) return;
        try
        {
            var visual = ElementCompositionPreview.GetElementVisual(element);
            var compositor = visual.Compositor;
            visual.Opacity = 0f;
            visual.Offset = new Vector3(0, (float)fromY, 0);

            var ease = compositor.CreateCubicBezierEasingFunction(new Vector2(0.2f, 0f), new Vector2(0f, 1f));
            var duration = TimeSpan.FromMilliseconds(milliseconds);

            var fade = compositor.CreateScalarKeyFrameAnimation();
            fade.InsertKeyFrame(0f, 0f);
            fade.InsertKeyFrame(1f, 1f, ease);
            fade.Duration = duration;

            var slide = compositor.CreateVector3KeyFrameAnimation();
            slide.InsertKeyFrame(0f, new Vector3(0, (float)fromY, 0));
            slide.InsertKeyFrame(1f, Vector3.Zero, ease);
            slide.Duration = duration;

            var batch = compositor.CreateScopedBatch(CompositionBatchTypes.Animation);
            visual.StartAnimation("Opacity", fade);
            visual.StartAnimation("Offset", slide);
            batch.Completed += (_, _) =>
            {
                try
                {
                    visual.Offset = Vector3.Zero;
                    visual.Opacity = 1f;
                }
                catch { }
            };
            batch.End();
        }
        catch { }
    }
}

/// <summary>
/// 数值滚动：把上一位显示值平滑过渡到新值，300ms 内完成。
/// 同一个 TextBlock 复用同一实例，避免定时器叠加。
/// </summary>
public sealed class NumberRoll
{
    private const int DurationMs = 300;
    private readonly TextBlock _target;
    private readonly DispatcherQueueTimer _timer;
    private double _from;
    private double _to;
    private string _format = "0";
    private string _suffix = "";
    private long _started;

    public NumberRoll(TextBlock target)
    {
        _target = target;
        _timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        _timer.Interval = TimeSpan.FromMilliseconds(16);
        _timer.IsRepeating = true;
        _timer.Tick += (_, _) => Step();
    }

    public void To(double value, string format = "0", string suffix = "")
    {
        if (!Motion.Enabled)
        {
            _from = _to = value;
            _target.Text = value.ToString(format) + suffix;
            return;
        }

        _from = _to;
        _to = value;
        _format = format;
        _suffix = suffix;
        _started = Stopwatch.GetTimestamp();
        if (!_timer.IsRunning) _timer.Start();
    }

    /// <summary>非数值状态（例如“—”），直接改写文本并让下次滚动从 0 开始。</summary>
    public void SetLiteral(string text)
    {
        _timer.Stop();
        _from = _to = 0;
        _target.Text = text;
    }

    private void Step()
    {
        var elapsed = (Stopwatch.GetTimestamp() - _started) * 1000.0 / Stopwatch.Frequency;
        var t = Math.Clamp(elapsed / DurationMs, 0d, 1d);
        var eased = 1 - Math.Pow(1 - t, 3);
        var current = _from + (_to - _from) * eased;
        _target.Text = current.ToString(_format) + _suffix;

        if (t < 1) return;
        _timer.Stop();
        _from = _to;
        _target.Text = _to.ToString(_format) + _suffix;
    }
}
