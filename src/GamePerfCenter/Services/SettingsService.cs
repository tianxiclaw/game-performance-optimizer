using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace GamePerfCenter.Services;

public sealed class SettingsService
{
    private JsonObject _root = new();

    public string Theme { get; set; } = "dark";
    public string Material { get; set; } = "deep";
    public bool MinimizeToTray { get; set; }
    public bool NotifyDriver { get; set; } = true;
    /// <summary>关闭界面动效：数值滚动与入场淡入直接跳到终态。</summary>
    public bool ReduceMotion { get; set; }

    /// <summary>命令面板的最近使用记录，最多 8 条，只存命令 Id。</summary>
    public List<string> CommandRecents { get; private set; } = new();

    public void RecordCommand(string id)
    {
        if (string.IsNullOrWhiteSpace(id)) return;
        CommandRecents.Remove(id);
        CommandRecents.Insert(0, id);
        if (CommandRecents.Count > 8) CommandRecents.RemoveRange(8, CommandRecents.Count - 8);
    }

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
            var material = GetString("Material", "deep").ToLowerInvariant();
            Material = material is "mica" or "mica-alt" or "glass" ? material : "deep";
            MinimizeToTray = GetBool("MinimizeToTray", false);
            NotifyDriver = GetBool("NotifyDriver", true);
            ReduceMotion = GetBool("ReduceMotion", false);

            CommandRecents = new List<string>();
            if (_root["CommandRecents"] is JsonArray array)
            {
                foreach (var node in array)
                {
                    var id = node?.GetValue<string>();
                    if (!string.IsNullOrWhiteSpace(id) && !CommandRecents.Contains(id)) CommandRecents.Add(id);
                    if (CommandRecents.Count >= 8) break;
                }
            }
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
            _root["Material"] = Material;
            _root["MinimizeToTray"] = MinimizeToTray;
            _root["NotifyDriver"] = NotifyDriver;
            _root["ReduceMotion"] = ReduceMotion;
            var recents = new JsonArray();
            foreach (var id in CommandRecents) recents.Add(id);
            _root["CommandRecents"] = recents;
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
