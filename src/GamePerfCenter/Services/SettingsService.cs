using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace GamePerfCenter.Services;

public sealed class SettingsService
{
    private JsonObject _root = new();

    public string Theme { get; set; } = "dark";
    public bool MinimizeToTray { get; set; }
    public bool NotifyDriver { get; set; } = true;

    public SettingsService()
    {
        Load();
    }

    public void Load()
    {
        try
        {
            if (!File.Exists(AppPaths.SettingsPath)) return;
            var text = File.ReadAllText(AppPaths.SettingsPath, Encoding.UTF8).TrimStart('\uFEFF');
            if (string.IsNullOrWhiteSpace(text)) return;
            _root = JsonNode.Parse(text) as JsonObject ?? new JsonObject();
            var theme = GetString("Theme", "dark").ToLowerInvariant();
            Theme = theme is "light" or "system" ? theme : "dark";
            MinimizeToTray = GetBool("MinimizeToTray", false);
            NotifyDriver = GetBool("NotifyDriver", true);
        }
        catch { }
    }

    public bool Save()
    {
        try
        {
            Directory.CreateDirectory(AppPaths.BaseDir);
            _root["Version"] = 3;
            _root.Remove("ExperimentalDpi");
            _root.Remove("ShowRenderInfo");
            _root["Theme"] = Theme;
            _root["MinimizeToTray"] = MinimizeToTray;
            _root["NotifyDriver"] = NotifyDriver;
            _root["Updated"] = DateTime.Now.ToString("s");
            _root["Ui"] = "winui3";
            var json = _root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(AppPaths.SettingsPath, json, new UTF8Encoding(true));
            return true;
        }
        catch { return false; }
    }

    private string GetString(string key, string fallback)
    {
        try { return _root[key]?.GetValue<string>() ?? fallback; } catch { return fallback; }
    }

    private bool GetBool(string key, bool fallback)
    {
        try { return _root[key]?.GetValue<bool>() ?? fallback; } catch { return fallback; }
    }
}
