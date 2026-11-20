using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Controls;

/// <summary>
/// 统一页头：左侧标题与一句说明，右侧当前页操作。
/// 窗口变窄时操作区移到标题下方；窗口变矮时收起说明，把高度让给内容区。
/// </summary>
public sealed class PageHeader : ContentControl
{
    private Grid? _root;
    private TextBlock? _title;
    private TextBlock? _subtitle;
    private ContentPresenter? _actions;
    private XamlRoot? _xamlRoot;
    private bool? _compact;
    private bool? _stacked;

    public PageHeader()
    {
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
    }

    public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(
        nameof(Title), typeof(string), typeof(PageHeader), new PropertyMetadata(""));

    public string Title
    {
        get => (string)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    public static readonly DependencyProperty SubtitleProperty = DependencyProperty.Register(
        nameof(Subtitle), typeof(string), typeof(PageHeader), new PropertyMetadata(""));

    public string Subtitle
    {
        get => (string)GetValue(SubtitleProperty);
        set => SetValue(SubtitleProperty, value);
    }

    public static readonly DependencyProperty CodeProperty = DependencyProperty.Register(
        nameof(Code), typeof(string), typeof(PageHeader), new PropertyMetadata(""));

    /// <summary>保留旧属性以兼容既有 XAML；页头不再展示模块代号。</summary>
    public string Code
    {
        get => (string)GetValue(CodeProperty);
        set => SetValue(CodeProperty, value);
    }

    protected override void OnApplyTemplate()
    {
        base.OnApplyTemplate();
        _root = GetTemplateChild("HeaderRoot") as Grid;
        _title = GetTemplateChild("TitleText") as TextBlock;
        _subtitle = GetTemplateChild("SubtitleText") as TextBlock;
        _actions = GetTemplateChild("ActionsHost") as ContentPresenter;

        _compact = null;
        _stacked = null;
        Update();
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (!ReferenceEquals(_xamlRoot, XamlRoot))
        {
            if (_xamlRoot is not null) _xamlRoot.Changed -= OnXamlRootChanged;
            _xamlRoot = XamlRoot;
            if (_xamlRoot is not null) _xamlRoot.Changed += OnXamlRootChanged;
        }
        Update();
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        if (_xamlRoot is not null)
        {
            _xamlRoot.Changed -= OnXamlRootChanged;
            _xamlRoot = null;
        }
    }

    private void OnXamlRootChanged(XamlRoot sender, XamlRootChangedEventArgs args) => Update();

    /// <summary>
    /// 常规：标题与操作同一行。堆叠（宽度 &lt; 900）：操作下移。紧凑（高度 &lt; 560）：隐藏说明。
    /// </summary>
    private void Update()
    {
        if (_root is null || _title is null || _subtitle is null || _actions is null)
        {
            return;
        }

        var size = XamlRoot?.Size;
        var width = size?.Width ?? 1280;
        var height = size?.Height ?? 800;

        var compact = height < 560;
        var stacked = !compact && width < 900;

        if (_compact == compact && _stacked == stacked) return;
        _compact = compact;
        _stacked = stacked;

        if (compact)
        {
            _title.FontSize = 21;
            _title.CharacterSpacing = -6;
            _subtitle.Visibility = Visibility.Collapsed;
            _root.ColumnSpacing = 12;

            Grid.SetRow(_actions, 0);
            Grid.SetColumn(_actions, 1);
            Grid.SetColumnSpan(_actions, 1);
            _actions.HorizontalAlignment = HorizontalAlignment.Right;
            _actions.VerticalAlignment = VerticalAlignment.Center;
            _actions.Margin = new Thickness(0);
            return;
        }

        _title.FontSize = 26;
        _title.CharacterSpacing = -10;
        _subtitle.Visibility = Visibility.Visible;
        // 说明最多两行：宁可让页头长 20px，也不要把后半句截成省略号。
        _subtitle.MaxLines = 2;

        if (stacked)
        {
            _root.ColumnSpacing = 16;

            Grid.SetRow(_actions, 1);
            Grid.SetColumn(_actions, 0);
            Grid.SetColumnSpan(_actions, 2);
            _actions.HorizontalAlignment = HorizontalAlignment.Left;
            _actions.VerticalAlignment = VerticalAlignment.Top;
            _actions.Margin = new Thickness(0, 10, 0, 0);
            return;
        }

        _root.ColumnSpacing = 20;

        Grid.SetRow(_actions, 0);
        Grid.SetColumn(_actions, 1);
        Grid.SetColumnSpan(_actions, 1);
        _actions.HorizontalAlignment = HorizontalAlignment.Right;
        _actions.VerticalAlignment = VerticalAlignment.Center;
        _actions.Margin = new Thickness(0);
    }
}