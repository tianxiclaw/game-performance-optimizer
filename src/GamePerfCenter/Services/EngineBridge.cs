using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace GamePerfCenter.Services;

public sealed class EngineException : Exception
{
    public string? Detail { get; }

    public EngineException(string message, string? detail = null) : base(message)
    {
        Detail = detail;
    }
}

/// <summary>一次引擎故障的快照，供报告和诊断使用。</summary>
public sealed class EngineFailure
{
    public string Summary { get; init; } = "引擎进程已退出";
    public string? Command { get; init; }
    public int? ExitCode { get; init; }
    public string? StderrTail { get; init; }
    public string? StdoutTail { get; init; }
    public string? LaunchError { get; init; }
    public string? PowerShellPath { get; init; }
    public DateTime StartedAt { get; init; }
    public DateTime ExitedAt { get; init; }
}

public sealed class EngineBridge : IAsyncDisposable
{
    private const int TailLimit = 200;

    private Process? _proc;
    private readonly SemaphoreSlim _startLock = new(1, 1);
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonElement>> _pending = new();
    private readonly ConcurrentQueue<string> _stderrTail = new();
    private readonly ConcurrentQueue<string> _stdoutTail = new();
    private int _seq;
    private bool _disposed;
    private volatile bool _stopping;
    private DateTime _startedAt;
    private string _powershellPath = "";
    private string? _lastCommand;
    private EngineFailure? _lastFailure;

