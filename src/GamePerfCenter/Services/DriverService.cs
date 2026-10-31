using System.Diagnostics;
using System.Management;
using System.Text.RegularExpressions;
using Microsoft.Win32;
using GamePerfCenter.Models;

namespace GamePerfCenter.Services;

public sealed class DriverService
{
    private List<DriverDevice>? _cache;
    private DateTime _cacheAt;

    public List<DriverDevice> GetDevices(bool force = false)
    {
        if (!force && _cache is not null && (DateTime.Now - _cacheAt).TotalSeconds < 30)
            return _cache;
        var list = new List<DriverDevice>();
        try
        {
            using var searcher = new ManagementObjectSearcher(
                "root\\CIMV2",
                "SELECT Name, DriverVersion, DriverDate, PNPDeviceID, Status, AdapterRAM FROM Win32_VideoController");
            foreach (ManagementObject obj in searcher.Get())
            {
                var name = obj["Name"]?.ToString()?.Trim() ?? "";
                if (string.IsNullOrEmpty(name)) continue;
                var device = new DriverDevice
                {
                    Name = name,
                    DriverVersion = obj["DriverVersion"]?.ToString(),
                    DriverDate = NormalizeWmiDate(obj["DriverDate"]?.ToString()),
                    PnpId = obj["PNPDeviceID"]?.ToString(),
                    Status = obj["Status"]?.ToString(),
                    AdapterRam = ToLong(obj["AdapterRAM"]),
                    Vendor = DetectVendor(name, obj["PNPDeviceID"]?.ToString() ?? "")
                };
                device.Integrated = IsIntegrated(name, device.Vendor, device.AdapterRam ?? 0);
                list.Add(device);
            }
        }
        catch (Exception ex)
        {
            AppLog.Write("驱动枚举失败: " + ex.Message);
        }

        var tools = DetectVendorTools();
        foreach (var device in list)
        {
            if (device.Vendor is not null && tools.TryGetValue(device.Vendor, out var tool))
            {
                device.ToolName = tool.name;
                device.ToolPath = tool.path;
            }
        }

        _cache = list;
        _cacheAt = DateTime.Now;
        return list;
    }

    public static string VendorDisplayName(string? vendor) => vendor switch
    {
        "NVIDIA" => "NVIDIA",
        "AMD" => "AMD",
        "INTEL" => "Intel",
        "QUALCOMM" => "Qualcomm",
        "MICROSOFT" => "Microsoft",
        _ => "其他"
    };

    public static string VendorDownloadUrl(string? vendor) => vendor switch
    {
        "NVIDIA" => "https://www.nvidia.cn/geforce/drivers/",
        "AMD" => "https://www.amd.com/zh-cn/support/download/drivers.html",
        "INTEL" => "https://www.intel.cn/content/www/cn/zh/support/detect.html",
        _ => "https://learn.microsoft.com/windows-hardware/drivers/"
    };

