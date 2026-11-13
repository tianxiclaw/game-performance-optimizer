using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace GamePerfCenter.Controls;

/// <summary>
/// 统一页头：左侧强调条 + 标题 / 说明，右侧模块代号与操作区。
/// 窗口变窄时操作区移到标题下方；窗口变矮时收成单行页头（隐藏说明与模块代号），
/// 把高度让给内容区，避免小窗口里“页头吃掉整屏”。
/// </summary>
public sealed class PageHeader : ContentControl
{
    private Grid? _root;
    private Border? _bar;
    private TextBlock? _title;
    private TextBlock? _subtitle;
    private StackPanel? _right;
    private TextBlock? _code;
    private Border? _codeLine;
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

    /// <summary>右上角等宽模块代号，例如 “GAMEPERF // OVERVIEW”。</summary>
    public string Code
    {
        get => (string)GetValue(CodeProperty);
        set => SetValue(CodeProperty, value);
    }

    protected override void OnApplyTemplate()
    {
        base.OnApplyTemplate();
        _root = GetTemplateChild("HeaderRoot") as Grid;
        _bar = GetTemplateChild("AccentBar") as Border;
        _title = GetTemplateChild("TitleText") as TextBlock;
        _subtitle = GetTemplateChild("SubtitleText") as TextBlock;
        _right = GetTemplateChild("RightBlock") as StackPanel;
        _code = GetTemplateChild("CodeBlock") as TextBlock;
        _codeLine = GetTemplateChild("CodeLine") as Border;

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
    /// 三种形态：常规（说明 + 代号 + 操作在右）、堆叠（操作下移）、紧凑（单行，
    /// 隐藏说明与代号）。阈值按窗口尺寸判断：1280×800 以下开始堆叠，600 高以下转紧凑。
    /// </summary>
    private void Update()
    {
        if (_root is null || _title is null || _subtitle is null || _right is null ||
            _code is null || _codeLine is null || _bar is null)
        {
            return;
        }

        var size = XamlRoot?.Size;
        var width = size?.Width ?? 1280;
        var height = size?.Height ?? 800;

        var compact = height < 600;
        var stacked = !compact && width < 1020;

        if (_compact == compact && _stacked == stacked) return;
        _compact = compact;
        _stacked = stacked;

        if (compact)
        {
            _title.FontSize = 22;
            _title.CharacterSpacing = -10;
            _bar.Height = 22;
            _bar.Margin = new Thickness(0, 4, 0, 0);
            _subtitle.Visibility = Visibility.Collapsed;
            _code.Visibility = Visibility.Collapsed;
            _codeLine.Visibility = Visibility.Collapsed;
            _root.ColumnSpacing = 12;

            Grid.SetRow(_right, 0);
            Grid.SetColumn(_right, 1);
            Grid.SetColumnSpan(_right, 1);
            _right.HorizontalAlignment = HorizontalAlignment.Right;
            _right.VerticalAlignment = VerticalAlignment.Center;
            _right.Margin = new Thickness(0);
            _right.MinWidth = 0;
            return;
        }

        _title.FontSize = 30;
        _title.CharacterSpacing = -20;
        _bar.Height = 32;
        _bar.Margin = new Thickness(0, 6, 0, 0);
        _subtitle.Visibility = Visibility.Visible;

        if (stacked)
        {
            _code.Visibility = Visibility.Collapsed;
            _codeLine.Visibility = Visibility.Collapsed;
            _root.ColumnSpacing = 18;

            Grid.SetRow(_right, 1);
            Grid.SetColumn(_right, 0);
            Grid.SetColumnSpan(_right, 2);
            _right.HorizontalAlignment = HorizontalAlignment.Left;
            _right.VerticalAlignment = VerticalAlignment.Top;
            _right.Margin = new Thickness(0, 12, 0, 0);
            _right.MinWidth = 0;
            return;
        }

        _code.Visibility = Visibility.Visible;
        _codeLine.Visibility = Visibility.Visible;
        _root.ColumnSpacing = 18;

        Grid.SetRow(_right, 0);
        Grid.SetColumn(_right, 1);
        Grid.SetColumnSpan(_right, 1);
        _right.HorizontalAlignment = HorizontalAlignment.Right;
        _right.VerticalAlignment = VerticalAlignment.Top;
        _right.Margin = new Thickness(0);
        _right.MinWidth = 180;
    }
}
