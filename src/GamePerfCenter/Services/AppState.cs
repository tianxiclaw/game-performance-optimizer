using System.Collections.ObjectModel;
using System.Text.Json;
using GamePerfCenter.Models;

namespace GamePerfCenter.Services;

public sealed class AppState
{
    private readonly EngineBridge _engine;
    private readonly SettingsService _settings;
    private readonly SemaphoreSlim _snapshotLock = new(1, 1);
    private Task? _snapshotTask;

    public ObservableCollection<ItemInfo> Items { get; } = new();
    public SnapshotInfo? Snapshot { get; private set; }
    public string StatusText { get; private set; } = "正在启动引擎...";
    public bool IsBusy { get; private set; }
    public string? LastError { get; private set; }
    public DateTime LastRefresh { get; private set; }
    public event Action? Changed;
    public event Action<string>? StatusChanged;

    public AppState(EngineBridge engine, SettingsService settings)
    {
        _engine = engine;
        _settings = settings;
        _engine.LogReceived += line => AppLog.Write(line);
        _engine.Faulted += msg => SetStatus("引擎连接中断: " + msg);
    }

    public void SetStatus(string text)
    {
        StatusText = text;
        StatusChanged?.Invoke(text);
    }

    public async Task EnsureSnapshotAsync(bool force = false, CancellationToken ct = default)
    {
        if (Snapshot is not null && !force) return;
        await _snapshotLock.WaitAsync(ct);
        try
        {
            if (Snapshot is not null && !force) return;
            if (_snapshotTask is not null)
            {
                await _snapshotTask;
                return;
            }
            _snapshotTask = LoadSnapshotCoreAsync(ct);
            try { await _snapshotTask; }
            finally { _snapshotTask = null; }
        }
        finally { _snapshotLock.Release(); }
    }

    private async Task LoadSnapshotCoreAsync(CancellationToken ct)
    {
        SetBusy(true, "正在读取硬件与优化项状态...");
        try
        {
            var data = await _engine.RequestAsync("snapshot", new { provisional = false },
                TimeSpan.FromMinutes(6), ct);
            var snap = data.Deserialize<SnapshotInfo>(JsonOptions);
            if (snap is null) throw new EngineException("状态数据为空");
            Snapshot = snap;
            Items.Clear();
            foreach (var item in snap.Items) Items.Add(item);
            LastRefresh = DateTime.Now;
            LastError = null;
            SetStatus($"已加载 {snap.Items.Count} 个优化项 · {snap.Machine}");
            AppLog.Write($"快照完成: {snap.Items.Count} 项, {snap.Machine}");
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            SetStatus("状态读取失败: " + ex.Message);
            AppLog.Write("快照失败: " + ex);
            throw;
        }
        finally
        {
            SetBusy(false, null);
            Changed?.Invoke();
        }
    }

    public async Task<ApplyResult> ApplyAsync(IEnumerable<string> ids, bool dryRun, bool restorePoint = false,
        CancellationToken ct = default)
    {
        var list = ids.Distinct().ToArray();
        SetBusy(true, dryRun ? "正在生成变更预览..." : $"正在应用 {list.Length} 项优化...");
        try
        {
            var data = await _engine.RequestAsync("apply", new { ids = list, dryRun, restorePoint },
                TimeSpan.FromMinutes(10), ct);
            var result = data.Deserialize<ApplyResult>(JsonOptions) ?? new ApplyResult();
            LastError = null;
            SetStatus(dryRun
                ? $"预览完成: {result.Preview.Count} 项将变更"
                : $"应用完成: 成功 {result.Ok} 项, 失败 {result.Fail} 项");
            if (!dryRun)
            {
                Snapshot = null;
                _ = EnsureSnapshotAsync(true);
            }
            return result;
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            SetStatus("操作失败: " + ex.Message);
            throw;
        }
        finally { SetBusy(false, null); Changed?.Invoke(); }
    }

    public Task<List<BackupInfo>> GetBackupsAsync(CancellationToken ct = default)
        => _engine.RequestAsync<List<BackupInfo>>("backups", null, TimeSpan.FromMinutes(2), ct);

    public Task<List<ProfileInfo>> GetProfilesAsync(CancellationToken ct = default)
        => _engine.RequestAsync<List<ProfileInfo>>("profiles", null, TimeSpan.FromMinutes(2), ct);

    public Task<string> SaveProfileAsync(string name, IEnumerable<string> ids, CancellationToken ct = default)
        => _engine.RequestAsync<string>("save_profile", new { name, ids = ids.ToArray() }, TimeSpan.FromMinutes(2), ct);

