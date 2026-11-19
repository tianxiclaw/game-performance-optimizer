using System.Collections.ObjectModel;
using System.Text.Json;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using GamePerfCenter.Helpers;
using GamePerfCenter.Models;
using GamePerfCenter.Services;

namespace GamePerfCenter.Pages;

public sealed partial class ItemsPage : Page, IThemeAware
{
    private List<ProfileInfo> _profiles = new();
    private bool _loadingProfiles;
    private bool _loading = true;
    private bool? _twoRow;
    private bool? _short;

    public ObservableCollection<ItemInfo> View { get; } = new();

    public ItemsPage()
    {
        InitializeComponent();
        NavigationCacheMode = Microsoft.UI.Xaml.Navigation.NavigationCacheMode.Required;
        App.Services.State.Changed += OnStateChanged;
        Loaded += OnLoaded;
        Loaded += (_, _) => ApplyDensity(ActualWidth, ActualHeight);
        // 行模板按需实例化，且会被回收复用；每次换内容时按当前语言刷新其中的静态文案。
        ItemsList.ContainerContentChanging += (_, e) =>
        {
            if (!e.InRecycleQueue && e.ItemContainer is DependencyObject container)
                Localization.Apply(container);
        };
        SizeChanged += (_, e) => ApplyDensity(e.NewSize.Width, e.NewSize.Height);
        Responsive.Watch(this, 640, narrow =>
            ViewCountText.Visibility = narrow ? Visibility.Collapsed : Visibility.Visible);
    }

