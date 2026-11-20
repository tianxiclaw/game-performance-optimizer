using System.Collections.ObjectModel;
using System.ComponentModel;
using GamePerfCenter.Services;
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
    private bool _expanded;
    private string _lastAppliedText = "尚未通过本工具应用";
    private string? _id;
    private string? _cat;
    private string? _name;
    private string? _desc;
    private string? _kind;
    private string? _risk;
    private string? _target;
    private string? _status;
    private string? _statusText;
    private bool _needsReboot;
    private string? _dep;
    private string? _depHint;

    public string? Id { get => _id; set => Set(ref _id, value); }
    public string? Cat { get => _cat; set => Set(ref _cat, value); }
    public string? Name { get => _name; set => Set(ref _name, value); }
    public string? Desc { get => _desc; set => Set(ref _desc, value); }
    public string? Kind { get => _kind; set => Set(ref _kind, value); }
    /// <summary>
    /// 界面勾选状态。引擎快照里的 Selected 表示“该项当前是否已启用”，与勾选无关，
    /// 反序列化时必须忽略，否则所有已生效项会被自动勾上。
    /// </summary>
    [JsonIgnore]
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
    public string? Risk { get => _risk; set => Set(ref _risk, value); }
    public string? Target { get => _target; set => Set(ref _target, value); }
    public string? Status { get => _status; set => Set(ref _status, value); }
    public string? StatusText { get => _statusText; set => Set(ref _statusText, value); }
    public bool NeedsReboot
    {
        get => _needsReboot;
        set
        {
            if (_needsReboot == value) return;
            _needsReboot = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(RebootText));
        }
    }
    public string? Dep { get => _dep; set { if (Set(ref _dep, value)) OnPropertyChanged(nameof(DependencyText)); } }
    public string? DepHint { get => _depHint; set { if (Set(ref _depHint, value)) OnPropertyChanged(nameof(DependencyText)); } }

    /// <summary>行内展开状态。列表重建时由页面重置，不参与序列化。</summary>
    [JsonIgnore]
    public bool IsExpanded
    {
        get => _expanded;
        set
        {
            if (_expanded == value) return;
            _expanded = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(ExpandVisibility));
            OnPropertyChanged(nameof(ExpandLabel));
            OnPropertyChanged(nameof(ExpandGlyph));
        }
    }

    [JsonIgnore]
    public Microsoft.UI.Xaml.Visibility ExpandVisibility
        => _expanded ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;

    [JsonIgnore]
    public string ExpandLabel => Localization.T(_expanded ? "收起" : "详情");

    [JsonIgnore]
    public string ExpandGlyph => _expanded ? "\uE70E" : "\uE70D";

    /// <summary>行内说明里的“目标”前缀，按当前语言显示。</summary>
    [JsonIgnore]
    public string TargetLabel => Localization.T("  目标：");

    [JsonIgnore]
    public string RebootText => Localization.T(NeedsReboot ? "需要重启后生效" : "无需重启");

    [JsonIgnore]
    public string DependencyText => !string.IsNullOrWhiteSpace(DepHint)
        ? DepHint!
        : !string.IsNullOrWhiteSpace(Dep) ? Dep! : Localization.T("无依赖");

    /// <summary>由页面根据快照里的 LastApply 写入，不来自引擎。</summary>
    [JsonIgnore]
    public string LastAppliedText
    {
        get => _lastAppliedText;
        set
        {
            if (_lastAppliedText == value) return;
            _lastAppliedText = value;
            OnPropertyChanged();
        }
    }

    /// <summary>
    /// 主题切换后让状态 / 风险颜色的单向绑定重新求值，
    /// 这样优化项列表不需要清空重建，滚动位置与展开行都能保留。
    /// </summary>
    public void NotifyThemeChanged()
    {
        OnPropertyChanged(nameof(Status));
        OnPropertyChanged(nameof(Risk));
    }

    /// <summary>快照刷新时就地更新已有实例，保留列表容器、勾选与展开状态。</summary>
    public void UpdateFrom(ItemInfo source)
    {
        Id = source.Id;
        Cat = source.Cat;
        Name = source.Name;
        Desc = source.Desc;
        Kind = source.Kind;
        Risk = source.Risk;
        Target = source.Target;
        Status = source.Status;
        StatusText = source.StatusText;
        NeedsReboot = source.NeedsReboot;
        Dep = source.Dep;
        DepHint = source.DepHint;
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(name);
        return true;
    }

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
        "ok" or "green" => Localization.T("正常"),
        "warn" or "yellow" => Localization.T("注意"),
        "bad" or "red" or "error" => Localization.T("警告"),
        "info" or "blue" => Localization.T("信息"),
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

public sealed partial class GameInfo
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
    public string Initial
    {
        get
        {
            var name = (Name ?? "").Trim();
            return name.Length == 0 ? "?" : name.Substring(0, 1).ToUpperInvariant();
        }
    }

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
    public double Share { get; set; }

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

public sealed class CapabilityInfo
{
    public string? Name { get; set; }
    public string? Desc { get; set; }
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

/// <summary>只读内存构成快照，用于解释“总量”和“进程累加”之间的差额。</summary>
public sealed class MemorySnapshot
{
    public double TotalGb { get; set; }
    public double UsedGb { get; set; }
    public double AvailableGb { get; set; }
    public double StandbyGb { get; set; }
    public double CommittedGb { get; set; }
    public double CommitLimitGb { get; set; }
    public double PagedPoolGb { get; set; }
    public double NonPagedPoolGb { get; set; }
    public double FreeGb { get; set; }
    public double ProcessTotalGb { get; set; }
    public DateTime UpdatedAt { get; set; }
    public List<MemoryProcessInfo> Processes { get; set; } = new();
}

public sealed class MemoryProcessInfo
{
    public string Name { get; init; } = "";
    public double PrivateMb { get; init; }
    public string PrivateText => $"{PrivateMb:0} MB";
}
