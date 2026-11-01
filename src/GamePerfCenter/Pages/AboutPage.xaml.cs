using System.Diagnostics;
using GamePerfCenter.Helpers;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;

namespace GamePerfCenter.Pages;

public sealed partial class AboutPage : Page, IThemeAware
{
    public AboutPage()
    {
        InitializeComponent();
        Loaded += OnLoaded;
        Responsive.Watch(this, 880, ApplyWidth);
    }

    private void ApplyWidth(bool narrow)
    {
        if (narrow)
        {
            Grid.SetColumnSpan(SupportCard, 2);
            Grid.SetColumnSpan(CapabilityCard, 2);
            Grid.SetColumn(CapabilityCard, 0);
            Grid.SetRow(CapabilityCard, 1);
            CapabilityCard.Margin = new Thickness(0, 16, 0, 0);
        }
        else
        {
            Grid.SetColumnSpan(SupportCard, 1);
            Grid.SetColumnSpan(CapabilityCard, 1);
            Grid.SetColumn(CapabilityCard, 1);
            Grid.SetRow(CapabilityCard, 0);
            CapabilityCard.Margin = new Thickness(0);
        }
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        VersionBadge.Text = "v" + AppPaths.Version;
        LoadImage(AppIcon, Path.Combine(AppPaths.BaseDir, "Assets", "AppIcon.png"));
        LoadImage(SupportQr, AppPaths.SupportImagePath);

        CapabilityList.ItemsSource = new List<CapabilityInfo>
        {
            new() { Name = "系统级优化", Desc = "电源计划、GPU 调度、网络与游戏模式等可还原的调优项。" },
            new() { Name = "游戏专属方案", Desc = "为单个游戏保存优先级、亲和性、全屏优化与启动参数。" },
            new() { Name = "驱动与硬件核查", Desc = "读取显卡、驱动版本与变更记录，跳转厂商原生工具。" },
            new() { Name = "诊断与备份", Desc = "一键诊断、导出报告与诊断包，任何改动都可回滚。" }
        };
    }

    private static void LoadImage(Image target, string path)
    {
        try
        {
            if (!File.Exists(path)) return;
            var bitmap = new BitmapImage();
            bitmap.UriSource = new Uri(path, UriKind.Absolute);
            target.Source = bitmap;
        }
        catch (Exception ex)
        {
            AppLog.Write("加载图片失败: " + ex.Message);
        }
    }

    private async void EnlargeQr_Click(object sender, RoutedEventArgs e) => await ShowQrDialogAsync();

    private async void SupportQr_Tapped(object sender, TappedRoutedEventArgs e) => await ShowQrDialogAsync();

    private async Task ShowQrDialogAsync()
    {
        if (!File.Exists(AppPaths.SupportImagePath))
        {
            await new ContentDialog
            {
                XamlRoot = XamlRoot,
                Title = "赞赏码缺失",
                Content = $"未找到赞赏码图片：\n{AppPaths.SupportImagePath}\n\n请确认程序目录中的 赞赏码.png 未被删除。",
                CloseButtonText = "知道了"
            }.ShowAsync();
            return;
        }

        var image = new Image
        {
            Width = 320,
            Height = 320,
            Stretch = Microsoft.UI.Xaml.Media.Stretch.Uniform
        };
        LoadImage(image, AppPaths.SupportImagePath);

        var panel = new StackPanel { Spacing = 12, HorizontalAlignment = HorizontalAlignment.Center };
        panel.Children.Add(new Border
        {
            Background = new Microsoft.UI.Xaml.Media.SolidColorBrush(Microsoft.UI.Colors.White),
            CornerRadius = new CornerRadius(14),
            Padding = new Thickness(12),
            Child = image
        });
        panel.Children.Add(new TextBlock
        {
            Text = "微信 / 支付宝 扫码赞赏 · 完全自愿",
            FontSize = 12,
            HorizontalAlignment = HorizontalAlignment.Center,
            Opacity = 0.72
        });

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "支持作者",
            Content = panel,
            PrimaryButtonText = "打开原图",
            CloseButtonText = "关闭",
            DefaultButton = ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() == ContentDialogResult.Primary)
            OpenQrOriginal();
    }

    private void OpenQrOriginal_Click(object sender, RoutedEventArgs e) => OpenQrOriginal();

    private void OpenQrOriginal()
    {
        try
        {
            if (File.Exists(AppPaths.SupportImagePath))
                Process.Start(new ProcessStartInfo { FileName = AppPaths.SupportImagePath, UseShellExecute = true });
        }
        catch (Exception ex)
        {
            AppLog.Write("打开赞赏码失败: " + ex.Message);
        }
    }

    private void OpenRepo_Click(object sender, RoutedEventArgs e) => OpenUrl("https://github.com/tianxiclaw/game-performance-optimizer");

    private void OpenReleases_Click(object sender, RoutedEventArgs e)
        => OpenUrl("https://github.com/tianxiclaw/game-performance-optimizer/releases/latest");

    private void OpenIssues_Click(object sender, RoutedEventArgs e)
        => OpenUrl("https://github.com/tianxiclaw/game-performance-optimizer/issues");

    private void OpenReadme_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            if (File.Exists(AppPaths.ReadmePath))
                Process.Start(new ProcessStartInfo { FileName = AppPaths.ReadmePath, UseShellExecute = true });
        }
        catch (Exception ex)
        {
            AppLog.Write("打开使用说明失败: " + ex.Message);
        }
    }

    private static void OpenUrl(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
        }
        catch { }
    }

    public void OnThemeChanged() { }
}
