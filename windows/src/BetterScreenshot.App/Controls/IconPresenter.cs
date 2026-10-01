using System.Windows;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Pen = System.Windows.Media.Pen;

namespace BetterScreenshot.App.Controls;

/// <summary>
/// Renders a hand-authored glyph from <c>Resources/Icons.xaml</c> by key (e.g. "camera", "gear"). Outline glyphs are
/// stroked; the keys in <see cref="Filled"/> are filled (their geometries use even-odd knockouts). The 24×24 source
/// geometry is scaled to fit the element, so icons are crisp at any DPI/size. Set <see cref="IconKey"/>,
/// <see cref="Brush"/>, and Width/Height.
/// </summary>
public sealed class IconPresenter : FrameworkElement
{
    /// <summary>Icon keys whose geometry is meant to be filled (rest are stroked).</summary>
    public static readonly IReadOnlySet<string> Filled = new HashSet<string>
    {
        "stop-circle", "record-circle", "check-circle", "close-circle",
        "play", "counter", "rect-fill", "blur", "pixelate", "bring-front", "send-back", "blackout",
        "video-fill", "pause", "stop",
    };

    public static readonly DependencyProperty IconKeyProperty = DependencyProperty.Register(
        nameof(IconKey), typeof(string), typeof(IconPresenter),
        new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.AffectsRender));

    public static readonly DependencyProperty BrushProperty = DependencyProperty.Register(
        nameof(Brush), typeof(Brush), typeof(IconPresenter),
        new FrameworkPropertyMetadata(Brushes.Black, FrameworkPropertyMetadataOptions.AffectsRender));

    public string? IconKey
    {
        get => (string?)GetValue(IconKeyProperty);
        set => SetValue(IconKeyProperty, value);
    }

    public Brush Brush
    {
        get => (Brush)GetValue(BrushProperty);
        set => SetValue(BrushProperty, value);
    }

    protected override void OnRender(DrawingContext dc)
    {
        if (IconKey is not { } key || Lookup(key) is not { } geometry) return;

        double side = Math.Min(ActualWidth, ActualHeight);
        if (side <= 0) return;
        double scale = side / 24.0;

        dc.PushTransform(new TranslateTransform((ActualWidth - side) / 2, (ActualHeight - side) / 2));
        dc.PushTransform(new ScaleTransform(scale, scale));

        if (Filled.Contains(key))
        {
            dc.DrawGeometry(Brush, null, geometry);
        }
        else
        {
            var pen = new Pen(Brush, 1.8)
            {
                LineJoin = PenLineJoin.Round,
                StartLineCap = PenLineCap.Round,
                EndLineCap = PenLineCap.Round,
            };
            dc.DrawGeometry(null, pen, geometry);
        }

        dc.Pop();
        dc.Pop();
    }

    private static Geometry? Lookup(string key) =>
        System.Windows.Application.Current?.TryFindResource($"icon-{key}") as Geometry;
}
