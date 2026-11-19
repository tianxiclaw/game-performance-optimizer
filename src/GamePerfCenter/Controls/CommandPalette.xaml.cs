using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.System;
using GamePerfCenter.Helpers;

namespace GamePerfCenter.Controls;

/// <summary>命令面板条目。Invoke 在面板关闭后执行，避免焦点留在遮罩里。</summary>
public sealed class CommandItem
{
    public string Id { get; init; } = "";
    public string Title { get; init; } = "";
    public string Detail { get; init; } = "";
    public string Glyph { get; init; } = "\uE8A5";
    public string Group { get; init; } = "";
    public string Keywords { get; init; } = "";
    public Action? Invoke { get; init; }
}

public sealed partial class CommandPalette : UserControl
{
    private readonly List<CommandItem> _all = new();
    private readonly List<CommandItem> _filtered = new();
    private readonly TranslateTransform _cardShift = new();
    private List<string> _recents = new();
    private Storyboard? _closeStory;
    private bool _closing;
    private Control? _previousFocus;

    public event Action<CommandItem>? CommandInvoked;

    public bool IsOpen => Layer.Visibility == Visibility.Visible;

    public CommandPalette()
    {
        InitializeComponent();
        Card.RenderTransform = _cardShift;
        Results.SelectedIndex = -1;
        // 列表容器会被回收复用：离开选中态的行如果不显式回到 Unselected，
        // 复用后仍会带着强调色遮罩。选中变化与容器实化时都同步一次。
        Results.SelectionChanged += (_, _) => SyncSelectionVisuals();
        Results.ContainerContentChanging += (_, e) =>
        {
            if (e.InRecycleQueue) return;
            if (e.ItemContainer is ListViewItem container) SyncContainerSelection(container);
        };
        // 搜索框内部的 TextBox 会先把 Enter / 方向键处理掉，冒泡阶段的 KeyDown 收不到，
        // 因此所有面板快捷键统一在 PreviewKeyDown（隧道阶段）处理。
        AddHandler(PreviewKeyDownEvent, new KeyEventHandler(Layer_PreviewKeyDown), true);
    }

    /// <summary>
    /// 已实化的行逐个对齐到真实选中状态。上/下键只改 SelectedIndex，
    /// 焦点仍在搜索框时框架未必更新旧行的选择状态，这里补一次。
    /// </summary>
    private void SyncSelectionVisuals()
    {
        for (var i = 0; i < _filtered.Count; i++)
        {
            if (Results.ContainerFromIndex(i) is ListViewItem container) SyncContainerSelection(container);
        }
    }

    private static void SyncContainerSelection(ListViewItem container)
        => VisualStateManager.GoToState(container, container.IsSelected ? "SelectedUnfocused" : "Unselected", false);

    public void Open(IEnumerable<CommandItem> commands, IEnumerable<string> recents)
    {
        _all.Clear();
        _all.AddRange(commands);
        _recents = recents.ToList();
        _closing = false;
        _closeStory?.Stop();
        _previousFocus = FocusManager.GetFocusedElement(XamlRoot) as Control;

        Layer.Visibility = Visibility.Visible;
        QueryBox.Text = string.Empty;
        ApplyFilter();

        if (Motion.Enabled)
        {
            Layer.Opacity = 0;
            _cardShift.Y = -10;
            var ease = new CubicEase { EasingMode = EasingMode.EaseOut };
            var story = new Storyboard();
            story.Children.Add(Animate(Layer, "Opacity", 0, 1, 140, ease));
            story.Children.Add(Animate(_cardShift, "Y", -10, 0, 190, ease));
            story.Begin();
        }
        else
        {
            Layer.Opacity = 1;
            _cardShift.Y = 0;
        }

        QueryBox.Focus(FocusState.Programmatic);
        _ = FocusQueryAsync();
    }

    /// <summary>
    /// 遮罩刚从 Collapsed 变为 Visible 时，搜索框还没完成布局，同步 Focus 会失败。
    /// 用 FocusManager 等一次布局后再聚焦；仍失败时补一次延迟重试。
    /// </summary>
    private async Task FocusQueryAsync()
    {
        try
        {
            await FocusManager.TryFocusAsync(QueryBox, FocusState.Programmatic);
            if (QueryBox.FocusState != FocusState.Unfocused) return;
        }
        catch
        {
            // 窗口正在关闭等情况下忽略。
        }

        await Task.Delay(60);
        if (IsOpen) QueryBox.Focus(FocusState.Programmatic);
    }

    /// <summary>游戏库等异步来源到达后，保持当前关键词与选中位置刷新列表。</summary>
    public void SetCommands(IEnumerable<CommandItem> commands)
    {
        _all.Clear();
        _all.AddRange(commands);
        if (IsOpen) ApplyFilter(keepSelection: true);
    }

    public void Close()
    {
        if (!IsOpen) return;

        if (!Motion.Enabled)
        {
            Layer.Visibility = Visibility.Collapsed;
            Layer.Opacity = 1;
            _cardShift.Y = 0;
            RestoreFocus();
            return;
        }

        if (_closing) return;
        _closing = true;
        var ease = new CubicEase { EasingMode = EasingMode.EaseIn };
        var story = new Storyboard();
        story.Children.Add(Animate(Layer, "Opacity", Layer.Opacity, 0, 110, ease));
        story.Children.Add(Animate(_cardShift, "Y", _cardShift.Y, -6, 110, ease));
        story.Completed += (_, _) =>
        {
            Layer.Visibility = Visibility.Collapsed;
            Layer.Opacity = 1;
            _cardShift.Y = 0;
            _closing = false;
            RestoreFocus();
        };
        _closeStory = story;
        story.Begin();
    }

