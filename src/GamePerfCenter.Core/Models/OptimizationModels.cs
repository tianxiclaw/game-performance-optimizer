using System.Text.Json;
using System.Text.Json.Serialization;

namespace GamePerfCenter.Core.Models;

/// <summary>
/// 优化项目录。检测与硬件分支由 PowerShell 引擎维护，执行/备份/还原统一由 Core 完成。
/// </summary>
public sealed class OptimizationCatalog
{
    public string? Version { get; set; }
    public string? Time { get; set; }
    public OptimizationContext Context { get; set; } = new();
    public List<OptimizationItem> Items { get; set; } = new();
}

public sealed class OptimizationContext
{
    public string? Machine { get; set; }
    public bool IsLaptop { get; set; }
    public bool HasDedicatedGpu { get; set; }
    public bool HasIntegratedGpu { get; set; }
    public bool HasWifi { get; set; }
    public bool IsIntel { get; set; }
    public bool IsCombo { get; set; }
    public int OsBuild { get; set; }
    public string? UserSid { get; set; }
    /// <summary>Intel 核显的注册表实例子键（intelpnp / intelftc / inteldps 使用）。</summary>
    public string? IntelKey { get; set; }
    /// <summary>启动者 SID 对应的 UserGpuPreferences 路径。</summary>
    public string? GpuPreferencesPath { get; set; }
}

/// <summary>单个优化项的完整定义，字段名与 PowerShell 的 $O 保持一致。</summary>
public sealed class OptimizationItem
{
    public string Id { get; set; } = "";
    public string? Cat { get; set; }
    public string? Name { get; set; }
    public string? Kind { get; set; }

    [JsonPropertyName("D")]
    public string? Desc { get; set; }

    [JsonPropertyName("TL")]
    public string? TargetLabel { get; set; }

    [JsonPropertyName("R")]
    public string? Risk { get; set; }

    [JsonPropertyName("E")]
    public bool DefaultEnabled { get; set; }

    public string? Dep { get; set; }

    [JsonPropertyName("DH")]
    public string? DepHint { get; set; }

    // ── 注册表 ──
    public string? P { get; set; }
    public string? V { get; set; }
    public string? V2 { get; set; }
    public string? VT { get; set; }

    // ── 电源 / 显卡 / 网卡 ──
    public string? SK { get; set; }
    public string? SE { get; set; }
    public string? TG { get; set; }
    public string? A { get; set; }
    public string? K { get; set; }
    public string? DID { get; set; }
    public string? DN { get; set; }
    public List<string> SV { get; set; } = new();

    // ── 数值字段（T/T2 在 PowerShell 中可能是数字或字符串） ──
    [JsonPropertyName("T")]
    public JsonElement? TargetValue { get; set; }

    [JsonPropertyName("T2")]
    public JsonElement? TargetValue2 { get; set; }

    public long? AC { get; set; }
    public long? DC { get; set; }
    public uint? BM { get; set; }
    public string? BL { get; set; }
    public int? RR { get; set; }
    public int? MR { get; set; }
    public int? W { get; set; }
    public int? H { get; set; }

    public string? TargetText => JsonValue.ToString(TargetValue);
    public uint? TargetUInt32 => JsonValue.ToUInt32(TargetValue);
    public int? TargetInt32 => JsonValue.ToInt32(TargetValue);
}

public sealed class OptimizationApplyOptions
{
    public bool DryRun { get; init; }
    public bool NoBackup { get; init; }
    public bool RestorePoint { get; init; }
    public bool NoRegSnapshot { get; init; }
    public string? BackupDirectory { get; init; }
}

public sealed class OptimizationPreview
{
    public string? Id { get; set; }
    public string? Name { get; set; }
    public string? Cat { get; set; }
    public string? Kind { get; set; }
    public string? Current { get; set; }
    public string? Target { get; set; }
    public string? Risk { get; set; }
    public bool NeedsReboot { get; set; }
}

