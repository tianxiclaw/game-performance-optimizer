using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Microsoft.UI;
using GamePerfCenter.Helpers;

namespace GamePerfCenter.Controls;

/// <summary>
/// 左侧导航项：切角选中底、3px 强调条、图标与等宽序号。
/// 不使用 NavigationView，才能完全控制选中态与紧凑态。
/// </summary>
public sealed class NavItem : Button
{
    private static readonly Brush Clear = new SolidColorBrush(Colors.Transparent);
    private bool _hover;

    private TechPanel? _face;
    private Border? _bar;
    private FontIcon? _icon;
    private TextBlock? _labelText;
    private TextBlock? _codeText;
    private Grid? _inner;
    private ColumnDefinition? _iconColumn;
    private ColumnDefinition? _labelColumn;
    private ColumnDefinition? _codeColumn;

    public static readonly DependencyProperty LabelProperty = DependencyProperty.Register(
        nameof(Label), typeof(string), typeof(NavItem),
        new PropertyMetadata("", (d, e) =>
        {
            var item = (NavItem)d;
            AutomationProperties.SetName(item, (string)e.NewValue);
            item.UpdateVisuals();
        }));

    public string Label
    {
        get => (string)GetValue(LabelProperty);
        set => SetValue(LabelProperty, value);
    }

    public static readonly DependencyProperty GlyphProperty = DependencyProperty.Register(
        nameof(Glyph), typeof(string), typeof(NavItem), new PropertyMetadata(""));

    public string Glyph
    {
        get => (string)GetValue(GlyphProperty);
        set => SetValue(GlyphProperty, value);
    }

    public static readonly DependencyProperty CodeProperty = DependencyProperty.Register(
        nameof(Code), typeof(string), typeof(NavItem), new PropertyMetadata(""));

    public string Code
    {
        get => (string)GetValue(CodeProperty);
        set => SetValue(CodeProperty, value);
    }

    public static readonly DependencyProperty IsSelectedProperty = DependencyProperty.Register(
        nameof(IsSelected), typeof(bool), typeof(NavItem),
        new PropertyMetadata(false, (d, _) => ((NavItem)d).UpdateVisuals()));

    public bool IsSelected
    {
        get => (bool)GetValue(IsSelectedProperty);
        set => SetValue(IsSelectedProperty, value);
    }

    public static readonly DependencyProperty IsCompactProperty = DependencyProperty.Register(
        nameof(IsCompact), typeof(bool), typeof(NavItem),
        new PropertyMetadata(false, (d, _) => ((NavItem)d).UpdateCompact()));

    public bool IsCompact
    {
        get => (bool)GetValue(IsCompactProperty);
        set => SetValue(IsCompactProperty, value);
    }

    public NavItem()
    {
        Background = Clear;
        BorderThickness = new Thickness(0);
        Padding = new Thickness(0);
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        VerticalContentAlignment = VerticalAlignment.Stretch;
        UseSystemFocusVisuals = true;
        Loaded += (_, _) => RefreshVisuals();
    }

    protected override void OnApplyTemplate()
    {
        base.OnApplyTemplate();
        _face = GetTemplateChild("Face") as TechPanel;
        _bar = GetTemplateChild("Bar") as Border;
        _icon = GetTemplateChild("Icon") as FontIcon;
        _labelText = GetTemplateChild("LabelText") as TextBlock;
        _codeText = GetTemplateChild("CodeText") as TextBlock;
        _inner = GetTemplateChild("Inner") as Grid;
        _iconColumn = GetTemplateChild("IconColumn") as ColumnDefinition;
        _labelColumn = GetTemplateChild("LabelColumn") as ColumnDefinition;
        _codeColumn = GetTemplateChild("CodeColumn") as ColumnDefinition;
        UpdateCompact();
        UpdateVisuals();
    }

    protected override void OnPointerEntered(PointerRoutedEventArgs e)
    {
        base.OnPointerEntered(e);
        _hover = true;
        UpdateVisuals();
    }

    protected override void OnPointerExited(PointerRoutedEventArgs e)
    {
        base.OnPointerExited(e);
        _hover = false;
        if (_face is not null) _face.Opacity = 1;
        UpdateVisuals();
    }

    protected override void OnPointerPressed(PointerRoutedEventArgs e)
    {
        base.OnPointerPressed(e);
        if (_face is not null) _face.Opacity = 0.72;
    }

    protected override void OnPointerReleased(PointerRoutedEventArgs e)
    {
        base.OnPointerReleased(e);
        if (_face is not null) _face.Opacity = 1;
    }

    /// <summary>主题切换后由外壳统一刷新，避免每个导航项各自监听主题事件。</summary>
    public void RefreshVisuals() => UpdateVisuals();

    private void UpdateVisuals()
    {
        if (_face is null || _bar is null || _icon is null || _labelText is null || _codeText is null)
        {
            return;
        }

        var selected = IsSelected;
        var fillKey = selected ? "NavSelectedBrush" : _hover ? "NavHoverBrush" : null;
        _face.Fill = fillKey is null ? Clear : ThemeResources.Get(fillKey);
        _face.Stroke = selected ? ThemeResources.Get("NavSelectedStrokeBrush") : Clear;

        _bar.Visibility = selected ? Visibility.Visible : Visibility.Collapsed;
        _icon.Foreground = ThemeResources.Get(selected ? "AccentBrush" : _hover ? "TextBrush" : "NavIconBrush");
        _labelText.Foreground = ThemeResources.Get(selected ? "TextBrush" : _hover ? "TextBrush" : "NavTextBrush");
        _labelText.FontWeight = selected
            ? Microsoft.UI.Text.FontWeights.SemiBold
            : Microsoft.UI.Text.FontWeights.Normal;
        _codeText.Foreground = ThemeResources.Get(selected ? "AccentBrush" : "MutedTextBrush");
        _codeText.Opacity = selected ? 1 : 0.7;
    }

    private void UpdateCompact()
    {
        if (_iconColumn is null || _labelColumn is null || _codeColumn is null ||
            _labelText is null || _codeText is null || _inner is null || _icon is null)
        {
            return;
        }

        if (IsCompact)
        {
            _iconColumn.Width = new GridLength(1, GridUnitType.Star);
            _labelColumn.Width = new GridLength(0);
            _codeColumn.Width = new GridLength(0);
            _labelText.Visibility = Visibility.Collapsed;
            _codeText.Visibility = Visibility.Collapsed;
            _inner.Padding = new Thickness(0);
            _icon.HorizontalAlignment = HorizontalAlignment.Center;
            _icon.FontSize = 17;
        }
        else
        {
            _iconColumn.Width = new GridLength(20);
            _labelColumn.Width = new GridLength(1, GridUnitType.Star);
            _codeColumn.Width = GridLength.Auto;
            _labelText.Visibility = Visibility.Visible;
            _codeText.Visibility = Visibility.Visible;
            _inner.Padding = new Thickness(14, 0, 12, 0);
            _icon.HorizontalAlignment = HorizontalAlignment.Center;
            _icon.FontSize = 16;
        }
    }
}
