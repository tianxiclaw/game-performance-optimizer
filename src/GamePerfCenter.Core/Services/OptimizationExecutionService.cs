using System.Globalization;
using System.Security.Principal;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using GamePerfCenter.Core.Infrastructure;
using GamePerfCenter.Core.Models;
using Microsoft.Win32;

namespace GamePerfCenter.Core.Services;

/// <summary>
/// 优化项执行内核：应用、预览、备份、还原统一在这里完成。
/// 项目录（哪些项适用于本机）仍由 PowerShell 引擎生成，保证硬件分支只有一份实现。
/// 备份 JSON 的字段与引擎完全兼容，旧版引擎创建的备份也能在这里还原。
/// </summary>
public sealed class OptimizationExecutionService
{
    private const string GraphicsDrivers = @"HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers";
    private const string PnpCleanPath = @"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\Device Driver Packages";
    private const string NicClassPath = @"HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}";
    private const string DwmExe = @"C:\Windows\System32\dwm.exe";
    private const uint AllBits = 0xFFFFFFFF;
    private const uint PnpPowerBits = 24;
    private const uint DpstBit = 16;
    private const uint PsrBit = 0x80000000;

    private static readonly Regex NicSubKeyPattern = new(@"^\d{4}$", RegexOptions.Compiled);

    private readonly string _baseDirectory;
    private readonly string _backupDirectory;
    private readonly string _userSid;
    private readonly string _gpuPreferencesPath;

    private static readonly JsonSerializerOptions BackupJson = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    public OptimizationExecutionService(string? baseDirectory = null, string? backupDirectory = null,
        string? userSid = null)
    {
        _baseDirectory = baseDirectory ?? AppContext.BaseDirectory;
        _backupDirectory = backupDirectory ?? Path.Combine(_baseDirectory, "backups");
        _userSid = userSid ?? GetCurrentSid();
        _gpuPreferencesPath = $@"Registry::HKEY_USERS\{_userSid}\SOFTWARE\Microsoft\DirectX\UserGpuPreferences";
    }

    public string BackupDirectory => _backupDirectory;

    // ───────────────────────────────────────────────────────
    // 应用 / 预览
    // ───────────────────────────────────────────────────────
    public OptimizationApplyResult Apply(OptimizationCatalog catalog, IEnumerable<string> ids,
        OptimizationApplyOptions options)
    {
        var wanted = new HashSet<string>(ids, StringComparer.OrdinalIgnoreCase);
        var selected = catalog.Items.Where(item => wanted.Contains(item.Id)).ToList();
        var missing = wanted.Where(id => selected.All(item => !string.Equals(item.Id, id, StringComparison.OrdinalIgnoreCase)))
            .ToArray();
        var result = Apply(catalog.Context, selected, options);
        foreach (var id in missing)
            result.Errors.Add(new OptimizationError { Id = id, Message = "目录中没有该优化项", Stage = "plan" });
        result.Fail += missing.Length;
        return result;
    }

    public OptimizationApplyResult Apply(OptimizationContext context, IReadOnlyList<OptimizationItem> items,
        OptimizationApplyOptions options)
    {
        var result = new OptimizationApplyResult { DryRun = options.DryRun };
        if (items.Count == 0)
        {
            result.Errors.Add(new OptimizationError { Message = "没有选中有效的优化项", Stage = "plan" });
            result.Fail = 1;
            return result;
        }

        var planRecords = new List<OptimizationBackupRecord>();
        foreach (var item in items)
        {
            try
            {
                var record = Execute(item, context, write: false);
                planRecords.Add(record);
                if (!IsSatisfied(item, record))
                    result.Preview.Add(BuildPreview(item, record));
            }
            catch (Exception ex)
            {
                result.Errors.Add(new OptimizationError
                {
                    Id = item.Id, Name = item.Name, Message = ex.Message, Stage = "plan"
                });
            }
        }

        if (options.DryRun)
        {
            result.Ok = items.Count - result.Errors.Count;
            result.Fail = result.Errors.Count;
            result.Records = planRecords;
            return result;
        }

        if (!options.NoRegSnapshot && planRecords.Count > 0)
        {
            try { result.RegDir = ExportRegSnapshot(planRecords); }
            catch { }
        }

        if (options.RestorePoint)
        {
            var (ok, message) = CreateRestorePoint();
            result.RestorePointCreated = ok;
            result.RestorePointMessage = message;
        }

        var records = new List<OptimizationBackupRecord>();
        var appliedItems = new List<OptimizationItem>();
        var applyErrors = new List<OptimizationError>();
        foreach (var item in items)
        {
            try
            {
                var record = Execute(item, context, write: true);
                records.Add(record);
                appliedItems.Add(item);
                result.Ok++;
            }
            catch (Exception ex)
            {
                applyErrors.Add(new OptimizationError
                {
                    Id = item.Id, Name = item.Name, Message = ex.Message, Stage = "apply"
                });
                result.Fail++;
            }
        }

        result.Errors = applyErrors;
        result.Records = records;

        if (!options.NoBackup && records.Count > 0)
        {
            try { result.Backup = WriteBackup(records); }
            catch (Exception ex)
            {
                result.Errors.Add(new OptimizationError
                {
                    Message = "备份写入失败: " + ex.Message, Stage = "backup"
                });
            }
        }

        if (appliedItems.Count > 0)
            WritePendingState(appliedItems, applyErrors, result.Backup);

        return result;
    }

    /// <summary>只读探测单项状态，供 CLI / WinUI 展示。</summary>
    public (bool Supported, bool Satisfied, string Current) Probe(OptimizationItem item, OptimizationContext context)
    {
        try
        {
            var record = Execute(item, context, write: false);
            return (true, IsSatisfied(item, record), CurrentText(item, record));
        }
        catch (Exception ex)
        {
            return (false, false, "查询异常: " + ex.Message);
        }
    }

    // ───────────────────────────────────────────────────────
    // 还原
    // ───────────────────────────────────────────────────────
    public OptimizationRestoreResult Restore(string path, bool dryRun = false)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("备份不存在", path);