    /// <summary>取消类关闭（Esc / 点遮罩）把焦点还给打开前的控件；执行命令后页面可能已切换，不再回填。</summary>
    private void RestoreFocus()
    {
        var target = _previousFocus;
        _previousFocus = null;
        if (target is null || !target.IsLoaded) return;
        try { target.Focus(FocusState.Programmatic); } catch { }
    }

    private static DoubleAnimation Animate(DependencyObject target, string property,
        double from, double to, int milliseconds, EasingFunctionBase ease)
    {
        var animation = new DoubleAnimation
        {
            From = from,
            To = to,
            Duration = TimeSpan.FromMilliseconds(milliseconds),
            EasingFunction = ease
        };
        Storyboard.SetTarget(animation, target);
        Storyboard.SetTargetProperty(animation, property);
        return animation;
    }

    private void ApplyFilter(bool keepSelection = false)
    {
        var keepId = keepSelection ? (Results.SelectedItem as CommandItem)?.Id : null;
        var query = QueryBox.Text?.Trim() ?? "";

        IEnumerable<CommandItem> ordered;
        if (query.Length == 0)
        {
            ordered = _all
                .OrderBy(RecentRank)
                .ThenBy(GroupRank)
                .ThenBy(c => c.Title, StringComparer.CurrentCultureIgnoreCase);
        }
        else
        {
            ordered = _all
                .Select(c => (Item: c, Score: Score(c, query)))
                .Where(x => x.Score > 0)
                .OrderByDescending(x => x.Score)
                .ThenBy(x => RecentRank(x.Item))
                .ThenBy(x => GroupRank(x.Item))
                .Select(x => x.Item);
        }

        _filtered.Clear();
        _filtered.AddRange(ordered.Take(query.Length == 0 ? 80 : 40));
        Results.ItemsSource = null;
        Results.ItemsSource = _filtered;

        EmptyText.Visibility = _filtered.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
        CountText.Text = query.Length == 0
            ? $"{_filtered.Count} 项"
            : $"{_filtered.Count} 个结果";

        var targetIndex = keepId is null ? -1 : _filtered.FindIndex(c => c.Id == keepId);
        Results.SelectedIndex = _filtered.Count == 0 ? -1 : Math.Max(0, targetIndex);
        if (_filtered.Count > 0) Results.ScrollIntoView(_filtered[Results.SelectedIndex]);
    }

    private int RecentRank(CommandItem item)
    {
        var index = _recents.IndexOf(item.Id);
        return index < 0 ? 100 : index;
    }

    private static int GroupRank(CommandItem item) => item.Group switch
    {
        "页面" => 0,
        "操作" => 1,
        "材质" => 2,
        "优化项" => 3,
        "游戏" => 4,
        _ => 5
    };

    private int Score(CommandItem item, string query)
    {
        var q = query.ToLowerInvariant();
        var title = item.Title.ToLowerInvariant();
        var detail = item.Detail.ToLowerInvariant();
        var keywords = item.Keywords.ToLowerInvariant();

        int score;
        if (title.Equals(q)) score = 240;
        else if (title.StartsWith(q, StringComparison.Ordinal)) score = 190;
        else if (title.Contains(q, StringComparison.Ordinal)) score = 150;
        else if (keywords.Contains(q, StringComparison.Ordinal)) score = 100;
        else if (detail.Contains(q, StringComparison.Ordinal)) score = 60;
        else return -1;

        var recent = _recents.IndexOf(item.Id);
        if (recent >= 0) score += Math.Max(4, 24 - recent * 3);
        return score;
    }

    private void QueryBox_TextChanged(object sender, TextChangedEventArgs e) => ApplyFilter();

    /// <summary>
    /// 面板内所有按键都在这一层处理：搜索框是 TextBox，Enter / 方向键会被它自己的
    /// 输入逻辑或输入法先行处理，挂在 TextBox 上的 KeyDown 收不到，必须监听已处理事件。
    /// </summary>
    private void Layer_PreviewKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (!IsOpen) return;

        switch (e.Key)
        {
            case VirtualKey.Escape:
                e.Handled = true;
                Close();
                break;
            case VirtualKey.Down:
                e.Handled = true;
                MoveSelection(1);
                break;
            case VirtualKey.Up:
                e.Handled = true;
                MoveSelection(-1);
                break;
            case VirtualKey.PageDown:
                e.Handled = true;
                MoveSelection(6);
                break;
            case VirtualKey.PageUp:
                e.Handled = true;
                MoveSelection(-6);
                break;
            case VirtualKey.Enter:
                e.Handled = true;
                InvokeSelected();
                break;
        }
    }

    private void MoveSelection(int delta)
    {
        if (_filtered.Count == 0) return;
        var index = Results.SelectedIndex < 0 ? 0 : Results.SelectedIndex + delta;
        index = Math.Clamp(index, 0, _filtered.Count - 1);
        Results.SelectedIndex = index;
        Results.ScrollIntoView(_filtered[index]);
    }

    private void InvokeSelected()
    {
        if ((Results.SelectedItem as CommandItem ?? _filtered.FirstOrDefault()) is not { } item) return;
        _previousFocus = null;
        Close();
        CommandInvoked?.Invoke(item);
    }

    private void Results_ItemClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not CommandItem item) return;
        _previousFocus = null;
        Close();
        CommandInvoked?.Invoke(item);
    }


    private void Layer_Tapped(object sender, TappedRoutedEventArgs e) => Close();

    private void Card_Tapped(object sender, TappedRoutedEventArgs e) => e.Handled = true;
}
