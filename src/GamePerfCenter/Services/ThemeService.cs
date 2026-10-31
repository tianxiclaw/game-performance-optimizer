using Microsoft.UI.Xaml;

namespace GamePerfCenter.Services;

public static class ThemeService
{
    public static bool IsDark { get; private set; } = true;

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