public sealed class OptimizationError
{
    public string? Id { get; set; }
    public string? Name { get; set; }
    public string? Message { get; set; }
    public string? Stage { get; set; }
}

public sealed class OptimizationApplyResult
{
    public int Ok { get; set; }
    public int Fail { get; set; }
    public List<OptimizationPreview> Preview { get; set; } = new();
    public List<OptimizationError> Errors { get; set; } = new();
    public string? Backup { get; set; }
    public string? RegDir { get; set; }
    public bool RestorePointCreated { get; set; }
    public string? RestorePointMessage { get; set; }
    public bool DryRun { get; set; }
    public List<OptimizationBackupRecord> Records { get; set; } = new();
}

public sealed class OptimizationRestoreResult
{
    public int Ok { get; set; }
    public int Fail { get; set; }
    public List<OptimizationError> Errors { get; set; } = new();
    public string? File { get; set; }
    public string? Version { get; set; }
    public int Records { get; set; }
    public bool DryRun { get; set; }
}

public sealed class OptimizationRestoreAllResult
{
    public int Ok { get; set; }
    public int Fail { get; set; }
    public int Files { get; set; }
    public List<OptimizationError> Errors { get; set; } = new();
    public List<OptimizationRestoreFileResult> Report { get; set; } = new();
}

public sealed class OptimizationRestoreFileResult
{
    public string? File { get; set; }
    public int Ok { get; set; }
    public int Fail { get; set; }
}

public sealed class OptimizationBackupFile
{
    public string? Time { get; set; }
    public string? Version { get; set; }
    public List<OptimizationBackupRecord> Records { get; set; } = new();
}

/// <summary>
/// 备份记录。字段与 PowerShell 引擎的备份 JSON 兼容，并兼容 v4.7 之前的旧字段名。
/// </summary>
public sealed class OptimizationBackupRecord
{
    public string? Id { get; set; }
    public string? Kind { get; set; }

    public string? P { get; set; }
    public string? V { get; set; }
    public string? V2 { get; set; }
    public string? VT { get; set; }
    public JsonElement? OV { get; set; }
    public JsonElement? OV2 { get; set; }
    public bool? OE { get; set; }
    public bool? OE2 { get; set; }

    // 旧字段名兼容
    public string? Path { get; set; }
    public string? Name { get; set; }
    public string? Name2 { get; set; }
    public string? SubKey { get; set; }
    public string? Adapter { get; set; }
    public string? Keyword { get; set; }
    public string? RegPath { get; set; }
    public JsonElement? Services { get; set; }
    public JsonElement? SV { get; set; }

    // 电源 / 方案
    public string? Sub { get; set; }
    public string? Set { get; set; }
    public JsonElement? OAC { get; set; }
    public JsonElement? ODC { get; set; }
    public string? OG { get; set; }
    public string? NG { get; set; }
    public bool? UC { get; set; }

    // 显示
    public string? DID { get; set; }
    public string? DN { get; set; }
    public JsonElement? RR { get; set; }
    public JsonElement? MR { get; set; }
    public JsonElement? W { get; set; }
    public JsonElement? H { get; set; }

    // GPU 首选项
    public string? Exe { get; set; }

    // 位掩码
    public uint? BM { get; set; }
    public uint? AB { get; set; }
    public string? SK { get; set; }

    // 网卡
    public string? A { get; set; }
    public string? K { get; set; }
    /// <summary>nicpower 定位到的网卡注册表子键。</summary>
    public string? R { get; set; }

    [JsonExtensionData]
    public Dictionary<string, JsonElement>? Extra { get; set; }

