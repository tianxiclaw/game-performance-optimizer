using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Path = Microsoft.UI.Xaml.Shapes.Path;

namespace GamePerfCenter.Controls;

/// <summary>
/// 战术控制台风格的面板：右上角与左下角可切角，1px 描边，可选顶部强调线与左上角括号。
/// 所有几何在尺寸变化时重建，因此可以随窗口缩放而不失真。
/// </summary>
[ContentProperty(Name = nameof(Content))]
public sealed class TechPanel : Grid
{
    // 装饰层放在 Canvas 里：Canvas 不参与测量，避免几何尺寸反过来影响面板尺寸造成布局循环。
    private readonly Canvas _decor = new() { IsHitTestVisible = false };
    private readonly Path _face = new() { IsHitTestVisible = false, Stretch = Stretch.None };
    private readonly Rectangle _topLine = new()
    {
        Height = 1,
        IsHitTestVisible = false
    };
    private readonly Rectangle _bracketH = new()
    {
        Height = 1,
        IsHitTestVisible = false
    };
    private readonly Rectangle _bracketV = new()
    {
        Width = 1,
        IsHitTestVisible = false
    };
    private readonly ContentPresenter _host = new()
    {
        HorizontalContentAlignment = HorizontalAlignment.Stretch,
        VerticalContentAlignment = VerticalAlignment.Stretch
    };

    public TechPanel()
    {
        Children.Add(_decor);
        Children.Add(_host);
        _decor.Children.Add(_face);
        _decor.Children.Add(_topLine);
        _decor.Children.Add(_bracketH);
        _decor.Children.Add(_bracketV);

        SizeChanged += (_, _) => UpdateGeometry();
        Loaded += (_, _) => UpdateGeometry();
        RegisterPropertyChangedCallback(PaddingProperty, (_, _) => _host.Margin = Padding);
    }

    public static readonly DependencyProperty ContentProperty = DependencyProperty.Register(
        nameof(Content), typeof(object), typeof(TechPanel),
        new PropertyMetadata(null, (d, e) => ((TechPanel)d)._host.Content = e.NewValue));

    public object? Content
    {
        get => GetValue(ContentProperty);
        set => SetValue(ContentProperty, value);
    }

    public static readonly DependencyProperty FillProperty = DependencyProperty.Register(
        nameof(Fill), typeof(Brush), typeof(TechPanel),
        new PropertyMetadata(null, (d, _) => ((TechPanel)d).UpdateGeometry()));

    public Brush? Fill
    {
        get => (Brush?)GetValue(FillProperty);
        set => SetValue(FillProperty, value);
    }

    public static readonly DependencyProperty StrokeProperty = DependencyProperty.Register(
        nameof(Stroke), typeof(Brush), typeof(TechPanel),
        new PropertyMetadata(null, (d, _) => ((TechPanel)d).UpdateGeometry()));

    public Brush? Stroke
    {
        get => (Brush?)GetValue(StrokeProperty);
        set => SetValue(StrokeProperty, value);
    }

    public static readonly DependencyProperty StrokeThicknessProperty = DependencyProperty.Register(
        nameof(StrokeThickness), typeof(double), typeof(TechPanel),
        new PropertyMetadata(1d, (d, _) => ((TechPanel)d).UpdateGeometry()));

    public double StrokeThickness
    {
        get => (double)GetValue(StrokeThicknessProperty);
        set => SetValue(StrokeThicknessProperty, value);
    }

    public static readonly DependencyProperty CutProperty = DependencyProperty.Register(
        nameof(Cut), typeof(double), typeof(TechPanel),
        new PropertyMetadata(12d, (d, _) => ((TechPanel)d).UpdateGeometry()));

    /// <summary>右上角切角尺寸。</summary>
    public double Cut
    {
        get => (double)GetValue(CutProperty);
        set => SetValue(CutProperty, value);
    }

    public static readonly DependencyProperty CutBottomProperty = DependencyProperty.Register(
        nameof(CutBottom), typeof(double), typeof(TechPanel),
        new PropertyMetadata(0d, (d, _) => ((TechPanel)d).UpdateGeometry()));

    /// <summary>左下角切角尺寸。</summary>
    public double CutBottom
    {
        get => (double)GetValue(CutBottomProperty);
        set => SetValue(CutBottomProperty, value);
    }

