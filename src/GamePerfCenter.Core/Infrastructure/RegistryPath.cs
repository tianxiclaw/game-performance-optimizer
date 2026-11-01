using Microsoft.Win32;

namespace GamePerfCenter.Core.Infrastructure;

/// <summary>把 PowerShell 注册表路径（HKLM:\、Registry::HKEY_USERS\SID\...）解析成 RegistryHive + 子键。</summary>
public static class RegistryPath
{
    public static bool TryParse(string? raw, out RegistryLocation location) =>
        RegistryLocation.TryParse(raw, out location);
}

public readonly record struct RegistryLocation(RegistryHive Hive, string SubKey)
{
    public static bool TryParse(string? raw, out RegistryLocation location)
    {
        location = default;
        if (string.IsNullOrWhiteSpace(raw)) return false;

        var text = raw.Trim();
        text = StripPrefix(text, "Microsoft.PowerShell.Core\\Registry::");
        text = StripPrefix(text, "Registry::");

        if (TryTakeHive(ref text, "HKEY_LOCAL_MACHINE", RegistryHive.LocalMachine, out location) ||
            TryTakeHive(ref text, "HKLM", RegistryHive.LocalMachine, out location) ||
            TryTakeHive(ref text, "HKEY_CURRENT_USER", RegistryHive.CurrentUser, out location) ||
            TryTakeHive(ref text, "HKCU", RegistryHive.CurrentUser, out location) ||
            TryTakeHive(ref text, "HKEY_USERS", RegistryHive.Users, out location) ||
            TryTakeHive(ref text, "HKU", RegistryHive.Users, out location) ||
            TryTakeHive(ref text, "HKEY_CLASSES_ROOT", RegistryHive.ClassesRoot, out location) ||
            TryTakeHive(ref text, "HKCR", RegistryHive.ClassesRoot, out location) ||
            TryTakeHive(ref text, "HKEY_CURRENT_CONFIG", RegistryHive.CurrentConfig, out location) ||
            TryTakeHive(ref text, "HKCC", RegistryHive.CurrentConfig, out location))
            return true;

        return false;
    }

    private static string StripPrefix(string text, string prefix) =>
        text.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) ? text[prefix.Length..] : text;

    private static bool TryTakeHive(ref string text, string token, RegistryHive hive, out RegistryLocation location)
    {
        location = default;
        if (!text.StartsWith(token, StringComparison.OrdinalIgnoreCase)) return false;
        var rest = text[token.Length..];
        if (rest.StartsWith(":\\", StringComparison.Ordinal)) rest = rest[2..];
        else if (rest.StartsWith(':')) rest = rest[1..];
        rest = rest.TrimStart('\\');
        location = new RegistryLocation(hive, rest);
        return true;
    }

    public RegistryKey? Open(bool writable)
    {
        try
        {
            var baseKey = RegistryKey.OpenBaseKey(Hive, RegistryView.Default);
            if (string.IsNullOrEmpty(SubKey))
                return baseKey;
            var key = writable
                ? baseKey.CreateSubKey(SubKey, writable: true)
                : baseKey.OpenSubKey(SubKey, writable: false);
            baseKey.Dispose();
            return key;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>reg.exe 使用的路径。</summary>
    public string ToRegExePath()
    {
        var hive = Hive switch
        {
            RegistryHive.LocalMachine => "HKEY_LOCAL_MACHINE",
            RegistryHive.CurrentUser => "HKEY_CURRENT_USER",
            RegistryHive.Users => "HKEY_USERS",
            RegistryHive.ClassesRoot => "HKEY_CLASSES_ROOT",
            RegistryHive.CurrentConfig => "HKEY_CURRENT_CONFIG",
            _ => "HKEY_LOCAL_MACHINE"
        };
        return string.IsNullOrEmpty(SubKey) ? hive : hive + "\\" + SubKey;
    }

    /// <summary>PowerShell 引擎可直接读取的路径，写回备份时保持与其一致。</summary>
    public string ToPowerShellPath()
    {
        var hive = Hive switch
        {
            RegistryHive.LocalMachine => "HKLM:",
            RegistryHive.CurrentUser => "HKCU:",
            RegistryHive.Users => "Registry::HKEY_USERS",
            RegistryHive.ClassesRoot => "HKCR:",
            RegistryHive.CurrentConfig => "HKCC:",
            _ => "HKLM:"
        };
        return Hive == RegistryHive.Users
            ? hive + "\\" + SubKey
            : hive + "\\" + SubKey;
    }
}

public readonly record struct RegistryValueSnapshot(bool Exists, object? Value, RegistryValueKind Kind)
{
    public uint AsUInt32()
    {
        if (!Exists || Value is null) return 0;
        return Value switch
        {
            int i => unchecked((uint)i),
            uint u => u,
            long l => unchecked((uint)l),
            short s => unchecked((uint)s),
            byte b => b,
            string text => uint.TryParse(text, out var parsed) ? parsed : 0,
            _ => 0
        };
    }

    public string AsText() => Value switch
    {
        null => "",
        int i => i.ToString(),
        uint u => u.ToString(),
        long l => l.ToString(),
        string s => s,
        string[] array => string.Join(";", array),
        byte[] bytes => Convert.ToHexString(bytes),
        _ => Value.ToString() ?? ""
    };
}