        OptimizationBackupFile? data;
        try
        {
            data = JsonSerializer.Deserialize<OptimizationBackupFile>(File.ReadAllText(path, Encoding.UTF8),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("备份解析失败: " + ex.Message, ex);
        }

        if (data?.Records is null || data.Records.Count == 0)
            throw new InvalidOperationException("备份中无记录");

        var records = data.Records.ToList();
        records.Reverse(); // 同一值被多项按位修改时，逆序才能正确回退

        var result = new OptimizationRestoreResult
        {
            File = path,
            Version = data.Version,
            Records = records.Count,
            DryRun = dryRun
        };

        foreach (var record in records)
        {
            try
            {
                if (!dryRun) RestoreRecord(record);
                result.Ok++;
            }
            catch (Exception ex)
            {
                result.Fail++;
                result.Errors.Add(new OptimizationError
                {
                    Id = record.Id, Message = ex.Message, Stage = "restore"
                });
            }
        }

        return result;
    }

    public OptimizationRestoreAllResult RestoreAll()
    {
        var result = new OptimizationRestoreAllResult();
        foreach (var file in EnumerateBackupFiles())
        {
            try
            {
                var one = Restore(file.FullName);
                result.Ok += one.Ok;
                result.Fail += one.Fail;
                result.Files++;
                result.Errors.AddRange(one.Errors);
                result.Report.Add(new OptimizationRestoreFileResult
                {
                    File = file.Name, Ok = one.Ok, Fail = one.Fail
                });
            }
            catch (Exception ex)
            {
                result.Fail++;
                result.Errors.Add(new OptimizationError { Id = file.Name, Message = ex.Message, Stage = "restore" });
                result.Report.Add(new OptimizationRestoreFileResult { File = file.Name, Ok = 0, Fail = 1 });
            }
        }
        return result;
    }

