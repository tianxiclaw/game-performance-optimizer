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
    /// <summary>应用内动效开关，由“减弱动效”设置决定，与 Windows 系统动画开关解耦。</summary>
    public static bool Enabled { get; private set; } = true;

    /// <summary>Windows 的“动画效果”开关，仅用于诊断与提示，不再直接停用应用内反馈。</summary>
    public static bool SystemEnabled { get; private set; } = Detect();

    /// <summary>重新读取系统开关；应用内动效只由用户自己的“减弱动效”设置控制。</summary>
    public static void Configure(bool reduceMotion)
    {
        SystemEnabled = Detect();
        Enabled = !reduceMotion;
    }

    private static bool Detect()
    {
        try { return new UISettings().AnimationsEnabled; }
        catch { return true; }
    }

    /// <summary>设置页展示用的状态说明。</summary>
    public static string Describe(bool reduceMotion)
        => reduceMotion
            ? "已关闭：数值与列表直接呈现最终状态。"
            : SystemEnabled
                ? "已启用：控件悬浮放大与按下回弹。"
                : "已启用：Windows 的“动画效果”处于关闭状态，本应用的控件反馈仍然生效。";

    /// <summary>
    /// 图标悬浮反馈：以图标中心为原点放大。只动画 Scale，不碰 Offset / 布局，
    /// 因此缩放结束后一定会回到原尺寸与原位置，不会与 XAML 布局互相覆盖。
    /// </summary>
    public static void IconHover(FrameworkElement? element, bool hover, float scale = 1.2f)
    {
        if (!Enabled || element is null) return;
        try
        {
            var visual = ElementCompositionPreview.GetElementVisual(element);
            if (element.ActualWidth <= 0 || element.ActualHeight <= 0) return;
            var compositor = visual.Compositor;
            visual.CenterPoint = new Vector3((float)element.ActualWidth / 2f, (float)element.ActualHeight / 2f, 0);

            var state = States.GetOrCreateValue(element);
            var token = ++state.Token;
            var ease = compositor.CreateCubicBezierEasingFunction(new Vector2(0.2f, 0f), new Vector2(0f, 1f));
            var duration = TimeSpan.FromMilliseconds(hover ? 180 : 130);

            var target = hover ? scale : 1f;
            // 从当前动画值起步，快速进出时平滑反向，而不是跳变。
            var from = visual.Scale.X;

            var anim = compositor.CreateVector3KeyFrameAnimation();
            anim.InsertKeyFrame(0f, new Vector3(from, from, 1f));
            anim.InsertKeyFrame(1f, new Vector3(target, target, 1f), ease);
            anim.Duration = duration;

            var batch = compositor.CreateScopedBatch(CompositionBatchTypes.Animation);
            batch.Completed += (_, _) =>
            {
                // 快速进出时旧批次会晚一步完成，只允许最后一次写入基础值。
                if (state.Token != token) return;
                try
                {
                    visual.StopAnimation("Scale");
                    visual.Scale = new Vector3(target, target, 1f);
                }
                catch { }
            };

            visual.StartAnimation("Scale", anim);
            batch.End();
        }
        catch { }
    }

    /// <summary>按下反馈：缩到 90%，松开回到悬浮尺寸。</summary>
    public static void IconPress(FrameworkElement? element, bool pressed, float hoverScale = 1.2f)
    {
        if (!Enabled || element is null) return;
        try
        {
            var visual = ElementCompositionPreview.GetElementVisual(element);
            if (element.ActualWidth <= 0 || element.ActualHeight <= 0) return;
            var compositor = visual.Compositor;
            visual.CenterPoint = new Vector3((float)element.ActualWidth / 2f, (float)element.ActualHeight / 2f, 0);

            var state = States.GetOrCreateValue(element);
            var token = ++state.Token;
            var ease = compositor.CreateCubicBezierEasingFunction(new Vector2(0.2f, 0f), new Vector2(0f, 1f));
            var target = pressed ? 0.9f : hoverScale;
            var from = visual.Scale.X;

            var anim = compositor.CreateVector3KeyFrameAnimation();
            anim.InsertKeyFrame(0f, new Vector3(from, from, 1f));
            anim.InsertKeyFrame(1f, new Vector3(target, target, 1f), ease);
            anim.Duration = TimeSpan.FromMilliseconds(pressed ? 80 : 140);

            var batch = compositor.CreateScopedBatch(CompositionBatchTypes.Animation);
            batch.Completed += (_, _) =>
            {
                if (state.Token != token) return;
                try
                {
                    visual.StopAnimation("Scale");
                    visual.Scale = new Vector3(target, target, 1f);
                }
                catch { }
            };

            visual.StartAnimation("Scale", anim);
            batch.End();
        }
        catch { }
    }

    private sealed class HoverState
    {
        public int Token;
    }

    private static readonly System.Runtime.CompilerServices.ConditionalWeakTable<FrameworkElement, HoverState> States = new();

    /// <summary>
    /// 透明度 + 垂直位移的入场，200ms 以内，只用于容器出现。
    /// 位移围绕元素当前的布局槽位做相对偏移：Offset 是 XAML 布局写入的坐标，
    /// 不能假设它是 0。动画结束后只 StopAnimation 交还布局值，
    /// 否则行内展开的详情会跳回父容器左上角，压住上一行。
    /// </summary>
    public static void FadeSlideIn(UIElement element, double fromY = 8, int milliseconds = 190)
    {
        if (!Enabled || element is null) return;
        try
        {
            var visual = ElementCompositionPreview.GetElementVisual(element);
            var compositor = visual.Compositor;
            // XAML 已经给出的布局坐标，动画只在这个坐标上叠加一个小的入场位移。
            var baseOffset = visual.Offset;
            var startOffset = new Vector3(baseOffset.X, baseOffset.Y + (float)fromY, baseOffset.Z);
            visual.Opacity = 0f;

            var ease = compositor.CreateCubicBezierEasingFunction(new Vector2(0.2f, 0f), new Vector2(0f, 1f));
            var duration = TimeSpan.FromMilliseconds(milliseconds);

            var fade = compositor.CreateScalarKeyFrameAnimation();
            fade.InsertKeyFrame(0f, 0f);
            fade.InsertKeyFrame(1f, 1f, ease);
            fade.Duration = duration;

            var slide = compositor.CreateVector3KeyFrameAnimation();
            slide.InsertKeyFrame(0f, startOffset);
            slide.InsertKeyFrame(1f, baseOffset, ease);
            slide.Duration = duration;

            var batch = compositor.CreateScopedBatch(CompositionBatchTypes.Animation);
            visual.StartAnimation("Opacity", fade);
            visual.StartAnimation("Offset", slide);
            batch.Completed += (_, _) =>
            {
                try
                {
                    // 不清零 Offset：停掉动画后由 XAML 的布局坐标接管，元素回到自己的槽位。
                    visual.StopAnimation("Opacity");
                    visual.StopAnimation("Offset");
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
        // 30fps 对数字滚动已经足够顺滑，比 60fps 少一半格式化与布局开销。
        _timer.Interval = TimeSpan.FromMilliseconds(33);
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

        // 采样噪声级别的变化不值得重新起一段动画；未在滚动时仍照常刷新终值。
        if (_timer.IsRunning && Math.Abs(value - _to) < 0.05) return;

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
