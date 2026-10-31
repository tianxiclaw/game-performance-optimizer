using System.Security.Principal;

namespace GamePerfCenter.Services;

public static class AppPaths
{
    public static string BaseDir { get; } = AppContext.BaseDirectory;
    public static string EnginePath => Path.Combine(BaseDir, "游戏性能优化.ps1");
    public static string BridgePath => Path.Combine(BaseDir, "engine-bridge.ps1");
    public static string SupportImagePath => Path.Combine(BaseDir, "赞赏码.png");
    public static string ReadmePath => Path.Combine(BaseDir, "使用说明.txt");
    public static string DataDir => Path.Combine(BaseDir, "data");
    public static string BackupDir => Path.Combine(BaseDir, "backups");
    public static string DiagnosticsDir => Path.Combine(BaseDir, "diagnostics");
    public static string SettingsPath => Path.Combine(BaseDir, "gui-settings.json");
    public static string AppLogPath => Path.Combine(DataDir, "winui.log");
    public static string Version => "6.0.4";

    public static string UserSid
    {
        get
        {
            try { return WindowsIdentity.GetCurrent().User?.Value ?? ""; }
            catch { return ""; }
        }
    }

    public static void EnsureDirectories()
    {
        foreach (var dir in new[] { DataDir, BackupDir, DiagnosticsDir })
        {
            try { Directory.CreateDirectory(dir); } catch { }
        }
    }
}
