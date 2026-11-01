using System.Globalization;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using GamePerfCenter.Core.Infrastructure;
using GamePerfCenter.Core.Models;

namespace GamePerfCenter.Core.Services;

/// <summary>
/// 通过 Windows Update 代理查询未安装的驱动更新。
/// 只读操作，不下载、不安装；需要网络与 Windows Update 服务可用。
/// </summary>
public sealed class WindowsUpdateDriverScanner
{
    private static readonly Regex VersionPattern = new(@"\d+\.\d+\.\d+\.\d+", RegexOptions.Compiled);

    private readonly object _lock = new();
    private IReadOnlyList<DriverUpdateInfo>? _cache;
    private DateTime _cacheAt = DateTime.MinValue;
    private readonly TimeSpan _cacheTtl;

    public WindowsUpdateDriverScanner(TimeSpan? cacheTtl = null)
    {
        _cacheTtl = cacheTtl ?? TimeSpan.FromMinutes(5);
    }

    public IReadOnlyList<DriverUpdateInfo> Scan(bool force = false)
    {
        lock (_lock)
        {
            if (!force && _cache is not null && DateTime.Now - _cacheAt < _cacheTtl)
                return _cache;
        }

        var result = Query();
        lock (_lock)
        {
            _cache = result;
            _cacheAt = DateTime.Now;
        }
        return result;
    }

    public void ClearCache()
    {
        lock (_lock)
        {
            _cache = null;
            _cacheAt = DateTime.MinValue;
        }
    }

    private static List<DriverUpdateInfo> Query()
    {
        // Windows Update 代理要求 STA；GUI 常在 MTA 线程池上调用，
        // 这里统一切到专用 STA 线程，保证 GUI 与 CLI 行为一致。
        if (Thread.CurrentThread.GetApartmentState() == ApartmentState.STA)
            return QueryOnCurrentThread();

        List<DriverUpdateInfo>? result = null;
        Exception? error = null;
        var thread = new Thread(() =>
        {
            try { result = QueryOnCurrentThread(); }
            catch (Exception ex) { error = ex; }
        })
        {
            IsBackground = true,
            Name = "gpc-wu-driver-scan"
        };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();

        if (error is not null) ExceptionDispatchInfo.Capture(error).Throw();
        return result ?? new List<DriverUpdateInfo>();
    }

    private static List<DriverUpdateInfo> QueryOnCurrentThread()
    {
        try
        {
            return QueryCore();
        }
        catch (COMException ex)
        {
            throw new InvalidOperationException(
                $"Windows Update 查询失败 (0x{ex.HResult:X8}): {ex.Message}。请确认 Windows Update 服务与网络可用后重试。",
                ex);
        }
    }

    private static List<DriverUpdateInfo> QueryCore()
    {
        var sessionType = Type.GetTypeFromProgID("Microsoft.Update.Session")
                          ?? throw new InvalidOperationException("本机未注册 Windows Update 代理（Microsoft.Update.Session）");
        dynamic session = Activator.CreateInstance(sessionType)
                          ?? throw new InvalidOperationException("无法创建 Windows Update 会话");
        dynamic searcher = session.CreateUpdateSearcher();
        dynamic result = searcher.Search("IsInstalled=0 and Type='Driver'");

        var list = new List<DriverUpdateInfo>();
        foreach (var update in result.Updates)
        {
            try
            {
                var title = (string?)update.Title ?? "";
                var match = VersionPattern.Match(title);
                var version = match.Success ? match.Value : "";

                var date = "";
                try
                {
                    object? raw = update.DriverVerDate;
                    if (raw is DateTime dt) date = dt.ToString("yyyy/M/d", CultureInfo.InvariantCulture);
                }
                catch
                {
                    // 某些更新没有 DriverVerDate
                }

                list.Add(new DriverUpdateInfo
                {
                    Id = (string?)update.Identity.UpdateID ?? "",
                    Title = title,
                    ClassName = (string?)update.DriverClass ?? "",
                    HardwareId = (string?)update.DriverHardwareID ?? "",
                    Date = date,
                    Version = version,
                    Hidden = (bool?)update.IsHidden ?? false
                });
            }
            catch
            {
                // 单条更新解析失败不影响其余结果
            }
        }
        return list;
    }
}
