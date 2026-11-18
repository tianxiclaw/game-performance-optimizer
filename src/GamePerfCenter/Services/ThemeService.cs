using Microsoft.UI.Xaml;

namespace GamePerfCenter.Services;

public static class ThemeService
{
    private static bool? _highContrast;

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
