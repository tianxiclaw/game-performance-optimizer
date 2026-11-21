namespace GamePerfCenter.Core.Services;

/// <summary>
/// Core 的统一诊断出口。Core 不直接依赖界面层，宿主启动时注入落盘实现；
/// 未注入时日志被丢弃，不影响任何业务路径。
/// </summary>
public static class CoreDiagnostics
{
    private static Action<string>? _sink;

    public static bool Enabled => _sink is not null;

    public static void SetSink(Action<string>? sink) => _sink = sink;

    public static void Log(string message)
    {
        if (string.IsNullOrWhiteSpace(message)) return;
        try { _sink?.Invoke(message); } catch { }
    }
}