    /// <summary>
    /// 窄窗口把筛选条折成两行，保证搜索框不会被下拉框挤成 0 宽；
    /// 矮窗口收紧内外边距并隐藏重复的状态计数，把高度留给列表本身。
    /// </summary>
    private void ApplyDensity(double width, double height)
    {
        if (width <= 0 || height <= 0) return;

        var twoRow = width < 780;
        if (_twoRow != twoRow)
        {
            _twoRow = twoRow;
            if (twoRow)
            {
                Grid.SetRow(SearchBox, 0);
                Grid.SetColumn(SearchBox, 0);
                Grid.SetColumnSpan(SearchBox, 4);

                Grid.SetRow(CategoryBox, 1);
                Grid.SetColumn(CategoryBox, 0);
                Grid.SetRow(RiskBox, 1);
                Grid.SetColumn(RiskBox, 1);
                Grid.SetRow(ProfileGroup, 1);
                Grid.SetColumn(ProfileGroup, 2);

                CategoryBox.Margin = new Thickness(0, 8, 0, 0);
                RiskBox.Margin = new Thickness(0, 8, 0, 0);
                ProfileGroup.Margin = new Thickness(0, 8, 0, 0);

                Grid.SetRow(StatusRow, 2);

                FilterGrid.ColumnDefinitions[0].Width = new GridLength(1, GridUnitType.Star);
                FilterGrid.ColumnDefinitions[1].Width = new GridLength(1, GridUnitType.Star);
                FilterGrid.ColumnDefinitions[2].Width = new GridLength(1.2, GridUnitType.Star);

                CategoryBox.MinWidth = 0;
                RiskBox.MinWidth = 0;
                ProfileBox.MinWidth = 0;
            }
            else
            {
                Grid.SetRow(SearchBox, 0);
                Grid.SetColumn(SearchBox, 0);
                Grid.SetColumnSpan(SearchBox, 1);

                Grid.SetRow(CategoryBox, 0);
                Grid.SetColumn(CategoryBox, 1);
                Grid.SetRow(RiskBox, 0);
                Grid.SetColumn(RiskBox, 2);
                Grid.SetRow(ProfileGroup, 0);
                Grid.SetColumn(ProfileGroup, 3);

                CategoryBox.Margin = new Thickness(0);
                RiskBox.Margin = new Thickness(0);
                ProfileGroup.Margin = new Thickness(0);

                Grid.SetRow(StatusRow, 1);

                FilterGrid.ColumnDefinitions[0].Width = new GridLength(1, GridUnitType.Star);
                FilterGrid.ColumnDefinitions[1].Width = GridLength.Auto;
                FilterGrid.ColumnDefinitions[2].Width = GridLength.Auto;

                CategoryBox.MinWidth = 132;
                RiskBox.MinWidth = 120;
                ProfileBox.MinWidth = 128;
            }
        }

        var shortHeight = height < 520;
        if (_short == shortHeight) return;
        _short = shortHeight;

        RootGrid.Padding = shortHeight ? new Thickness(14, 10, 14, 10) : new Thickness(24, 18, 24, 18);
        RootGrid.RowSpacing = shortHeight ? 6 : 10;

        FilterPanel.Padding = shortHeight ? new Thickness(12, 8, 12, 8) : new Thickness(14, 12, 14, 12);
        StatusRow.Visibility = shortHeight ? Visibility.Collapsed : Visibility.Visible;

        ListPanel.Padding = shortHeight ? new Thickness(12, 8, 12, 4) : new Thickness(14, 10, 14, 6);
        ActionPanel.Padding = shortHeight ? new Thickness(12, 6, 12, 6) : new Thickness(14, 10, 14, 10);
        ActionHint.Visibility = shortHeight ? Visibility.Collapsed : Visibility.Visible;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        _loading = true;
        InitFilters();
        RefreshView();
        try
        {
            await App.Services.State.EnsureSnapshotAsync();
            _loading = false;
            InitFilters();
            RefreshView();
            await LoadProfilesAsync();
        }
        catch (Exception ex)
        {
            _loading = false;
            RefreshView();
            ShowInfo("状态读取失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private void OnStateChanged()
    {
        DispatcherQueue.TryEnqueue(() =>
        {
            RefreshView();
            _ = LoadProfilesAsync();
        });
    }

    private void InitFilters()
    {
        var currentCat = (CategoryBox.SelectedItem as ComboBoxItem)?.Tag as string;
        var items = App.Services.State.Items;
        var cats = items.Select(i => i.Cat).Where(c => !string.IsNullOrWhiteSpace(c))
            .Select(c => c!).Distinct().OrderBy(c => c).ToList();

        _loadingProfiles = true;
        CategoryBox.Items.Clear();
        CategoryBox.Items.Add(new ComboBoxItem { Content = Localization.T("全部分类"), Tag = null });
        foreach (var c in cats) CategoryBox.Items.Add(new ComboBoxItem { Content = c, Tag = c });
        CategoryBox.SelectedIndex = currentCat is null ? 0 : Math.Max(0, cats.IndexOf(currentCat) + 1);

        // 风险项按当前语言重建，切换语言后标题立即同步。
        var currentRisk = SelectedTag(RiskBox);
        RiskBox.Items.Clear();
        RiskBox.Items.Add(new ComboBoxItem { Content = Localization.T("全部风险"), Tag = null });
        RiskBox.Items.Add(new ComboBoxItem { Content = Localization.T("低风险"), Tag = "low" });
        RiskBox.Items.Add(new ComboBoxItem { Content = Localization.T("中风险"), Tag = "mid" });
        RiskBox.Items.Add(new ComboBoxItem { Content = Localization.T("高风险"), Tag = "high" });
        RiskBox.SelectedIndex = currentRisk switch
        {
            "low" => 1,
            "mid" => 2,
            "high" => 3,
            _ => 0
        };
        _loadingProfiles = false;
    }

    private async Task LoadProfilesAsync()
    {
        try
        {
            var profiles = await App.Services.State.GetProfilesAsync();
            _profiles = profiles;
            _loadingProfiles = true;
            ProfileBox.ItemsSource = profiles;
            ProfileBox.DisplayMemberPath = "Name";
            if (profiles.Count > 0 && ProfileBox.SelectedIndex < 0) ProfileBox.SelectedIndex = 0;
        }
        catch (Exception ex)
        {
            AppLog.Write("方案加载失败: " + ex.Message);
        }
        finally { _loadingProfiles = false; }
    }

    private static string? SelectedTag(ComboBox box)
        => (box.SelectedItem as ComboBoxItem)?.Tag as string;

    private void RefreshView()
    {
        if (CategoryBox.Items.Count == 0) InitFilters();
        var search = SearchBox.Text?.Trim() ?? "";
        var cat = SelectedTag(CategoryBox);
        var risk = SelectedTag(RiskBox);

        // 上次应用时间来自快照，不随单项刷新变化；先写回模型，行内详情直接绑定。
        var lastApply = App.Services.State.Snapshot?.LastApply;
        foreach (var item in App.Services.State.Items)
        {
            var hit = lastApply?.Items?.FirstOrDefault(x => x.Id == item.Id);
            item.LastAppliedText = hit is null
                ? Localization.T("尚未通过本工具应用")
                : Localization.F("上次应用 {0}", ShortTime(lastApply!.Time));
        }

        var filtered = App.Services.State.Items.Where(i =>
        {
            if (!string.IsNullOrEmpty(cat) && !string.Equals(i.Cat, cat, StringComparison.OrdinalIgnoreCase)) return false;
            if (!string.IsNullOrEmpty(risk) && !string.Equals(i.Risk, risk, StringComparison.OrdinalIgnoreCase)) return false;
            if (search.Length > 0)
            {
                var hay = $"{i.Name} {i.Cat} {i.Desc} {i.StatusText}".ToLowerInvariant();
                if (hay.IndexOf(search.ToLowerInvariant(), StringComparison.Ordinal) < 0) return false;
            }
            return true;
        }).ToList();

        View.Clear();
        foreach (var item in filtered) View.Add(item);
        EmptyHint.Visibility = View.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        var all = App.Services.State.Items;
        var initializing = _loading && all.Count == 0;
        EmptyTitle.Text = Localization.T(initializing ? "正在读取优化项" : "没有符合条件的优化项");
        EmptyDetail.Text = Localization.T(initializing
            ? "正在读取当前系统状态，通常需要几秒。"
            : "试试清空搜索词，或把分类、风险筛选恢复为全部。");

        var applied = all.Count(i => i.Status == "ok");
        var pending = all.Count(i => i.Status == "no");
        var na = all.Count(i => i.Status == "na");
        var selected = all.Where(i => i.Selected).ToList();
        AppliedChip.Text = initializing ? Localization.T("已生效 —") : Localization.F("已生效 {0}", applied);
        PendingChip.Text = initializing ? Localization.T("待优化 —") : Localization.F("待优化 {0}", pending);
        NaChip.Text = initializing ? Localization.T("不适用 —") : Localization.F("不适用 {0}", na);
        SelectedChip.Text = Localization.F("已选 {0}", selected.Count);
        ViewCountText.Text = initializing ? Localization.T("正在读取...") : Localization.F("显示 {0} / {1} 项", View.Count, all.Count);

        var low = selected.Count(i => i.Risk == "low");
        var mid = selected.Count(i => i.Risk == "mid");
        var high = selected.Count(i => i.Risk == "high");
        if (selected.Count == 0)
        {
            ActionSummary.Text = Localization.T("未选择项目");
        }
        else
        {
            ActionSummary.Text = Localization.F("已选 {0} 项 · 低风险 {1} · 中风险 {2} · 高风险 {3}",
                selected.Count, low, mid, high);
        }
        PreviewButton.IsEnabled = selected.Count > 0;
        ApplyButton.IsEnabled = selected.Count > 0;
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e) => RefreshView();

    private void Filter_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loadingProfiles) return;
        RefreshView();
    }

    private void ItemCheck_Click(object sender, RoutedEventArgs e) => RefreshView();

    private void SelectRecommended_Click(object sender, RoutedEventArgs e)
    {
        foreach (var item in App.Services.State.Items)
            item.Selected = item.Risk == "low" && item.Status is "no" or "checking";
        RefreshView();
        ShowInfo("已选择推荐项", "已勾选全部待优化的低风险项目。", InfoBarSeverity.Informational);
    }

    private void ClearSelection_Click(object sender, RoutedEventArgs e)
    {
        foreach (var item in App.Services.State.Items) item.Selected = false;
        RefreshView();
    }

    private async void LoadProfile_Click(object sender, RoutedEventArgs e)
    {
        if (ProfileBox.SelectedItem is not ProfileInfo profile)
        {
            ShowInfo("请选择方案", "下拉框中没有可载入的预设方案。", InfoBarSeverity.Warning);
            return;
        }
        var ids = profile.Ids ?? new List<string>();
        foreach (var item in App.Services.State.Items)
            item.Selected = item.Id is not null && ids.Contains(item.Id);
        RefreshView();
        ShowInfo("方案已载入", Localization.F("已载入「{0}」，共勾选 {1} 项。",
                profile.Name, App.Services.State.Items.Count(i => i.Selected)),
            InfoBarSeverity.Success);
        await Task.CompletedTask;
    }

    private async void SaveProfile_Click(object sender, RoutedEventArgs e)
    {
        var selected = App.Services.State.Items.Where(i => i.Selected).ToList();
        if (selected.Count == 0)
        {
            ShowInfo("没有选中项", "请先勾选要保存的优化项。", InfoBarSeverity.Warning);
            return;
        }
        var box = new TextBox { PlaceholderText = Localization.T("例如：我的竞技配置"), MinWidth = 320 };
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = Localization.T("保存自定义方案"),
            Content = box,
            PrimaryButtonText = Localization.T("保存"),
            CloseButtonText = Localization.T("取消"),
            DefaultButton = ContentDialogButton.Primary
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        var name = box.Text?.Trim();
        if (string.IsNullOrWhiteSpace(name))
        {
            ShowInfo("名称不能为空", "请输入方案名称。", InfoBarSeverity.Warning);
            return;
        }
        try
        {
            await App.Services.State.SaveProfileAsync(name, selected.Select(i => i.Id!));
            await LoadProfilesAsync();
            ShowInfo("方案已保存", Localization.F("「{0}」包含 {1} 项，已保存到本机 profiles.json。",
                    name, selected.Count),
                InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowInfo("保存失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            ShowInfo("正在刷新", "重新检测全部优化项状态...", InfoBarSeverity.Informational);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            InitFilters();
            RefreshView();
            ShowInfo("刷新完成", "优化项状态已更新。", InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowInfo("刷新失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    /// <summary>行内展开：同一时间只展开一项，避免列表被拉得过长。</summary>
    private void ToggleExpanded(ItemInfo item)
    {
        var expand = !item.IsExpanded;
        foreach (var other in View) other.IsExpanded = false;
        item.IsExpanded = expand;
        if (!expand) return;

        ItemsList.ScrollIntoView(item);
        DispatcherQueue.TryEnqueue(() =>
        {
            if (ItemsList.ContainerFromItem(item) is not DependencyObject container) return;
            var detail = FindDescendant<Border>(container, b => (b.Tag as string) == "ItemDetail");
            if (detail is not null) Motion.FadeSlideIn(detail, 5, 150);
        });
    }

    private void Expand_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is ItemInfo item) ToggleExpanded(item);
    }

    private void Row_Tapped(object sender, TappedRoutedEventArgs e)
    {
        if (IsInteractiveSource(e.OriginalSource as DependencyObject)) return;
        if (sender is not FrameworkElement { DataContext: ItemInfo item }) return;
        ToggleExpanded(item);
        e.Handled = true;
    }

    private ItemInfo? _contextItem;
    private MenuFlyout? _rowMenu;

    /// <summary>右键菜单复用行内操作，避免为每个功能再开一个入口。</summary>
    private void Row_RightTapped(object sender, RightTappedRoutedEventArgs e)
    {
        var row = sender as FrameworkElement;
        var item = row?.DataContext as ItemInfo;
        if (item is null && FindRowContainer(e.OriginalSource as DependencyObject) is { } container)
            item = ItemsList.ItemFromContainer(container) as ItemInfo;
        if (row is null || item is null) return;
        _contextItem = item;
        _rowMenu ??= BuildRowMenu();
        // 菜单是复用的，每次打开按当前语言刷新文案，切换语言后不会留旧文本。
        if (_rowMenu.Items[0] is MenuFlyoutItem expand)
            expand.Text = Localization.T(item.IsExpanded ? "收起详情" : "查看详情");
        if (_rowMenu.Items[1] is MenuFlyoutItem apply)
            apply.Text = Localization.T("应用此项");
        if (_rowMenu.Items[3] is MenuFlyoutItem copy)
            copy.Text = Localization.T("复制 ID");
        _rowMenu.ShowAt(row, new FlyoutShowOptions { Position = e.GetPosition(row) });
        e.Handled = true;
    }

    private MenuFlyout BuildRowMenu()
    {
        var expand = new MenuFlyoutItem { Text = Localization.T("查看详情"), Icon = new FontIcon { Glyph = "\uE70D" } };
        expand.Click += (_, _) => { if (_contextItem is { } item) ToggleExpanded(item); };

        var apply = new MenuFlyoutItem { Text = Localization.T("应用此项"), Icon = new FontIcon { Glyph = "\uE768" } };
        apply.Click += (_, _) => { if (_contextItem is { } item) _ = ApplyItemAsync(item); };

        var copy = new MenuFlyoutItem { Text = Localization.T("复制 ID") };
        copy.Click += (_, _) => { if (_contextItem is { } item) CopyItemId(item); };

        var menu = new MenuFlyout();
        menu.Items.Add(expand);
        menu.Items.Add(apply);
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(copy);
        return menu;
    }

    /// <summary>按钮、勾选框与已展开的详情区域不参与整行展开。</summary>
    private static bool IsInteractiveSource(DependencyObject? source)
    {
        for (var i = 0; i < 12 && source is not null; i++)
        {
            if (source is Button or CheckBox or TextBox) return true;
            if (source is FrameworkElement { Tag: "ItemDetail" }) return true;
            source = VisualTreeHelper.GetParent(source);
        }
        return false;
    }

    /// <summary>从命中的子元素向上找所属行容器，不依赖 DataContext 是否传播。</summary>
    private static ListViewItem? FindRowContainer(DependencyObject? source)
    {
        for (var i = 0; i < 16 && source is not null; i++)
        {
            if (source is ListViewItem item) return item;
            source = VisualTreeHelper.GetParent(source);
        }
        return null;
    }

    private static T? FindDescendant<T>(DependencyObject root, Func<T, bool>? match = null)
        where T : DependencyObject
    {
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < count; i++)
        {
            var child = VisualTreeHelper.GetChild(root, i);
            if (child is T typed && (match is null || match(typed))) return typed;
            var found = FindDescendant(child, match);
            if (found is not null) return found;
        }
        return null;
    }

    private async void ApplyItem_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is ItemInfo item) await ApplyItemAsync(item);
    }

    private async Task ApplyItemAsync(ItemInfo item)
    {
        if (string.IsNullOrWhiteSpace(item.Id)) return;

        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = Localization.F("应用「{0}」", item.Name),
            Content = new TextBlock
            {
                Text = Localization.F("目标：{0}\n风险：{1}\n\n应用前会自动生成原值备份与 .reg 快照，可在「备份还原」中撤销。",
                    item.Target, RiskLabel(item.Risk)),
                TextWrapping = TextWrapping.Wrap,
                LineHeight = 22
            },
            PrimaryButtonText = Localization.T("应用"),
            CloseButtonText = Localization.T("取消"),
            DefaultButton = ContentDialogButton.Primary
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        await RunApplyAsync(new List<string> { item.Id! }, dryRun: false);
    }

    private void CopyId_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.DataContext is ItemInfo item) CopyItemId(item);
    }

