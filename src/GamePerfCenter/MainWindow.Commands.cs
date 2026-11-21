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
    private void CommandButton_Click(object sender, RoutedEventArgs e) => ToggleCommandPalette();

    private void ToggleCommandPalette()
    {
        if (Palette.IsOpen)
        {
            Palette.Close();
            return;
        }
        Palette.Open(BuildCommands(), App.Services.Settings.CommandRecents);
        _ = LoadGamesForPaletteAsync();
    }

    private void OnCommandInvoked(CommandItem item)
    {
        App.Services.Settings.RecordCommand(item.Id);
        App.Services.Settings.Save();
        try { item.Invoke?.Invoke(); }
        catch (Exception ex)
        {
            AppLog.Write("命令执行失败: " + ex);
            ShowError("命令执行失败", ex.Message);
        }
    }

    private List<CommandItem> BuildCommands()
    {
        var commands = new List<CommandItem>();
        void Page(string tag, string title, string glyph, string detail, string keywords)
        {
            commands.Add(new CommandItem
            {
                Id = "page:" + tag,
                Title = Localization.T(title),
                Detail = Localization.T(detail),
                Glyph = glyph,
                Group = Localization.T("页面"),
                Keywords = tag + " " + keywords,
                Invoke = () => NavigateTo(tag)
            });
        }

        Page("overview", "概览", "\uE80F", "实时负载、优化进度与硬件摘要", "home dashboard 首页 工作台");
        Page("items", "优化项", "\uE9D9", "按分类筛选并应用可还原的系统优化", "optimize items 优化 项目 应用");
        Page("diagnostics", "诊断报告", "\uE9D5", "只读检查 VBS、内存、PCIe、NVMe 与显示链路", "diagnostics report 诊断 报告");
        Page("startup", "启动项与后台", "\uE7C4", "查看开机自启项与内存占用较高的后台进程", "startup background 启动 后台");
        Page("games", "游戏库", "\uE7FC", "识别本地游戏并保存独立运行配置", "games library 游戏 库 steam epic");
        Page("driver", "驱动中心", "\uE7F8", "显卡驱动版本、厂商工具与回退记录", "driver gpu 驱动 显卡");
        Page("backup", "备份还原", "\uE777", "原值备份、单项还原与全部回放", "backup restore 备份 还原 回滚");
        Page("log", "运行日志", "\uE8A5", "本机操作与引擎输出，不上传", "log 日志 输出");
        Page("settings", "设置", "\uE713", "外观、托盘与配置文件", "settings 设置 配置 主题 材质");
        Page("about", "关于与支持", "\uE946", "版本信息、赞赏码与项目链接", "about version support 关于 版本");

        commands.Add(new CommandItem
        {
            Id = "action:refresh",
            Title = Localization.T("刷新硬件与优化项"),
            Detail = Localization.T("重新采样 CPU、GPU、内存与本机状态"),
            Glyph = "\uE72C",
            Group = Localization.T("操作"),
            Keywords = "refresh snapshot 刷新 状态 采样",
            Invoke = () => _ = RefreshSnapshotAsync()
        });
        commands.Add(new CommandItem
        {
            Id = "action:open-base",
            Title = Localization.T("打开程序目录"),
            Detail = AppPaths.BaseDir,
            Glyph = "\uE838",
            Group = Localization.T("操作"),
            Keywords = "open folder 打开 目录 程序",
            Invoke = () => OpenDirectory(AppPaths.BaseDir)
        });
        commands.Add(new CommandItem
        {
            Id = "action:open-backups",
            Title = Localization.T("打开备份目录"),
            Detail = AppPaths.BackupDir,
            Glyph = "\uE777",
            Group = Localization.T("操作"),
            Keywords = "open backup folder 打开 备份 目录",
            Invoke = () => OpenDirectory(AppPaths.BackupDir)
        });
        commands.Add(new CommandItem
        {
            Id = "action:open-data",
            Title = Localization.T("打开数据目录"),
            Detail = AppPaths.DataDir,
            Glyph = "\uE8A5",
            Group = Localization.T("操作"),
            Keywords = "open data log folder 打开 数据 日志 目录",
            Invoke = () => OpenDirectory(AppPaths.DataDir)
        });
        commands.Add(new CommandItem
        {
            Id = "action:open-settings",
            Title = Localization.T("打开配置文件"),
            Detail = AppPaths.SettingsPath,
            Glyph = "\uE713",
            Group = Localization.T("操作"),
            Keywords = "open settings json 打开 配置 文件",
            Invoke = () => OpenFile(AppPaths.SettingsPath)
        });

        var material = MaterialService.Normalize(App.Services.Settings.Material);
        void Material(string key, string title, string label, string detail, string glyph)
        {
            var supported = MaterialService.IsSupported(key);
            commands.Add(new CommandItem
            {
                Id = "material:" + key,
                Title = Localization.T(title),
                Detail = (material == key ? Localization.T("当前材质 · ") : "") + Localization.T(detail) +
                         (supported ? "" : Localization.T(" · 当前系统不支持，会回退深空")),
                Glyph = glyph,
                Group = Localization.T("材质"),
                Keywords = "material theme 材质 外观 " + key,
                Invoke = () => SetMaterial(key, Localization.T(label))
            });
        }
        Material("deep", "材质：深空", "深空", "自带渐变背景，不依赖系统合成层", "\uE790");
        Material("mica", "材质：云母", "云母", "Windows 11 Mica，桌面颜色直接透出", "\uE790");
        Material("mica-alt", "材质：云母 Alt", "云母 Alt", "Mica Alt 底色更深，适合深色桌面与高对比内容", "\uE790");
        Material("glass", "材质：液态玻璃", "液态玻璃", "Acrylic 半透明，适合浅色桌面", "\uE790");

        var theme = App.Services.Settings.Theme;
        void Theme(string key, string title, string label)
        {
            commands.Add(new CommandItem
            {
                Id = "theme:" + key,
                Title = Localization.T(title),
                Detail = Localization.T(theme == key ? "当前主题" : "切换后立即生效"),
                Glyph = "\uE793",
                Group = Localization.T("操作"),
                Keywords = "theme 主题 外观 " + key,
                Invoke = () => SetTheme(key, Localization.T(label))
            });
        }
        Theme("dark", "主题：深色", "深色");
        Theme("light", "主题：浅色", "浅色");
        Theme("system", "主题：跟随系统", "跟随系统");

        foreach (var item in App.Services.State.Items)
        {
            if (string.IsNullOrWhiteSpace(item.Id)) continue;
            commands.Add(new CommandItem
            {
                Id = "item:" + item.Id,
                Title = item.Name ?? item.Id,
                Detail = $"{item.Cat} · {item.StatusText}",
                Glyph = "\uE9D9",
                Group = Localization.T("优化项"),
                Keywords = $"{item.Id} {item.Cat} {item.Desc} {item.StatusText}",
                Invoke = () => FocusItem(item.Id)
            });
        }

        if (_paletteGames is not null)
        {
            foreach (var game in _paletteGames)
            {
                if (string.IsNullOrWhiteSpace(game.Exe)) continue;
                commands.Add(new CommandItem
                {
                    Id = "game:" + game.Exe,
                    Title = string.IsNullOrWhiteSpace(game.Name) ? Path.GetFileNameWithoutExtension(game.Exe) : game.Name!,
                    Detail = $"{game.SourceText} · {game.ProfileText}",
                    Glyph = "\uE7FC",
                    Group = Localization.T("游戏"),
                    Keywords = $"{game.Exe} {game.SourceText} 游戏 启动 launch play",
                    Invoke = () => _ = LaunchGameFromPaletteAsync(game)
                });
            }
        }

        return commands;
    }

    private async Task LoadGamesForPaletteAsync()
    {
        if (_paletteGamesLoading) return;
        if (_paletteGames is not null && DateTime.Now - _paletteGamesAt < TimeSpan.FromMinutes(5)) return;

        _paletteGamesLoading = true;
        try
        {
            _paletteGames = await App.Services.State.GetGamesAsync(false);
            _paletteGamesAt = DateTime.Now;
        }
        catch (Exception ex)
        {
            AppLog.Write("命令面板游戏库读取失败: " + ex.Message);
            return;
        }
        finally
        {
            _paletteGamesLoading = false;
        }

        if (Palette.IsOpen) Palette.SetCommands(BuildCommands());
    }

    private async Task LaunchGameFromPaletteAsync(GameInfo game)
    {
        try
        {
            SetStatus("正在启动游戏...", true);
            var result = await App.Services.State.StartGameAsync(game.Exe ?? "", game.Profile);
            var ok = !result.TryGetProperty("Ok", out var okEl) || okEl.ValueKind != JsonValueKind.False;
            var message = result.TryGetProperty("Message", out var msg) ? msg.ToString() : "";
            ShowInfo(ok ? "已启动" : "启动失败",
                string.IsNullOrEmpty(message) ? (game.Name ?? "游戏") + " 已交给系统启动。" : message,
                ok ? InfoBarSeverity.Success : InfoBarSeverity.Error);
        }
        catch (Exception ex)
        {
            ShowError("启动失败", ex.Message);
        }
        finally
        {
            SetStatus("就绪", false);
        }
    }
}
