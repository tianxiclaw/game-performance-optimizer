using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Text.Json;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Pages;

public sealed partial class GamesPage : Page, IThemeAware
{
    private readonly List<GameInfo> _all = new();
    private readonly ObservableCollection<GameInfo> _view = new();
    private bool _loaded;

    public GamesPage()
    {
        InitializeComponent();
        GameList.ItemsSource = _view;
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_loaded) return;
        _loaded = true;
        await LoadAsync(false);
    }

    private async Task LoadAsync(bool force)
    {
        try
        {
            App.Services.State.SetStatus(force ? "正在扫描游戏库..." : "正在读取游戏库...");
            var games = await App.Services.State.GetGamesAsync(force);
            _all.Clear();
            _all.AddRange(games);
            ApplyFilter();
        }
        catch (Exception ex)
        {
            ShowInfo("读取游戏库失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            App.Services.State.SetStatus("就绪");
        }
    }

    private void ApplyFilter()
    {
        var keyword = SearchBox.Text?.Trim() ?? "";
        _view.Clear();
        foreach (var game in _all)
        {
            if (keyword.Length > 0 &&
                !(game.Name ?? "").Contains(keyword, StringComparison.OrdinalIgnoreCase) &&
                !(game.Exe ?? "").Contains(keyword, StringComparison.OrdinalIgnoreCase))
                continue;
            _view.Add(game);
        }
        CountText.Text = $"{_view.Count} / {_all.Count} 个游戏";
        EmptyHint.Visibility = _view.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => ApplyFilter();

    private async void Scan_Click(object sender, RoutedEventArgs e) => await LoadAsync(true);

    private void OpenGameDir_Click(object sender, RoutedEventArgs e)
    {
        if (GameList.SelectedItem is not GameInfo game)
        {
            ShowInfo("请先选择游戏", "在列表中选中一个游戏后再打开目录。", InfoBarSeverity.Informational);
            return;
        }

        try
        {
            var dir = game.Dir;
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir))
                dir = Path.GetDirectoryName(game.Exe ?? "");
            if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir))
            {
                ShowInfo("目录不可用", "游戏路径已失效，请重新扫描或手动添加。", InfoBarSeverity.Warning);
                return;
            }
            Process.Start(new ProcessStartInfo { FileName = "explorer.exe", Arguments = $"\"{dir}\"", UseShellExecute = true });
        }
        catch (Exception ex)
        {
            ShowInfo("无法打开目录", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async void AddGame_Click(object sender, RoutedEventArgs e)
    {
        var nameBox = new TextBox { PlaceholderText = "游戏名称", MinHeight = 34 };
        var exeBox = new TextBox { PlaceholderText = "游戏可执行文件完整路径", MinHeight = 34 };
        var browse = new Button { Content = "浏览...", HorizontalAlignment = HorizontalAlignment.Right };
        browse.Click += async (_, _) =>
        {
            var picked = await PickExeAsync();
            if (string.IsNullOrEmpty(picked)) return;
            exeBox.Text = picked;
            if (string.IsNullOrWhiteSpace(nameBox.Text))
                nameBox.Text = Path.GetFileNameWithoutExtension(picked);
        };

        var panel = new StackPanel { Spacing = 10, MinWidth = 460 };
        panel.Children.Add(new TextBlock { Text = "名称", FontSize = 12, Opacity = 0.72 });
        panel.Children.Add(nameBox);
        panel.Children.Add(new TextBlock { Text = "可执行文件", FontSize = 12, Opacity = 0.72 });
        panel.Children.Add(exeBox);
        panel.Children.Add(browse);

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "手动添加游戏",
            Content = panel,
            PrimaryButtonText = "添加",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary
        };

        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        var name = nameBox.Text?.Trim() ?? "";
        var exe = exeBox.Text?.Trim().Trim('"') ?? "";
        if (string.IsNullOrEmpty(exe) || !File.Exists(exe))
        {
            ShowInfo("路径无效", "请选择一个存在的 exe 文件。", InfoBarSeverity.Warning);
            return;
        }
        if (string.IsNullOrEmpty(name)) name = Path.GetFileNameWithoutExtension(exe);

        try
        {
            await App.Services.State.AddGameAsync(name, exe);
            ShowInfo("已添加", $"{name} 已加入游戏库。", InfoBarSeverity.Success);
            await LoadAsync(false);
        }
        catch (Exception ex)
        {
            ShowInfo("添加失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async void Profile_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not GameInfo game) return;
        await EditProfileAsync(game);
    }

    private async Task EditProfileAsync(GameInfo game)
    {
        var priority = new ComboBox { MinHeight = 34, HorizontalAlignment = HorizontalAlignment.Stretch };
        priority.Items.Add("默认（不调整）");
        priority.Items.Add("高于正常");
        priority.Items.Add("高");
        priority.SelectedIndex = (game.Profile?.Priority) switch
        {
            "High" => 2,
            "AboveNormal" => 1,
            _ => 0
        };

        var affinity = new ComboBox { MinHeight = 34, HorizontalAlignment = HorizontalAlignment.Stretch };
        affinity.Items.Add("全部核心");
        affinity.Items.Add("仅物理核心（关闭超线程）");
        affinity.SelectedIndex = game.Profile?.Affinity == "Physical" ? 1 : 0;

        var fsOff = new CheckBox { Content = "启动时请求全屏独占（禁用全屏优化）", IsChecked = game.Profile?.FsOff ?? false };
        var gpuHigh = new CheckBox { Content = "为该游戏指定高性能 GPU", IsChecked = game.Profile?.GpuHigh ?? false };
        var admin = new CheckBox { Content = "以管理员身份启动", IsChecked = game.Profile?.RunAsAdmin ?? false };
        var args = new TextBox { PlaceholderText = "额外启动参数（可选）", Text = game.Profile?.Args ?? "", MinHeight = 34 };

        var panel = new StackPanel { Spacing = 10, MinWidth = 460 };
        panel.Children.Add(new TextBlock { Text = "CPU 优先级", FontSize = 12, Opacity = 0.72 });
        panel.Children.Add(priority);
        panel.Children.Add(new TextBlock { Text = "CPU 亲和性", FontSize = 12, Opacity = 0.72 });
        panel.Children.Add(affinity);
        panel.Children.Add(fsOff);
        panel.Children.Add(gpuHigh);
        panel.Children.Add(admin);
        panel.Children.Add(new TextBlock { Text = "启动参数", FontSize = 12, Opacity = 0.72 });
        panel.Children.Add(args);

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "启动方案 · " + game.Name,
            Content = new ScrollViewer
            {
                Content = panel,
                MaxHeight = 460,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            },
            PrimaryButtonText = "保存",
            SecondaryButtonText = "保存并应用",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary
        };

        var result = await dialog.ShowAsync();
        if (result == ContentDialogResult.None) return;

        var profile = new GameProfile
        {
            Priority = priority.SelectedIndex switch { 1 => "AboveNormal", 2 => "High", _ => "Normal" },
            Affinity = affinity.SelectedIndex == 1 ? "Physical" : "All",
            FsOff = fsOff.IsChecked == true,
            GpuHigh = gpuHigh.IsChecked == true,
            RunAsAdmin = admin.IsChecked == true,
            Args = args.Text ?? "",
            HasSaved = true
        };

        try
        {
            await App.Services.State.SaveGameProfileAsync(game.Exe ?? "", profile);
            if (result == ContentDialogResult.Secondary)
                await App.Services.State.ApplyGameProfileAsync(game.Exe ?? "", profile);
            ShowInfo("方案已保存", result == ContentDialogResult.Secondary
                ? $"{game.Name} 的方案已保存并应用到系统。"
                : $"{game.Name} 的方案已保存，启动时自动生效。", InfoBarSeverity.Success);
            await LoadAsync(false);
        }
        catch (Exception ex)
        {
            ShowInfo("保存方案失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async void Apply_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not GameInfo game) return;
        try
        {
            App.Services.State.SetStatus("正在应用游戏方案...");
            var result = await App.Services.State.ApplyGameProfileAsync(game.Exe ?? "", game.Profile);
            var ok = !result.TryGetProperty("Ok", out var okEl) || okEl.ValueKind != JsonValueKind.False;
            ShowInfo(ok ? "方案已应用" : "应用未完成",
                ok ? $"{game.Name} 的系统级设置已写入。" : result.ToString(),
                ok ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
        }
        catch (Exception ex)
        {
            ShowInfo("应用失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            App.Services.State.SetStatus("就绪");
        }
    }

    private async void Start_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not GameInfo game) return;
        try
        {
            App.Services.State.SetStatus("正在启动游戏...");
            var result = await App.Services.State.StartGameAsync(game.Exe ?? "", game.Profile);
            var ok = !result.TryGetProperty("Ok", out var okEl) || okEl.ValueKind != JsonValueKind.False;
            var message = result.TryGetProperty("Message", out var msg) ? msg.ToString() : "";
            ShowInfo(ok ? "已启动" : "启动失败",
                string.IsNullOrEmpty(message) ? game.Name + " 已交给系统启动。" : message,
                ok ? InfoBarSeverity.Success : InfoBarSeverity.Error);
        }
        catch (Exception ex)
        {
            ShowInfo("启动失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            App.Services.State.SetStatus("就绪");
        }
    }

    private async void Remove_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not GameInfo game) return;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "从游戏库移除",
            Content = new TextBlock
            {
                Text = $"仅移除“{game.Name}”的库条目与启动方案，不会删除游戏文件。\n\n确定继续吗？",
                TextWrapping = TextWrapping.Wrap,
                LineHeight = 22
            },
            PrimaryButtonText = "移除",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;

        try
        {
            await App.Services.State.RemoveManualGameAsync(game.Exe ?? "");
            ShowInfo("已移除", game.Name + " 已从游戏库移除。", InfoBarSeverity.Success);
            await LoadAsync(false);
        }
        catch (Exception ex)
        {
            ShowInfo("移除失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async Task<string?> PickExeAsync()
    {
        try
        {
            var picker = new Windows.Storage.Pickers.FileOpenPicker();
            picker.FileTypeFilter.Add(".exe");
            if (App.MainWindow is not null)
                WinRT.Interop.InitializeWithWindow.Initialize(picker,
                    WinRT.Interop.WindowNative.GetWindowHandle(App.MainWindow));
            var file = await picker.PickSingleFileAsync();
            return file?.Path;
        }
        catch (Exception ex)
        {
            AppLog.Write("选择 exe 失败: " + ex.Message);
            return null;
        }
    }

    private void ShowInfo(string title, string message, InfoBarSeverity severity)
    {
        PageInfo.Title = title;
        PageInfo.Message = message;
        PageInfo.Severity = severity;
        PageInfo.IsOpen = true;
    }

    public void OnThemeChanged() { }
}
