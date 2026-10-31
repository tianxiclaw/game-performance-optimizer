using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using GamePerfCenter.Services;

namespace GamePerfCenter.Helpers;

internal static class UiPalette
{
    public static SolidColorBrush Brush(byte r, byte g, byte b) => new(Color.FromArgb(255, r, g, b));

    public static SolidColorBrush Ok() => ThemeService.IsDark ? Brush(34, 197, 94) : Brush(21, 128, 61);
    public static SolidColorBrush Warn() => ThemeService.IsDark ? Brush(245, 158, 11) : Brush(180, 83, 9);
    public static SolidColorBrush Danger() => ThemeService.IsDark ? Brush(251, 113, 133) : Brush(190, 18, 60);
    public static SolidColorBrush Info() => ThemeService.IsDark ? Brush(96, 165, 250) : Brush(29, 78, 216);
    public static SolidColorBrush Muted() => ThemeService.IsDark ? Brush(100, 116, 139) : Brush(100, 116, 139);
    public static SolidColorBrush Accent() => ThemeService.IsDark ? Brush(34, 211, 238) : Brush(0, 115, 140);
    public static SolidColorBrush Text() => ThemeService.IsDark ? Brush(230, 237, 247) : Brush(15, 23, 42);
}

public sealed class StatusToBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return (value as string) switch
        {
            "ok" => UiPalette.Ok(),
            "no" => UiPalette.Warn(),
            "checking" => UiPalette.Info(),
            _ => UiPalette.Muted()
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException();
}

public sealed class StatusToTextConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return (value as string) switch
        {
            "ok" => "已生效",
            "no" => "待优化",
            "checking" => "检测中",
            _ => "不适用"
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException();
}

public sealed class RiskToBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return (value as string) switch
        {
            "low" => UiPalette.Ok(),
            "mid" => UiPalette.Warn(),
            "high" => UiPalette.Danger(),
            _ => UiPalette.Muted()
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException();
}

public sealed class RiskToTextConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return (value as string) switch
        {
            "low" => "低风险",
            "mid" => "中风险",
            "high" => "高风险",
            _ => "未知"
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException();
}

public sealed class LevelToBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return (value as string)?.ToLowerInvariant() switch
        {
            "green" => UiPalette.Ok(),
            "yellow" => UiPalette.Warn(),
            "red" => UiPalette.Danger(),
            "cyan" => UiPalette.Accent(),
            _ => UiPalette.Muted()
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException();
}

public sealed class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
        => value is true ? Visibility.Visible : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException();
}

public sealed class InverseBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
        => value is true ? Visibility.Collapsed : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException();
}

public sealed class NullToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
        => value is null || (value is string s && string.IsNullOrWhiteSpace(s))
            ? Visibility.Collapsed
            : Visibility.Visible;

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException();
}

public sealed class InverseNullToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
        => value is null || (value is string s && string.IsNullOrWhiteSpace(s))
            ? Visibility.Visible
            : Visibility.Collapsed;

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException();
}

public sealed class FileSizeConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        var size = value is null ? 0d : System.Convert.ToDouble(value);
        if (size < 1024) return $"{size:0} B";
        if (size < 1024 * 1024) return $"{size / 1024:0.0} KB";
        return $"{size / 1024 / 1024:0.0} MB";
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException();
}

public sealed class BoolToGlyphConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
        => value is true ? "\uE73E" : "\uE739";

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotSupportedException();
}
