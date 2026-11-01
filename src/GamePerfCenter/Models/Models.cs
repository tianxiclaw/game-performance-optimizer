using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace GamePerfCenter.Models;

public sealed class SnapshotInfo
{
    public string? Version { get; set; }
    public string? Time { get; set; }
    public string? Machine { get; set; }
    public bool IsLaptop { get; set; }
    public bool? OnAC { get; set; }
    public string? PowerConfidence { get; set; }
    public List<GpuInfo> Gpus { get; set; } = new();
    public List<DisplayInfo> Displays { get; set; } = new();
    public List<string> Nics { get; set; } = new();
    public List<ItemInfo> Items { get; set; } = new();
    public SummaryInfo Summary { get; set; } = new();
    public PendingRebootInfo? PendingReboot { get; set; }
    public PendingStateInfo? LastApply { get; set; }
    public List<DiagEntry> Diagnostics { get; set; } = new();
}

public sealed class GpuInfo
{
    public string? Name { get; set; }
    public string? Vendor { get; set; }
    public bool Integrated { get; set; }
    public bool Dedicated { get; set; }
    public bool Basic { get; set; }
    public bool Virtual { get; set; }
    public long? VRAM { get; set; }
    public string? DriverKey { get; set; }
}

public sealed class DisplayInfo
{
    public string? Device { get; set; }
    public string? Name { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
    public int Refresh { get; set; }
    public int MaxRefresh { get; set; }
}

public sealed class ItemInfo : INotifyPropertyChanged
{
    private bool _selected;

    public string? Id { get; set; }
    public string? Cat { get; set; }
    public string? Name { get; set; }
    public string? Desc { get; set; }
    public string? Kind { get; set; }
    public bool Selected
    {
        get => _selected;
        set
        {
            if (_selected == value) return;
            _selected = value;
            OnPropertyChanged();
        }
    }
    public string? Risk { get; set; }
    public string? Target { get; set; }
    public string? Status { get; set; }
    public string? StatusText { get; set; }
    public bool NeedsReboot { get; set; }
    public string? Dep { get; set; }
    public string? DepHint { get; set; }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public sealed class SummaryInfo
{
    public int Total { get; set; }
    public int Applied { get; set; }
    public int Pending { get; set; }
    public int NotApplicable { get; set; }
    public int Checking { get; set; }
}

public sealed class PendingRebootInfo
{
    public bool Pending { get; set; }
    public List<string> Reasons { get; set; } = new();
}

public sealed class PendingStateInfo
{
    public string? Time { get; set; }
    public List<PendingItemInfo> Items { get; set; } = new();
    public List<ApplyError> Errors { get; set; } = new();
    public string? Backup { get; set; }
    public bool Checked { get; set; }
    public string? Result { get; set; }
}

public sealed class PendingItemInfo
{
    public string? Id { get; set; }
    public string? Name { get; set; }
}

public sealed class DiagEntry
{
    public string? Group { get; set; }
    public string? Name { get; set; }
    public string? Value { get; set; }
    public string? Level { get; set; }
    public string? Hint { get; set; }

    [JsonIgnore]
    public string LevelText => Level?.ToLowerInvariant() switch
    {
        "ok" or "green" => "正常",
        "warn" or "yellow" => "注意",
        "bad" or "red" or "error" => "警告",
        "info" or "blue" => "信息",
        _ => ""
    };
}

public sealed class ApplyResult
{
    public int Ok { get; set; }
    public int Fail { get; set; }
    public List<PreviewItem> Preview { get; set; } = new();
    public List<ApplyError> Errors { get; set; } = new();
    public string? Backup { get; set; }
    public string? RegDir { get; set; }
    public JsonElement RestorePoint { get; set; }
    public bool DryRun { get; set; }
}

public sealed class PreviewItem
{
    public string? Id { get; set; }
    public string? Name { get; set; }
    public string? Cat { get; set; }
    public string? Current { get; set; }
    public string? Target { get; set; }
    public string? Risk { get; set; }
    public bool NeedsReboot { get; set; }
}

public sealed class ApplyError
{
    public string? Id { get; set; }
    public string? Name { get; set; }
    public string? Message { get; set; }
    public string? Stage { get; set; }
}

public sealed class ProfileInfo
{
    public string? Name { get; set; }
    public bool Builtin { get; set; }
    public List<string> Ids { get; set; } = new();
}

public sealed class BackupInfo
{
    public string? Name { get; set; }
    public string? Path { get; set; }
    public string? Time { get; set; }
    public long Size { get; set; }
    public int Records { get; set; }

