using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using GamePerfCenter.Core.Infrastructure;
using GamePerfCenter.Core.Models;
using GamePerfCenter.Core.Services;
using Microsoft.Win32;

// 无外部依赖的功能测试：覆盖驱动版本比较、硬件 ID 归一化与注册表路径解析。
// 运行：dotnet run --project src/GamePerfCenter.Tests -c Release
// 约定：退出码 0 表示全部通过，1 表示存在失败。

var failures = new List<string>();
var passed = 0;

void Check(string name, bool ok, string? detail = null)
{
    if (ok)
    {
        passed++;
        return;
    }
    failures.Add(detail is null ? name : $"{name} -> {detail}");
}

void Equal<T>(string name, T expected, T actual)
{
    Check(name, EqualityComparer<T>.Default.Equals(expected, actual), $"expected={expected}, actual={actual}");
}

// DriverUtils: 硬件 ID 归一化
Equal("HardwareBase 去除 REV 并大写",
    @"PCI\VEN_10DE&DEV_2684",
    DriverUtils.HardwareBase(@"pci\ven_10de&dev_2684&rev_a1"));
Equal("HardwareBase 空值", "", DriverUtils.HardwareBase("  "));

// DriverUtils: 版本解析与比较
Equal("VersionParts 常规", "31,0,101,5333", string.Join(",", DriverUtils.VersionParts("31.0.101.5333")));
Equal("VersionParts 无效", 0, DriverUtils.VersionParts("abc").Length);
Check("CompareVersion 1.2 < 1.10", DriverUtils.CompareVersion("1.2", "1.10") < 0);
Check("CompareVersion 1.2.0 == 1.2", DriverUtils.CompareVersion("1.2.0", "1.2") == 0);
Check("CompareVersion 空值按 0 处理", DriverUtils.CompareVersion(null, "0.0.1") < 0);

// DriverUtils: pnputil 版本串拆分
var split = DriverUtils.SplitDriverVersion("03/14/2024 31.0.101.5333");
Equal("SplitDriverVersion 日期", "2024/3/14", split.Date);
Equal("SplitDriverVersion 版本", "31.0.101.5333", split.Version);
var rawOnly = DriverUtils.SplitDriverVersion("only-version-text");
Equal("SplitDriverVersion 无法拆分时保留原文", "only-version-text", rawOnly.Version);
Equal("NormalizeDate 兼容短横线", "2024/3/14", DriverUtils.NormalizeDate("2024-03-14"));

// DriverUtils: 硬件 ID 匹配
Check("HardwareMatches 前缀兼容", DriverUtils.HardwareMatches(
    @"PCI\VEN_10DE&DEV_2684&SUBSYS_12345678", @"PCI\VEN_10DE&DEV_2684"));
Check("HardwareMatches 空值不匹配", !DriverUtils.HardwareMatches("", @"PCI\VEN_10DE"));

// RegistryLocation: 路径解析
Check("RegistryLocation 解析 HKLM", RegistryLocation.TryParse(@"HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip", out var hklm)
    && hklm.Hive == RegistryHive.LocalMachine
    && hklm.SubKey == @"SYSTEM\CurrentControlSet\Services\Tcpip");
Check("RegistryLocation 解析 Registry::HKEY_USERS", RegistryLocation.TryParse(@"Registry::HKEY_USERS\S-1-5-21\Software", out var hku)
    && hku.Hive == RegistryHive.Users
    && hku.SubKey == @"S-1-5-21\Software");
Check("RegistryLocation 解析 HKCU 冒号", RegistryLocation.TryParse(@"HKCU:Software\Microsoft", out var hkcu)
    && hkcu.Hive == RegistryHive.CurrentUser
    && hkcu.SubKey == @"Software\Microsoft");
Check("RegistryLocation 拒绝普通路径", !RegistryLocation.TryParse(@"C:\Temp", out _));

var regPath = new RegistryLocation(RegistryHive.LocalMachine, @"SYSTEM\Test");
Equal("ToRegExePath", @"HKEY_LOCAL_MACHINE\SYSTEM\Test", regPath.ToRegExePath());
Equal("ToPowerShellPath", @"HKLM:\SYSTEM\Test", regPath.ToPowerShellPath());

// RegistryValueSnapshot: 值转换
Equal("AsUInt32 整数", 42u, new RegistryValueSnapshot(true, 42, RegistryValueKind.DWord).AsUInt32());
Equal("AsUInt32 字符串", 7u, new RegistryValueSnapshot(true, "7", RegistryValueKind.String).AsUInt32());
Equal("AsUInt32 缺失", 0u, new RegistryValueSnapshot(false, null, RegistryValueKind.Unknown).AsUInt32());
Equal("AsText 字符串数组", "a;b", new RegistryValueSnapshot(true, new[] { "a", "b" }, RegistryValueKind.MultiString).AsText());

