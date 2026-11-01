using System.Globalization;
using System.Text.RegularExpressions;

namespace GamePerfCenter.Core.Infrastructure;

public static class DriverUtils
{
    private static readonly Regex RevPattern = new(@"&REV_[0-9A-Fa-f]+", RegexOptions.Compiled);
    private static readonly Regex VersionPattern = new(@"\d+(?:\.\d+){0,3}", RegexOptions.Compiled);

    /// <summary>去掉 REV 后缀并统一大写，用于比较硬件 ID 前缀。</summary>
    public static string HardwareBase(string? id)
    {
        if (string.IsNullOrWhiteSpace(id)) return "";
        return RevPattern.Replace(id, "").Trim().ToUpperInvariant();
    }

    public static int[] VersionParts(string? version)
    {
        if (string.IsNullOrWhiteSpace(version)) return Array.Empty<int>();
        var match = VersionPattern.Match(version);
        if (!match.Success) return Array.Empty<int>();
        var parts = match.Value.Split('.');
        var values = new int[parts.Length];
        for (var i = 0; i < parts.Length; i++)
        {
            if (!int.TryParse(parts[i], NumberStyles.Integer, CultureInfo.InvariantCulture, out values[i]))
                values[i] = 0;
        }
        return values;
    }

    /// <summary>逐段比较驱动版本号，缺失段按 0 处理。</summary>
    public static int CompareVersion(string? left, string? right)
    {
        var a = VersionParts(left);
        var b = VersionParts(right);
        var count = Math.Max(a.Length, b.Length);
        for (var i = 0; i < count; i++)
        {
            var x = i < a.Length ? a[i] : 0;
            var y = i < b.Length ? b[i] : 0;
            if (x < y) return -1;
            if (x > y) return 1;
        }
        return 0;
    }

    /// <summary>把 pnputil 的 "MM/dd/yyyy version" 拆成日期与版本。</summary>
    public static (string Date, string Version) SplitDriverVersion(string? raw)
    {
        raw = (raw ?? "").Trim();
        if (raw.Length == 0) return ("", "");
        var match = Regex.Match(raw, @"^(?<date>.*?)\s+(?<ver>\d+(?:\.\d+){1,3})$");
        if (!match.Success) return ("", raw);
        return (NormalizeDate(match.Groups["date"].Value.Trim()), match.Groups["ver"].Value.Trim());
    }

    public static string NormalizeDate(string? raw)
    {
        raw = (raw ?? "").Trim();
        if (raw.Length == 0) return "";
        var formats = new[] { "MM/dd/yyyy", "M/d/yyyy", "yyyy/M/d", "yyyy-M-d", "yyyy/MM/dd", "yyyy-MM-dd" };
        if (DateTime.TryParseExact(raw, formats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var exact))
            return exact.ToString("yyyy/M/d", CultureInfo.InvariantCulture);
        if (DateTime.TryParse(raw, CultureInfo.CurrentCulture, DateTimeStyles.None, out var current))
            return current.ToString("yyyy/M/d", CultureInfo.InvariantCulture);
        if (DateTime.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.None, out var invariant))
            return invariant.ToString("yyyy/M/d", CultureInfo.InvariantCulture);
        return raw;
    }

    public static bool HardwareMatches(string? deviceHardwareId, string? candidateHardwareId)
    {
        var device = HardwareBase(deviceHardwareId);
        var candidate = HardwareBase(candidateHardwareId);
        if (device.Length == 0 || candidate.Length == 0) return false;
        return device == candidate ||
               device.StartsWith(candidate, StringComparison.Ordinal) ||
               candidate.StartsWith(device, StringComparison.Ordinal);
    }
}