    public void OpenVendorTool(DriverDevice device)
    {
        try
        {
            if (!string.IsNullOrEmpty(device.ToolPath) && File.Exists(device.ToolPath))
            {
                Process.Start(new ProcessStartInfo { FileName = device.ToolPath, UseShellExecute = true });
                return;
            }
            Process.Start(new ProcessStartInfo
            {
                FileName = VendorDownloadUrl(device.Vendor),
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            AppLog.Write("打开厂商工具失败: " + ex.Message);
        }
    }

    private static Dictionary<string, (string name, string path)> DetectVendorTools()
    {
        var result = new Dictionary<string, (string, string)>(StringComparer.OrdinalIgnoreCase);

        var known = new (string vendor, string name, string path)[]
        {
            ("NVIDIA", "NVIDIA App", @"C:\Program Files\NVIDIA Corporation\NVIDIA App\CEF\NVIDIA App.exe"),
            ("NVIDIA", "GeForce Experience", @"C:\Program Files\NVIDIA Corporation\NVIDIA GeForce Experience\NVIDIA GeForce Experience.exe"),
            ("NVIDIA", "NVIDIA 控制面板", @"C:\Windows\System32\nvcplui.exe"),
            ("AMD", "AMD Software", @"C:\Program Files\AMD\CNext\CNext\RadeonSoftware.exe"),
            ("AMD", "AMD Software", @"C:\Program Files\AMD\CNext\CNext\AMDRSServ.exe"),
            ("INTEL", "Intel Arc Control", @"C:\Program Files\Intel\Arc Control\ArcControlAssist.exe"),
            ("INTEL", "Intel 显卡控制中心", @"C:\Program Files\Intel\Intel Graphics Command Center\IntelGraphicsCommandCenter.exe"),
            ("INTEL", "Intel 驱动支持助手", @"C:\Program Files\Intel\Driver and Support Assistant\DSATray.exe"),
            ("INTEL", "Intel 驱动支持助手", @"C:\Program Files\Intel\Driver and Support Assistant\DSA.exe")
        };
        foreach (var item in known)
        {
            if (File.Exists(item.path) && !result.ContainsKey(item.vendor))
                result[item.vendor] = (item.name, item.path);
        }

        foreach (var entry in EnumerateUninstallEntries())
        {
            var display = entry.display;
            if (string.IsNullOrEmpty(display)) continue;
            var lowered = display.ToLowerInvariant();
            string? vendor = null;
            string? friendly = null;
            if (lowered.Contains("nvidia app")) { vendor = "NVIDIA"; friendly = "NVIDIA App"; }
            else if (lowered.Contains("geforce experience")) { vendor = "NVIDIA"; friendly = "GeForce Experience"; }
            else if (lowered.Contains("amd software") || lowered.Contains("radeon software")) { vendor = "AMD"; friendly = "AMD Software"; }
            else if (lowered.Contains("intel arc control")) { vendor = "INTEL"; friendly = "Intel Arc Control"; }
            else if (lowered.Contains("intel graphics command")) { vendor = "INTEL"; friendly = "Intel 显卡控制中心"; }
            else if (lowered.Contains("driver & support assistant") || lowered.Contains("driver and support assistant"))
            { vendor = "INTEL"; friendly = "Intel 驱动支持助手"; }
            if (vendor is null || result.ContainsKey(vendor)) continue;

            var path = ResolveExecutable(entry.icon, entry.install);
            if (!string.IsNullOrEmpty(path) && File.Exists(path))
                result[vendor] = (friendly ?? display, path);
        }

        return result;
    }

    private static IEnumerable<(string? display, string? icon, string? install)> EnumerateUninstallEntries()
    {
        var roots = new (RegistryKey root, string path)[]
        {
            (Registry.LocalMachine, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
            (Registry.LocalMachine, @"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
            (Registry.CurrentUser, @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")
        };
        foreach (var (root, path) in roots)
        {
            RegistryKey? key = null;
            try { key = root.OpenSubKey(path); } catch { }
            if (key is null) continue;
            using (key)
            {
                foreach (var subName in key.GetSubKeyNames())
                {
                    RegistryKey? sub = null;
                    try { sub = key.OpenSubKey(subName); } catch { }
                    if (sub is null) continue;
                    using (sub)
                    {
                        yield return (
                            sub.GetValue("DisplayName")?.ToString(),
                            sub.GetValue("DisplayIcon")?.ToString(),
                            sub.GetValue("InstallLocation")?.ToString()
                        );
                    }
                }
            }
        }
    }

    private static string? ResolveExecutable(string? icon, string? install)
    {
        if (!string.IsNullOrWhiteSpace(icon))
        {
            var path = icon.Trim();
            if (path.StartsWith('"'))
            {
                var end = path.IndexOf('"', 1);
                if (end > 0) path = path.Substring(1, end - 1);
            }
            else
            {
                var comma = path.LastIndexOf(',');
                if (comma > 0) path = path.Substring(0, comma);
                path = path.Trim();
            }
            if (path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) && File.Exists(path))
                return path;
        }
        if (!string.IsNullOrWhiteSpace(install) && Directory.Exists(install))
        {
            foreach (var pattern in new[] { "*.exe" })
            {
                try
                {
                    var candidates = Directory.GetFiles(install, pattern, SearchOption.TopDirectoryOnly);
                    var preferred = candidates.FirstOrDefault(f =>
                        Path.GetFileName(f).Contains("NVIDIA", StringComparison.OrdinalIgnoreCase) ||
                        Path.GetFileName(f).Contains("Radeon", StringComparison.OrdinalIgnoreCase) ||
                        Path.GetFileName(f).Contains("Arc", StringComparison.OrdinalIgnoreCase) ||
                        Path.GetFileName(f).Contains("DSA", StringComparison.OrdinalIgnoreCase));
                    if (preferred is not null) return preferred;
                }
                catch { }
            }
        }
        return null;
    }

    private static string DetectVendor(string name, string pnp)
    {
        var all = (name + " " + pnp).ToUpperInvariant();
        if (all.Contains("NVIDIA")) return "NVIDIA";
        if (all.Contains("AMD") || all.Contains("RADEON") || all.Contains("ATI ")) return "AMD";
        if (all.Contains("INTEL")) return "INTEL";
        if (all.Contains("QUALCOMM") || all.Contains("ADRENO")) return "QUALCOMM";
        if (all.Contains("MICROSOFT")) return "MICROSOFT";
        return "OTHER";
    }

    private static bool IsIntegrated(string name, string vendor, long vram)
    {
        var n = name.ToLowerInvariant();
        if (n.Contains("microsoft basic") || n.Contains("basic display")) return true;
        if (n.Contains("virtual") || n.Contains("vmware") || n.Contains("virtualbox") || n.Contains("svga")) return true;
        if (vendor == "NVIDIA") return false;
        if (vendor == "QUALCOMM") return true;
        if (vendor == "AMD")
        {
            if (n.Contains("radeon rx") || n.Contains("radeon pro") || n.Contains("firepro")) return false;
            return n.Contains("radeon graphics") || n.Contains("vega") || vram < 2L * 1024 * 1024 * 1024;
        }
        if (vendor == "INTEL")
        {
            if (n.Contains("arc(tm) a") || n.Contains("arc a") || n.Contains("arc(tm) b") || n.Contains("arc b"))
                return false;
            return n.Contains("uhd") || n.Contains("iris") || n.Contains("hd graphics") ||
                   n.Contains("graphics") || vram < 2L * 1024 * 1024 * 1024;
        }
        return vram < 2L * 1024 * 1024 * 1024;
    }

    private static string? NormalizeWmiDate(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var m = Regex.Match(raw, @"^(\d{4})(\d{2})(\d{2})");
        if (m.Success) return $"{m.Groups[1].Value}-{m.Groups[2].Value}-{m.Groups[3].Value}";
        return raw;
    }

    private static long? ToLong(object? value)
    {
        try { return value is null ? null : Convert.ToInt64(value); }
        catch { return null; }
    }
}