    private void CopyItemId(ItemInfo item)
    {
        if (string.IsNullOrWhiteSpace(item.Id)) return;
        try
        {
            var package = new DataPackage();
            package.SetText(item.Id);
            Clipboard.SetContent(package);
            Clipboard.Flush();
            ShowInfo("已复制 ID", Localization.F("{0} 已写入剪贴板。", item.Id), InfoBarSeverity.Success);
        }
        catch (Exception ex)
        {
            ShowInfo("复制失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private static string ShortTime(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "时间未知";
        var text = value.Replace('T', ' ');
        return text.Length >= 16 && text[4] == '-' ? text.Substring(5, 11) : text;
    }

    /// <summary>命令面板定位：清空筛选、展开目标行并滚动到可见位置。</summary>
    public void FocusItem(string id)
    {
        _loadingProfiles = true;
        SearchBox.Text = string.Empty;
        if (CategoryBox.Items.Count > 0) CategoryBox.SelectedIndex = 0;
        if (RiskBox.Items.Count > 0) RiskBox.SelectedIndex = 0;
        _loadingProfiles = false;
        RefreshView();

        var item = View.FirstOrDefault(i => string.Equals(i.Id, id, StringComparison.OrdinalIgnoreCase));
        if (item is null)
        {
            var source = App.Services.State.Items
                .FirstOrDefault(i => string.Equals(i.Id, id, StringComparison.OrdinalIgnoreCase));
            if (source is null) return;
            SearchBox.Text = source.Name ?? "";
            RefreshView();
            item = View.FirstOrDefault(i => string.Equals(i.Id, id, StringComparison.OrdinalIgnoreCase));
        }
        if (item is null) return;

        foreach (var other in View) other.IsExpanded = false;
        item.IsExpanded = true;
        ItemsList.ScrollIntoView(item);
        ItemsList.Focus(FocusState.Programmatic);
        DispatcherQueue.TryEnqueue(() =>
        {
            ItemsList.ScrollIntoView(item);
            if (ItemsList.ContainerFromItem(item) is DependencyObject container)
            {
                var detail = FindDescendant<Border>(container, b => (b.Tag as string) == "ItemDetail");
                if (detail is not null) Motion.FadeSlideIn(detail, 5, 150);
            }
        });
    }

    private static string RiskLabel(string? risk) => Localization.T(risk switch
    {
        "low" => "低风险",
        "mid" => "中风险",
        "high" => "高风险",
        _ => "未知风险"
    });

    private List<string> SelectedIds()
        => App.Services.State.Items.Where(i => i.Selected && !string.IsNullOrEmpty(i.Id))
            .Select(i => i.Id!).ToList();

    private async void PreviewSelected_Click(object sender, RoutedEventArgs e)
    {
        var ids = SelectedIds();
        if (ids.Count == 0)
        {
            ShowInfo("没有选中项", "请先勾选要预览的优化项。", InfoBarSeverity.Warning);
            return;
        }
        await RunApplyAsync(ids, dryRun: true);
    }

    private async void ApplySelected_Click(object sender, RoutedEventArgs e)
    {
        var ids = SelectedIds();
        if (ids.Count == 0)
        {
            ShowInfo("没有选中项", "请先勾选要应用的优化项。", InfoBarSeverity.Warning);
            return;
        }
        var high = App.Services.State.Items.Count(i => i.Selected && i.Risk == "high");
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = Localization.T("应用所选优化"),
            Content = new TextBlock
            {
                Text = high > 0
                    ? Localization.F("将应用 {0} 项优化，其中 {1} 项为高风险。\n\n应用前会自动生成原值备份与 .reg 快照，可在「备份还原」中撤销。", ids.Count, high)
                    : Localization.F("将应用 {0} 项优化。\n\n应用前会自动生成原值备份与 .reg 快照，可在「备份还原」中撤销。", ids.Count),
                TextWrapping = TextWrapping.Wrap,
                LineHeight = 22
            },
            PrimaryButtonText = Localization.T("确认应用"),
            CloseButtonText = Localization.T("取消"),
            DefaultButton = ContentDialogButton.Primary
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        await RunApplyAsync(ids, dryRun: false);
    }

    private async Task RunApplyAsync(List<string> ids, bool dryRun)
    {
        try
        {
            var result = await App.Services.State.ApplyAsync(ids, dryRun);
            if (dryRun)
            {
                await ShowPreviewAsync(result);
                return;
            }
            var msg = Localization.F("成功 {0} 项 · 失败 {1} 项", result.Ok, result.Fail);
            if (!string.IsNullOrWhiteSpace(result.Backup)) msg += $"\n备份：{result.Backup}";
            ShowInfo(result.Fail == 0 ? "优化已应用" : "部分项目失败", msg,
                result.Fail == 0 ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            InitFilters();
            RefreshView();
        }
        catch (Exception ex)
        {
            ShowInfo("操作失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private async Task ShowPreviewAsync(ApplyResult result)
    {
        var panel = new StackPanel { Spacing = 10 };
        if (result.Preview.Count == 0)
        {
            panel.Children.Add(new TextBlock { Text = Localization.T("所选项目均已处于推荐值，无需变更。") });
        }
        else
        {
            panel.Children.Add(new TextBlock
            {
                Text = Localization.F("共 {0} 项将发生变更（预览不会写入系统）：", result.Preview.Count),
                FontWeight = FontWeights.SemiBold
            });
            foreach (var item in result.Preview)
            {
                var row = new StackPanel { Spacing = 2, Margin = new Thickness(0, 2, 0, 6) };
                row.Children.Add(new TextBlock { Text = item.Name, FontWeight = FontWeights.SemiBold });
                row.Children.Add(new TextBlock
                {
                    Text = Localization.F(item.NeedsReboot
                            ? "当前：{0}  →  目标：{1}  · 需重启"
                            : "当前：{0}  →  目标：{1}", item.Current, item.Target),
                    Opacity = 0.78,
                    FontSize = 12.5,
                    TextWrapping = TextWrapping.Wrap
                });
                panel.Children.Add(row);
            }
        }
        await new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = Localization.T("变更预览"),
            Content = new ScrollViewer { Content = panel, MaxHeight = 460 },
            CloseButtonText = Localization.T("关闭")
        }.ShowAsync();
    }

    private async void RestoreLatest_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = Localization.T("恢复最近备份"),
            Content = new TextBlock
            {
                Text = Localization.T("将把最近一次应用的原值写回系统。此操作会修改注册表/服务/电源设置。\n\n确定继续吗？"),
                TextWrapping = TextWrapping.Wrap,
                LineHeight = 22
            },
            PrimaryButtonText = Localization.T("恢复"),
            CloseButtonText = Localization.T("取消"),
            DefaultButton = ContentDialogButton.Close
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        try
        {
            var result = await App.Services.State.RestoreAsync(null);
            var ok = ReadInt(result, "Ok");
            var fail = ReadInt(result, "Fail");
            ShowInfo("恢复完成", Localization.F("成功 {0} 项 · 失败 {1} 项", ok, fail),
                fail == 0 ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
            await App.Services.State.EnsureSnapshotAsync(force: true);
            RefreshView();
        }
        catch (Exception ex)
        {
            ShowInfo("恢复失败", ex.Message, InfoBarSeverity.Error);
        }
    }

    private static int ReadInt(JsonElement element, string name)
    {
        if (!element.TryGetProperty(name, out var value)) return 0;
        if (value.ValueKind == JsonValueKind.Number) return value.TryGetInt32(out var n) ? n : 0;
        return int.TryParse(value.ToString(), out var parsed) ? parsed : 0;
    }

    private void ShowInfo(string title, string message, InfoBarSeverity severity)
    {
        PageInfo.Title = Localization.T(title);
        PageInfo.Message = Localization.T(message);
        PageInfo.Severity = severity;
        PageInfo.IsOpen = true;
    }

    public void OnThemeChanged() => RefreshView();

    public void OnLanguageChanged()
    {
        InitFilters();
        RefreshView();
    }
}
