using System.Collections.Generic;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace GamePerfCenter.Services;

public static class ThemeService
{
    private static bool? _highContrast;
    private static readonly Dictionary<string, Color> BaseColors = new();

    public static bool IsDark { get; private set; } = true;

    /// <summary>系统高对比度模式。开启时窗口材质强制回退深空，颜色改走系统色。</summary>
    public static bool IsHighContrast
    {
        get
        {
            if (_highContrast is null) RefreshHighContrast();
            return _highContrast ?? false;
        }
    }

    public static void RefreshHighContrast()
    {
        _highContrast = Helpers.HighContrast.IsEnabled;
    }

    public static ElementTheme Resolve(string theme)
    {
        return theme switch
        {
            "light" => ElementTheme.Light,
            "system" => ElementTheme.Default,
            _ => ElementTheme.Dark
        };
    }

    public static ElementTheme Apply(FrameworkElement root, string theme)
    {
        var resolved = Resolve(theme);
        root.RequestedTheme = resolved;
        if (resolved == ElementTheme.Default)
        {
            IsDark = Application.Current.RequestedTheme == ApplicationTheme.Dark;
        }
        else
        {
            IsDark = resolved == ElementTheme.Dark;
        }
        return resolved;
    }

    /// <summary>
    /// 液态玻璃下把卡片底色压到半透明，让 Acrylic 背景真正透上来。
    /// 直接改活动主题字典里的画刷对象：XAML 里 ThemeResource 引用的是同一个实例，
    /// 改 Color 会即时作用到所有已加载的卡片，不需要重建页面。
    /// 切回云母/深空时把捕获到的原始 alpha 还原。
    /// </summary>
    public static void ApplyGlassSurfaces(bool glass)
    {
        if (IsHighContrast) glass = false;

        // 只降低 alpha，不改变色相；上限越大越不透明。
        if (!glass)
        {
            foreach (var key in GlassSurfaceKeys) ApplyAlpha(key, null);
            return;
        }

        var caps = IsDark
            ? new (string Key, byte Alpha)[]
            {
                ("CardSurfaceBrush", 0x99),
                ("HeroSurfaceBrush", 0xA6),
                ("CardBrush", 0x99),
                ("CardHoverBrush", 0xB3),
                ("InsetBrush", 0x59),
                ("Surface2Brush", 0x73),
                ("FloatSurfaceBrush", 0xEB)
            }
            : new (string Key, byte Alpha)[]
            {
                ("CardSurfaceBrush", 0xCC),
                ("HeroSurfaceBrush", 0xD9),
                ("CardBrush", 0xCC),
                ("CardHoverBrush", 0xD9),
                ("InsetBrush", 0x99),
                ("Surface2Brush", 0xB3),
                ("FloatSurfaceBrush", 0xF5)
            };

        foreach (var (key, alpha) in caps) ApplyAlpha(key, alpha);
    }

    private static readonly string[] GlassSurfaceKeys =
    {
        "CardSurfaceBrush", "HeroSurfaceBrush", "CardBrush", "CardHoverBrush",
        "InsetBrush", "Surface2Brush", "FloatSurfaceBrush"
    };

    private static void ApplyAlpha(string key, byte? cap)
    {
        var themeKey = IsDark ? "Default" : "Light";
        var brush = FindBrush(Application.Current.Resources, themeKey, key);
        if (brush is null) return;

        if (brush is SolidColorBrush solid)
        {
            var id = $"{themeKey}|{key}|0";
            if (!BaseColors.TryGetValue(id, out var baseColor))
            {
                baseColor = solid.Color;
                BaseColors[id] = baseColor;
            }
            solid.Color = cap is null
                ? baseColor
                : WithAlpha(baseColor, System.Math.Min(baseColor.A, cap.Value));
            return;
        }

        if (brush is LinearGradientBrush gradient)
        {
            for (var i = 0; i < gradient.GradientStops.Count; i++)
            {
                var stop = gradient.GradientStops[i];
                var id = $"{themeKey}|{key}|{i}";
                if (!BaseColors.TryGetValue(id, out var baseColor))
                {
                    baseColor = stop.Color;
                    BaseColors[id] = baseColor;
                }
                stop.Color = cap is null
                    ? baseColor
                    : WithAlpha(baseColor, System.Math.Min(baseColor.A, cap.Value));
            }
        }
    }

    private static Color WithAlpha(Color color, byte alpha)
        => Color.FromArgb(alpha, color.R, color.G, color.B);

    private static Brush? FindBrush(ResourceDictionary dictionary, string themeKey, string key)
    {
        try
        {
            if (dictionary.ThemeDictionaries.TryGetValue(themeKey, out var entry) &&
                entry is ResourceDictionary themed &&
                themed.TryGetValue(key, out var value) && value is Brush brush)
            {
                return brush;
            }

            foreach (var merged in dictionary.MergedDictionaries)
            {
                var found = FindBrush(merged, themeKey, key);
                if (found is not null) return found;
            }
        }
        catch { }
        return null;
    }

    public static string Next(string theme) => theme switch
    {
        "dark" => "light",
        "light" => "system",
        _ => "dark"
    };

    public static string DisplayName(string theme) => theme switch
    {
        "light" => "浅色",
        "system" => "跟随系统",
        _ => "深色"
    };
}
