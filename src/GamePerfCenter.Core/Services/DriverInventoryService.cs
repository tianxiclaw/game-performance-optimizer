using GamePerfCenter.Core.Infrastructure;
using GamePerfCenter.Core.Models;

namespace GamePerfCenter.Core.Services;

/// <summary>
/// 把设备、驱动仓库、INF 元数据与 Windows Update 结果合成一份驱动清单。
/// GUI 与 CLI 共用同一套判定逻辑，避免两端出现“设备数/可更新数”不一致。
/// </summary>
public sealed class DriverInventoryService
{
    private static readonly string[] CategoryOrder = { "全部", "显卡", "音频", "外设", "网络", "其他" };

    private readonly object _scanLock = new();
    private readonly object _cacheLock = new();
    private DriverInventory? _cache;
    private DateTime _cacheAt = DateTime.MinValue;
    private readonly TimeSpan _cacheTtl;

    public DriverDeviceScanner DeviceScanner { get; }
    public DriverPackageScanner PackageScanner { get; }
    public InfMetadataReader InfReader { get; }
    public WindowsUpdateDriverScanner UpdateScanner { get; }

    public DriverInventoryService(
        DriverDeviceScanner? deviceScanner = null,
        DriverPackageScanner? packageScanner = null,
        InfMetadataReader? infReader = null,
        WindowsUpdateDriverScanner? updateScanner = null,
        TimeSpan? cacheTtl = null)
    {
        DeviceScanner = deviceScanner ?? new DriverDeviceScanner();
        PackageScanner = packageScanner ?? new DriverPackageScanner();
        InfReader = infReader ?? new InfMetadataReader();
        UpdateScanner = updateScanner ?? new WindowsUpdateDriverScanner();
        _cacheTtl = cacheTtl ?? TimeSpan.FromSeconds(30);
    }

    /// <summary>
    /// 扫描驱动清单。<paramref name="includeUpdates"/> 为 false 时只做本地扫描，
    /// 不访问 Windows Update，适合启动阶段快速出结果。
    /// </summary>
    public DriverInventory Scan(bool includeUpdates = false, bool force = false)
    {
        lock (_cacheLock)
        {
            if (!force && _cache is not null && DateTime.Now - _cacheAt < _cacheTtl &&
                (!includeUpdates || _cache.WuChecked))
                return _cache;
        }

        lock (_scanLock)
        {
            var devices = DeviceScanner.Scan(force).ToList();
            var packages = PackageScanner.Scan(force);

            IReadOnlyList<DriverUpdateInfo>? updates = null;
            string? updateError = null;
            if (includeUpdates)
            {
                try { updates = UpdateScanner.Scan(force); }
                catch (Exception ex) { updateError = ex.Message; }
            }

            foreach (var device in devices) Enrich(device, packages, updates);

            var inventory = new DriverInventory
            {
                Devices = devices,
                ScannedAt = DateTime.Now,
                WuChecked = includeUpdates && updates is not null,
                UpdateError = updateError,
                Summary = BuildSummary(devices, packages, includeUpdates && updates is not null)
            };

            lock (_cacheLock)
            {
                _cache = inventory;
                _cacheAt = DateTime.Now;
            }
            return inventory;
        }
    }

    public void ClearCache()
    {
        DeviceScanner.ClearCache();
        PackageScanner.ClearCache();
        InfReader.ClearCache();
        UpdateScanner.ClearCache();
        lock (_cacheLock)
        {
            _cache = null;
            _cacheAt = DateTime.MinValue;
        }
    }