    public Task<List<GameInfo>> GetGamesAsync(bool force, CancellationToken ct = default)
        => _engine.RequestAsync<List<GameInfo>>("games", new { force }, TimeSpan.FromMinutes(5), ct);

    public Task<List<DiagEntry>> GetDiagnosticsAsync(CancellationToken ct = default)
        => _engine.RequestAsync<List<DiagEntry>>("diagnostics", null, TimeSpan.FromMinutes(8), ct);

    public Task<List<StartupEntry>> GetStartupAsync(CancellationToken ct = default)
        => _engine.RequestAsync<List<StartupEntry>>("startup", null, TimeSpan.FromMinutes(3), ct);

    public Task<List<BackgroundProc>> GetBackgroundAsync(int top = 14, CancellationToken ct = default)
        => _engine.RequestAsync<List<BackgroundProc>>("background", new { top }, TimeSpan.FromMinutes(3), ct);

    public Task<DriverHistoryWrapper> GetDriverHistoryAsync(CancellationToken ct = default)
        => _engine.RequestAsync<DriverHistoryWrapper>("driver_history", null, TimeSpan.FromMinutes(2), ct);

    public Task<string> ExportReportAsync(CancellationToken ct = default)
        => _engine.RequestAsync<string>("report", null, TimeSpan.FromMinutes(5), ct);

    public Task<string> ExportBundleAsync(CancellationToken ct = default)
        => _engine.RequestAsync<string>("bundle", null, TimeSpan.FromMinutes(8), ct);

    public Task<JsonElement> RestoreAsync(string? path, CancellationToken ct = default)
        => _engine.RequestAsync<JsonElement>("restore", new { path }, TimeSpan.FromMinutes(8), ct);

    public Task<JsonElement> RestoreAllAsync(CancellationToken ct = default)
        => _engine.RequestAsync<JsonElement>("restore_all", null, TimeSpan.FromMinutes(10), ct);

    public Task<JsonElement> CreateRestorePointAsync(CancellationToken ct = default)
        => _engine.RequestAsync<JsonElement>("restore_point", null, TimeSpan.FromMinutes(6), ct);

    public Task<JsonElement> SaveGameProfileAsync(string exe, GameProfile profile, CancellationToken ct = default)
        => _engine.RequestAsync<JsonElement>("game_save", new { exe, profile }, TimeSpan.FromMinutes(2), ct);

    public Task<JsonElement> ApplyGameProfileAsync(string exe, GameProfile profile, CancellationToken ct = default)
        => _engine.RequestAsync<JsonElement>("game_apply", new { exe, profile }, TimeSpan.FromMinutes(2), ct);

    public Task<JsonElement> RemoveGameProfileAsync(string exe, CancellationToken ct = default)
        => _engine.RequestAsync<JsonElement>("game_remove", new { exe }, TimeSpan.FromMinutes(2), ct);

    public Task<JsonElement> StartGameAsync(string exe, GameProfile profile, CancellationToken ct = default)
        => _engine.RequestAsync<JsonElement>("game_start", new { exe, profile }, TimeSpan.FromMinutes(2), ct);

    public Task<string> AddGameAsync(string name, string exe, CancellationToken ct = default)
        => _engine.RequestAsync<string>("game_add", new { name, exe }, TimeSpan.FromMinutes(2), ct);

    public Task<JsonElement> RemoveManualGameAsync(string exe, CancellationToken ct = default)
        => _engine.RequestAsync<JsonElement>("game_delete", new { exe }, TimeSpan.FromMinutes(2), ct);

    private void SetBusy(bool busy, string? status)
    {
        IsBusy = busy;
        if (!string.IsNullOrEmpty(status)) SetStatus(status);
        Changed?.Invoke();
    }

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        NumberHandling = System.Text.Json.Serialization.JsonNumberHandling.AllowReadingFromString
    };
}

public static class AppLog
{
    private static readonly object Gate = new();

    public static void Write(string message)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.DataDir);
            var line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {message}{Environment.NewLine}";
            lock (Gate)
            {
                var file = AppPaths.AppLogPath;
                if (File.Exists(file) && new FileInfo(file).Length > 2 * 1024 * 1024)
                    File.Move(file, file + ".1", true);
                File.AppendAllText(file, line, System.Text.Encoding.UTF8);
            }
        }
        catch { }
    }

    /// <summary>删除当前日志与轮转备份，返回是否成功。日志只用于排查问题。</summary>
    public static bool Clear()
    {
        try
        {
            lock (Gate)
            {
                foreach (var file in new[] { AppPaths.AppLogPath, AppPaths.AppLogPath + ".1" })
                {
                    if (File.Exists(file)) File.Delete(file);
                }
            }
            return true;
        }
        catch { return false; }
    }
}