    public List<OptimizationBackupInfo> GetBackups()
    {
        var list = new List<OptimizationBackupInfo>();
        foreach (var file in EnumerateBackupFiles())
        {
            var time = file.LastWriteTime.ToString("s");
            var count = 0;
            try
            {
                var data = JsonSerializer.Deserialize<OptimizationBackupFile>(
                    File.ReadAllText(file.FullName, Encoding.UTF8),
                    new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                if (!string.IsNullOrWhiteSpace(data?.Time)) time = data!.Time!;
                count = data?.Records.Count ?? 0;
            }
            catch { }

            list.Add(new OptimizationBackupInfo
            {
                Name = file.Name,
                Path = file.FullName,
                Time = time,
                Size = file.Length,
                Records = count
            });
        }
        return list;
    }

    public OptimizationPendingState? GetPendingState()
    {
        var path = Path.Combine(_backupDirectory, "state_last_apply.json");
        if (!File.Exists(path)) return null;
        try
        {
            return JsonSerializer.Deserialize<OptimizationPendingState>(File.ReadAllText(path, Encoding.UTF8),
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        }
        catch { return null; }
    }

    public OptimizationPendingReboot GetPendingReboot()
    {
        var reasons = new List<string>();
        var ignored = 0;

        if (KeyExists(@"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"))
            reasons.Add("CBS");
        if (KeyExists(@"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired"))
            reasons.Add("WindowsUpdate");

        try
        {
            var pending = ReadValue(@"HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager", "PendingFileRenameOperations");
            if (pending.Exists && pending.Value is string[] operations)
            {
                for (var i = 0; i + 1 < operations.Length; i += 2)
                {
                    var source = operations[i];
                    if (string.IsNullOrWhiteSpace(source)) continue;
                    string? file = null;
                    if (source.StartsWith(@"\??\", StringComparison.Ordinal)) file = source[4..];
                    else if (source.StartsWith(@"\SystemRoot\", StringComparison.OrdinalIgnoreCase))
                        file = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), source[12..]);
                    else if (source.StartsWith(@"\DosDevices\", StringComparison.OrdinalIgnoreCase)) file = source[12..];

                    if (file is null) { ignored++; continue; }
                    if (File.Exists(file)) reasons.Add("PendingFileRename");
                }
            }
        }
        catch { }

        if (KeyExists(@"HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\PackagesPending"))
            reasons.Add("PackagesPending");

        return new OptimizationPendingReboot
        {
            Pending = reasons.Count > 0,
            Reasons = reasons.Distinct().ToList(),
            Ignored = ignored
        };
    }

    public (bool Ok, string Message) CreateRestorePoint()
    {
        try
        {
            PowerShellRunner.RunScript(
                "Checkpoint-Computer -Description '游戏性能优化 - 应用前' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop | Out-Null",
                TimeSpan.FromMinutes(5));
            return (true, "已创建系统还原点");
        }
        catch (Exception ex)
        {
            return (false, ex.Message);
        }
    }

    // ───────────────────────────────────────────────────────
    // 执行单个 Kind（write=false 时只读预演）
    // ───────────────────────────────────────────────────────
    private OptimizationBackupRecord Execute(OptimizationItem item, OptimizationContext context, bool write)
    {
        var kind = item.Kind ?? "";
        switch (kind)
        {
            case "reg":
            {
                var path = Require(item.P, "注册表路径");
                var name = Require(item.V, "注册表值名");
                var type = item.VT ?? "DWord";
                var original = ReadValue(path, name);
                if (write) WriteValue(path, name, item.TargetValue, type);
                return Record(item, kind, r =>
                {
                    r.P = path; r.V = name; r.VT = type;
                    r.OV = ToElement(original.Value); r.OE = original.Exists;
                });
            }

            case "reg2":
            {
                var path = Require(item.P, "注册表路径");
                var name = Require(item.V, "注册表值名");
                var name2 = Require(item.V2, "第二个注册表值名");
                var type = item.VT ?? "DWord";
                var original = ReadValue(path, name);
                var original2 = ReadValue(path, name2);
                if (write)
                {
                    WriteValue(path, name, item.TargetValue, type);
                    WriteValue(path, name2, item.TargetValue2, type);
                }
                return Record(item, kind, r =>
                {
                    r.P = path; r.V = name; r.V2 = name2; r.VT = type;
                    r.OV = ToElement(original.Value); r.OV2 = ToElement(original2.Value);
                    r.OE = original.Exists; r.OE2 = original2.Exists;
                });
            }

            case "regdel":
            {
                var path = Require(item.P, "注册表路径");
                var name = Require(item.V, "注册表值名");
                var original = ReadValue(path, name);
                if (write && original.Exists) DeleteValue(path, name);
                return Record(item, kind, r =>
                {
                    r.P = path; r.V = name;
                    r.OV = ToElement(original.Value); r.OE = original.Exists;
                });
            }

            case "drr":
            {
                var path = GraphicsDrivers;
                var name = "DrrMigrationControl";
                var original = ReadValue(path, name);
                if (write) WriteUInt32(path, name, item.TargetUInt32 ?? 0);
                return Record(item, kind, r =>
                {
                    r.P = path; r.OV = ToElement(original.Value); r.OE = original.Exists;
                });
            }

            case "pnpclean":
            {
                var path = PnpCleanPath;
                var name = "Autorun";
                var original = ReadValue(path, name);
                if (write) WriteUInt32(path, name, item.TargetUInt32 ?? 0);
                return Record(item, kind, r =>
                {
                    r.P = path; r.OV = ToElement(original.Value); r.OE = original.Exists;
                });
            }

            case "svc":
            {
                var services = item.SV.Where(s => !string.IsNullOrWhiteSpace(s)).ToArray();
                if (services.Length == 0) throw new InvalidOperationException("服务列表为空");
                var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (var service in services)
                {
                    var start = ReadValue($@"HKLM:\SYSTEM\CurrentControlSet\Services\{service}", "Start");
                    map[service] = (start.Exists ? start.AsUInt32() : 3).ToString(CultureInfo.InvariantCulture);
                    if (write)
                    {
                        try { PowerShellRunner.Execute("sc.exe", new[] { "stop", service }, TimeSpan.FromSeconds(20)); }
                        catch { }
                    }
                }

                if (write)
                {
                    var target = StartValue(item.TargetText);
                    foreach (var service in services)
                        WriteUInt32($@"HKLM:\SYSTEM\CurrentControlSet\Services\{service}", "Start", target);
                }

                return Record(item, kind, r => r.SV = ToElement(map));
            }

            case "power":
            {
                var sub = Require(item.SK, "电源子组");
                var setting = Require(item.SE, "电源设置项");
                var (queryOk, ac, dc) = PowerCfg.QueryValue(sub, setting);
                if (!queryOk) throw new InvalidOperationException("powercfg 读不到该电源项");
                if (write)
                {
                    PowerCfg.SetValue(sub, setting,
                        item.AC is null ? null : unchecked((uint)item.AC.Value),
                        item.DC is null ? null : unchecked((uint)item.DC.Value));
                }
                return Record(item, kind, r =>
                {
                    r.Sub = PowerCfg.Resolve(sub); r.Set = PowerCfg.Resolve(setting);
                    r.OAC = ToElement(ac); r.ODC = ToElement(dc);
                });
            }

            case "scheme":
            {
                var active = PowerCfg.GetActiveScheme() ?? throw new InvalidOperationException("无法读取当前电源方案");
                var target = PowerCfg.Resolve(Require(item.TG, "目标电源方案"));
                var already = string.Equals(active, target, StringComparison.OrdinalIgnoreCase);
                string? newGuid = null;
                if (write && !already)
                {
                    var guid = target;
                    if (!PowerCfg.SchemeExists(target)) guid = PowerCfg.DuplicateScheme(target);
                    PowerCfg.SetActive(guid);
                    var now = PowerCfg.GetActiveScheme();
                    if (!string.Equals(now, guid, StringComparison.OrdinalIgnoreCase))
                        throw new InvalidOperationException($"校验不一致: 期望 {guid}, 实际 {now}");
                    newGuid = guid;
                }
                return Record(item, kind, r =>
                {
                    r.OG = active; r.NG = newGuid; r.UC = already;
                });
            }

            case "display":
            {
                var device = Require(item.DID, "显示器设备名");
                var current = DisplaySettings.GetRefreshRate(device) ?? item.RR ?? 0;
                var target = item.MR ?? item.RR ?? current;
                if (write) DisplaySettings.ChangeRefreshRate(device, target);
                return Record(item, kind, r =>
                {
                    r.DID = device; r.DN = item.DN;
                    r.RR = ToElement(current); r.MR = ToElement(target);
                    r.W = ToElement(item.W); r.H = ToElement(item.H);
                });
            }

            case "gpupref":
            {
                var path = context.GpuPreferencesPath ?? _gpuPreferencesPath;
                var original = ReadValue(path, DwmExe);
                if (write) WriteValue(path, DwmExe, ToElement("GpuPreference=2"), "String");
                return Record(item, kind, r =>
                {
                    r.Exe = DwmExe; r.OV = ToElement(original.Value); r.OE = original.Exists;
                });
            }

            case "intelpnp":
            {
                var path = context.IntelKey ?? throw new InvalidOperationException("无法定位 Intel 核显子键");
                return ApplyBitMask(item, kind, path, "PnPCapabilities", item.BM ?? PnpPowerBits, write);
            }

            case "gpupnp":
            {
                var path = Require(item.SK, "独显子键路径");
                return ApplyBitMask(item, kind, path, "PnPCapabilities", item.BM ?? PnpPowerBits, write);
            }

            case "intelftc":
            {
                var path = context.IntelKey ?? throw new InvalidOperationException("无法定位 Intel 核显子键");
                return ApplyBitMask(item, kind, path, "FeatureTestControl", item.BM ?? 0, write);
            }

            case "inteldps":
            {
                var path = context.IntelKey ?? throw new InvalidOperationException("无法定位 Intel 核显子键");
                var original = ReadValue(path, "DisplayPowerSavings");
                if (write) WriteUInt32(path, "DisplayPowerSavings", 0);
                return Record(item, kind, r =>
                {
                    r.SK = path; r.OV = ToElement(original.Value); r.OE = original.Exists;
                });
            }

            case "tdrdelay":
            {
                var path = GraphicsDrivers;
                var original = ReadValue(path, "TdrDelay");
                if (write) WriteUInt32(path, "TdrDelay", item.TargetUInt32 ?? 8);
                return Record(item, kind, r =>
                {
                    r.P = path; r.OV = ToElement(original.Value); r.OE = original.Exists;
                });
            }

            case "nic":
            {
                var adapter = Require(item.A, "网卡名");
                var keyword = Require(item.K, "网卡属性名");
                var value = ReadNicValue(adapter, keyword)
                            ?? throw new InvalidOperationException($"网卡不支持该属性（{keyword}）");
                if (write) WriteNicValue(adapter, keyword, item.TargetValue);
                return Record(item, kind, r =>
                {
                    r.A = adapter; r.K = keyword; r.OV = value; r.OE = true;
                });
            }

            case "nicpower":
            {
                var adapter = Require(item.A, "网卡名");
                var resolved = ResolveNicPower(adapter);
                if (!resolved.Supported)
                    throw new InvalidOperationException("该网卡不支持省电设置（无注册表键且无电源管理接口）");
                if (write)
                {
                    var target = item.TargetUInt32 ?? 24;
                    WriteNicPower(adapter, resolved, target);
                }
                return Record(item, kind, r =>
                {
                    r.A = adapter; r.R = resolved.Path;
                    r.OV = ToElement(resolved.Value); r.OE = resolved.Exists;
                });
            }

            default:
                throw new InvalidOperationException($"未注册 Kind: {kind}");
        }
    }

    private OptimizationBackupRecord ApplyBitMask(OptimizationItem item, string kind, string path,
        string valueName, uint mask, bool write)
    {
        var original = ReadValue(path, valueName);
        var current = original.AsUInt32();
        var updated = current | mask;
        var added = mask & ~current;
        if (write) WriteUInt32(path, valueName, updated);
        return Record(item, kind, r =>
        {
            r.SK = path; r.BM = mask; r.AB = added;
            r.OV = ToElement(current); r.OE = original.Exists;
        });
    }

    private static OptimizationBackupRecord Record(OptimizationItem item, string kind,
        Action<OptimizationBackupRecord> fill)
    {
        var record = new OptimizationBackupRecord { Id = item.Id, Kind = kind };
        fill(record);
        return record;
    }

    // ───────────────────────────────────────────────────────
    // Kind 还原
    // ───────────────────────────────────────────────────────
    private void RestoreRecord(OptimizationBackupRecord r)
    {
        var kind = r.Kind ?? "";
        switch (kind)
        {
            case "reg":
            {
                var path = r.GetString("P", "Path") ?? throw new InvalidOperationException("备份缺少路径");
                var name = r.GetString("V", "Name", "Value") ?? throw new InvalidOperationException("备份缺少值名");
                RestoreRegistryValue(path, name, r.GetString("VT") ?? "DWord", r.GetElement("OV"), r.OE ?? false);
                break;
            }
            case "reg2":
            {
                var path = r.GetString("P", "Path") ?? throw new InvalidOperationException("备份缺少路径");
                var name = r.GetString("V", "Name");
                var name2 = r.GetString("V2", "Name2");
                var type = r.GetString("VT") ?? "DWord";
                if (!string.IsNullOrWhiteSpace(name))
                    RestoreRegistryValue(path, name, type, r.GetElement("OV"), r.OE ?? false);
                if (!string.IsNullOrWhiteSpace(name2))
                    RestoreRegistryValue(path, name2, type, r.GetElement("OV2"), r.OE2 ?? false);
                break;
            }
            case "regdel":
            {
                var path = r.GetString("P", "Path");
                var name = r.GetString("V", "Name");
                if (!string.IsNullOrWhiteSpace(path) && !string.IsNullOrWhiteSpace(name) &&
                    (r.OE ?? false) && r.OV is not null)
                    WriteValue(path, name, r.GetElement("OV"), "DWord");
                break;
            }
            case "drr":
            {
                var path = r.GetString("P", "Path") ?? GraphicsDrivers;
                RestoreRegistryValue(path, "DrrMigrationControl", "DWord", r.GetElement("OV"), r.OE ?? false);
                break;
            }
            case "pnpclean":
            {
                var path = r.GetString("P", "Path") ?? PnpCleanPath;
                RestoreRegistryValue(path, "Autorun", "DWord", r.GetElement("OV"), r.OE ?? false);
                break;
            }
            case "svc":
            {
                var map = ReadServiceMap(r.GetElement("SV", "Services"));
                foreach (var (service, value) in map)
                {
                    var start = StartValue(value);
                    // 旧备份曾把 DiagTrack 记为 Disabled；禁用会导致系统 UI 卡顿，必须拦截。
                    if (string.Equals(service, "DiagTrack", StringComparison.OrdinalIgnoreCase) && start == 4)
                        continue;
                    WriteUInt32($@"HKLM:\SYSTEM\CurrentControlSet\Services\{service}", "Start", start);
                }
                break;
            }
            case "svcquota":
            {
                var map = ReadServiceMap(r.GetElement("SV", "Services"));
                foreach (var (service, _) in map)
                {
                    try
                    {
                        DeleteValue($@"HKLM:\SYSTEM\CurrentControlSet\Services\{service}", "Priority");
                        DeleteValue($@"HKLM:\SYSTEM\CurrentControlSet\Services\{service}", "DelayedAutoStart");
                    }
                    catch { }
                    try
                    {
                        PowerShellRunner.Execute("schtasks.exe",
                            new[] { "/Delete", "/TN", $"SvcQuota_{service}", "/F" }, TimeSpan.FromSeconds(20));
                    }
                    catch { }
                }
                break;
            }
            case "power":
            {
                var sub = r.GetString("Sub", "SK");
                var setting = r.GetString("Set", "SE");
                if (string.IsNullOrWhiteSpace(sub) || string.IsNullOrWhiteSpace(setting)) break;
                PowerCfg.SetValue(sub, setting,
                    JsonValue.ToUInt32(r.GetElement("OAC")),
                    JsonValue.ToUInt32(r.GetElement("ODC")));
                break;
            }
            case "scheme":
            {
                if (!(r.UC ?? false) && !string.IsNullOrWhiteSpace(r.OG))
                    PowerCfg.SetActive(r.OG!);
                break;
            }
            case "display":
            {
                var device = r.GetString("DID");
                var refresh = JsonValue.ToInt32(r.GetElement("RR")) ?? 0;
                if (!string.IsNullOrWhiteSpace(device) && refresh > 0)
                    DisplaySettings.ChangeRefreshRate(device, refresh);
                break;
            }
            case "gpupref":
            {
                var exe = r.GetString("Exe");
                if (string.IsNullOrWhiteSpace(exe)) break;
                var path = _gpuPreferencesPath;
                var value = JsonValue.ToString(r.GetElement("OV"));
                if (r.OE ?? false)
                {
                    if (!string.IsNullOrEmpty(value))
                        WriteValue(path, exe, ToElement(value), "String");
                }
                else
                {
                    DeleteValue(path, exe);
                }
                break;
            }
            case "intelpnp":
            case "gpupnp":
                RestoreBitMask(r, "PnPCapabilities");
                break;
            case "intelftc":
                RestoreBitMask(r, "FeatureTestControl");
                break;
            case "inteldpst":
                ClearBit(r, "FeatureTestControl", DpstBit);
                break;
            case "intelpsr":
                ClearBit(r, "FeatureTestControl", PsrBit);
                break;
            case "inteldps":
            {
                var path = r.GetString("SK", "SubKey");
                if (string.IsNullOrWhiteSpace(path)) break;
                RestoreRegistryValue(path, "DisplayPowerSavings", "DWord", r.GetElement("OV"), r.OE ?? false);
                break;
            }
            case "tdrdelay":
            {
                var path = r.GetString("P", "Path") ?? GraphicsDrivers;
                RestoreRegistryValue(path, "TdrDelay", "DWord", r.GetElement("OV"), r.OE ?? false);
                break;
            }
            case "nic":
            {
                var adapter = r.GetString("A", "Adapter");
                var keyword = r.GetString("K", "Keyword");
                var value = r.GetElement("OV");
                if (string.IsNullOrWhiteSpace(adapter) || string.IsNullOrWhiteSpace(keyword) || value is null)
                    break;
                WriteNicValue(adapter, keyword, value);
                break;
            }
            case "nicpower":
            {
                var adapter = r.GetString("A", "Adapter");
                var path = r.GetString("R", "RegPath");
                var value = JsonValue.ToUInt32(r.GetElement("OV")) ?? 0;
                if (!string.IsNullOrWhiteSpace(path))
                {
                    if (value == 0) DeleteValue(path, "PnPCapabilities");
                    else WriteUInt32(path, "PnPCapabilities", value);
                }
                else if (!string.IsNullOrWhiteSpace(adapter))
                {
                    var resolved = ResolveNicPower(adapter);
                    if (resolved.Supported) WriteNicPower(adapter, resolved, value);
                }
                break;
            }
            default:
                throw new InvalidOperationException($"未注册 Kind: {kind}");
        }
    }

    private void RestoreBitMask(OptimizationBackupRecord r, string valueName)
    {
        var path = r.GetString("SK", "SubKey", "Path");
        if (string.IsNullOrWhiteSpace(path)) throw new InvalidOperationException("备份缺少子键路径");

        var bits = r.AB ?? r.BM;
        if (bits is not null)
        {
            var current = ReadValue(path, valueName).AsUInt32();
            var updated = current & ~bits.Value;
            WriteUInt32(path, valueName, updated);
        }
        else if ((r.OE ?? false) && r.OV is not null)
        {
            WriteValue(path, valueName, r.GetElement("OV"), "DWord");
        }
        else
        {
            DeleteValue(path, valueName);
        }
    }

    private void ClearBit(OptimizationBackupRecord r, string valueName, uint bit)
    {
        var path = r.GetString("SK", "SubKey");
        if (string.IsNullOrWhiteSpace(path)) throw new InvalidOperationException("备份缺少子键路径");
        var current = ReadValue(path, valueName).AsUInt32();
        WriteUInt32(path, valueName, current & ~bit);
    }

    private static void RestoreRegistryValue(string path, string name, string type, JsonElement? value, bool existed)
    {
        if (existed && value is not null) WriteValue(path, name, value, type);
        else DeleteValue(path, name);
    }

    // ───────────────────────────────────────────────────────
    // 状态判定 / 预览文本
    // ───────────────────────────────────────────────────────
    private static bool IsSatisfied(OptimizationItem item, OptimizationBackupRecord record)
    {
        var kind = item.Kind ?? "";
        switch (kind)
        {
            case "reg":
                return ValueMatches(record.OV, item.TargetValue, item.VT);
            case "reg2":
                return ValueMatches(record.OV, item.TargetValue, item.VT) &&
                       ValueMatches(record.OV2, item.TargetValue2, item.VT);
            case "regdel":
                return !(record.OE ?? false);
            case "drr":
            case "pnpclean":
                return (JsonValue.ToUInt32(record.OV) ?? 0) == (item.TargetUInt32 ?? 0);
            case "tdrdelay":
                return (JsonValue.ToUInt32(record.OV) ?? 0) >= (item.TargetUInt32 ?? 8);
            case "svc":
            {
                var map = ReadServiceMap(record.SV);
                if (map.Count == 0) return false;
                var target = item.TargetText ?? "Manual";
                return string.Equals(target, "Disabled", StringComparison.OrdinalIgnoreCase)
                    ? map.Values.All(v => StartValue(v) == 4)
                    : map.Values.All(v => StartValue(v) != 2);
            }
            case "power":
            {
                var ac = JsonValue.ToUInt32(record.OAC);
                var dc = JsonValue.ToUInt32(record.ODC);
                return ac is not null && dc is not null &&
                       ac == (uint?)item.AC && dc == (uint?)item.DC;
            }
            case "scheme":
                return record.UC ?? false;
            case "display":
                return (JsonValue.ToInt32(record.RR) ?? 0) >= (item.MR ?? 0);
            case "gpupref":
                return (JsonValue.ToString(record.OV) ?? "").Contains("GpuPreference=2", StringComparison.OrdinalIgnoreCase);
            case "intelpnp":
            case "gpupnp":
                return ((JsonValue.ToUInt32(record.OV) ?? 0) & (item.BM ?? PnpPowerBits)) != 0;
            case "intelftc":
                return ((JsonValue.ToUInt32(record.OV) ?? 0) & (item.BM ?? 0)) != 0;
            case "inteldps":
                return (record.OE ?? false) && (JsonValue.ToUInt32(record.OV) ?? 1) == 0;
            case "nic":
                return string.Equals(JsonValue.ToString(record.OV), item.TargetText, StringComparison.OrdinalIgnoreCase);
            case "nicpower":
                return (JsonValue.ToUInt32(record.OV) ?? 0) == (item.TargetUInt32 ?? 24);
            default:
                return false;
        }
    }

    private static bool ValueMatches(JsonElement? value, JsonElement? target, string? type)
    {
        if (target is null) return value is null;
        if (string.Equals(type, "DWord", StringComparison.OrdinalIgnoreCase) ||
            target.Value.ValueKind == JsonValueKind.Number)
            return (JsonValue.ToUInt32(value) ?? 0) == (JsonValue.ToUInt32(target) ?? 0);
        return string.Equals(JsonValue.ToString(value), JsonValue.ToString(target),
            StringComparison.OrdinalIgnoreCase);
    }

    private static OptimizationPreview BuildPreview(OptimizationItem item, OptimizationBackupRecord record) =>
        new()
        {
            Id = item.Id,
            Name = item.Name,
            Cat = item.Cat,
            Kind = item.Kind,
            Current = CurrentText(item, record),
            Target = item.TargetLabel,
            Risk = item.Risk,
            NeedsReboot = NeedsReboot(item)
        };

    private static string CurrentText(OptimizationItem item, OptimizationBackupRecord record)
    {
        var kind = item.Kind ?? "";
        switch (kind)
        {
            case "reg":
                return FormatValue(record.OV, record.OE ?? false);
            case "reg2":
                return $"{FormatValue(record.OV, record.OE ?? false)} / " +
                       $"{item.V2}={FormatValue(record.OV2, record.OE2 ?? false)}";
            case "regdel":
                return (record.OE ?? false) ? $"残留值={JsonValue.ToString(record.OV)}" : "已移除";
            case "svc":
            {
                var map = ReadServiceMap(record.SV);
                var manual = map.Values.Count(v => StartValue(v) == 3);
                return $"{manual}/{map.Count} 个服务为手动启动";
            }
            case "power":
                return $"AC={JsonValue.ToUInt32(record.OAC)?.ToString() ?? "?"}/DC=" +
                       $"{JsonValue.ToUInt32(record.ODC)?.ToString() ?? "?"}";
            case "scheme":
                return (record.UC ?? false) ? "已是目标方案" : "当前方案";
            case "display":
                return $"当前{JsonValue.ToInt32(record.RR) ?? 0}Hz/最高{item.MR ?? 0}Hz";
            case "gpupref":
                return FormatValue(record.OV, record.OE ?? false);
            case "intelpnp":
            case "gpupnp":
                return $"PnP={JsonValue.ToUInt32(record.OV) ?? 0}";
            case "intelftc":
                return $"FTC=0x{(JsonValue.ToUInt32(record.OV) ?? 0):X8}";
            case "inteldps":
                return (record.OE ?? false) ? $"DPS={JsonValue.ToUInt32(record.OV) ?? 0}" : "未设置(驱动默认)";
            case "tdrdelay":
                return (record.OE ?? false) ? $"TDR={JsonValue.ToUInt32(record.OV) ?? 0}秒" : "未设置(默认2秒)";
            case "nic":
                return JsonValue.ToString(record.OV) ?? "未设置";
            case "nicpower":
                return $"PnPCapabilities={JsonValue.ToUInt32(record.OV) ?? 0}";
            default:
                return FormatValue(record.OV, record.OE ?? false);
        }
    }

    private static string FormatValue(JsonElement? value, bool exists) =>
        !exists || value is null ? "(未设置)" : JsonValue.ToString(value) ?? "";

    private static bool NeedsReboot(OptimizationItem item)
    {
        var kind = item.Kind ?? "";
        if (kind is "nicpower" or "intelpnp" or "gpupnp" or "inteldps" or "tdrdelay" or "pnpclean" or "drr")
            return true;
        return item.Id is "hags" or "tcpoffload" or "idpst" or "ipsr" or "nvpstate" or "amdulps";
    }

    // ───────────────────────────────────────────────────────
    // 备份 / 快照 / 待重启状态
    // ───────────────────────────────────────────────────────
    private string WriteBackup(IReadOnlyList<OptimizationBackupRecord> records)
    {
        Directory.CreateDirectory(_backupDirectory);
        var stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        var path = Path.Combine(_backupDirectory, $"backup_{stamp}.json");
        if (File.Exists(path))
            path = Path.Combine(_backupDirectory, $"backup_{stamp}_{DateTime.Now:fff}.json");

        var data = new OptimizationBackupFile
        {
            Time = DateTime.Now.ToString("s"),
            Version = "v5.0",
            Records = records.ToList()
        };
        File.WriteAllText(path, JsonSerializer.Serialize(data, BackupJson), new UTF8Encoding(false));
        return path;
    }

    private void WritePendingState(IReadOnlyList<OptimizationItem> items,
        IReadOnlyList<OptimizationError> errors, string? backup)
    {
        try
        {
            Directory.CreateDirectory(_backupDirectory);
            var state = new OptimizationPendingState
            {
                Time = DateTime.Now.ToString("s"),
                Items = items.Select(i => new OptimizationPendingItem { Id = i.Id, Name = i.Name }).ToList(),
                Errors = errors.ToList(),
                Backup = backup,
                Checked = false
            };
            File.WriteAllText(Path.Combine(_backupDirectory, "state_last_apply.json"),
                JsonSerializer.Serialize(state, BackupJson), new UTF8Encoding(false));
        }
        catch { }
    }

    private string? ExportRegSnapshot(IReadOnlyList<OptimizationBackupRecord> records)
    {
        var keys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var record in records)
        {
            foreach (var name in new[] { "P", "SK", "R", "SubKey", "Path" })
            {
                var raw = record.GetString(name);
                if (string.IsNullOrWhiteSpace(raw)) continue;
                if (RegistryPath.TryParse(raw, out var location)) keys.Add(location.ToRegExePath());
            }
        }
        if (keys.Count == 0) return null;

        var dir = Path.Combine(_backupDirectory, $"reg_{DateTime.Now:yyyyMMdd_HHmmss}");
        Directory.CreateDirectory(dir);
        var index = 0;
        foreach (var key in keys)
        {
            index++;
            var safe = Regex.Replace(key, @"[^A-Za-z0-9_\-]", "_");
            if (safe.Length > 70) safe = safe[^70..];
            var file = Path.Combine(dir, $"{index:D2}_{safe}.reg");
            try
            {
                PowerShellRunner.Execute("reg.exe", new[] { "export", key, file, "/y" },
                    TimeSpan.FromSeconds(30));
            }
            catch { }
        }
        return dir;
    }

    private IEnumerable<FileInfo> EnumerateBackupFiles()
    {
        if (!Directory.Exists(_backupDirectory)) yield break;
        foreach (var file in new DirectoryInfo(_backupDirectory)
                     .GetFiles("backup_*.json")
                     .OrderByDescending(f => f.LastWriteTime))
            yield return file;
    }

    // ───────────────────────────────────────────────────────
    // 注册表 / 网卡 / 电源辅助
    // ───────────────────────────────────────────────────────
    private static RegistryValueSnapshot ReadValue(string path, string name)
    {
        if (!RegistryPath.TryParse(path, out var location)) return default;
        try
        {
            using var key = location.Open(writable: false);
            if (key is null) return default;
            var names = key.GetValueNames();
            if (!names.Any(n => string.Equals(n, name, StringComparison.OrdinalIgnoreCase))) return default;
            var value = key.GetValue(name, null, RegistryValueOptions.DoNotExpandEnvironmentNames);
            var kind = key.GetValueKind(name);
            return new RegistryValueSnapshot(true, value, kind);
        }
        catch
        {
            return default;
        }
    }

    private static void WriteValue(string path, string name, JsonElement? value, string type)
    {
        if (!RegistryPath.TryParse(path, out var location))
            throw new InvalidOperationException($"无法解析注册表路径: {path}");
        using var key = location.Open(writable: true)
                        ?? throw new InvalidOperationException($"无法打开注册表路径: {path}");

        var kind = ParseKind(type);
        object data = kind switch
        {
            RegistryValueKind.DWord => unchecked((int)(JsonValue.ToUInt32(value) ?? 0)),
            RegistryValueKind.QWord => (long)(JsonValue.ToUInt32(value) ?? 0),
            RegistryValueKind.MultiString => (JsonValue.ToString(value) ?? "").Split('\0',
                StringSplitOptions.RemoveEmptyEntries),
            RegistryValueKind.Binary => ParseBinary(JsonValue.ToString(value)),
            _ => JsonValue.ToString(value) ?? ""
        };
        key.SetValue(name, data, kind);
    }

    private static void WriteUInt32(string path, string name, uint value) =>
        WriteValue(path, name, ToElement(value), "DWord");

    private static void DeleteValue(string path, string name)
    {
        if (!RegistryPath.TryParse(path, out var location)) return;
        try
        {
            using var key = location.Open(writable: true);
            if (key is null) return;
            var names = key.GetValueNames();
            if (names.Any(n => string.Equals(n, name, StringComparison.OrdinalIgnoreCase)))
                key.DeleteValue(name, throwOnMissingValue: false);
        }
        catch { }
    }

    private static bool KeyExists(string path)
    {
        if (!RegistryPath.TryParse(path, out var location)) return false;
        try
        {
            using var key = location.Open(writable: false);
            return key is not null;
        }
        catch { return false; }
    }

    private static RegistryValueKind ParseKind(string type) => type.ToLowerInvariant() switch
    {
        "dword" => RegistryValueKind.DWord,
        "qword" => RegistryValueKind.QWord,
        "expandstring" => RegistryValueKind.ExpandString,
        "multistring" => RegistryValueKind.MultiString,
        "binary" => RegistryValueKind.Binary,
        _ => RegistryValueKind.String
    };

    private static byte[] ParseBinary(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return Array.Empty<byte>();
        try { return Convert.FromHexString(text.Replace(" ", "").Replace("-", "")); }
        catch { return Array.Empty<byte>(); }
    }

    private static uint StartValue(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return 3;
        return value.Trim().ToLowerInvariant() switch
        {
            "boot" => 0,
            "system" => 1,
            "automatic" => 2,
            "manual" => 3,
            "disabled" => 4,
            _ => uint.TryParse(value, out var parsed) ? parsed : 3
        };
    }

    private static Dictionary<string, string> ReadServiceMap(JsonElement? element)
    {
        var map = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (element is null || element.Value.ValueKind != JsonValueKind.Object) return map;
        foreach (var property in element.Value.EnumerateObject())
            map[property.Name] = JsonValue.ToString(property.Value) ?? "";
        return map;
    }

    private static JsonElement? ReadNicValue(string adapter, string keyword)
    {
        var script = $@"
$ErrorActionPreference = 'Stop'
$p = Get-NetAdapterAdvancedProperty -Name {PsQuote(adapter)} -RegistryKeyword {PsQuote(keyword)} -ErrorAction Stop | Select-Object -First 1
if (-not $p) {{ throw '未找到该网卡属性' }}
@{{ RegistryValue = $p.RegistryValue }} | ConvertTo-Json -Compress
";
        var output = PowerShellRunner.RunScript(script, TimeSpan.FromSeconds(60)).Trim();
        if (string.IsNullOrWhiteSpace(output)) return null;
        using var doc = JsonDocument.Parse(output);
        if (!doc.RootElement.TryGetProperty("RegistryValue", out var value)) return null;
        return value.Clone();
    }

    private static void WriteNicValue(string adapter, string keyword, JsonElement? value)
    {
        var literal = PsLiteral(value);
        var script = $@"
$ErrorActionPreference = 'Stop'
Set-NetAdapterAdvancedProperty -Name {PsQuote(adapter)} -RegistryKeyword {PsQuote(keyword)} -RegistryValue {literal} -ErrorAction Stop
";
        PowerShellRunner.RunScript(script, TimeSpan.FromSeconds(60));
    }

    private (bool Supported, string? Path, uint Value, bool Exists) ResolveNicPower(string adapter)
    {
        try
        {
            var script = $@"
$ErrorActionPreference = 'Stop'
$n = Get-NetAdapter -Name {PsQuote(adapter)} -ErrorAction Stop | Select-Object -First 1
@{{ InterfaceGuid = [string]$n.InterfaceGuid; InterfaceDescription = [string]$n.InterfaceDescription;
    PnPDeviceID = [string]$n.PnPDeviceID }} | ConvertTo-Json -Compress
";
            var output = PowerShellRunner.RunScript(script, TimeSpan.FromSeconds(30)).Trim();
            if (string.IsNullOrWhiteSpace(output)) return (false, null, 0, false);
            using var doc = JsonDocument.Parse(output);
            var root = doc.RootElement;
            var guid = NormalizeGuid(root.TryGetProperty("InterfaceGuid", out var g) ? g.GetString() : null);
            var pnp = NormalizeGuid(root.TryGetProperty("PnPDeviceID", out var p) ? p.GetString() : null);
            var description = root.TryGetProperty("InterfaceDescription", out var d) ? d.GetString() : null;

            if (RegistryPath.TryParse(NicClassPath, out var classLocation))
            {
                using var classKey = classLocation.Open(writable: false);
                if (classKey is not null)
                {
                    foreach (var subName in classKey.GetSubKeyNames())
                    {
                        if (!NicSubKeyPattern.IsMatch(subName)) continue;
                        using var sub = classKey.OpenSubKey(subName, writable: false);
                        if (sub is null) continue;
                        var netCfg = NormalizeGuid(sub.GetValue("NetCfgInstanceId") as string);
                        var deviceId = NormalizeGuid(sub.GetValue("DeviceInstanceID") as string);
                        var driverDesc = sub.GetValue("DriverDesc") as string;

                        var hit = (!string.IsNullOrEmpty(guid) && guid == netCfg) ||
                                  (!string.IsNullOrEmpty(pnp) && pnp == deviceId) ||
                                  (!string.IsNullOrEmpty(description) &&
                                   string.Equals(description, driverDesc, StringComparison.OrdinalIgnoreCase)) ||
                                  (!string.IsNullOrEmpty(description) && !string.IsNullOrEmpty(driverDesc) &&
                                   description.StartsWith(driverDesc!, StringComparison.OrdinalIgnoreCase));
                        if (!hit) continue;

                        var path = $@"HKLM:\SYSTEM\CurrentControlSet\Control\Class\{{4d36e972-e325-11ce-bfc1-08002be10318}}\{subName}";
                        var value = ReadValue(path, "PnPCapabilities");
                        return (true, path, value.AsUInt32(), value.Exists);
                    }
                }
            }
        }
        catch { }

        try
        {
            var script = $@"
$ErrorActionPreference = 'Stop'
$pm = Get-NetAdapterPowerManagement -Name {PsQuote(adapter)} -ErrorAction Stop
if (-not $pm -or 'AllowComputerToTurnOffDevice' -notin $pm.PSObject.Properties.Name) {{ throw '不支持' }}
[string]$pm.AllowComputerToTurnOffDevice
";
            var state = PowerShellRunner.RunScript(script, TimeSpan.FromSeconds(30)).Trim();
            if (state.Length == 0) return (false, null, 0, false);
            return (true, null, string.Equals(state, "Disabled", StringComparison.OrdinalIgnoreCase) ? 24u : 0u, false);
        }
        catch
        {
            return (false, null, 0, false);
        }
    }

    private static void WriteNicPower(string adapter, (bool Supported, string? Path, uint Value, bool Exists) resolved,
        uint target)
    {
        if (!string.IsNullOrWhiteSpace(resolved.Path))
        {
            if (target == 0) DeleteValue(resolved.Path!, "PnPCapabilities");
            else WriteUInt32(resolved.Path!, "PnPCapabilities", target);
            return;
        }

        var script = target != 0
            ? $"$ErrorActionPreference = 'Stop'; Disable-NetAdapterPowerManagement -Name {PsQuote(adapter)} -ErrorAction Stop | Out-Null"
            : $"$ErrorActionPreference = 'Stop'; Enable-NetAdapterPowerManagement -Name {PsQuote(adapter)} -ErrorAction Stop | Out-Null";
        try
        {
            PowerShellRunner.RunScript(script, TimeSpan.FromSeconds(60));
        }
        catch (Exception ex)
        {
            throw new InvalidOperationException("网卡电源管理命令失败: " + ex.Message, ex);
        }
    }

    // ───────────────────────────────────────────────────────
    // 杂项
    // ───────────────────────────────────────────────────────
    private static string Require(string? value, string what) =>
        string.IsNullOrWhiteSpace(value) ? throw new InvalidOperationException("缺少" + what) : value.Trim();

    private static JsonElement? ToElement(object? value)
    {
        if (value is null) return null;
        if (value is JsonElement element) return element.Clone();
        return JsonSerializer.SerializeToElement(value);
    }

    private static string PsQuote(string value) => "'" + value.Replace("'", "''") + "'";

    private static string PsLiteral(JsonElement? value)
    {
        if (value is null) return "$null";
        var element = value.Value;
        return element.ValueKind switch
        {
            JsonValueKind.Number => element.GetRawText(),
            JsonValueKind.True => "$true",
            JsonValueKind.False => "$false",
            JsonValueKind.String => PsQuote(element.GetString() ?? ""),
            _ => PsQuote(element.GetRawText())
        };
    }

    private static string NormalizeGuid(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "" : value.Trim().Trim('{', '}').ToLowerInvariant();

    private static string GetCurrentSid()
    {
        try { return WindowsIdentity.GetCurrent().User?.Value ?? ""; }
        catch { return ""; }
    }
}
