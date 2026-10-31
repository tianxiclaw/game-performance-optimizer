using System.Collections.Concurrent;
using System.Diagnostics;
using System.Text;
using System.Text.Json;

namespace GamePerfCenter.Services;

public sealed class EngineException : Exception
{
    public EngineException(string message) : base(message) { }
}

public sealed class EngineBridge : IAsyncDisposable
{
    private Process? _proc;
    private readonly SemaphoreSlim _startLock = new(1, 1);
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private readonly ConcurrentDictionary<string, TaskCompletionSource<JsonElement>> _pending = new();
    private int _seq;
    private bool _disposed;

    public bool IsRunning => _proc is { HasExited: false };
    public event Action<string>? LogReceived;
    public event Action<string>? Faulted;

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
            DisposeProcess();
            if (!File.Exists(AppPaths.BridgePath))
                throw new EngineException($"引擎桥接脚本缺失: {AppPaths.BridgePath}");
            if (!File.Exists(AppPaths.EnginePath))
                throw new EngineException($"引擎脚本缺失: {AppPaths.EnginePath}");

            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = new UTF8Encoding(false),
                StandardErrorEncoding = new UTF8Encoding(false),
                WorkingDirectory = AppPaths.BaseDir
            };
            psi.ArgumentList.Add("-NoProfile");
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

            var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
            proc.Exited += (_, _) =>
            {
                var msg = "引擎进程已退出";
                Faulted?.Invoke(msg);
                FailPending(msg);
            };
            if (!proc.Start()) throw new EngineException("无法启动引擎进程");
            _proc = proc;
            _ = Task.Run(ReadStdoutAsync);
            _ = Task.Run(ReadStderrAsync);

            var data = await RequestCoreAsync("ping", null, TimeSpan.FromMinutes(3), ct).ConfigureAwait(false);
            if (data.ValueKind == JsonValueKind.Object && data.TryGetProperty("pong", out _))
                LogReceived?.Invoke("引擎已就绪");
        }
        finally
        {
            _startLock.Release();
        }
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
        if (result is null) throw new EngineException("引擎返回了空数据");
        return result;
    }

    private async Task<JsonElement> RequestCoreAsync(string cmd, object? args, TimeSpan timeout, CancellationToken ct)
    {
        var proc = _proc;
        if (proc is null || proc.HasExited) throw new EngineException("引擎未运行");

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
                throw new EngineException($"引擎响应超时: {cmd}");
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
                        tcs.TrySetException(new EngineException(err ?? "未知错误"));
                    }
                }
            }
        }
        catch (Exception ex)
        {
            LogReceived?.Invoke($"[stdout] {ex.Message}");
        }
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
                if (!string.IsNullOrWhiteSpace(line)) LogReceived?.Invoke("[stderr] " + line.Trim());
            }
        }
        catch { }
    }

    private void FailPending(string message)
    {
        foreach (var kv in _pending)
        {
            if (_pending.TryRemove(kv.Key, out var tcs))
                tcs.TrySetException(new EngineException(message));
        }
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