    private void Enrich(
        DriverDeviceInfo device,
        IReadOnlyList<DriverPackageInfo> packages,
        IReadOnlyList<DriverUpdateInfo>? updates)
    {
        device.Packages = new List<DriverPackageMatch>();
        device.Updates = new List<DriverUpdateInfo>();
        device.Flags = new List<string>();
        device.UpdateCount = 0;
        device.OldCount = 0;
        device.HasUpdate = false;
        device.Enriched = false;

        var deviceClass = device.Class ?? "";
        var currentVersion = device.Version ?? "";
        var matches = new List<DriverPackageMatch>();

        foreach (var package in packages)
        {
            var packageClass = package.ClassName ?? "";
            if (!packageClass.Equals(deviceClass, StringComparison.OrdinalIgnoreCase) &&
                !packageClass.Equals("Extension", StringComparison.OrdinalIgnoreCase))
                continue;

            var meta = InfReader.Read(package.PublishedName);
            if (meta is null) continue;

            var matched = meta.HardwareIds.Any(infHardwareId =>
                DriverUtils.HardwareMatches(device.HardwareId, infHardwareId));
            if (!matched) continue;

            var version = string.IsNullOrWhiteSpace(meta.Version) ? package.Version : meta.Version;
            var date = string.IsNullOrWhiteSpace(meta.Date) ? package.Date : meta.Date;
            var inUse = string.Equals(package.PublishedName, device.InfName, StringComparison.OrdinalIgnoreCase);
            var compare = !string.IsNullOrWhiteSpace(version) && !string.IsNullOrWhiteSpace(currentVersion)
                ? DriverUtils.CompareVersion(version, currentVersion)
                : 0;

            matches.Add(new DriverPackageMatch
            {
                PublishedName = package.PublishedName,
                OriginalName = package.OriginalName,
                ClassName = packageClass,
                Version = version,
                Date = date,
                Provider = meta.Provider,
                InUse = inUse,
                Compare = compare
            });
        }

        device.Packages = matches
            .OrderBy(m => m.InUse ? 0 : 1)
            .ThenBy(m => m.PublishedName, StringComparer.OrdinalIgnoreCase)
            .ToList();

        var flags = new List<string>();
        if (!device.StatusOk) flags.Add("设备状态异常");

        var oldPackages = device.Packages
            .Where(m => m.Compare < 0 && !m.InUse)
            .ToList();
        if (oldPackages.Count > 0) flags.Add($"仓库中有 {oldPackages.Count} 个旧版本包");

        var extensionMismatch = device.Packages.Count(m =>
            m.ClassName.Equals("Extension", StringComparison.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(m.Version) &&
            !string.IsNullOrWhiteSpace(currentVersion) &&
            DriverUtils.CompareVersion(m.Version, currentVersion) != 0);
        if (extensionMismatch > 0) flags.Add("扩展包版本与主驱动不一致");

        var deviceUpdates = updates is null
            ? new List<DriverUpdateInfo>()
            : updates.Where(u => DriverUtils.HardwareMatches(device.HardwareId, u.HardwareId)).ToList();
        device.Updates = deviceUpdates;

        var updateCount = deviceUpdates.Count(u =>
            !u.Hidden &&
            !string.IsNullOrWhiteSpace(u.Version) &&
            DriverUtils.CompareVersion(u.Version, currentVersion) > 0);
        device.UpdateCount = updateCount;
        if (updateCount > 0) flags.Add($"有 {updateCount} 个可用更新");

        device.HasUpdate = updateCount > 0;
        device.OldCount = oldPackages.Count;
        device.Flags = flags;
        device.Enriched = true;
    }

    private static DriverSummary BuildSummary(
        IReadOnlyList<DriverDeviceInfo> devices,
        IReadOnlyList<DriverPackageInfo> packages,
        bool wuChecked)
    {
        var counts = new Dictionary<string, int>(StringComparer.Ordinal)
        {
            ["全部"] = devices.Count
        };
        foreach (var category in CategoryOrder)
        {
            if (category == "全部") continue;
            counts[category] = devices.Count(d => d.Category == category);
        }

        return new DriverSummary
        {
            DeviceCount = devices.Count,
            UpdateCount = devices.Sum(d => d.UpdateCount),
            IssueCount = devices.Count(d => !d.StatusOk || d.OldCount > 0),
            OldPackageCount = devices.Sum(d => d.OldCount),
            PackageCount = packages.Count,
            WuChecked = wuChecked,
            CategoryCounts = counts
        };
    }
}
