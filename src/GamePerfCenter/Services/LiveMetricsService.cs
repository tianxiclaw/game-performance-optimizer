using System.Diagnostics;
using System.Management;
using System.Net.NetworkInformation;
using System.Runtime.InteropServices;
using GamePerfCenter.Models;

namespace GamePerfCenter.Services;

public sealed class LiveMetricsService
{
    private static readonly TimeSpan GpuInterval = TimeSpan.FromSeconds(1);
    private static readonly TimeSpan GpuRetryInterval = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan NicRefreshInterval = TimeSpan.FromSeconds(10);

    private ulong _lastIdle, _lastKernel, _lastUser;
    private long _lastNetRecv, _lastNetSent;
    private DateTime _lastAt = DateTime.MinValue;
    private readonly object _gate = new();
    private bool _primed;
    private double _lastGpu;
    private DateTime _lastGpuAt = DateTime.MinValue;
    private NetworkInterface[] _activeNics = Array.Empty<NetworkInterface>();
    private DateTime _nicsAt = DateTime.MinValue;

    public LiveMetricsService()
    {
        // 先取一次基线，让 250ms 后的首个采样就能给出真实的 CPU / 网络数值。
        SampleCpu();
        SampleNetwork();
    }

    public bool GpuAvailable { get; private set; } = true;
    public string? GpuError { get; private set; }

    public LiveMetrics Sample()
    {
        var result = new LiveMetrics();
        lock (_gate)
        {
            result.Cpu = SampleCpu();
            var mem = SampleMemory();
            result.RamPercent = mem.pct;
            result.RamUsedGb = mem.used;
            result.RamTotalGb = mem.total;
            var net = SampleNetwork();
            result.NetDownKbps = net.down;
            result.NetUpKbps = net.up;
        }
        result.Gpu = SampleGpuThrottled();
        return result;
    }

    /// <summary>
    /// GPU 走 WMI，单次查询比 CPU / 内存 / 网络贵一个数量级。
    /// 界面仍按 250ms 刷新，但 WMI 结果按 1 秒缓存，避免采样器自己吃掉一个核的十几%。
    /// </summary>
    private double SampleGpuThrottled()
    {
        var now = DateTime.UtcNow;
        // 查询失败后拉长重试间隔：没有GPU性能计数器的机器不必每秒撞一次 WMI。
        var interval = GpuAvailable ? GpuInterval : GpuRetryInterval;
        if (now - _lastGpuAt < interval) return _lastGpu;
        _lastGpuAt = now;
        _lastGpu = SampleGpu();
        return _lastGpu;
    }

    private double SampleCpu()
    {
        if (!GetSystemTimes(out var idle, out var kernel, out var user)) return 0;
        ulong i = ToUInt64(idle), k = ToUInt64(kernel), u = ToUInt64(user);
        if (!_primed)
        {
            _lastIdle = i; _lastKernel = k; _lastUser = u; _primed = true;
            return 0;
        }
        var idleDelta = i - _lastIdle;
        var totalDelta = (k - _lastKernel) + (u - _lastUser);
        _lastIdle = i; _lastKernel = k; _lastUser = u;
        if (totalDelta == 0) return 0;
        var value = (1.0 - (double)idleDelta / totalDelta) * 100.0;
        return Math.Clamp(value, 0, 100);
    }

    internal static (double pct, double used, double total) SampleMemory()
    {
        var status = new MEMORYSTATUSEX { dwLength = (uint)Marshal.SizeOf<MEMORYSTATUSEX>() };
        if (!GlobalMemoryStatusEx(ref status)) return (0, 0, 0);
        var total = status.ullTotalPhys / 1024.0 / 1024.0 / 1024.0;
        var avail = status.ullAvailPhys / 1024.0 / 1024.0 / 1024.0;
        var used = Math.Max(0, total - avail);
        var pct = total <= 0 ? 0 : used / total * 100.0;
        return (pct, used, total);
    }

    /// <summary>
    /// 网卡集合变化很慢，没必要每 250ms 枚举一次全部接口。
    /// 这里缓存 10 秒，期间只读已筛选网卡的计数器。
    /// </summary>
    private NetworkInterface[] ActiveNics()
    {
        var now = DateTime.UtcNow;
        if (now - _nicsAt < NicRefreshInterval) return _activeNics;

        var list = new List<NetworkInterface>();
        try
        {
            foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (nic.OperationalStatus != OperationalStatus.Up) continue;
                if (nic.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel) continue;
                list.Add(nic);
            }
        }
        catch { }
        _activeNics = list.ToArray();
        _nicsAt = now;
        return _activeNics;
    }

    private (double down, double up) SampleNetwork()
    {
        long recv = 0, sent = 0;
        foreach (var nic in ActiveNics())
        {
            try
            {
                var stats = nic.GetIPv4Statistics();
                recv += stats.BytesReceived;
                sent += stats.BytesSent;
            }
            catch { }
        }

        var now = DateTime.UtcNow;
        if (_lastAt == DateTime.MinValue)
        {
            _lastNetRecv = recv; _lastNetSent = sent; _lastAt = now;
            return (0, 0);
        }
        var seconds = Math.Max(0.5, (now - _lastAt).TotalSeconds);
        var down = Math.Max(0, (recv - _lastNetRecv) / 1024.0 / seconds);
        var up = Math.Max(0, (sent - _lastNetSent) / 1024.0 / seconds);
        _lastNetRecv = recv; _lastNetSent = sent; _lastAt = now;
        return (down, up);
    }

    private double SampleGpu()
    {
        try
        {
            var total = 0.0;
            using var searcher = new ManagementObjectSearcher(
                "root\\CIMV2",
                "SELECT Name, UtilizationPercentage FROM Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine");
            foreach (ManagementObject obj in searcher.Get())
            {
                var name = obj["Name"]?.ToString() ?? "";
                if (!name.Contains("engtype_3D", StringComparison.OrdinalIgnoreCase)) continue;
                var raw = obj["UtilizationPercentage"];
                if (raw is null) continue;
                total += Convert.ToDouble(raw);
            }
            GpuAvailable = true;
            GpuError = null;
            return Math.Clamp(total, 0, 100);
        }
        catch (Exception ex)
        {
            GpuAvailable = false;
            GpuError = ex.Message;
            return 0;
        }
    }

    private static ulong ToUInt64(FILETIME ft) => ((ulong)ft.dwHighDateTime << 32) | ft.dwLowDateTime;

    [StructLayout(LayoutKind.Sequential)]
    private struct FILETIME { public uint dwLowDateTime; public uint dwHighDateTime; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetSystemTimes(out FILETIME idleTime, out FILETIME kernelTime, out FILETIME userTime);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
}
