using System.Management;
using GamePerfCenter.Models;

namespace GamePerfCenter.Services;

/// <summary>
/// 只读采集内存构成：物理使用、待机缓存、提交量、内核池与进程专用工作集。
/// WMI 查询比 250ms 实时采样重，调用方应放到后台线程并按需刷新。
/// </summary>
public static class MemoryDiagnosticsService
{
    private const string OsQuery =
        "SELECT CommitLimit, CommittedBytes, FreeAndZeroPageListBytes, " +
        "PoolNonpagedBytes, PoolPagedBytes, StandbyCacheCoreBytes, " +
        "StandbyCacheNormalPriorityBytes, StandbyCacheReserveBytes " +
        "FROM Win32_PerfFormattedData_PerfOS_Memory";

    private const string ProcessQuery =
        "SELECT Name, IDProcess, WorkingSetPrivate " +
        "FROM Win32_PerfFormattedData_PerfProc_Process";

    public static MemorySnapshot Sample()
    {
        var snapshot = new MemorySnapshot();

        // 总量与任务管理器“使用中”同源，保证与概览页数字一致。
        try
        {
            var mem = LiveMetricsService.SampleMemory();
            snapshot.TotalGb = mem.total;
            snapshot.UsedGb = mem.used;
            snapshot.AvailableGb = Math.Max(0, mem.total - mem.used);
        }
        catch { }

        try { ReadOsMemory(snapshot); } catch { }
        try { ReadProcesses(snapshot); } catch { }

        snapshot.UpdatedAt = DateTime.Now;
        return snapshot;
    }

    private static void ReadOsMemory(MemorySnapshot snapshot)
    {
        using var searcher = new ManagementObjectSearcher("root\\CIMV2", OsQuery);
        foreach (ManagementObject obj in searcher.Get())
        {
            snapshot.StandbyGb = ToGb(obj, "StandbyCacheNormalPriorityBytes")
                                 + ToGb(obj, "StandbyCacheReserveBytes")
                                 + ToGb(obj, "StandbyCacheCoreBytes");
            snapshot.CommittedGb = ToGb(obj, "CommittedBytes");
            snapshot.CommitLimitGb = ToGb(obj, "CommitLimit");
            snapshot.PagedPoolGb = ToGb(obj, "PoolPagedBytes");
            snapshot.NonPagedPoolGb = ToGb(obj, "PoolNonpagedBytes");
            snapshot.FreeGb = ToGb(obj, "FreeAndZeroPageListBytes");
            break;
        }
    }

    private static void ReadProcesses(MemorySnapshot snapshot)
    {
        var byName = new Dictionary<string, double>(StringComparer.OrdinalIgnoreCase);
        using var searcher = new ManagementObjectSearcher("root\\CIMV2", ProcessQuery);
        foreach (ManagementObject obj in searcher.Get())
        {
            try
            {
                var rawName = obj["Name"]?.ToString() ?? "";
                var hash = rawName.IndexOf('#');
                if (hash > 0) rawName = rawName[..hash];
                if (rawName.Length == 0 ||
                    rawName.Equals("_Total", StringComparison.OrdinalIgnoreCase) ||
                    rawName.Equals("Idle", StringComparison.OrdinalIgnoreCase))
                    continue;

                var pid = Convert.ToUInt32(obj["IDProcess"] ?? 0u);
                if (pid == 0) continue;

                var privateMb = Convert.ToDouble(obj["WorkingSetPrivate"] ?? 0d) / 1024.0 / 1024.0;
                if (privateMb <= 0) continue;

                byName[rawName] = byName.GetValueOrDefault(rawName) + privateMb;
            }
            catch { }
        }

        snapshot.ProcessTotalGb = byName.Values.Sum() / 1024.0;
        snapshot.Processes = byName
            .OrderByDescending(pair => pair.Value)
            .Take(8)
            .Select(pair => new MemoryProcessInfo
            {
                Name = pair.Key,
                PrivateMb = Math.Round(pair.Value, 0)
            })
            .ToList();
    }

    private static double ToGb(ManagementObject obj, string property)
    {
        try { return Convert.ToDouble(obj[property] ?? 0d) / 1024.0 / 1024.0 / 1024.0; }
        catch { return 0; }
    }
}