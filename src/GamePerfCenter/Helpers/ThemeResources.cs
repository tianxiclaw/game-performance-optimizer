using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using GamePerfCenter.Services;

namespace GamePerfCenter.Helpers;

/// <summary>
/// 代码里需要按主题取 token 时使用。ThemeDictionaries 在合并字典内，
/// 不能直接从 Application.Resources 取，否则会拿到 null 或透明色。
/// </summary>
public static class ThemeResources
{
    public static Brush Get(string key)
    {
        var themeKey = ThemeService.IsDark ? "Default" : "Light";
        return Find(Application.Current.Resources, themeKey, key)
               ?? new SolidColorBrush(Colors.Transparent);
    }

    private static Brush? Find(ResourceDictionary dictionary, string themeKey, string key)
    {
        try
        {
            if (dictionary.ThemeDictionaries.TryGetValue(themeKey, out var entry) &&
                entry is ResourceDictionary themed &&
                themed.TryGetValue(key, out var value) && value is Brush brush)
                return brush;

            foreach (var merged in dictionary.MergedDictionaries)
            {
                var found = Find(merged, themeKey, key);
                if (found is not null) return found;
            }
        }
        catch { }
        return null;
    }
}
