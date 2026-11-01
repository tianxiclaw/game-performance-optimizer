using System.Text.RegularExpressions;
using GamePerfCenter.Core.Infrastructure;
using GamePerfCenter.Core.Models;

namespace GamePerfCenter.Core.Services;

/// <summary>读取 %WINDIR%\INF 下的驱动 INF，提取版本、日期、厂商与硬件 ID。</summary>
public sealed class InfMetadataReader
{
    private static readonly Regex SectionPattern = new(@"^\[(.+)\]$", RegexOptions.Compiled);
    private static readonly Regex DriverVerPattern = new(@"^(?i)DriverVer\s*=\s*([^,]+),\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex ProviderPattern = new(@"^(?i)Provider\s*=\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex ClassPattern = new(@"^(?i)Class\s*=\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex StringPattern = new(@"^([^=]+?)\s*=\s*(.+)$", RegexOptions.Compiled);
    private static readonly Regex ProviderTokenPattern = new(@"^%(.+)%$", RegexOptions.Compiled);
    private static readonly Regex ExcludedSectionPattern = new(
        @"^(?i)(Version|Strings|Manufacturer|SourceDisksNames|SourceDisksFiles|DestinationDirs|ControlFlags|ClassInstall.*|AddReg|CopyFiles|DeleteFiles|RenFiles|UpdateInis|UpdateIniFields|Ini2Reg|LogConfig.*|.*\.Services|.*\.HW|.*\.CoInstallers.*)$",
        RegexOptions.Compiled);
    private static readonly Regex HardwareIdPattern = new(
        @"^(?i)(PCI|USB|HID|ROOT|SWC|ACPI|BTHENUM|BTHLEDEVICE|SCSI|IDE|STORAGE|SWD|DISPLAY|MODEM|MF|PCMCIA|1394|SD|SMBIOS|INTELAUDIO|HDAUDIO)\\",
        RegexOptions.Compiled);
    private static readonly Regex GuidPattern = new(@"^\{[0-9A-Fa-f\-]{36}\}$", RegexOptions.Compiled);

    private readonly string _infDirectory;
    private readonly Dictionary<string, InfMetadata?> _cache = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _lock = new();

    public InfMetadataReader(string? infDirectory = null)
    {
        _infDirectory = string.IsNullOrWhiteSpace(infDirectory)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "INF")
            : infDirectory;
    }

    public InfMetadata? Read(string? infName)
    {
        if (string.IsNullOrWhiteSpace(infName)) return null;
        var key = infName.Trim();
        lock (_lock)
        {
            if (_cache.TryGetValue(key, out var cached)) return cached;
        }

        var metadata = Parse(key);
        lock (_lock)
        {
            _cache[key] = metadata;
        }
        return metadata;
    }

    /// <summary>读取任意路径的 INF，用于安装包不在 %WINDIR%\INF 的场景。</summary>
    public InfMetadata? ReadFile(string? path)
    {
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return null;
        return ParseFile(Path.GetFileName(path), path);
    }

    public void ClearCache()
    {
        lock (_lock) { _cache.Clear(); }
    }

    private InfMetadata? Parse(string infName)
    {
        var path = Path.Combine(_infDirectory, infName);
        if (!File.Exists(path)) return null;
        return ParseFile(infName, path);
    }

    private InfMetadata? ParseFile(string infName, string path)
    {
        try
        {
            var sections = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
            string? current = null;
            foreach (var raw in TextFileReader.ReadAllText(path).Split('\n'))
            {
                var line = raw.Trim().TrimEnd('\r');
                var section = SectionPattern.Match(line);
                if (section.Success)
                {
                    current = section.Groups[1].Value;
                    if (!sections.ContainsKey(current)) sections[current] = new List<string>();
                    continue;
                }
                if (current is not null && line.Length > 0) sections[current].Add(line);
            }

            var version = "";
            var date = "";
            var provider = "";
            var className = "";
            if (sections.TryGetValue("Version", out var versionLines))
            {
                foreach (var line in versionLines)
                {
                    var match = DriverVerPattern.Match(line);
                    if (match.Success)
                    {
                        date = match.Groups[1].Value.Trim();
                        version = match.Groups[2].Value.Trim();
                        continue;
                    }
                    match = ProviderPattern.Match(line);
                    if (match.Success)
                    {
                        provider = match.Groups[1].Value.Trim();
                        continue;
                    }
                    match = ClassPattern.Match(line);
                    if (match.Success) className = match.Groups[1].Value.Trim();
                }
            }

            var strings = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (sections.TryGetValue("Strings", out var stringLines))
            {
                foreach (var line in stringLines)
                {
                    var match = StringPattern.Match(line);
                    if (!match.Success) continue;
                    var value = match.Groups[2].Value.Trim().Trim('"');
                    strings[match.Groups[1].Value.Trim()] = value;
                }
            }

            var providerToken = ProviderTokenPattern.Match(provider);
            if (providerToken.Success && strings.TryGetValue(providerToken.Groups[1].Value, out var resolved))
                provider = resolved;

            var hardwareIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var (sectionName, lines) in sections)
            {
                if (ExcludedSectionPattern.IsMatch(sectionName)) continue;
                foreach (var line in lines)
                {
                    var equals = line.IndexOf('=');
                    if (equals < 0) continue;
                    var parts = line.Split(',');
                    if (parts.Length < 2) continue;
                    for (var i = 1; i < parts.Length; i++)
                    {
                        var hardwareId = parts[i].Trim();
                        var semicolon = hardwareId.IndexOf(';');
                        if (semicolon >= 0) hardwareId = hardwareId[..semicolon].Trim();
                        if (hardwareId.Length == 0) continue;
                        if (HardwareIdPattern.IsMatch(hardwareId) || GuidPattern.IsMatch(hardwareId))
                            hardwareIds.Add(hardwareId.ToUpperInvariant());
                    }
                }
            }

            return new InfMetadata
            {
                InfName = infName,
                Version = version,
                Date = date,
                Provider = provider,
                ClassName = className,
                HardwareIds = hardwareIds.ToArray()
            };
        }
        catch
        {
            return null;
        }
    }
}
