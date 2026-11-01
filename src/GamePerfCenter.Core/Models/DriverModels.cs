namespace GamePerfCenter.Core.Models;

/// <summary>单个 INF 文件解析结果。</summary>
public sealed class InfMetadata
{
    public string InfName { get; init; } = "";
    public string Version { get; init; } = "";
    public string Date { get; init; } = "";
    public string Provider { get; init; } = "";
    public string ClassName { get; init; } = "";
    public IReadOnlyList<string> HardwareIds { get; init; } = Array.Empty<string>();
}

/// <summary>驱动仓库中的一个驱动包（pnputil /enum-drivers）。</summary>
public sealed class DriverPackageInfo
{
    public string PublishedName { get; init; } = "";
    public string OriginalName { get; init; } = "";
    public string ProviderName { get; init; } = "";
    public string ClassName { get; init; } = "";
    public string ClassGuid { get; init; } = "";
    public string Version { get; init; } = "";
    public string Date { get; init; } = "";
    public string DriverVersionRaw { get; init; } = "";
}

/// <summary>与某台设备匹配的本地驱动包。</summary>
public sealed class DriverPackageMatch
{
    public string PublishedName { get; init; } = "";
    public string OriginalName { get; init; } = "";
    public string ClassName { get; init; } = "";
    public string Version { get; init; } = "";

    /// <summary>驱动包日期，统一格式 yyyy/M/d。</summary>
    public string Date { get; init; } = "";
    public string Provider { get; init; } = "";
    public bool InUse { get; init; }

    /// <summary>与设备当前驱动版本比较：-1 旧、0 相同、1 新。</summary>
    public int Compare { get; init; }
}

/// <summary>Windows Update 提供的驱动更新。</summary>
public sealed class DriverUpdateInfo
{
    public string Id { get; init; } = "";
    public string Title { get; init; } = "";
    public string ClassName { get; init; } = "";
    public string HardwareId { get; init; } = "";
    public string Date { get; init; } = "";
    public string Version { get; init; } = "";
    public bool Hidden { get; init; }
}

/// <summary>一台已连接设备及其驱动核对结果。</summary>
public sealed class DriverDeviceInfo
{
    public string Name { get; set; } = "";
    public string Class { get; set; } = "";
    public string Category { get; set; } = "其他";
    public string DeviceId { get; set; } = "";
    public string HardwareId { get; set; } = "";
    public string InfName { get; set; } = "";
    public string Version { get; set; } = "";

    /// <summary>驱动日期，统一格式 yyyy/M/d。</summary>
    public string Date { get; set; } = "";
    public string Provider { get; set; } = "";
    public string StatusText { get; set; } = "正常";
    public bool StatusOk { get; set; } = true;

    public List<DriverPackageMatch> Packages { get; set; } = new();
    public List<DriverUpdateInfo> Updates { get; set; } = new();
    public List<string> Flags { get; set; } = new();

    public bool HasUpdate { get; set; }
    public int UpdateCount { get; set; }
    public int OldCount { get; set; }
    public bool Enriched { get; set; }
}

/// <summary>驱动清单汇总。</summary>
public sealed class DriverSummary
{
    public int DeviceCount { get; init; }
    public int UpdateCount { get; init; }
    public int IssueCount { get; init; }
    public int OldPackageCount { get; init; }
    public int PackageCount { get; init; }
    public bool WuChecked { get; init; }
    public IReadOnlyDictionary<string, int> CategoryCounts { get; init; } =
        new Dictionary<string, int>();
}

/// <summary>一次完整的驱动扫描结果。</summary>
public sealed class DriverInventory
{
    public IReadOnlyList<DriverDeviceInfo> Devices { get; init; } = Array.Empty<DriverDeviceInfo>();
    public DateTime ScannedAt { get; init; } = DateTime.Now;
    public bool WuChecked { get; init; }

    /// <summary>Windows Update 检测失败时的原因；成功或未检测时为 null。</summary>
    public string? UpdateError { get; init; }
    public DriverSummary Summary { get; init; } = new();
}