// OptimizationCatalogService: 项目录解析
const string catalogJson = """
    {
      "version": "v5.0",
      "context": { "machine": "TEST-PC", "osBuild": 22631 },
      "items": [
        { "Id": "t_reg", "Cat": "测试", "Name": "示例", "Kind": "reg",
          "T": 1, "TL": "开启(1)", "R": "low", "E": true }
      ]
    }
    """;
var catalog = OptimizationCatalogService.Parse(catalogJson);
Equal("Catalog 解析项数", 1, catalog.Items.Count);
Equal("Catalog 解析 Kind", "reg", catalog.Items[0].Kind);
Equal("Catalog 解析 TargetUInt32", 1u, catalog.Items[0].TargetUInt32);
Equal("Catalog 解析上下文", "TEST-PC", catalog.Context.Machine);

// OptimizationExecutionService: 备份写入与还原解析
var tempRoot = Path.Combine(Path.GetTempPath(), "gpc_tests_" + Guid.NewGuid().ToString("N"));
var backupDir = Path.Combine(tempRoot, "backups");
var service = new OptimizationExecutionService(tempRoot, backupDir, "S-1-5-21-TEST");
try
{
    var record = new OptimizationBackupRecord
    {
        Id = "t_reg", Kind = "reg", P = @"HKCU:\Software\GamePerfCenter.Tests",
        V = "Example", VT = "DWord", OV = JsonSerializer.SerializeToElement(7), OE = true
    };
    var backupPath = service.WriteBackup(new[] { record });
    Check("WriteBackup 生成文件", File.Exists(backupPath));

    var backup = JsonSerializer.Deserialize<OptimizationBackupFile>(
        File.ReadAllText(backupPath, Encoding.UTF8),
        new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
    Equal("备份格式版本", "v5.0", backup?.Version);
    Equal("备份记录数", 1, backup?.Records.Count ?? 0);
    Equal("备份原始值", 7, JsonValue.ToInt32(backup!.Records[0].OV) ?? -1);

    var restore = service.Restore(backupPath, dryRun: true);
    Equal("dry-run 还原成功数", 1, restore.Ok);
    Equal("dry-run 还原失败数", 0, restore.Fail);
    Equal("dry-run 还原记录数", 1, restore.Records);

    var second = service.WriteBackup(new[] { record });
    Check("同一秒内备份文件名不冲突",
        !string.Equals(backupPath, second, StringComparison.OrdinalIgnoreCase));

    var emptyPath = Path.Combine(tempRoot, "empty.json");
    File.WriteAllText(emptyPath, "{\"version\":\"v5.0\",\"records\":[]}");
    var emptyThrew = false;
    try { service.Restore(emptyPath, dryRun: true); }
    catch (InvalidOperationException) { emptyThrew = true; }
    Check("空备份被拒绝", emptyThrew);

    var badPath = Path.Combine(tempRoot, "bad.json");
    File.WriteAllText(badPath, "not json");
    var badThrew = false;
    try { service.Restore(badPath, dryRun: true); }
    catch (InvalidOperationException) { badThrew = true; }
    Check("损坏备份被拒绝", badThrew);
}
finally
{
    try { if (Directory.Exists(tempRoot)) Directory.Delete(tempRoot, true); } catch { }
}

// OptimizationExecutionService: 备份失败时必须中止写入
var blockedRoot = Path.Combine(Path.GetTempPath(), "gpc_block_" + Guid.NewGuid().ToString("N"));
var blockedFile = Path.Combine(blockedRoot, "blocked");
Directory.CreateDirectory(blockedRoot);
File.WriteAllText(blockedFile, "x");
try
{
    var failing = new OptimizationExecutionService(blockedRoot, blockedFile, "S-1-5-21-TEST");
    var item = new OptimizationItem
    {
        Id = "t_regdel", Kind = "regdel", Name = "test",
        P = @"HKCU:\Software\GamePerfCenter.Tests\NoSuch", V = "NoSuchValue"
    };
    var result = failing.Apply(new OptimizationContext(), new[] { item },
        new OptimizationApplyOptions { NoRegSnapshot = true });
    Equal("备份失败时中止应用", 0, result.Ok);
    Check("备份失败写入错误", result.Errors.Any(e => e.Stage == "backup"));
    Check("备份失败时失败计数", result.Fail > 0);
}
finally
{
    try { Directory.Delete(blockedRoot, true); } catch { }
}

// 仓库级一致性检查：引擎 Kind、界面文案
var repoRoot = FindRepoRoot();
Check("定位仓库根目录", repoRoot is not null);
if (repoRoot is not null)
{
    var engineText = File.ReadAllText(Path.Combine(repoRoot, "游戏性能优化.ps1"));
    var coreText = File.ReadAllText(Path.Combine(repoRoot,
        "src", "GamePerfCenter.Core", "Services", "OptimizationExecutionService.cs"));
    var engineKinds = Regex.Matches(engineText, @"Kind\s*=\s*['""]([a-z0-9]+)['""]")
        .Select(m => m.Groups[1].Value).ToHashSet(StringComparer.Ordinal);
    var coreKinds = Regex.Matches(coreText, @"case ""([a-z0-9]+)"":")
        .Select(m => m.Groups[1].Value).ToHashSet(StringComparer.Ordinal);
    var missingKinds = engineKinds.Except(coreKinds).OrderBy(k => k).ToArray();
    Check("引擎 Kind 均有 Core 处理器", missingKinds.Length == 0,
        string.Join(",", missingKinds));
    Check("引擎 Kind 数量", engineKinds.Count >= 15, $"count={engineKinds.Count}");

    var localizationPath = Path.Combine(repoRoot,
        "src", "GamePerfCenter", "Services", "Localization.cs");
    var localizationText = File.ReadAllText(localizationPath);
    var dictStart = localizationText.IndexOf(
        "private static readonly Dictionary<string, string> English", StringComparison.Ordinal);
    var dictText = dictStart >= 0 ? localizationText[dictStart..] : "";
    var keys = Regex.Matches(dictText, @"\[""((?:[^""\\]|\\.)*)""\]\s*=\s*""")
        .Select(m => m.Groups[1].Value).ToHashSet(StringComparer.Ordinal);

    var missingXaml = new List<string>();
    foreach (var file in Directory.EnumerateFiles(Path.Combine(repoRoot, "src", "GamePerfCenter"),
                 "*.xaml", SearchOption.AllDirectories))
    {
        if (IsBuildPath(file)) continue;
        foreach (Match m in Regex.Matches(File.ReadAllText(file),
                     @"\b(?:Text|Header|Content|Title|Subtitle|Description|ToolTipService\.ToolTip|PlaceholderText|OnContent|OffContent|AutomationProperties\.Name)=""([^""]*)"""))
        {
            var value = m.Groups[1].Value.Trim();
            if (!ContainsChinese(value) || value.StartsWith('{')) continue;
            if (!keys.Contains(value)) missingXaml.Add($"{Path.GetFileName(file)}: {value}");
        }
    }
    Check("XAML 中文文案均有英文词条", missingXaml.Count == 0,
        string.Join(" | ", missingXaml.Distinct().Take(5)));

    var missingCode = new List<string>();
    foreach (var file in Directory.EnumerateFiles(Path.Combine(repoRoot, "src", "GamePerfCenter"),
                 "*.cs", SearchOption.AllDirectories))
    {
        if (IsBuildPath(file)) continue;
        foreach (Match m in Regex.Matches(File.ReadAllText(file),
                     @"Localization\.(?:T|F)\(\s*""((?:[^""\\]|\\.)*)"""))
        {
            var value = m.Groups[1].Value;
            if (!ContainsChinese(value) || keys.Contains(value)) continue;
            missingCode.Add($"{Path.GetFileName(file)}: {value}");
        }
    }
    Check("代码中文文案均有英文词条", missingCode.Count == 0,
        string.Join(" | ", missingCode.Distinct().Take(5)));

    var propsText = File.ReadAllText(Path.Combine(repoRoot, "Directory.Build.props"));
    var appVersion = Regex.Match(propsText, @"<AppVersion>\s*([^<]+?)\s*</AppVersion>")
        .Groups[1].Value;
    var issText = File.ReadAllText(Path.Combine(repoRoot, "安装包", "游戏性能优化中心.iss"));
    var issVersion = Regex.Match(issText, @"#define\s+MyAppVersion\s+""([^""]+)""")
        .Groups[1].Value;
    Check("安装包版本与 Directory.Build.props 一致",
        !string.IsNullOrEmpty(appVersion) && appVersion == issVersion,
        $"props={appVersion}, iss={issVersion}");
}

static string? FindRepoRoot()
{
    var dir = new DirectoryInfo(AppContext.BaseDirectory);
    for (var i = 0; i < 10 && dir is not null; i++, dir = dir.Parent)
    {
        if (File.Exists(Path.Combine(dir.FullName, "游戏性能优化.ps1")) &&
            Directory.Exists(Path.Combine(dir.FullName, "src")))
            return dir.FullName;
    }
    return null;
}

static bool IsBuildPath(string path) =>
    path.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}") ||
    path.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}");

static bool ContainsChinese(string value) =>
    value.Any(c => c >= 0x4E00 && c <= 0x9FFF);

Console.WriteLine($"通过 {passed} 项，失败 {failures.Count} 项。");
if (failures.Count == 0) return 0;

foreach (var failure in failures) Console.WriteLine("FAIL " + failure);
return 1;
