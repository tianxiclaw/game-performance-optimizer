using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Text.Json;
using GamePerfCenter.Helpers;
using GamePerfCenter.Models;
using GamePerfCenter.Services;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.Windows.Storage.Pickers;

namespace GamePerfCenter.Pages;

public sealed partial class GamesPage : Page, IThemeAware
{
    private readonly List<GameInfo> _all = new();
    private readonly ObservableCollection<GameInfo> _view = new();
    private GameInfo? _selected;
    private bool _loaded;
    private bool _syncingSelection;
    private bool _narrow;

    public GamesPage()
    {
        InitializeComponent();
        GameList.ItemsSource = _view;
        Loaded += OnLoaded;
        Responsive.Watch(this, 920, ApplyWidth);
    }

    /// <summary>宽窗口左列表右详情；窄窗口选中后整页显示详情，并可返回列表。</summary>
    private void ApplyWidth(bool narrow)
    {
        _narrow = narrow;
        Grid.SetColumnSpan(LibraryCard, narrow ? 2 : 1);
        Grid.SetRow(LibraryCard, 0);
        Grid.SetColumn(LibraryCard, 0);
        LibraryColumn.Width = narrow
            ? new GridLength(1, GridUnitType.Star)
            : new GridLength(340);
        LibraryRow.Height = new GridLength(1, GridUnitType.Star);

        Grid.SetRow(DetailPanel, 0);
        Grid.SetColumn(DetailPanel, narrow ? 0 : 1);
        Grid.SetColumnSpan(DetailPanel, narrow ? 2 : 1);
        DetailRow.Height = new GridLength(0);
        UpdateNarrowVisibility();
    }

    private void UpdateNarrowVisibility()
    {
        var showDetail = _narrow && _selected is not null;
        LibraryCard.Visibility = showDetail ? Visibility.Collapsed : Visibility.Visible;
        DetailPanel.Visibility = !_narrow || showDetail ? Visibility.Visible : Visibility.Collapsed;
        DetailBackButton.Visibility = showDetail ? Visibility.Visible : Visibility.Collapsed;
    }

    private void DetailBack_Click(object sender, RoutedEventArgs e)
    {
        _selected = null;
        _syncingSelection = true;
        GameList.SelectedItem = null;
        _syncingSelection = false;
        UpdateDetail(null);
        UpdateNarrowVisibility();
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (_loaded) return;
        _loaded = true;
        await LoadAsync(false);
    }

