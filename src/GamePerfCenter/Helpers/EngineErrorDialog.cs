using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using GamePerfCenter.Services;

namespace GamePerfCenter.Helpers;

/// <summary>
/// PCL 风格故障报告弹窗：先说人话（发生了什么、可能原因、怎么办），
/// 再给可展开的完整技术详情，并支持复制与打开日志目录。
/// </summary>
public static class EngineErrorDialog
{
    public static async Task<ContentDialogResult> ShowAsync(XamlRoot xamlRoot, EngineReport report)
    {
        var danger = Brush("DangerBrush");
        var sub = Brush("SubTextBrush");
        var text = Brush("TextBrush");
        var mono = (FontFamily)Application.Current.Resources["MonoFontFamily"];

        // 窄窗口（最小 480 DIP）下也保证弹窗完整可见；内容超高时由中间滚动区消化。
        var contentWidth = Math.Min(660, Math.Max(360, xamlRoot.Size.Width - 120));
        var root = new Grid
        {
            Width = contentWidth,
            MaxHeight = Math.Max(300, xamlRoot.Size.Height - 150),
            RowSpacing = 14
        };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        // 标题
        var header = new StackPanel { Spacing = 4 };
        var titleRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        titleRow.Children.Add(new FontIcon { Glyph = "\uEA39", FontSize = 26, Foreground = danger });
        titleRow.Children.Add(new TextBlock
        {
            Text = "优化引擎出错了",
            FontSize = 22,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = text,
            VerticalAlignment = VerticalAlignment.Center
        });
        header.Children.Add(titleRow);
        header.Children.Add(new TextBlock
        {
            Text = report.Summary,
            FontSize = 13,
            Foreground = sub,
            TextWrapping = TextWrapping.Wrap
        });
        root.Children.Add(header);

        // 主体：原因 + 建议 + 技术详情
        var body = new StackPanel { Spacing = 14 };

        var causeCard = new Border
        {
            Background = Brush("DangerSoftBrush"),
            CornerRadius = new CornerRadius(10),
            Padding = new Thickness(14, 12, 14, 12)
        };
        var causePanel = new StackPanel { Spacing = 6 };
        causePanel.Children.Add(new TextBlock
        {
            Text = "可能的原因",
            FontSize = 11.5,
            Foreground = sub
        });
        causePanel.Children.Add(new TextBlock
        {
            Text = report.Cause,
            FontSize = 13.5,
            Foreground = text,
            TextWrapping = TextWrapping.Wrap,
            LineHeight = 21
        });
        causeCard.Child = causePanel;
        body.Children.Add(causeCard);

        if (report.Suggestions.Count > 0)
        {
            var advice = new StackPanel { Spacing = 6 };
            advice.Children.Add(new TextBlock
            {
                Text = "可以这样排查",
                FontSize = 11.5,
                Foreground = sub
            });
            for (var i = 0; i < report.Suggestions.Count; i++)
            {
                advice.Children.Add(new TextBlock
                {
                    Text = $"{i + 1}. {report.Suggestions[i]}",
                    FontSize = 13,
                    Foreground = text,
                    TextWrapping = TextWrapping.Wrap,
                    LineHeight = 20
                });
            }
            body.Children.Add(advice);
        }

        var detailsBox = new TextBox
        {
            Text = report.Details,
            IsReadOnly = true,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            FontFamily = mono,
            FontSize = 11.5,
            BorderThickness = new Thickness(0),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            Padding = new Thickness(10)
        };
        var detailsScroll = new ScrollViewer
        {
            Content = detailsBox,
            Height = 210,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        var expander = new Expander
        {
            Header = "技术详情",
            Content = detailsScroll,
            HorizontalAlignment = HorizontalAlignment.Stretch
        };
        body.Children.Add(expander);
        var bodyScroll = new ScrollViewer
        {
            Content = body,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollMode = ScrollMode.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        Grid.SetRow(bodyScroll, 1);
        root.Children.Add(bodyScroll);

        // 底部：报告路径 + 打开日志目录
        var footer = new Grid { ColumnSpacing = 10 };
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var pathText = new TextBlock
        {
            Text = report.ReportPath ?? Path.Combine(AppPaths.DataDir, "engine-report.txt"),
            FontSize = 11.5,
            FontFamily = mono,
            Foreground = sub,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center
        };
        var statusText = new TextBlock
        {
            Text = "",
            FontSize = 11.5,
            Foreground = Brush("OkBrush"),
            VerticalAlignment = VerticalAlignment.Center
        };
        var pathPanel = new StackPanel { Spacing = 2 };
        pathPanel.Children.Add(pathText);
        pathPanel.Children.Add(statusText);
        footer.Children.Add(pathPanel);

        var openButton = new Button
        {
            Content = "打开日志目录",
            Style = (Style)Application.Current.Resources["GhostButtonStyle"]
        };
        openButton.Click += (_, _) => OpenLogFolder(report.ReportPath);
        Grid.SetColumn(openButton, 1);
        footer.Children.Add(openButton);
        Grid.SetRow(footer, 2);
        root.Children.Add(footer);

        var dialog = new ContentDialog
        {
            XamlRoot = xamlRoot,
            Content = root,
            PrimaryButtonText = "重新连接",
            SecondaryButtonText = "复制报告",
            CloseButtonText = "关闭",
            DefaultButton = ContentDialogButton.Primary
        };
        dialog.Resources["ContentDialogMaxWidth"] = 760.0;
        dialog.Resources["ContentDialogMinWidth"] = 320.0;
        dialog.SecondaryButtonClick += (_, args) =>
        {
            try
            {
                var package = new DataPackage();
                package.SetText(report.Details);
                Clipboard.SetContent(package);
                statusText.Text = "报告已复制到剪贴板";
            }
            catch

            {
                statusText.Text = "复制失败，请打开日志目录手动复制";
                statusText.Foreground = danger;
            }
            args.Cancel = true;
        };

        return await dialog.ShowAsync();
    }

    private static Brush Brush(string key)
    {
        try { return (Brush)Application.Current.Resources[key]; }
        catch { return new SolidColorBrush(Microsoft.UI.Colors.Gray); }
    }

    private static void OpenLogFolder(string? reportPath)
    {
        try
        {
            Directory.CreateDirectory(AppPaths.DataDir);
            if (!string.IsNullOrWhiteSpace(reportPath) && File.Exists(reportPath))
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "explorer.exe",
                    Arguments = $"/select,\"{reportPath}\"",
                    UseShellExecute = true
                });
            }
            else
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "explorer.exe",
                    Arguments = $"\"{AppPaths.DataDir}\"",
                    UseShellExecute = true
                });
            }
        }
        catch { }
    }
}