    public bool IsRunning => _proc is { HasExited: false };
    public EngineFailure? LastFailure => _lastFailure;
    public event Action<string>? LogReceived;
    public event Action<EngineFailure>? Crashed;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        NumberHandling = System.Text.Json.Serialization.JsonNumberHandling.AllowReadingFromString
    };

    public async Task StartAsync(CancellationToken ct = default)
    {
        if (IsRunning) return;
        await _startLock.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            if (IsRunning) return;
            _stopping = false;
            DisposeProcess();
            ResetTail();

            if (!File.Exists(AppPaths.BridgePath))
                throw FailStart($"引擎桥接脚本缺失: {AppPaths.BridgePath}");
            if (!File.Exists(AppPaths.EnginePath))
                throw FailStart($"引擎脚本缺失: {AppPaths.EnginePath}");
            if (!Directory.Exists(AppPaths.BaseDir))
                throw FailStart($"程序目录不存在: {AppPaths.BaseDir}");

            var powershell = ResolvePowerShell(out var pathError);
            if (powershell is null)
                throw FailStart(pathError ?? "找不到 Windows PowerShell");
            _powershellPath = powershell;

            var psi = new ProcessStartInfo
            {
                FileName = powershell,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardInputEncoding = new UTF8Encoding(false),
                StandardOutputEncoding = new UTF8Encoding(false),
                StandardErrorEncoding = new UTF8Encoding(false),
                WorkingDirectory = AppPaths.BaseDir
            };
            psi.ArgumentList.Add("-NoLogo");
            psi.ArgumentList.Add("-NoProfile");
            psi.ArgumentList.Add("-NonInteractive");
            psi.ArgumentList.Add("-ExecutionPolicy");
            psi.ArgumentList.Add("Bypass");
            psi.ArgumentList.Add("-STA");
            psi.ArgumentList.Add("-WindowStyle");
            psi.ArgumentList.Add("Hidden");
            psi.ArgumentList.Add("-File");
            psi.ArgumentList.Add(AppPaths.BridgePath);
            if (!string.IsNullOrEmpty(AppPaths.UserSid))
            {
                psi.ArgumentList.Add("-Sid");
                psi.ArgumentList.Add(AppPaths.UserSid);
            }

            _startedAt = DateTime.Now;
            var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
            proc.Exited += (_, _) => _ = OnProcessExitedAsync(proc);
            if (!proc.Start())
                throw FailStart("无法启动 Windows PowerShell 进程");
            _proc = proc;
            _ = Task.Run(ReadStdoutAsync);
            _ = Task.Run(ReadStderrAsync);

            var data = await RequestCoreAsync("ping", null, TimeSpan.FromMinutes(3), ct).ConfigureAwait(false);
            if (data.ValueKind == JsonValueKind.Object && data.TryGetProperty("pong", out _))
            {
                var version = data.TryGetProperty("engine", out var ver) ? ver.GetString() : "";
                _lastFailure = null;
                LogReceived?.Invoke($"引擎已就绪 · PowerShell {version}".TrimEnd());
            }
        }
        finally
        {
            _startLock.Release();
        }
    }

    /// <summary>停掉当前进程重新连接，供错误报告里的“重新连接”使用。</summary>
    public async Task RestartAsync(CancellationToken ct = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await _startLock.WaitAsync(ct).ConfigureAwait(false);
        try
        {
            _stopping = true;
            DisposeProcess();
            _stopping = false;
            _lastFailure = null;
        }
        finally
        {
            _startLock.Release();
        }
        await StartAsync(ct).ConfigureAwait(false);
    }

    public async Task<JsonElement> RequestAsync(string cmd, object? args = null,
        TimeSpan? timeout = null, CancellationToken ct = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await StartAsync(ct).ConfigureAwait(false);
        return await RequestCoreAsync(cmd, args, timeout ?? TimeSpan.FromMinutes(2), ct).ConfigureAwait(false);
    }

    public async Task<T> RequestAsync<T>(string cmd, object? args = null,
        TimeSpan? timeout = null, CancellationToken ct = default)
    {
        var data = await RequestAsync(cmd, args, timeout, ct).ConfigureAwait(false);
        var result = data.Deserialize<T>(JsonOptions);
        if (result is null) throw new EngineException("引擎返回了空数据", DescribeLastFailure());
        return result;
    }

    private EngineException FailStart(string message)
    {
        var failure = new EngineFailure
        {
            Summary = message,
            Command = "启动",
            LaunchError = message,
            PowerShellPath = _powershellPath,
            StartedAt = _startedAt == default ? DateTime.Now : _startedAt,
            ExitedAt = DateTime.Now
        };
        _lastFailure = failure;
        AppLog.Write("引擎启动失败: " + message);
        return new EngineException(message, DescribeFailure(failure));
    }

    private async Task<JsonElement> RequestCoreAsync(string cmd, object? args, TimeSpan timeout, CancellationToken ct)
    {
        var proc = _proc;
        if (proc is null || proc.HasExited)
            throw new EngineException("引擎未运行", DescribeLastFailure());

        _lastCommand = cmd;
        var id = Interlocked.Increment(ref _seq).ToString();
        var tcs = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        _pending[id] = tcs;

        try
        {
            var payload = JsonSerializer.Serialize(new { id, cmd, args }, new JsonSerializerOptions
            {
                DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull
            });
            await _writeLock.WaitAsync(ct).ConfigureAwait(false);
            try
            {
                await proc.StandardInput.WriteLineAsync(payload.AsMemory(), ct).ConfigureAwait(false);
                await proc.StandardInput.FlushAsync(ct).ConfigureAwait(false);
            }
            finally { _writeLock.Release(); }

            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(timeout);
            try
            {
                return await tcs.Task.WaitAsync(cts.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!ct.IsCancellationRequested)
            {
                throw new EngineException($"引擎响应超时: {cmd}", DescribeLastFailure(
                    $"命令 {cmd} 超过 {timeout.TotalSeconds:0} 秒没有返回。引擎可能卡在硬件查询或系统调用上。"));
            }
        }
        finally
        {
            _pending.TryRemove(id, out _);
        }
    }

    private async Task ReadStdoutAsync()
    {
        var proc = _proc;
        if (proc is null) return;
        try
        {
            while (true)
            {
                var line = await proc.StandardOutput.ReadLineAsync().ConfigureAwait(false);
                if (line is null) break;
                if (string.IsNullOrWhiteSpace(line)) continue;
                line = line.TrimStart('\uFEFF');
                JsonDocument doc;
                try
                {
                    doc = JsonDocument.Parse(line);
                }
                catch
                {
                    EnqueueTail(_stdoutTail, line);
                    LogReceived?.Invoke(line);
                    continue;
                }

                using (doc)
                {
                    var root = doc.RootElement;
                    if (!root.TryGetProperty("id", out var idEl)) continue;
                    var id = idEl.GetString();
                    if (string.IsNullOrEmpty(id)) continue;
                    if (!_pending.TryRemove(id, out var tcs)) continue;

                    foreach (var log in ReadLogs(root))
                        LogReceived?.Invoke(log);

                    if (root.TryGetProperty("ok", out var okEl) && okEl.ValueKind == JsonValueKind.True)
                    {
                        if (root.TryGetProperty("data", out var dataEl))
                            tcs.TrySetResult(dataEl.Clone());
                        else
                            tcs.TrySetResult(JsonDocument.Parse("null").RootElement.Clone());
                    }
                    else
                    {
                        var err = root.TryGetProperty("error", out var e) ? e.GetString() : "未知错误";
                        var detail = ReadErrorDetail(root);
                        tcs.TrySetException(new EngineException(err ?? "未知错误", detail));
                    }
                }
            }
        }
        catch (Exception ex)
        {
            EnqueueTail(_stdoutTail, "[stdout] " + ex.Message);
            LogReceived?.Invoke($"[stdout] {ex.Message}");
        }
    }

    private static string? ReadErrorDetail(JsonElement root)
    {
        if (!root.TryGetProperty("errorDetail", out var d) || d.ValueKind != JsonValueKind.Object)
            return null;
        var lines = new List<string>();
        foreach (var name in new[] { "type", "id", "category", "line", "position", "stack" })
        {
            if (d.TryGetProperty(name, out var v) && v.ValueKind != JsonValueKind.Null)
            {
                var text = v.GetString();
                if (!string.IsNullOrWhiteSpace(text)) lines.Add($"{name}: {text}");
            }
        }
        return lines.Count == 0 ? null : string.Join(Environment.NewLine, lines);
    }

    private static IEnumerable<string> ReadLogs(JsonElement root)
    {
        if (!root.TryGetProperty("logs", out var logs) || logs.ValueKind != JsonValueKind.Array)
            yield break;
        foreach (var item in logs.EnumerateArray())
        {
            var text = item.GetString();
            if (!string.IsNullOrWhiteSpace(text)) yield return text;
        }
    }

    private async Task ReadStderrAsync()
    {
        var proc = _proc;
        if (proc is null) return;
        try
        {
            while (true)
            {
                var line = await proc.StandardError.ReadLineAsync().ConfigureAwait(false);
                if (line is null) break;
                if (!string.IsNullOrWhiteSpace(line))
                {
                    var text = line.Trim();
                    EnqueueTail(_stderrTail, text);
                    LogReceived?.Invoke("[stderr] " + text);
                }
            }
        }
        catch { }
    }

    private async Task OnProcessExitedAsync(Process proc)
    {
        if (_stopping) return;
        // stderr 可能比 Exited 事件晚到，稍等一下再生成报告。
        try { await Task.Delay(150).ConfigureAwait(false); } catch { }

        int? exitCode = null;
        try { if (proc.HasExited) exitCode = proc.ExitCode; } catch { }

        var stderr = string.Join(Environment.NewLine, _stderrTail);
        var stdout = string.Join(Environment.NewLine, _stdoutTail);
        var summary = exitCode is null
            ? "引擎进程已退出"
            : $"引擎进程异常退出（代码 {exitCode} / 0x{exitCode:X8}）";

        var failure = new EngineFailure
        {
            Summary = summary,
            Command = _lastCommand,
            ExitCode = exitCode,
            StderrTail = stderr,
            StdoutTail = stdout,
            PowerShellPath = _powershellPath,
            StartedAt = _startedAt,
            ExitedAt = DateTime.Now
        };
        _lastFailure = failure;

        AppLog.Write($"{summary} · 最后命令: {_lastCommand ?? "—"} · {_powershellPath}");
        if (!string.IsNullOrWhiteSpace(stderr))
        {
            var tail = string.Join(" | ", stderr.Split('\n').TakeLast(5).Select(s => s.Trim()));
            AppLog.Write("引擎 stderr: " + tail);
        }

        Crashed?.Invoke(failure);
        FailPending(summary, DescribeFailure(failure));
    }

    private void FailPending(string message, string? detail = null)
    {
        foreach (var kv in _pending)
        {
            if (_pending.TryRemove(kv.Key, out var tcs))
                tcs.TrySetException(new EngineException(message, detail));
        }
    }

    private string DescribeLastFailure(string? prefix = null)
    {
        var failure = _lastFailure;
        if (failure is null) return prefix ?? "引擎没有返回更多信息。";
        return DescribeFailure(failure, prefix);
    }

    private static string DescribeFailure(EngineFailure failure, string? prefix = null)
    {
        var lines = new List<string>();
        if (!string.IsNullOrWhiteSpace(prefix)) lines.Add(prefix);
        lines.Add($"时间: {failure.ExitedAt:yyyy-MM-dd HH:mm:ss}");
        if (failure.ExitCode is int code)
            lines.Add($"退出代码: {code} (0x{code:X8})");
        if (!string.IsNullOrWhiteSpace(failure.Command))
            lines.Add($"最后命令: {failure.Command}");
        if (!string.IsNullOrWhiteSpace(failure.LaunchError))
            lines.Add($"启动错误: {failure.LaunchError}");
        if (!string.IsNullOrWhiteSpace(failure.PowerShellPath))
            lines.Add($"PowerShell: {failure.PowerShellPath}");
        if (!string.IsNullOrWhiteSpace(failure.StderrTail))
        {
            lines.Add("stderr:");
            lines.AddRange(failure.StderrTail.Split('\n').TakeLast(12).Select(s => "  " + s.TrimEnd()));
        }
        return string.Join(Environment.NewLine, lines);
    }

    private void ResetTail()
    {
        while (_stderrTail.TryDequeue(out _)) { }
        while (_stdoutTail.TryDequeue(out _)) { }
    }

    private static void EnqueueTail(ConcurrentQueue<string> queue, string line)
    {
        queue.Enqueue(line);
        while (queue.Count > TailLimit) queue.TryDequeue(out _);
    }

    internal static string? ResolvePowerShell(out string? error)
    {
        var candidates = new List<string>();
        var system = Environment.GetFolderPath(Environment.SpecialFolder.System);
        if (!string.IsNullOrWhiteSpace(system))
            candidates.Add(Path.Combine(system, "WindowsPowerShell", "v1.0", "powershell.exe"));
        var windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        if (!string.IsNullOrWhiteSpace(windows))
            candidates.Add(Path.Combine(windows, "Sysnative", "WindowsPowerShell", "v1.0", "powershell.exe"));

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                error = null;
                return candidate;
            }
        }

        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        foreach (var dir in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var candidate = Path.Combine(dir.Trim(), "powershell.exe");
                if (File.Exists(candidate))
                {
                    error = null;
                    return candidate;
                }
            }
            catch { }
        }

        error = "找不到 powershell.exe。Windows PowerShell 可能被安全软件删除、被组策略禁用，或系统组件损坏。";
        return null;
    }

    private void DisposeProcess()
    {
        var proc = _proc;
        _proc = null;
        if (proc is null) return;
        try
        {
            if (!proc.HasExited)
            {
                try { proc.StandardInput.Close(); } catch { }
                if (!proc.WaitForExit(1500)) proc.Kill(entireProcessTree: true);
            }
        }
        catch { }
        try { proc.Dispose(); } catch { }
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;
        _stopping = true;
        try
        {
            if (IsRunning)
            {
                try { await _proc!.StandardInput.WriteLineAsync("{\"id\":\"bye\",\"cmd\":\"bye\"}"); await _proc.StandardInput.FlushAsync(); } catch { }
            }
        }
        catch { }
        DisposeProcess();
        _startLock.Dispose();
        _writeLock.Dispose();
        await Task.CompletedTask;
    }
}
