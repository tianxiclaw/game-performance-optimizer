using System.Globalization;
using System.Management;
using System.Text.RegularExpressions;
using GamePerfCenter.Core.Infrastructure;
using GamePerfCenter.Core.Models;

namespace GamePerfCenter.Core.Services;

/// <summary>
/// 枚举已连接设备。优先一次 pnputil 调用拿全设备与当前驱动；
/// 老系统不支持 /enum-devices 时退回 WMI。
/// </summary>
public sealed class DriverDeviceScanner
{
    private static readonly HashSet<string> AllowedClasses = new(StringComparer.OrdinalIgnoreCase)
    {
        "DISPLAY", "MEDIA", "MOUSE", "KEYBOARD", "HIDCLASS", "NET", "BLUETOOTH"
    };

    private static readonly Regex InstancePattern = new(@"^(?:Instance ID|设备实例 ID)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex DescriptionPattern = new(@"^(?:Device Description|设备描述)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex ClassNamePattern = new(@"^(?:Class Name|类名称)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex ClassGuidPattern = new(@"^(?:Class GUID|类 GUID)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex ManufacturerPattern = new(@"^(?:Manufacturer Name|制造商名称)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex StatusPattern = new(@"^(?:Status|状态)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex DriverNamePattern = new(@"^(?:Driver Name|驱动程序名称)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex HardwareIdsPattern = new(@"^(?:Hardware IDs|硬件 ID)\s*:\s*(.*)$", RegexOptions.Compiled);
    private static readonly Regex HardwareLinePattern = new(@"^\s{12,}(\S.*)$", RegexOptions.Compiled);
    private static readonly Regex MatchingDriversPattern = new(@"^(?:Matching Drivers|匹配的驱动程序)\s*:", RegexOptions.Compiled);
    private static readonly Regex CandidateNamePattern = new(@"^\s+(?:Driver Name|驱动程序名称)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex CandidateVersionPattern = new(@"^\s+(?:Driver Version|驱动程序版本)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex CandidateProviderPattern = new(@"^\s+(?:Provider Name|提供程序名称)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex CandidateStatusPattern = new(@"^\s+(?:Driver Status|驱动程序状态)\s*:\s*(.+)$", RegexOptions.Compiled);

    private readonly object _lock = new();
    private IReadOnlyList<DriverDeviceInfo>? _cache;
    private DateTime _cacheAt = DateTime.MinValue;
    private readonly TimeSpan _cacheTtl;

    public DriverDeviceScanner(TimeSpan? cacheTtl = null)
    {
        _cacheTtl = cacheTtl ?? TimeSpan.FromSeconds(30);
    }

    public IReadOnlyList<DriverDeviceInfo> Scan(bool force = false)
    {
        lock (_lock)
        {
            if (!force && _cache is not null && DateTime.Now - _cacheAt < _cacheTtl)
                return _cache;
        }

        var devices = ScanViaPnPUtil();
        if (devices.Count == 0) devices = ScanViaWmi();
        devices = Sort(devices);

        lock (_lock)
        {
            _cache = devices;
            _cacheAt = DateTime.Now;
        }
        return devices;
    }

    public void ClearCache()
    {
        lock (_lock)
        {
            _cache = null;
            _cacheAt = DateTime.MinValue;
        }
    }

    private static List<DriverDeviceInfo> ScanViaPnPUtil()
    {
        List<RawDevice> raw;
        try
        {
            raw = ParseDevices(PnPUtilRunner.Run("/enum-devices /connected /drivers /ids"));
        }
        catch
        {
            return new List<DriverDeviceInfo>();
        }

        var result = new List<DriverDeviceInfo>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var device in raw)
        {
            var cls = device.ClassName.ToUpperInvariant();
            if (!AllowedClasses.Contains(cls)) continue;

            var infName = device.DriverName?.Trim() ?? "";
            if (infName.Length == 0 || infName.Equals("null", StringComparison.OrdinalIgnoreCase) ||
                infName.Equals("n/a", StringComparison.OrdinalIgnoreCase)) continue;

            var name = device.Name?.Trim() ?? "";
            if (name.Length == 0) continue;
            if (cls == "DISPLAY" && Regex.IsMatch(name, @"(?i)Basic Display|Basic Render")) continue;
            if (cls == "HIDCLASS" && !Regex.IsMatch(name, @"(?i)mouse|keyboard|logitech|razer|steelseries|corsair|罗技|雷蛇|键盘|鼠标")) continue;
            if (cls == "NET" && Regex.IsMatch(name, @"(?i)WAN Miniport|TAP-|VPN|Virtual|Hyper-V|Loopback|Kernel Debug")) continue;

            var deviceId = device.DeviceId?.Trim() ?? "";
            if (deviceId.Length == 0) continue;
            if (!seen.Add(deviceId + "|" + infName)) continue;

            var candidate = device.Candidates.FirstOrDefault(c =>
                                string.Equals(c.Name, infName, StringComparison.OrdinalIgnoreCase))
                            ?? device.Candidates.FirstOrDefault();

            var versionRaw = candidate?.VersionRaw?.Trim() ?? "";
            var (date, version) = DriverUtils.SplitDriverVersion(versionRaw);
            var provider = candidate?.Provider?.Trim() ?? "";
            if (provider.Length == 0) provider = device.Manufacturer?.Trim() ?? "";

            var (statusOk, statusText) = MapStatus(device.Status);
            var category = MapCategory(cls);

            result.Add(new DriverDeviceInfo
            {
                Name = name,
                Class = cls,
                Category = category,
                DeviceId = deviceId,
                HardwareId = device.HardwareIds.FirstOrDefault()?.Trim() ?? "",
                InfName = infName,
                Version = version,
                Date = date,
                Provider = provider,
                StatusText = statusText,
                StatusOk = statusOk
            });
        }

        return result;
    }

    private static List<RawDevice> ParseDevices(IReadOnlyList<string> lines)
    {
        var result = new List<RawDevice>();
        RawDevice? current = null;
        RawCandidate? candidate = null;
        var inHardware = false;
        var inMatching = false;

        void Flush()
        {
            if (current is null) return;
            result.Add(current);
            current = null;
        }

        foreach (var line in lines)
        {
            var trimmed = line.Trim();
            var match = InstancePattern.Match(trimmed);
            if (match.Success)
            {
                Flush();
                current = new RawDevice { DeviceId = match.Groups[1].Value.Trim() };
                candidate = null;
                inHardware = false;
                inMatching = false;
                continue;
            }
            if (current is null) continue;

            if (inHardware)
            {
                match = HardwareLinePattern.Match(line);
                if (match.Success)
                {
                    current.HardwareIds.Add(match.Groups[1].Value.Trim());
                    continue;
                }
                inHardware = false;
            }

            if (MatchingDriversPattern.IsMatch(trimmed))
            {
                inMatching = true;
                continue;
            }

            if (inMatching)
            {
                if ((match = CandidateNamePattern.Match(line)).Success)
                {
                    candidate = new RawCandidate { Name = match.Groups[1].Value.Trim() };
                    current.Candidates.Add(candidate);
                }
                else if ((match = CandidateVersionPattern.Match(line)).Success)
                {
                    if (candidate is not null) candidate.VersionRaw = match.Groups[1].Value.Trim();
                }
                else if ((match = CandidateProviderPattern.Match(line)).Success)
                {
                    if (candidate is not null) candidate.Provider = match.Groups[1].Value.Trim();
                }
                else if ((match = CandidateStatusPattern.Match(line)).Success)
                {
                    if (candidate is not null) candidate.Status = match.Groups[1].Value.Trim();
                }
                continue;
            }

            if ((match = DescriptionPattern.Match(trimmed)).Success)
            {
                current.Name = match.Groups[1].Value.Trim();
            }
            else if ((match = ClassNamePattern.Match(trimmed)).Success)
            {
                current.ClassName = match.Groups[1].Value.Trim();
            }
            else if ((match = ClassGuidPattern.Match(trimmed)).Success)
            {
                current.ClassGuid = match.Groups[1].Value.Trim();
            }
            else if ((match = ManufacturerPattern.Match(trimmed)).Success)
            {
                current.Manufacturer = match.Groups[1].Value.Trim();
            }
            else if ((match = StatusPattern.Match(trimmed)).Success)
            {
                current.Status = match.Groups[1].Value.Trim();
            }
            else if ((match = DriverNamePattern.Match(trimmed)).Success)
            {
                current.DriverName = match.Groups[1].Value.Trim();
            }
            else if ((match = HardwareIdsPattern.Match(trimmed)).Success)
            {
                var value = match.Groups[1].Value.Trim();
                if (value.Length > 0) current.HardwareIds.Add(value);
                inHardware = true;
            }
        }

        Flush();
        return result;
    }

    private static List<DriverDeviceInfo> ScanViaWmi()
    {
        var result = new List<DriverDeviceInfo>();
        try
        {
            var pnpMap = new Dictionary<string, ManagementObject>(StringComparer.OrdinalIgnoreCase);
            using (var pnpSearcher = new ManagementObjectSearcher("root\\CIMV2",
                       "SELECT DeviceID, Name, Manufacturer, Status, ConfigManagerErrorCode, HardwareID FROM Win32_PnPEntity"))
            {
                foreach (ManagementObject item in pnpSearcher.Get())
                {
                    var key = item["DeviceID"]?.ToString();
                    if (!string.IsNullOrWhiteSpace(key)) pnpMap[key] = item;
                }
            }

            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            using var searcher = new ManagementObjectSearcher("root\\CIMV2",
                "SELECT DeviceClass, DeviceID, DeviceName, DriverDate, DriverProviderName, DriverVersion, HardwareID, InfName FROM Win32_PnPSignedDriver");

            foreach (ManagementObject item in searcher.Get())
            {
                try
                {
                    var cls = (item["DeviceClass"]?.ToString() ?? "").ToUpperInvariant();
                    if (!AllowedClasses.Contains(cls)) continue;

                    var deviceId = item["DeviceID"]?.ToString()?.Trim() ?? "";
                    var infName = item["InfName"]?.ToString()?.Trim() ?? "";
                    if (deviceId.Length == 0 || infName.Length == 0 || infName.Equals("null", StringComparison.OrdinalIgnoreCase)) continue;

                    pnpMap.TryGetValue(deviceId, out var pnp);
                    var name = item["DeviceName"]?.ToString()?.Trim() ?? "";
                    if (name.Length == 0) name = pnp?["Name"]?.ToString()?.Trim() ?? "";
                    if (name.Length == 0) continue;

                    if (cls == "DISPLAY" && Regex.IsMatch(name, @"(?i)Basic Display|Basic Render")) continue;
                    if (cls == "HIDCLASS" && !Regex.IsMatch(name, @"(?i)mouse|keyboard|logitech|razer|steelseries|corsair|罗技|雷蛇|键盘|鼠标")) continue;
                    if (cls == "NET" && Regex.IsMatch(name, @"(?i)WAN Miniport|TAP-|VPN|Virtual|Hyper-V|Loopback|Kernel Debug")) continue;
                    if (!seen.Add(deviceId + "|" + infName)) continue;

                    var hardware = FirstString(item["HardwareID"]) ?? FirstString(pnp?["HardwareID"]) ?? "";

                    var statusOk = true;
                    var statusText = "正常";
                    if (pnp is not null)
                    {
                        var status = pnp["Status"]?.ToString() ?? "";
                        var errorCode = ToInt(pnp["ConfigManagerErrorCode"]);
                        if (status.Length > 0 && status != "OK" && status != "Unknown")
                        {
                            statusText = status;
                            statusOk = false;
                        }
                        if (errorCode != 0)
                        {
                            statusText = $"错误码 {errorCode}";
                            statusOk = false;
                        }
                    }

                    var date = "";
                    var driverDate = item["DriverDate"];
                    if (driverDate is DateTime dt)
                        date = dt.ToString("yyyy/M/d", CultureInfo.InvariantCulture);

                    var provider = item["DriverProviderName"]?.ToString()?.Trim() ?? "";
                    if (provider.Length == 0) provider = pnp?["Manufacturer"]?.ToString()?.Trim() ?? "";

                    result.Add(new DriverDeviceInfo
                    {
                        Name = name,
                        Class = cls,
                        Category = MapCategory(cls),
                        DeviceId = deviceId,
                        HardwareId = hardware,
                        InfName = infName,
                        Version = item["DriverVersion"]?.ToString()?.Trim() ?? "",
                        Date = date,
                        Provider = provider,
                        StatusText = statusText,
                        StatusOk = statusOk
                    });
                }
                catch
                {
                    // 单台设备读取失败不影响整体枚举
                }
            }

            foreach (var item in pnpMap.Values) item.Dispose();
        }
        catch
        {
            // WMI 不可用时返回已收集到的结果
        }
        return result;
    }

    private static (bool Ok, string Text) MapStatus(string? status)
    {
        var value = (status ?? "").Trim();
        if (value.Length == 0 || value == "Started" || value == "OK" || value == "Unknown") return (true, "正常");
        if (Regex.IsMatch(value, @"(?i)disabled|已禁用")) return (false, "已禁用");
        if (Regex.IsMatch(value, @"(?i)stopped|已停止")) return (false, "已停止");
        if (Regex.IsMatch(value, @"(?i)problem|error|错误")) return (false, "异常");
        return (false, value);
    }

    private static string MapCategory(string cls) => cls.ToUpperInvariant() switch
    {
        "DISPLAY" => "显卡",
        "MEDIA" => "音频",
        "MOUSE" => "外设",
        "KEYBOARD" => "外设",
        "HIDCLASS" => "外设",
        "NET" => "网络",
        "BLUETOOTH" => "网络",
        _ => "其他"
    };

    private static List<DriverDeviceInfo> Sort(List<DriverDeviceInfo> devices)
    {
        var order = new Dictionary<string, int>
        {
            ["显卡"] = 0,
            ["音频"] = 1,
            ["外设"] = 2,
            ["网络"] = 3,
            ["其他"] = 4
        };
        return devices
            .OrderBy(d => order.GetValueOrDefault(d.Category, 4))
            .ThenBy(d => d.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static string? FirstString(object? value)
    {
        try
        {
            if (value is string[] array) return array.FirstOrDefault();
            return value?.ToString();
        }
        catch
        {
            return null;
        }
    }

    private static int ToInt(object? value)
    {
        try { return value is null ? 0 : Convert.ToInt32(value, CultureInfo.InvariantCulture); }
        catch { return 0; }
    }

    private sealed class RawDevice
    {
        public string DeviceId { get; init; } = "";
        public string Name { get; set; } = "";
        public string ClassName { get; set; } = "";
        public string ClassGuid { get; set; } = "";
        public string Manufacturer { get; set; } = "";
        public string Status { get; set; } = "";
        public string DriverName { get; set; } = "";
        public List<string> HardwareIds { get; } = new();
        public List<RawCandidate> Candidates { get; } = new();
    }

    private sealed class RawCandidate
    {
        public string Name { get; init; } = "";
        public string VersionRaw { get; set; } = "";
        public string Provider { get; set; } = "";
        public string Status { get; set; } = "";
    }
}
