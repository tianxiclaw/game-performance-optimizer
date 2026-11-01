using System.Text.RegularExpressions;

namespace GamePerfCenter.Core.Infrastructure;

/// <summary>powercfg 的薄封装。数值解析只依赖 0x 十六进制，不受系统语言影响。</summary>
public static class PowerCfg
{
    public static readonly IReadOnlyDictionary<string, string> Aliases = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
    {
        ["SUB_PCI"] = "501a4d13-42af-4429-9fd1-a8218c268e20",
        ["ASPM"] = "ee12f906-d277-404b-b6da-e5fa1a576df5",
        ["SUB_USB"] = "2a737441-1930-4402-8d77-b2bebba308a3",
        ["USBSEL"] = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226",
        ["SUB_PROC"] = "54533251-82be-4824-96c1-47b60b740d00",
        ["PMIN"] = "893dee8e-2bef-41e0-89c6-b55d0929964c",
        ["PMAX"] = "bc5038f7-23e0-4960-96da-33abaf5935ec",
        ["CPMINCORES"] = "0cc5b647-c1df-4637-891a-dec35c318583",
        ["SUB_WL"] = "19cbb8fa-5279-450e-9fac-8a3d5fedd0c1",
        ["WLSAVE"] = "12bbebe6-58d6-4636-95bb-3217ef867c1a",
        ["ULTIMATE"] = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    };

    private static readonly Regex HexPattern = new(@"0x([0-9A-Fa-f]+)", RegexOptions.Compiled);
    private static readonly Regex GuidPattern = new(
        @"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
        RegexOptions.Compiled);

    public static string Resolve(string keyOrGuid) =>
        Aliases.TryGetValue(keyOrGuid, out var value) ? value : keyOrGuid;

    /// <summary>查询当前 AC/DC 索引。Ok=false 表示 powercfg 查询失败；Ok=true 但值缺失表示该设置项处于隐藏状态。</summary>
    public static (bool Ok, uint? Ac, uint? Dc) QueryValue(string subGroup, string setting)
    {
        var result = Run("/q", "SCHEME_CURRENT", Resolve(subGroup), Resolve(setting));
        if (result.ExitCode != 0) return (false, null, null);

        // 输出的最后两个 0x 值分别是当前交流/直流索引（前面是可能值的最小/最大/增量）。
        var values = new List<uint>();
        foreach (Match match in HexPattern.Matches(result.OutputText))
        {
            if (uint.TryParse(match.Groups[1].Value, System.Globalization.NumberStyles.HexNumber,
                    System.Globalization.CultureInfo.InvariantCulture, out var parsed))
                values.Add(parsed);
        }
        if (values.Count == 0) return (true, null, null);
        if (values.Count == 1) return (true, values[0], null);
        return (true, values[^2], values[^1]);
    }

    public static void SetValue(string subGroup, string setting, uint? ac, uint? dc)
    {
        if (ac is not null)
        {
            var result = Run("/setacvalueindex", "SCHEME_CURRENT", Resolve(subGroup), Resolve(setting),
                ac.Value.ToString(System.Globalization.CultureInfo.InvariantCulture));
            if (result.ExitCode != 0) throw new InvalidOperationException("powercfg /setacvalueindex 失败");
        }
        if (dc is not null)
        {
            var result = Run("/setdcvalueindex", "SCHEME_CURRENT", Resolve(subGroup), Resolve(setting),
                dc.Value.ToString(System.Globalization.CultureInfo.InvariantCulture));
            if (result.ExitCode != 0) throw new InvalidOperationException("powercfg /setdcvalueindex 失败");
        }
        var active = Run("/setactive", "SCHEME_CURRENT");
        if (active.ExitCode != 0) throw new InvalidOperationException("powercfg /setactive 失败");
    }

    public static string? GetActiveScheme()
    {
        var result = Run("/getactivescheme");
        if (result.ExitCode != 0) return null;
        var match = GuidPattern.Match(result.OutputText);
        return match.Success ? match.Value.ToLowerInvariant() : null;
    }

    public static bool SchemeExists(string guid)
    {
        var result = Run("/q", guid);
        return result.ExitCode == 0;
    }

    public static string DuplicateScheme(string guid)
    {
        var result = Run("/duplicatescheme", guid);
        if (result.ExitCode != 0)
            throw new InvalidOperationException("powercfg /duplicatescheme 失败");
        var matches = GuidPattern.Matches(result.OutputText);
        if (matches.Count == 0)
            throw new InvalidOperationException("无法解析复制后的电源方案 GUID");
        return matches[^1].Value.ToLowerInvariant();
    }

    public static void SetActive(string guid)
    {
        var result = Run("/setactive", guid);
        if (result.ExitCode != 0) throw new InvalidOperationException("powercfg /setactive 失败");
    }

    private static ProcessResult Run(params string[] arguments) =>
        PowerShellRunner.Execute("powercfg.exe", arguments, TimeSpan.FromSeconds(30));
}