    [JsonIgnore]
    public string RecordsText => $"{Records} 条记录";
}

public sealed class GameInfo
{
    public string? Name { get; set; }
    public string? Exe { get; set; }
    public string? Dir { get; set; }
    public string? Source { get; set; }
    public string? AppId { get; set; }
    public bool Exists { get; set; }
    public bool Manual { get; set; }
    public GameProfile Profile { get; set; } = new();

    [JsonIgnore]
    public string SourceText => (Source ?? "").Trim().ToLowerInvariant() switch
    {
        "steam" => "Steam",
        "epic" => "Epic",
        "xbox" => "Xbox",
        "wegame" => "WeGame",
        "手动" or "manual" => "手动添加",
        "" => "本地",
        _ => Source!
    };

    [JsonIgnore]
    public string ProfileText
    {
        get
        {
            if (Profile is null || !Profile.HasSaved) return "尚未保存方案 · 使用默认启动";
            var parts = new List<string>();
            if (Profile.Priority == "High") parts.Add("高优先级");
            else if (Profile.Priority == "AboveNormal") parts.Add("高于正常");
            if (Profile.Affinity == "Physical") parts.Add("仅物理核心");
            if (Profile.FsOff) parts.Add("全屏独占");
            if (Profile.GpuHigh) parts.Add("高性能 GPU");
            if (Profile.RunAsAdmin) parts.Add("管理员启动");
            if (!string.IsNullOrWhiteSpace(Profile.Args)) parts.Add("自定义参数");
            return parts.Count == 0 ? "已保存方案（默认策略）" : string.Join(" · ", parts);
        }
    }

    [JsonIgnore]
    public string StateText => Exists ? "可启动" : "路径失效";
}

public sealed class GameProfile
{
    public string? Priority { get; set; } = "Normal";
    public string? Affinity { get; set; } = "All";
    public bool FsOff { get; set; }
    public bool GpuHigh { get; set; }
    public bool RunAsAdmin { get; set; }
    public string? Args { get; set; } = "";
    public bool HasSaved { get; set; }
}

public sealed class StartupEntry
{
    public string? Name { get; set; }
    public string? Command { get; set; }
    public string? Source { get; set; }
    public string? Location { get; set; }
}

public sealed class BackgroundProc
{
    public string? Name { get; set; }
    public string? Title { get; set; }
    public int Id { get; set; }
    public double MemMB { get; set; }
    public bool Foreground { get; set; }

    [JsonIgnore]
    public string MemText => $"{MemMB:0.0} MB";

    [JsonIgnore]
    public string PidText => "PID " + Id;

    [JsonIgnore]
    public string StateText => Foreground ? "有窗口" : "后台";

    [JsonIgnore]
    public string TitleText => string.IsNullOrWhiteSpace(Title) ? "无窗口标题" : Title;
}

public sealed class DriverChange
{
    public string? Type { get; set; }
    public string? DeviceId { get; set; }
    public string? Name { get; set; }
    public string? From { get; set; }
    public string? To { get; set; }
    public string? FromInf { get; set; }
    public string? ToInf { get; set; }
    public string? At { get; set; }
}

public sealed class DriverHistoryWrapper
{
    public Dictionary<string, DriverHistEntry> Devices { get; set; } = new();
    public List<DriverChange> LastChanges { get; set; } = new();
}

public sealed class DriverHistEntry
{
    public string? Name { get; set; }
    public string? Class { get; set; }
    public string? Inf { get; set; }
    public string? Version { get; set; }
    public string? Date { get; set; }
    public string? At { get; set; }
}

public sealed class DriverDevice
{
    public string? Name { get; set; }
    public string? Vendor { get; set; }
    public string? DriverVersion { get; set; }
    public string? DriverDate { get; set; }
    public string? PnpId { get; set; }
    public string? Status { get; set; }
    public long? AdapterRam { get; set; }
    public bool Integrated { get; set; }
    public string? ToolName { get; set; }
    public string? ToolPath { get; set; }

