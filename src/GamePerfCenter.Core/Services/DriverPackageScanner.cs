using System.Text.RegularExpressions;
using GamePerfCenter.Core.Infrastructure;
using GamePerfCenter.Core.Models;

namespace GamePerfCenter.Core.Services;

/// <summary>扫描本机驱动仓库（pnputil /enum-drivers）。</summary>
public sealed class DriverPackageScanner
{
    private static readonly Regex PublishedPattern = new(@"^\s*(?:Published Name|发布名称)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex OriginalPattern = new(@"^\s*(?:Original Name|原始名称)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex ProviderPattern = new(@"^\s*(?:Provider Name|提供程序名称)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex ClassNamePattern = new(@"^\s*(?:Class Name|类名称)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex ClassGuidPattern = new(@"^\s*(?:Class GUID|类 GUID)\s*:\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex VersionPattern = new(@"^\s*(?:Driver Version|驱动程序版本)\s*:\s*(.+)$", RegexOptions.Compiled);

    private readonly object _lock = new();
    private IReadOnlyList<DriverPackageInfo>? _cache;
    private DateTime _cacheAt = DateTime.MinValue;
    private readonly TimeSpan _cacheTtl;

    public DriverPackageScanner(TimeSpan? cacheTtl = null)
    {
        _cacheTtl = cacheTtl ?? TimeSpan.FromSeconds(30);
    }

    public IReadOnlyList<DriverPackageInfo> Scan(bool force = false)
    {
        lock (_lock)
        {
            if (!force && _cache is not null && DateTime.Now - _cacheAt < _cacheTtl)
                return _cache;
        }

        var result = Parse(PnPUtilRunner.Run("/enum-drivers"));

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

    private static List<DriverPackageInfo> Parse(IReadOnlyList<string> lines)
    {
        var result = new List<DriverPackageInfo>();
        var current = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        void Flush()
        {
            if (current.Count == 0) return;
            var raw = current.GetValueOrDefault("DriverVersionRaw", "");
            var (date, version) = DriverUtils.SplitDriverVersion(raw);
            result.Add(new DriverPackageInfo
            {
                PublishedName = current.GetValueOrDefault("PublishedName", "").Trim(),
                OriginalName = current.GetValueOrDefault("OriginalName", "").Trim(),
                ProviderName = current.GetValueOrDefault("ProviderName", "").Trim(),
                ClassName = current.GetValueOrDefault("ClassName", "").Trim(),
                ClassGuid = current.GetValueOrDefault("ClassGuid", "").Trim(),
                Version = version,
                Date = date,
                DriverVersionRaw = raw
            });
            current.Clear();
        }

        foreach (var line in lines)
        {
            Match match;
            if ((match = PublishedPattern.Match(line)).Success)
            {
                Flush();
                current["PublishedName"] = match.Groups[1].Value;
            }
            else if ((match = OriginalPattern.Match(line)).Success)
            {
                current["OriginalName"] = match.Groups[1].Value;
            }
            else if ((match = ProviderPattern.Match(line)).Success)
            {
                current["ProviderName"] = match.Groups[1].Value;
            }
            else if ((match = ClassNamePattern.Match(line)).Success)
            {
                current["ClassName"] = match.Groups[1].Value;
            }
            else if ((match = ClassGuidPattern.Match(line)).Success)
            {
                current["ClassGuid"] = match.Groups[1].Value;
            }
            else if ((match = VersionPattern.Match(line)).Success)
            {
                current["DriverVersionRaw"] = match.Groups[1].Value;
            }
        }
        Flush();

        return result
            .Where(p => !string.IsNullOrWhiteSpace(p.PublishedName))
            .ToList();
    }
}