    public string? GetString(params string[] names)
    {
        foreach (var name in names)
        {
            var value = name switch
            {
                "P" => P,
                "V" => V,
                "V2" => V2,
                "VT" => VT,
                "Path" => Path,
                "Name" => Name,
                "Name2" => Name2,
                "SubKey" => SubKey,
                "Adapter" => Adapter,
                "Keyword" => Keyword,
                "RegPath" => RegPath,
                "Sub" => Sub,
                "Set" => Set,
                "OG" => OG,
                "NG" => NG,
                "DID" => DID,
                "DN" => DN,
                "Exe" => Exe,
                "SK" => SK,
                "A" => A,
                "K" => K,
                "R" => R,
                _ => null
            };
            if (!string.IsNullOrWhiteSpace(value)) return value;
            if (Extra is not null && Extra.TryGetValue(name, out var extra) &&
                extra.ValueKind == JsonValueKind.String)
                return extra.GetString();
        }
        return null;
    }

    public JsonElement? GetElement(params string[] names)
    {
        foreach (var name in names)
        {
            var value = name switch
            {
                "OV" => OV,
                "OV2" => OV2,
                "OAC" => OAC,
                "ODC" => ODC,
                "RR" => RR,
                "MR" => MR,
                "W" => W,
                "H" => H,
                "SV" => SV,
                "Services" => Services,
                _ => null
            };
            if (value is not null) return value;
            if (Extra is not null && Extra.TryGetValue(name, out var extra)) return extra;
        }
        return null;
    }
}

public sealed class OptimizationBackupInfo
{
    public string? Name { get; set; }
    public string? Path { get; set; }
    public string? Time { get; set; }
    public long Size { get; set; }
    public int Records { get; set; }
}

public sealed class OptimizationPendingState
{
    public string? Time { get; set; }
    public List<OptimizationPendingItem> Items { get; set; } = new();
    public List<OptimizationError> Errors { get; set; } = new();
    public string? Backup { get; set; }
    public bool Checked { get; set; }
    public string? Result { get; set; }
}

public sealed class OptimizationPendingItem
{
    public string? Id { get; set; }
    public string? Name { get; set; }
}

public sealed class OptimizationPendingReboot
{
    public bool Pending { get; set; }
    public List<string> Reasons { get; set; } = new();
    public int Ignored { get; set; }
}

/// <summary>JsonElement 的安全转换助手，兼容 PowerShell 输出的数字/字符串/布尔。</summary>
public static class JsonValue
{
    public static string? ToString(JsonElement? element)
    {
        if (element is null) return null;
        var value = element.Value;
        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString(),
            JsonValueKind.Number => value.GetRawText(),
            JsonValueKind.True => "True",
            JsonValueKind.False => "False",
            JsonValueKind.Array => string.Join(" ", value.EnumerateArray().Select(v =>
                v.ValueKind == JsonValueKind.String ? v.GetString() : v.GetRawText())),
            JsonValueKind.Null or JsonValueKind.Undefined => null,
            _ => value.GetRawText()
        };
    }

    public static int? ToInt32(JsonElement? element)
    {
        if (element is null) return null;
        var value = element.Value;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var number)) return number;
        var text = ToString(element);
        return int.TryParse(text, out var parsed) ? parsed : null;
    }

    public static uint? ToUInt32(JsonElement? element)
    {
        if (element is null) return null;
        var value = element.Value;
        if (value.ValueKind == JsonValueKind.Number)
        {
            if (value.TryGetUInt32(out var unsigned)) return unsigned;
            if (value.TryGetInt64(out var signed)) return unchecked((uint)signed);
        }
        var text = ToString(element);
        if (uint.TryParse(text, out var parsed)) return parsed;
        if (int.TryParse(text, out var signed32)) return unchecked((uint)signed32);
        return null;
    }

    public static bool? ToBool(JsonElement? element)
    {
        if (element is null) return null;
        var value = element.Value;
        if (value.ValueKind is JsonValueKind.True or JsonValueKind.False) return value.GetBoolean();
        var text = ToString(element);
        if (bool.TryParse(text, out var parsed)) return parsed;
        if (text == "1") return true;
        if (text == "0") return false;
        return null;
    }
}