    public static readonly DependencyProperty TopLineBrushProperty = DependencyProperty.Register(
        nameof(TopLineBrush), typeof(Brush), typeof(TechPanel),
        new PropertyMetadata(null, (d, _) => ((TechPanel)d).UpdateGeometry()));

    /// <summary>顶部 1px 强调线；为空时不显示。</summary>
    public Brush? TopLineBrush
    {
        get => (Brush?)GetValue(TopLineBrushProperty);
        set => SetValue(TopLineBrushProperty, value);
    }

    public static readonly DependencyProperty TopLineOpacityProperty = DependencyProperty.Register(
        nameof(TopLineOpacity), typeof(double), typeof(TechPanel),
        new PropertyMetadata(1d, (d, _) => ((TechPanel)d).UpdateGeometry()));

    public double TopLineOpacity
    {
        get => (double)GetValue(TopLineOpacityProperty);
        set => SetValue(TopLineOpacityProperty, value);
    }

    public static readonly DependencyProperty BracketsProperty = DependencyProperty.Register(
        nameof(Brackets), typeof(bool), typeof(TechPanel),
        new PropertyMetadata(false, (d, _) => ((TechPanel)d).UpdateGeometry()));

    /// <summary>左上角短括号，用于强调当前面板。</summary>
    public bool Brackets
    {
        get => (bool)GetValue(BracketsProperty);
        set => SetValue(BracketsProperty, value);
    }

    public static readonly DependencyProperty BracketBrushProperty = DependencyProperty.Register(
        nameof(BracketBrush), typeof(Brush), typeof(TechPanel),
        new PropertyMetadata(null, (d, _) => ((TechPanel)d).UpdateGeometry()));

    public Brush? BracketBrush
    {
        get => (Brush?)GetValue(BracketBrushProperty);
        set => SetValue(BracketBrushProperty, value);
    }

    private void UpdateGeometry()
    {
        var width = ActualWidth;
        var height = ActualHeight;
        if (width < 1 || height < 1)
        {
            return;
        }

        var thickness = Math.Max(0, StrokeThickness);
        var inset = thickness / 2;
        var left = inset;
        var top = inset;
        var right = Math.Max(left, width - inset);
        var bottom = Math.Max(top, height - inset);
        var maxCut = Math.Min(right - left, bottom - top) * 0.5;
        var cut = Math.Clamp(Cut, 0, maxCut);
        var cutBottom = Math.Clamp(CutBottom, 0, maxCut);

        var figure = new PathFigure
        {
            StartPoint = new Point(left, top),
            IsClosed = true,
            IsFilled = true
        };
        figure.Segments.Add(new LineSegment { Point = new Point(right - cut, top) });
        figure.Segments.Add(new LineSegment { Point = new Point(right, top + cut) });
        figure.Segments.Add(new LineSegment { Point = new Point(right, bottom) });
        figure.Segments.Add(new LineSegment { Point = new Point(left + cutBottom, bottom) });
        figure.Segments.Add(new LineSegment { Point = new Point(left, bottom - cutBottom) });

        var geometry = new PathGeometry();
        geometry.Figures.Add(figure);

        _face.Width = width;
        _face.Height = height;
        _face.Data = geometry;
        _face.Fill = Fill;
        _face.Stroke = Stroke;
        _face.StrokeThickness = thickness;
        _face.StrokeLineJoin = PenLineJoin.Miter;

        Canvas.SetLeft(_topLine, left);
        Canvas.SetTop(_topLine, top);
        _topLine.Width = Math.Max(0, right - left - cut);
        _topLine.Fill = TopLineBrush;
        _topLine.Opacity = Math.Clamp(TopLineOpacity, 0, 1);
        _topLine.Visibility = TopLineBrush is null ? Visibility.Collapsed : Visibility.Visible;

        var bracketBrush = BracketBrush ?? TopLineBrush ?? Stroke;
        var bracketLength = 16d;
        Canvas.SetLeft(_bracketH, left + 1);
        Canvas.SetTop(_bracketH, top + 1);
        _bracketH.Width = bracketLength;
        _bracketH.Fill = bracketBrush;
        _bracketH.Visibility = Brackets ? Visibility.Visible : Visibility.Collapsed;

        Canvas.SetLeft(_bracketV, left + 1);
        Canvas.SetTop(_bracketV, top + 1);
        _bracketV.Height = bracketLength;
        _bracketV.Fill = bracketBrush;
        _bracketV.Visibility = Brackets ? Visibility.Visible : Visibility.Collapsed;

        _host.Margin = Padding;
    }
}