    private async Task LoadAsync(bool force)
    {
        var keepExe = _selected?.Exe;
        try
        {
            App.Services.State.SetStatus(force ? "正在扫描游戏库..." : "正在读取游戏库...");
            var games = await App.Services.State.GetGamesAsync(force);
            _all.Clear();
            _all.AddRange(games);
            ApplyFilter(keepExe);
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

    private void ApplyFilter(string? keepExe = null)
    {
        keepExe ??= _selected?.Exe;
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

        var target = keepExe is null
            ? null
            : _view.FirstOrDefault(g => string.Equals(g.Exe, keepExe, StringComparison.OrdinalIgnoreCase));
        var narrowNow = _narrow || (ActualWidth > 0 && ActualWidth < 920);
        if (!narrowNow) target ??= _view.FirstOrDefault();

        _syncingSelection = true;
        GameList.SelectedItem = target;
        _syncingSelection = false;
        _selected = target;
        UpdateDetail(target);
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => ApplyFilter();

    private async void Scan_Click(object sender, RoutedEventArgs e) => await LoadAsync(true);

    private void GameList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_syncingSelection) return;
        _selected = GameList.SelectedItem as GameInfo;
        UpdateDetail(_selected);
    }

    private async void EditProfile_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not GameInfo game) return;
        SelectGame(game);
        await EditProfileAsync(game);
    }

    private async void Row_DoubleTapped(object sender, Microsoft.UI.Xaml.Input.DoubleTappedRoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is not GameInfo game) return;
        SelectGame(game);
        await EditProfileAsync(game);
    }

    private void SelectGame(GameInfo game)
    {
        _syncingSelection = true;
        GameList.SelectedItem = game;
        _syncingSelection = false;
        _selected = game;
        UpdateDetail(game);
    }

    private async void DetailLaunch_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is { } game) await LaunchGameAsync(game);
    }

    private async void DetailEdit_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is { } game) await EditProfileAsync(game);
    }

    private async void DetailRemove_Click(object sender, RoutedEventArgs e)
    {
        if (_selected is { } game) await RemoveManualGame(game);
    }

    private void DetailFolder_Click(object sender, RoutedEventArgs e)
    {
        if (_selected?.Exe is not { Length: > 0 } exe) return;
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "explorer.exe",
                Arguments = $"/select,\"{exe}\"",
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            ShowInfo("打开目录失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    /// <summary>右侧详情只做展示与动作，所有字段来自当前选中项。</summary>
    private void UpdateDetail(GameInfo? game)
    {
        var has = game is not null;
        DetailContent.Visibility = has ? Visibility.Visible : Visibility.Collapsed;
        DetailEmpty.Visibility = has ? Visibility.Collapsed : Visibility.Visible;
        if (!has)
        {
            DetailLaunchButton.IsEnabled = false;
            DetailEditButton.IsEnabled = false;
            DetailFolderButton.IsEnabled = false;
            DetailRemoveButton.Visibility = Visibility.Collapsed;
            UpdateNarrowVisibility();
            return;
        }

        var name = string.IsNullOrWhiteSpace(game!.Name) ? "未命名游戏" : game.Name;
        DetailMonogram.Text = game.Initial;
        DetailName.Text = name;
        DetailSource.Text = game.SourceText;
        DetailState.Text = game.StateText;
        DetailState.Foreground = ThemeResources.Get(game.Exists ? "OkBrush" : "DangerBrush");
        DetailManualPill.Visibility = game.Manual ? Visibility.Visible : Visibility.Collapsed;
        DetailPath.Text = string.IsNullOrWhiteSpace(game.Exe) ? "未记录可执行文件路径" : game.Exe;
        DetailProfileText.Text = game.ProfileText;
        DetailProfileHint.Text = game.Profile?.HasSaved == true
            ? "点击「编辑方案」调整 CPU 优先级、亲和性、全屏与启动参数。"
            : "点击「编辑方案」为该游戏单独设置亲和性、优先级与启动参数。";
        DetailPriorityFact.Text = game.Profile?.Priority switch
        {
            "High" => "高",
            "AboveNormal" => "高于正常",
            _ => "默认"
        };
        DetailAffinityFact.Text = game.Profile?.Affinity == "Physical" ? "仅物理核心" : "全部核心";
        DetailFsFact.Text = game.Profile?.FsOff == true ? "开启" : "关闭";
        DetailGpuFact.Text = game.Profile?.GpuHigh == true ? "开启" : "关闭";
        DetailAdminFact.Text = game.Profile?.RunAsAdmin == true ? "开启" : "关闭";
        DetailArgsLine.Text = string.IsNullOrWhiteSpace(game.Profile?.Args)
            ? "启动参数：无"
            : "启动参数：" + game.Profile!.Args;

        DetailLaunchButton.IsEnabled = game.Exists;
        DetailEditButton.IsEnabled = true;
        DetailFolderButton.IsEnabled = !string.IsNullOrWhiteSpace(game.Exe) && game.Exists;
        DetailRemoveButton.Visibility = game.Manual ? Visibility.Visible : Visibility.Collapsed;
        UpdateNarrowVisibility();
    }


    private async Task EditProfileAsync(GameInfo game)
    {
        var path = new TextBlock
        {
            Text = game.Exe ?? "",
            FontSize = 11,
            Opacity = 0.62,
            TextWrapping = TextWrapping.Wrap,
            MaxLines = 2,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        var state = new TextBlock
        {
            Text = game.Profile?.HasSaved == true
                ? "当前方案：" + game.ProfileText
                : "尚未保存方案，当前使用默认启动策略。",
            FontSize = 12,
            Opacity = 0.72,
            TextWrapping = TextWrapping.Wrap
        };

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
        affinity.Items.Add("仅物理核心（每核保留 1 线程）");
        affinity.SelectedIndex = game.Profile?.Affinity == "Physical" ? 1 : 0;

        var affinityHint = new TextBlock
        {
            FontSize = 11,
            Opacity = 0.55,
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed
        };
        void UpdateAffinityHint()
        {
            if (affinity.SelectedIndex != 1)
            {
                affinityHint.Visibility = Visibility.Collapsed;
                return;
            }
            affinityHint.Text = CpuTopology.HasSmt
                ? $"本机 {CpuTopology.PhysicalCores} 核 {CpuTopology.LogicalProcessors} 线程：每个物理核心只保留一个线程。可能改善调度，也可能降低多线程性能。"
                : $"本机 {CpuTopology.PhysicalCores} 核 {CpuTopology.LogicalProcessors} 线程，没有超线程；此选项不会改变核心数量，建议保持“全部核心”。";
            affinityHint.Visibility = Visibility.Visible;
        }
        affinity.SelectionChanged += (_, _) => UpdateAffinityHint();
        UpdateAffinityHint();

        var fsOff = new CheckBox { Content = "请求全屏独占（禁用全屏优化）", IsChecked = game.Profile?.FsOff ?? false };
        var gpuHigh = new CheckBox { Content = "为该游戏指定高性能 GPU", IsChecked = game.Profile?.GpuHigh ?? false };
        var admin = new CheckBox { Content = "以管理员身份启动", IsChecked = game.Profile?.RunAsAdmin ?? false };
        var args = new TextBox { PlaceholderText = "额外启动参数（可选）", Text = game.Profile?.Args ?? "", MinHeight = 34 };

        var panel = new StackPanel { Spacing = 8, MinWidth = 420 };
        panel.Children.Add(path);
        panel.Children.Add(state);
        panel.Children.Add(new TextBlock { Text = "CPU 优先级", FontSize = 12, Opacity = 0.72 });
        panel.Children.Add(priority);
        panel.Children.Add(new TextBlock { Text = "CPU 亲和性", FontSize = 12, Opacity = 0.72 });
        panel.Children.Add(affinity);
        panel.Children.Add(affinityHint);
        panel.Children.Add(fsOff);
        panel.Children.Add(gpuHigh);
        panel.Children.Add(admin);
        panel.Children.Add(new TextBlock { Text = "启动参数", FontSize = 12, Opacity = 0.72 });
        panel.Children.Add(args);
        panel.Children.Add(new TextBlock
        {
            Text = "方案仅对该游戏生效，可随时在“应用/还原”中恢复系统原值。",
            FontSize = 11,
            Opacity = 0.55,
            TextWrapping = TextWrapping.Wrap
        });

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "启动方案 · " + (string.IsNullOrWhiteSpace(game.Name) ? "游戏" : game.Name),
            PrimaryButtonText = "保存方案",
            SecondaryButtonText = "保存并应用",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary
        };

        var body = new StackPanel { Spacing = 8 };
        body.Children.Add(new ScrollViewer
        {
            Content = panel,
            MaxHeight = 340,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        });

        var removeRequested = false;
        if (game.Manual)
        {
            var remove = new Button
            {
                Content = "从游戏库移除",
                HorizontalAlignment = HorizontalAlignment.Stretch
            };
            // 只关闭当前弹窗。确认框要等 ShowAsync 返回后再弹，
            // 否则 WinUI 会报 “Only a single ContentDialog can be open at any time”。
            remove.Click += (_, _) =>
            {
                removeRequested = true;
                dialog.Hide();
            };
            // 放在滚动区外面，保证始终可见、可点击。
            body.Children.Add(remove);
        }
        dialog.Content = body;

        var result = await dialog.ShowAsync();
        if (removeRequested)
        {
            await RemoveManualGame(game);
            return;
        }
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
            App.Services.State.SetStatus("正在保存游戏方案...");
            await App.Services.State.SaveGameProfileAsync(game.Exe ?? "", profile);
            var applied = false;
            if (result == ContentDialogResult.Secondary)
            {
                var appliedResult = await App.Services.State.ApplyGameProfileAsync(game.Exe ?? "", profile);
                applied = !appliedResult.TryGetProperty("Ok", out var okEl) || okEl.ValueKind != JsonValueKind.False;
            }
            ShowInfo("方案已保存", applied
                ? $"{game.Name} 的方案已保存并应用到系统。"
                : $"{game.Name} 的方案已保存，点击“启动”时自动生效。", InfoBarSeverity.Success);
            await LoadAsync(false);
        }
        catch (Exception ex)
        {
            ShowInfo("保存方案失败", ex.Message, InfoBarSeverity.Error);
        }
        finally
        {
            App.Services.State.SetStatus("就绪");
        }
    }

    private async void Start_Click(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).DataContext is GameInfo game) await LaunchGameAsync(game);
    }

    private async Task LaunchGameAsync(GameInfo game)
    {
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

    private async void AddGame_Click(object sender, RoutedEventArgs e)
    {
        var nameBox = new TextBox { PlaceholderText = "游戏名称（可留空，自动使用文件名）", MinHeight = 36 };
        var exeBox = new TextBox { PlaceholderText = @"例如 D:\Games\MyGame\MyGame.exe", MinHeight = 36 };
        var browse = new Button { Content = "浏览 exe...", HorizontalAlignment = HorizontalAlignment.Left };
        var error = new TextBlock
        {
            Foreground = new SolidColorBrush(Colors.OrangeRed),
            TextWrapping = TextWrapping.Wrap,
            Visibility = Visibility.Collapsed,
            FontSize = 12
        };

        void SetError(string text)
        {
            error.Text = text;
            error.Visibility = string.IsNullOrEmpty(text) ? Visibility.Collapsed : Visibility.Visible;
        }

        browse.Click += async (_, _) =>
        {
            try
            {
                var picked = await PickExeAsync();
                if (string.IsNullOrEmpty(picked)) return;
                exeBox.Text = picked;
                if (string.IsNullOrWhiteSpace(nameBox.Text))
                    nameBox.Text = Path.GetFileNameWithoutExtension(picked);
                SetError("");
            }
            catch (Exception ex)
            {
                SetError("无法打开文件对话框：" + ex.Message + "\n可以手动粘贴完整路径。");
            }
        };

        var panel = new StackPanel { Spacing = 10, MinWidth = 420 };
        panel.Children.Add(new TextBlock { Text = "名称", FontSize = 12, Opacity = 0.72 });
        panel.Children.Add(nameBox);
        panel.Children.Add(new TextBlock { Text = "可执行文件", FontSize = 12, Opacity = 0.72 });
        panel.Children.Add(exeBox);
        panel.Children.Add(browse);
        panel.Children.Add(new TextBlock
        {
            Text = "Steam / Epic / WeGame 游戏会自动扫描，无需手动添加。",
            FontSize = 12,
            Opacity = 0.62,
            TextWrapping = TextWrapping.Wrap
        });
        panel.Children.Add(error);

        var added = false;
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = "手动添加游戏",
            Content = new ScrollViewer
            {
                Content = panel,
                MaxHeight = 320,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto
            },
            PrimaryButtonText = "添加",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Primary
        };

        dialog.PrimaryButtonClick += async (_, args) =>
        {
            var deferral = args.GetDeferral();
            try
            {
                SetError("");
                var exe = exeBox.Text?.Trim().Trim('"') ?? "";
                if (string.IsNullOrEmpty(exe))
                {
                    args.Cancel = true;
                    SetError("请填写或选择游戏 exe 路径。");
                    return;
                }
                if (!File.Exists(exe))
                {
                    args.Cancel = true;
                    SetError("找不到文件：" + exe + "\n如果游戏位于映射网络驱动器，请改用完整的 UNC 路径。");
                    return;
                }

                var name = nameBox.Text?.Trim() ?? "";
                if (string.IsNullOrEmpty(name)) name = Path.GetFileNameWithoutExtension(exe);
                await App.Services.State.AddGameAsync(name, exe);
                added = true;
            }
            catch (Exception ex)
            {
                args.Cancel = true;
                SetError("添加失败：" + ex.Message);
            }
            finally
            {
                deferral.Complete();
            }
        };

        await dialog.ShowAsync();
        if (!added) return;

        ShowInfo("已添加", "游戏已加入游戏库，可以点击“编辑”保存专属启动方案。", InfoBarSeverity.Success);
        await LoadAsync(false);
    }

    private async Task RemoveManualGame(GameInfo game)
    {
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
            _selected = null;
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
        if (App.MainWindow is null) return null;
        var picker = new FileOpenPicker(App.MainWindow.AppWindow.Id)
        {
            SuggestedStartLocation = PickerLocationId.ComputerFolder,
            CommitButtonText = "选择"
        };
        picker.FileTypeFilter.Add(".exe");
        var result = await picker.PickSingleFileAsync();
        return result?.Path;
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