    [JsonIgnore]
    public string KindText => Integrated ? "集成显卡" : "独立显卡";

    [JsonIgnore]
    public string VramText => AdapterRam is > 0
        ? $"{AdapterRam.Value / 1048576.0:0.#} MB"
        : "共享内存";

    [JsonIgnore]
    public string ToolText => string.IsNullOrEmpty(ToolName) ? "厂商官网" : ToolName;

    [JsonIgnore]
    public string DriverText => string.IsNullOrEmpty(DriverVersion)
        ? "驱动版本未知"
        : $"驱动 {DriverVersion} · {(string.IsNullOrEmpty(DriverDate) ? "日期未知" : DriverDate)}";
}

public sealed class DriverHistRow
{
    public string? Name { get; set; }
    public string? Class { get; set; }
    public string? Inf { get; set; }
    public string? Version { get; set; }
    public string? Date { get; set; }
    public string? At { get; set; }

    [JsonIgnore]
    public string MetaText
    {
        get
        {
            var parts = new List<string>();
            if (!string.IsNullOrEmpty(Inf)) parts.Add(Inf);
            if (!string.IsNullOrEmpty(Version)) parts.Add("v" + Version);
            if (!string.IsNullOrEmpty(Date)) parts.Add(Date);
            if (!string.IsNullOrEmpty(At)) parts.Add("记录于 " + At);
            return string.Join(" · ", parts);
        }
    }
}

/// <summary>驱动中心页面使用的设备行，数据来自 GamePerfCenter.Core。</summary>
public sealed class DriverInventoryRow
{
    public string Name { get; init; } = "";
    public string Category { get; init; } = "";
    public string ClassName { get; init; } = "";
    public string DeviceId { get; init; } = "";
    public string InfName { get; init; } = "";
    public string Version { get; init; } = "";
    public string Provider { get; init; } = "";
    public string Date { get; init; } = "";
    public string StatusText { get; init; } = "";
    public bool StatusOk { get; init; }
    public int UpdateCount { get; init; }
    public int OldCount { get; init; }
    public int PackageCount { get; init; }
    public string FlagsText { get; init; } = "";
    public string Level { get; init; } = "green";
    public string Vendor { get; init; } = "";
    public bool CanOpenVendor { get; init; }

    [JsonIgnore]
    public string StatusGlyph => StatusOk ? "\uE73E" : "\uE7BA";

    [JsonIgnore]
    public string MetaText
    {
        get
        {
            var parts = new List<string>();
            if (!string.IsNullOrEmpty(Provider)) parts.Add(Provider);
            if (!string.IsNullOrEmpty(Date)) parts.Add(Date);
            if (!string.IsNullOrEmpty(InfName)) parts.Add(InfName);
            return parts.Count == 0 ? "驱动信息未知" : string.Join(" · ", parts);
        }
    }

    [JsonIgnore]
    public string PackageText => PackageCount == 0
        ? "驱动仓库无匹配包"
        : $"仓库 {PackageCount} 包 · 旧版本 {OldCount} · 更新 {UpdateCount}";

    [JsonIgnore]
    public GamePerfCenter.Core.Models.DriverDeviceInfo? Device { get; init; }
}


public sealed class DiagGroup
{
    public string? Name { get; set; }
    public string? Hint { get; set; }
    public List<DiagEntry> Items { get; set; } = new();
}

public sealed class SupportInfo
{
    public string? Version { get; set; }
    public string? Path { get; set; }
}

public sealed class CapabilityInfo
{
    public string? Name { get; set; }
    public string? Desc { get; set; }
}

public sealed class AppLogLine
{
    public string Text { get; set; } = "";
    public string Color { get; set; } = "Gray";
    public DateTime At { get; set; } = DateTime.Now;
}

public sealed class LiveMetrics
{
    public double Cpu { get; set; }
    public double Gpu { get; set; }
    public double RamPercent { get; set; }
    public double RamUsedGb { get; set; }
    public double RamTotalGb { get; set; }
    public double NetDownKbps { get; set; }
    public double NetUpKbps { get; set; }
}
