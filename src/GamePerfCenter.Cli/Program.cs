using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;
using GamePerfCenter.Core.Models;
using GamePerfCenter.Core.Services;

namespace GamePerfCenter.Cli;

internal static class Program
{
    private const string Version = "6.3.0";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping
    };

    private static int Main(string[] args)
    {
        try { Console.OutputEncoding = new UTF8Encoding(false); } catch { }

        try
        {
            return Run(args);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("错误: " + ex.Message);
            return 1;
        }
    }

    private static int Run(string[] args)
    {
        if (args.Length == 0 || IsHelp(args[0]))
        {
            PrintHelp();
            return 0;
        }

        if (args[0] is "--version" or "-v" or "version")
        {
            Console.WriteLine($"gpc {Version}");
            return 0;
        }

        if (string.Equals(args[0], "audio", StringComparison.OrdinalIgnoreCase))
            return RunAudio(args);

        if (string.Equals(args[0], "items", StringComparison.OrdinalIgnoreCase))
            return RunItems(args);

        if (!string.Equals(args[0], "drivers", StringComparison.OrdinalIgnoreCase))
        {
            Console.Error.WriteLine($"未知命令: {args[0]}");
            PrintHelp();
            return 1;
        }

        var subcommand = args.Length > 1 && !args[1].StartsWith('-') ? args[1].ToLowerInvariant() : "scan";
        var json = HasFlag(args, "--json", "-j");
        var force = HasFlag(args, "--force", "--no-cache");
        var withUpdates = HasFlag(args, "--updates", "-u");

        var service = new DriverInventoryService();

        switch (subcommand)
        {
            case "reinstall":
                return RunReinstall(service, args, json);
            case "switch":
                return RunSwitch(service, args, json);
            case "delete":
            case "clean":
                return RunDelete(service, args, json);
            case "install":
                return RunInstall(service, args, json);
            case "scan":
            {
                var inventory = service.Scan(withUpdates, force);
                if (json) WriteJson(inventory);
                else PrintInventory(inventory);
                return 0;
            }
            case "devices":
            {
                var devices = service.DeviceScanner.Scan(force);
                if (json) WriteJson(new { count = devices.Count, devices });
                else PrintDevices(devices);
                return 0;
            }
            case "packages":
            {
                var packages = service.PackageScanner.Scan(force);
                if (json) WriteJson(new { count = packages.Count, packages });
                else PrintPackages(packages);
                return 0;
            }
            case "updates":
            {
                var updates = service.UpdateScanner.Scan(force);
                if (json) WriteJson(new { count = updates.Count, updates });
                else PrintUpdates(updates);
                return 0;
            }
            default:
                Console.Error.WriteLine($"未知子命令: drivers {subcommand}");
                PrintHelp();
                return 1;
        }
    }

    private static bool HasFlag(string[] args, params string[] names) =>
        args.Any(arg => names.Any(name => string.Equals(arg, name, StringComparison.OrdinalIgnoreCase)));

    private static bool IsHelp(string value) =>
        value is "-h" or "--help" or "help" or "/?";

    private static void WriteJson(object value) =>
        Console.WriteLine(JsonSerializer.Serialize(value, JsonOptions));

    private static void PrintInventory(DriverInventory inventory)
    {
        var summary = inventory.Summary;
        Console.WriteLine("游戏性能优化中心 · 驱动清单");
        Console.WriteLine($"扫描时间  {inventory.ScannedAt:yyyy/M/d HH:mm:ss}");
        var wuText = summary.WuChecked
            ? "已检测 Windows Update"
            : inventory.UpdateError is null ? "未检测 Windows Update" : "Windows Update 检测失败";
        Console.WriteLine($"设备 {summary.DeviceCount} · 可更新 {summary.UpdateCount} · 需处理 {summary.IssueCount} · 驱动包 {summary.PackageCount} · {wuText}");
        if (inventory.UpdateError is not null)
            Console.WriteLine($"更新检测错误: {inventory.UpdateError}");
        Console.WriteLine();

        foreach (var group in inventory.Devices.GroupBy(d => d.Category))
        {
            Console.WriteLine($"── {group.Key} ({group.Count()}) ──");
            foreach (var device in group)
            {
                var status = device.StatusOk ? "正常" : device.StatusText;
                Console.WriteLine($"  [{(device.StatusOk ? "OK" : "!!")}] {device.Name}   {status}");
                Console.WriteLine($"       当前 {ValueOrUnknown(device.Version)} · {ValueOrUnknown(device.Provider)} · {ValueOrUnknown(device.Date)} · {device.InfName}");
                Console.WriteLine($"       仓库 {device.Packages.Count} 包 · 旧版本 {device.OldCount} · 更新 {device.UpdateCount}");
                if (device.Flags.Count > 0)
                    Console.WriteLine("       提示 " + string.Join("；", device.Flags));
            }
            Console.WriteLine();
        }
    }

    private static void PrintDevices(IReadOnlyList<DriverDeviceInfo> devices)
    {
        Console.WriteLine($"已连接设备 {devices.Count} 个");
        foreach (var group in devices.GroupBy(d => d.Category))
        {
            Console.WriteLine();
            Console.WriteLine($"── {group.Key} ({group.Count()}) ──");
            foreach (var device in group)
            {
                var status = device.StatusOk ? "正常" : device.StatusText;
                Console.WriteLine($"  {device.Name}   {ValueOrUnknown(device.Version)} · {ValueOrUnknown(device.Provider)} · {status}");
                Console.WriteLine($"     {device.InfName}   {device.DeviceId}");
            }
        }
    }

    private static void PrintPackages(IReadOnlyList<DriverPackageInfo> packages)
    {
        Console.WriteLine($"驱动仓库共 {packages.Count} 个驱动包");
        Console.WriteLine();
        Console.WriteLine($"{"发布名称",-14} {"类",-12} {"版本",-18} {"日期",-12} 厂商 / 原始名称");
        foreach (var package in packages)
        {
            Console.WriteLine(
                $"{package.PublishedName,-14} {package.ClassName,-12} {package.Version,-18} {package.Date,-12} " +
                $"{package.ProviderName} / {package.OriginalName}");
        }
    }

    private static void PrintUpdates(IReadOnlyList<DriverUpdateInfo> updates)
    {
        if (updates.Count == 0)
        {
            Console.WriteLine("Windows Update 未发现可用的驱动更新。");
            return;
        }
        Console.WriteLine($"Windows Update 可用驱动更新 {updates.Count} 个");
        Console.WriteLine();
        foreach (var update in updates)
        {
            var hidden = update.Hidden ? "（已隐藏）" : "";
            Console.WriteLine($"  {update.Title}{hidden}");
            Console.WriteLine($"     {update.Version} · {update.ClassName} · {update.Date} · {update.HardwareId}");
        }
    }

    private static int RunItems(string[] args)
    {
        var sub = args.Length > 1 && !args[1].StartsWith('-') ? args[1].ToLowerInvariant() : "list";
        var json = HasFlag(args, "--json", "-j");
        var catalogService = new OptimizationCatalogService();
        var engineDir = Path.GetDirectoryName(catalogService.EnginePath);
        var execution = new OptimizationExecutionService(
            string.IsNullOrWhiteSpace(engineDir) ? null : engineDir);

        switch (sub)
        {
            case "list":
                return RunItemsList(args, json, catalogService, execution);
            case "apply":
                return RunItemsApply(args, json, catalogService, execution);
            case "restore":
                return RunItemsRestore(args, json, execution);
            case "backups":
                return RunItemsBackups(json, execution);
            case "pending":
                return RunItemsPending(json, execution);
            default:
                Console.Error.WriteLine($"未知子命令: items {sub}");
                PrintHelp();
                return 1;
        }
    }

    private static int RunItemsList(string[] args, bool json, OptimizationCatalogService catalogService,
        OptimizationExecutionService execution)
    {
        var catalog = catalogService.Load(HasFlag(args, "--refresh", "--force"));
        var category = GetOption(args, "--category");
        var withStatus = HasFlag(args, "--status");
        var items = catalog.Items
            .Where(item => string.IsNullOrWhiteSpace(category) ||
                           string.Equals(item.Cat, category, StringComparison.OrdinalIgnoreCase))
            .ToList();

        var rows = new List<object>();
        foreach (var item in items)
        {
            bool? satisfied = null;
            string? current = null;
            string? status = null;
            if (withStatus)
            {
                var probe = execution.Probe(item, catalog.Context);
                satisfied = probe.Supported && probe.Satisfied;
                current = probe.Current;
                status = !probe.Supported ? "na" : probe.Satisfied ? "ok" : "no";
            }

            rows.Add(new
            {
                id = item.Id,
                cat = item.Cat,
                name = item.Name,
                kind = item.Kind,
                desc = item.Desc,
                target = item.TargetLabel,
                risk = item.Risk,
                defaultEnabled = item.DefaultEnabled,
                status,
                current
            });
        }

        if (json)
        {
            WriteJson(new
            {
                version = catalog.Version,
                time = catalog.Time,
                machine = catalog.Context.Machine,
                count = rows.Count,
                items = rows
            });
            return 0;
        }

        Console.WriteLine($"游戏性能优化中心 · 优化项目录  {catalog.Version}");
        Console.WriteLine($"{catalog.Context.Machine} · 共 {items.Count} 项"
                          + (withStatus ? " · 已检测当前状态" : " · 加 --status 可检测当前状态"));
        Console.WriteLine();
        foreach (var group in items.GroupBy(i => i.Cat ?? "其他"))
        {
            Console.WriteLine($"── {group.Key} ({group.Count()}) ──");
            foreach (var item in group)
            {
                var mark = item.DefaultEnabled ? "[推荐]" : "[可选]";
                var risk = item.Risk?.ToLowerInvariant() switch
                {
                    "low" => "低",
                    "med" => "中",
                    "high" => "高",
                    _ => "-"
                };
                Console.Write($"  {mark} {item.Name}  目标 {item.TargetLabel}  风险 {risk}");
                if (withStatus)
                {
                    var probe = execution.Probe(item, catalog.Context);
                    var state = !probe.Supported ? "不可用" : probe.Satisfied ? "已生效" : "待处理";
                    Console.Write($"  · {state} ({probe.Current})");
                }
                Console.WriteLine();
                if (!string.IsNullOrWhiteSpace(item.Desc)) Console.WriteLine($"        {item.Desc}");
            }
            Console.WriteLine();
        }
        return 0;
    }

    private static int RunItemsApply(string[] args, bool json, OptimizationCatalogService catalogService,
        OptimizationExecutionService execution)
    {
        var catalog = catalogService.Load(HasFlag(args, "--refresh", "--force"));
        var ids = GetPositionals(args, 2).ToList();
        if (ids.Count == 0)
        {
            ids = HasFlag(args, "--all")
                ? catalog.Items.Select(i => i.Id).ToList()
                : catalog.Items.Where(i => string.Equals(i.Risk, "low", StringComparison.OrdinalIgnoreCase))
                    .Select(i => i.Id).ToList();
        }
        if (ids.Count == 0)
        {
            Console.Error.WriteLine("没有可应用的优化项。");
            return 1;
        }

        var execute = HasFlag(args, "--yes", "-y");
        var options = new OptimizationApplyOptions
        {
            DryRun = HasFlag(args, "--dry-run") || !execute,
            NoBackup = HasFlag(args, "--no-backup"),
            RestorePoint = HasFlag(args, "--restore-point")
        };
        var result = execution.Apply(catalog, ids, options);

        if (json) WriteJson(result);
        else
        {
            if (options.DryRun)
            {
                Console.WriteLine($"预览：{result.Preview.Count} 项将变更，{result.Errors.Count} 项无法执行。");
                foreach (var item in result.Preview)
                {
                    Console.WriteLine($"  {item.Name}");
                    Console.WriteLine($"    {item.Current} → {item.Target}" +
                                      (item.NeedsReboot ? "（需重启）" : ""));
                }
                foreach (var error in result.Errors)
                    Console.WriteLine($"  [失败] {error.Name ?? error.Id}: {error.Message}");
                if (result.Preview.Count > 0)
                    Console.WriteLine("\n这是预览，未写入系统。确认无误后加 --yes 执行。");
            }
            else
            {
                Console.WriteLine($"应用完成：成功 {result.Ok} 项，失败 {result.Fail} 项。");
                if (!string.IsNullOrWhiteSpace(result.Backup)) Console.WriteLine($"备份：{result.Backup}");
                if (!string.IsNullOrWhiteSpace(result.RegDir)) Console.WriteLine($".reg 快照：{result.RegDir}");
                if (result.RestorePointCreated) Console.WriteLine("已创建系统还原点。");
                else if (!string.IsNullOrWhiteSpace(result.RestorePointMessage))
                    Console.WriteLine($"还原点未创建：{result.RestorePointMessage}");
                foreach (var error in result.Errors)
                    Console.WriteLine($"  [失败] {error.Name ?? error.Id}: {error.Message}");
            }
        }

        return result.Fail == 0 ? 0 : 1;
    }

    private static int RunItemsRestore(string[] args, bool json, OptimizationExecutionService execution)
    {
        if (HasFlag(args, "--all"))
        {
            var all = execution.RestoreAll();
            if (json) WriteJson(all);
            else
            {
                Console.WriteLine($"全量还原完成：{all.Files} 份备份，成功 {all.Ok} 项，失败 {all.Fail} 项。");
                foreach (var error in all.Errors)
                    Console.WriteLine($"  [失败] {error.Id}: {error.Message}");
            }
            return all.Fail == 0 ? 0 : 1;
        }

        var path = GetPositional(args, 2);
        if (string.IsNullOrWhiteSpace(path) || HasFlag(args, "--latest"))
        {
            path = execution.GetBackups().FirstOrDefault()?.Path;
            if (string.IsNullOrWhiteSpace(path))
            {
                Console.Error.WriteLine("没有可用备份。");
                return 1;
            }
        }

        var dryRun = HasFlag(args, "--dry-run");
        var result = execution.Restore(path, dryRun);
        if (json) WriteJson(result);
        else
        {
            Console.WriteLine(dryRun
                ? $"还原预览（{Path.GetFileName(result.File)}）：共 {result.Records} 条记录，可解析 {result.Ok} 项。"
                : $"还原完成（{Path.GetFileName(result.File)}）：成功 {result.Ok} 项，失败 {result.Fail} 项。");
            foreach (var error in result.Errors)
                Console.WriteLine($"  [失败] {error.Id}: {error.Message}");
            if (dryRun) Console.WriteLine("这是预览，未写入系统。确认无误后去掉 --dry-run 执行。");
        }
        return result.Fail == 0 ? 0 : 1;
    }

    private static int RunItemsBackups(bool json, OptimizationExecutionService execution)
    {
        var list = execution.GetBackups();
        if (json)
        {
            WriteJson(new { count = list.Count, backups = list });
            return 0;
        }

        Console.WriteLine($"可用备份 {list.Count} 份");
        foreach (var backup in list)
        {
            Console.WriteLine($"  {backup.Time}  {backup.Records} 条记录  {backup.Size / 1024.0:0.#} KB  {backup.Name}");
        }
        return 0;
    }

    private static int RunItemsPending(bool json, OptimizationExecutionService execution)
    {
        var state = execution.GetPendingState();
        var reboot = execution.GetPendingReboot();
        if (json)
        {
            WriteJson(new { lastApply = state, reboot });
            return 0;
        }

        if (state is null) Console.WriteLine("暂无上次应用记录。");
        else
        {
            Console.WriteLine($"上次应用：{state.Time} · {state.Items.Count} 项"
                              + (state.Errors.Count > 0 ? $" · 失败 {state.Errors.Count}" : ""));
            if (!string.IsNullOrWhiteSpace(state.Result)) Console.WriteLine($"复核：{state.Result}");
            if (!string.IsNullOrWhiteSpace(state.Backup)) Console.WriteLine($"备份：{state.Backup}");
        }

        if (reboot.Pending)
            Console.WriteLine($"系统等待重启：{string.Join(", ", reboot.Reasons)}");
        else
            Console.WriteLine("系统当前无需重启。");
        return 0;
    }

    private static IEnumerable<string> GetPositionals(string[] args, int startIndex)
    {
        for (var i = startIndex; i < args.Length; i++)
            if (!args[i].StartsWith('-')) yield return args[i];
    }

    private static int RunAudio(string[] args)
    {
        var guard = new AudioEndpointGuard();
        var captured = guard.Capture();
        var restored = 0;
        if (args.Length > 1 && string.Equals(args[1], "restore", StringComparison.OrdinalIgnoreCase))
            restored = guard.Restore();

        if (HasFlag(args, "--json", "-j"))
        {
            WriteJson(new { endpoints = captured, restored });
            return 0;
        }

        Console.WriteLine($"活动音频端点 {captured} 个");
        if (args.Length > 1 && string.Equals(args[1], "restore", StringComparison.OrdinalIgnoreCase))
            Console.WriteLine($"立即恢复静音状态 {restored} 个");
        return captured > 0 ? 0 : 2;
    }

    private static int RunReinstall(DriverInventoryService service, string[] args, bool json)
    {
        var query = GetPositional(args, 2);
        if (string.IsNullOrWhiteSpace(query))
        {
            Console.Error.WriteLine("缺少设备标识。用法: gpc drivers reinstall <设备ID|INF|名称> --yes");
            return 1;
        }

        var inventory = service.Scan();
        var device = FindDevice(inventory.Devices, query, out var error);
        if (device is null)
        {
            Console.Error.WriteLine(error ?? $"未找到设备: {query}");
            return 1;
        }

        var options = BuildOperationOptions(args);
        var result = new DriverOperationService().RebindCurrent(device, options);
        return PrintOperation(result, json, options);
    }

    private static int RunSwitch(DriverInventoryService service, string[] args, bool json)
    {
        var packageName = GetPositional(args, 2);
        if (string.IsNullOrWhiteSpace(packageName))
        {
            Console.Error.WriteLine("缺少驱动包名称。用法: gpc drivers switch <oemXX.inf> [--device <设备ID>] --yes");
            return 1;
        }

        var inventory = service.Scan();
        var device = FindDeviceForPackage(inventory.Devices, packageName, GetOption(args, "--device"), out var package, out var error);
        if (device is null || package is null)
        {
            Console.Error.WriteLine(error ?? "未找到匹配的设备或驱动包。");
            return 1;
        }

        var options = BuildOperationOptions(args);
        var result = new DriverOperationService().SwitchPackage(device, package, options);
        return PrintOperation(result, json, options);
    }

    private static int RunDelete(DriverInventoryService service, string[] args, bool json)
    {
        var packageName = GetPositional(args, 2);
        if (string.IsNullOrWhiteSpace(packageName))
        {
            Console.Error.WriteLine("缺少驱动包名称。用法: gpc drivers delete <oemXX.inf> [--device <设备ID>] --yes");
            return 1;
        }

        var inventory = service.Scan();
        var device = FindDeviceForPackage(inventory.Devices, packageName, GetOption(args, "--device"), out var package, out var error);
        if (device is null || package is null)
        {
            Console.Error.WriteLine(error ?? "未找到匹配的设备或驱动包。");
            return 1;
        }

        var options = BuildOperationOptions(args);
        var result = new DriverOperationService().DeletePackage(device, package, options);
        return PrintOperation(result, json, options);
    }

    private static int RunInstall(DriverInventoryService service, string[] args, bool json)
    {
        var infPath = GetPositional(args, 2);
        if (string.IsNullOrWhiteSpace(infPath))
        {
            Console.Error.WriteLine("缺少 INF 路径。用法: gpc drivers install <inf路径> [--device <设备ID>] --yes");
            return 1;
        }

        DriverDeviceInfo? device = null;
        var deviceQuery = GetOption(args, "--device");
        if (!string.IsNullOrWhiteSpace(deviceQuery))
        {
            var inventory = service.Scan();
            device = FindDevice(inventory.Devices, deviceQuery, out var error);
            if (device is null)
            {
                Console.Error.WriteLine(error ?? $"未找到设备: {deviceQuery}");
                return 1;
            }
        }

        var options = BuildOperationOptions(args);
        var result = new DriverOperationService().InstallInf(infPath, device, options);
        return PrintOperation(result, json, options);
    }

    private static DriverOperationOptions BuildOperationOptions(string[] args)
    {
        var execute = HasFlag(args, "--yes", "-y");
        var dryRun = HasFlag(args, "--dry-run") || !execute;
        var force = HasFlag(args, "--force");
        return new DriverOperationOptions
        {
            DryRun = dryRun,
            Uninstall = !HasFlag(args, "--keep-device"),
            Force = force,
            AllowUnverifiedInf = force
        };
    }

    private static int PrintOperation(DriverOperationResult result, bool json, DriverOperationOptions options)
    {
        if (json) WriteJson(result);
        else
        {
            Console.WriteLine($"{result.Action}: {(result.Ok ? "成功" : "失败")}{(result.DryRun ? "（预览）" : "")}");
            if (!string.IsNullOrWhiteSpace(result.DeviceName)) Console.WriteLine($"设备  {result.DeviceName}");
            if (!string.IsNullOrWhiteSpace(result.PublishedName)) Console.WriteLine($"驱动包  {result.PublishedName}");
            if (!string.IsNullOrWhiteSpace(result.InfPath)) Console.WriteLine($"INF  {result.InfPath}");
            if (!string.IsNullOrWhiteSpace(result.Command)) Console.WriteLine($"命令  {result.Command}");
            if (result.AudioEndpoints > 0)
                Console.WriteLine($"音频端点  {result.AudioEndpoints} 个，已恢复静音状态 {result.AudioRestored} 个");
            if (result.RebootRecommended && result.Ok && !result.DryRun)
                Console.WriteLine("提示  部分驱动需要重启后才会完全生效。");
            if (options.DryRun && result.Ok)
                Console.WriteLine("这是预览，未写入系统。确认无误后加 --yes 执行。");
            if (!string.IsNullOrWhiteSpace(result.Message)) Console.WriteLine(result.Message);
        }

        return result.Ok ? 0 : 1;
    }

    private static string? GetOption(string[] args, string name)
    {
        for (var i = 0; i < args.Length - 1; i++)
        {
            if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
                return args[i + 1];
            if (args[i].StartsWith(name + "=", StringComparison.OrdinalIgnoreCase))
                return args[i][(name.Length + 1)..];
        }
        return null;
    }

    private static string? GetPositional(string[] args, int startIndex)
    {
        for (var i = startIndex; i < args.Length; i++)
        {
            if (!args[i].StartsWith('-')) return args[i];
        }
        return null;
    }

    private static DriverDeviceInfo? FindDevice(
        IReadOnlyList<DriverDeviceInfo> devices,
        string query,
        out string? error)
    {
        error = null;
        var exact = devices.Where(d =>
            string.Equals(d.DeviceId, query, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(d.InfName, query, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(d.Name, query, StringComparison.OrdinalIgnoreCase)).ToList();
        if (exact.Count == 1) return exact[0];
        if (exact.Count > 1)
        {
            error = $"“{query}”匹配到多台设备，请改用更完整的设备 ID：\n" +
                    string.Join("\n", exact.Select(d => $"  {d.Name}  {d.DeviceId}"));
            return null;
        }

        var fuzzy = devices.Where(d =>
            d.DeviceId.Contains(query, StringComparison.OrdinalIgnoreCase) ||
            d.Name.Contains(query, StringComparison.OrdinalIgnoreCase)).ToList();
        if (fuzzy.Count == 1) return fuzzy[0];
        if (fuzzy.Count > 1)
        {
            error = $"“{query}”匹配到多台设备，请改用更完整的设备 ID：\n" +
                    string.Join("\n", fuzzy.Select(d => $"  {d.Name}  {d.DeviceId}"));
            return null;
        }

        error = $"未找到设备: {query}";
        return null;
    }

    private static DriverDeviceInfo? FindDeviceForPackage(
        IReadOnlyList<DriverDeviceInfo> devices,
        string packageName,
        string? deviceQuery,
        out DriverPackageMatch? package,
        out string? error)
    {
        package = null;
        error = null;

        IEnumerable<DriverDeviceInfo> candidates = devices;
        if (!string.IsNullOrWhiteSpace(deviceQuery))
        {
            var device = FindDevice(devices, deviceQuery, out error);
            if (device is null) return null;
            candidates = new[] { device };
        }

        var hits = new List<(DriverDeviceInfo Device, DriverPackageMatch Package)>();
        foreach (var device in candidates)
        {
            var match = device.Packages.FirstOrDefault(p =>
                string.Equals(p.PublishedName, packageName, StringComparison.OrdinalIgnoreCase));
            if (match is not null) hits.Add((device, match));
        }

        if (hits.Count == 0)
        {
            error = $"未找到驱动包“{packageName}”。可先运行 gpc drivers scan 查看本机仓库。";
            return null;
        }
        if (hits.Count > 1)
        {
            error = $"驱动包“{packageName}”被多台设备引用，请用 --device 指定设备：\n" +
                    string.Join("\n", hits.Select(h => $"  {h.Device.Name}  {h.Device.DeviceId}"));
            return null;
        }

        package = hits[0].Package;
        return hits[0].Device;
    }

    private static string ValueOrUnknown(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "未知" : value;

    private static void PrintHelp()
    {
        Console.WriteLine($"""
            游戏性能优化中心 CLI  gpc {Version}

            用法:
              gpc drivers scan [--json] [--updates] [--force]
                  扫描设备与驱动仓库；--updates 额外查询 Windows Update
              gpc drivers devices [--json] [--force]
                  只列出已连接设备
              gpc drivers packages [--json] [--force]
                  只列出本机驱动仓库
              gpc drivers updates [--json] [--force]
                  只查询 Windows Update 可用驱动更新

              gpc drivers reinstall <设备ID|INF|名称> [--dry-run] [--yes]
                  用当前 INF 重新绑定驱动
              gpc drivers switch <oemXX.inf> [--device <设备ID>] [--dry-run] [--yes]
                  把设备切换到本机仓库中的另一个驱动包
              gpc drivers delete <oemXX.inf> [--device <设备ID>] [--dry-run] [--yes] [--keep-device] [--force]
                  从驱动仓库清理旧包；默认同时 /uninstall
              gpc drivers install <inf路径> [--device <设备ID>] [--dry-run] [--yes] [--force]
                  安装指定 INF；--force 跳过 INF 与设备的硬件 ID 校验

              gpc audio [status|restore] [--json]
                  查看活动音频端点；restore 立即恢复本次捕获到的静音状态

              gpc items list [--json] [--status] [--category <分类>] [--refresh]
                  列出本机适用的优化项目录；--status 逐项检测当前状态
              gpc items apply [ID...] [--recommended|--all] [--dry-run] [--yes]
                              [--restore-point] [--no-backup] [--json]
                  应用优化项；默认按推荐项（低风险）预览，加 --yes 实际写入
              gpc items restore [备份路径] [--latest|--all] [--dry-run] [--json]
                  还原一份备份；--all 按时间倒序回放全部备份，--dry-run 只校验记录
              gpc items backups [--json]
                  列出可用备份
              gpc items pending [--json]
                  查看上次应用记录与系统待重启状态

              gpc --version
                  显示版本

            说明:
              --json      输出机器可读 JSON
              --force     扫描时跳过 30 秒缓存；驱动操作时跳过硬件 ID 校验并追加 /force
              --dry-run   只预览将执行的命令
              --yes       确认实际执行；不加时驱动操作一律按预览处理
            """);
    }
}
