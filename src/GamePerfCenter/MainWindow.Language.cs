using System.Diagnostics;
using System.Numerics;
using System.Text.Json;
using Microsoft.UI;
using Microsoft.UI.Composition;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Microsoft.UI.Xaml.Navigation;
using Windows.Graphics;
using Windows.System;
using GamePerfCenter.Controls;
using GamePerfCenter.Helpers;
using GamePerfCenter.Models;
using GamePerfCenter.Pages;
using GamePerfCenter.Services;
using Rectangle = Microsoft.UI.Xaml.Shapes.Rectangle;
using Ellipse = Microsoft.UI.Xaml.Shapes.Ellipse;

namespace GamePerfCenter;

public sealed partial class MainWindow
{
    private void LanguageButton_Click(object sender, RoutedEventArgs e)
    {
        var next = Localization.IsEnglish ? "zh" : "en";
        App.Services.Settings.Language = next;
        App.Services.Settings.Save();
        ApplyLanguage(next);
    }

    internal void SwitchLanguageForAudit(string next) => ApplyLanguage(next);

    internal DependencyObject AuditRoot => RootGrid;

    private void ApplyLanguage(string next)
    {
        Localization.Configure(next);

        Localization.Apply(RootGrid);
        if (ContentFrame.Content is Page current && current is ILanguageAware languageAware)
            languageAware.OnLanguageChanged();
        SelectNav(_currentTag, navigate: false);
        UpdateShellInfo();
        UpdateLanguageButton();

        // 状态文案可能是带参数的动态字符串，用最后一次的渲染器重新生成。
        StatusText.Text = _statusRender();
        EngineStateText.Text = Localization.T(_lastEngineStateZh);
        // 通知栏默认标题也要跟随语言，否则未弹过提示时英文界面会残留 XAML 里的中文标题。
        EngineInfoBar.Title = Localization.T(
            string.IsNullOrEmpty(_lastInfoTitle) ? "引擎错误" : _lastInfoTitle);
        if (!string.IsNullOrEmpty(_lastInfoMessage))
            EngineInfoBar.Message = Localization.T(_lastInfoMessage);

        // Dock 悬浮提示由指针事件即时写入，切换语言时直接收起，下一次悬浮会按新语言重建。
        if (DockHintHost.Visibility == Visibility.Visible)
            DockHintHost.Visibility = Visibility.Collapsed;

        var title = Localization.T("游戏性能优化中心");
        Title = title;
        try { AppWindow.Title = title; } catch { }
    }

    private void UpdateLanguageButton()
    {
        var tip = Localization.IsEnglish
            ? "Interface language: English (click for 中文)"
            : "界面语言：中文（点击切换到 English）";
        ToolTipService.SetToolTip(LanguageButton, tip);
        AutomationProperties.SetName(LanguageButton, tip);
        try
        {
            LanguageButton.Foreground = ThemeResources.Get(
                Localization.IsEnglish ? "AccentBrush" : "SubTextBrush");
        }
        catch { }
    }
}
