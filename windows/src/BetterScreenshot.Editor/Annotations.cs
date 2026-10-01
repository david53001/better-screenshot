using BetterScreenshot.Core;

namespace BetterScreenshot.Editor;

/// <summary>
/// An annotation object living in base-image pixel space (top-left origin). Concrete types hold their own
/// geometry; the WPF <c>DocumentRenderer</c> switches on the concrete type to draw. Kept UI-free so the model
/// is headless-testable.
/// </summary>
public interface IAnnotation
{
    Guid Id { get; }
    AnnotationStyle Style { get; }
    PxRect BoundingBox();
    IAnnotation MovedBy(double dx, double dy);
    IAnnotation WithStyle(AnnotationStyle style);
}

/// <summary>A box-shaped object the 8 square handles can resize (rectangles, ellipses, redactions, spotlights).</summary>
public interface IFramedAnnotation : IAnnotation
{
    PxRect Frame { get; }
    IAnnotation WithFrame(PxRect frame);
}

public static class AnnotationExtensions
{
    public const double HitSlop = 6;

    /// <summary>Lenient hit-test: the bounding box inflated by <paramref name="slop"/> on every side.</summary>
    public static bool HitTest(this IAnnotation a, PxPoint p, double slop = HitSlop)
    {
        var b = a.BoundingBox();
        var inflated = new PxRect(b.X - slop, b.Y - slop, b.Width + 2 * slop, b.Height + 2 * slop);
        return inflated.Contains(p);
    }

    internal static PxRect BoundsOfSegment(PxPoint a, PxPoint b) =>
        PxRect.FromLtrb(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Max(a.X, b.X), Math.Max(a.Y, b.Y));

    internal static PxRect Inflate(PxRect r, double dx, double dy) => new(r.X - dx, r.Y - dy, r.Width + 2 * dx, r.Height + 2 * dy);
}

public sealed record ArrowAnnotation(Guid Id, AnnotationStyle Style, PxPoint Start, PxPoint End) : IAnnotation
{
    public PxRect BoundingBox() => AnnotationExtensions.BoundsOfSegment(Start, End);
    public IAnnotation MovedBy(double dx, double dy) => this with { Start = Start.Offset(dx, dy), End = End.Offset(dx, dy) };
    public IAnnotation WithStyle(AnnotationStyle style) => this with { Style = style };
}

public sealed record LineAnnotation(Guid Id, AnnotationStyle Style, PxPoint Start, PxPoint End) : IAnnotation
{
    public PxRect BoundingBox() => AnnotationExtensions.BoundsOfSegment(Start, End);
    public IAnnotation MovedBy(double dx, double dy) => this with { Start = Start.Offset(dx, dy), End = End.Offset(dx, dy) };
    public IAnnotation WithStyle(AnnotationStyle style) => this with { Style = style };
}

public sealed record RectangleAnnotation(Guid Id, AnnotationStyle Style, PxRect Frame, bool Filled) : IFramedAnnotation
{
    public PxRect BoundingBox() => Frame;
    public IAnnotation MovedBy(double dx, double dy) => this with { Frame = Frame.Offset(dx, dy) };
    public IAnnotation WithStyle(AnnotationStyle style) => this with { Style = style };
    public IAnnotation WithFrame(PxRect frame) => this with { Frame = frame };
}

public sealed record FilledRectangleAnnotation(Guid Id, AnnotationStyle Style, PxRect Frame) : IFramedAnnotation
{
    public PxRect BoundingBox() => Frame;
    public IAnnotation MovedBy(double dx, double dy) => this with { Frame = Frame.Offset(dx, dy) };
    public IAnnotation WithStyle(AnnotationStyle style) => this with { Style = style };
    public IAnnotation WithFrame(PxRect frame) => this with { Frame = frame };
}

public sealed record EllipseAnnotation(Guid Id, AnnotationStyle Style, PxRect Frame) : IFramedAnnotation
{
    public PxRect BoundingBox() => Frame;
    public IAnnotation MovedBy(double dx, double dy) => this with { Frame = Frame.Offset(dx, dy) };
    public IAnnotation WithStyle(AnnotationStyle style) => this with { Style = style };
    public IAnnotation WithFrame(PxRect frame) => this with { Frame = frame };
}

/// <summary>
/// Measures laid-out text (natural width/height in image px for a given wrap width). The App installs the real
/// WPF measurer at startup; the default is a headless approximation so the pure model stays testable.
/// </summary>
public static class TextMetrics
{
    public static Func<string, AnnotationStyle, double?, PxSize> Measure { get; set; } = Approximate;

    public static PxSize Approximate(string text, AnnotationStyle style, double? wrapWidth)
    {
        double charW = style.FontSize * 0.55, lineH = style.FontSize * 1.33;
        double width = 0; int lines = 0;
        foreach (var raw in (text.Length == 0 ? " " : text).Split('\n'))
        {
            double w = Math.Max(1, raw.Length) * charW;
            if (wrapWidth is { } ww && ww > 0 && w > ww) { lines += (int)Math.Ceiling(w / ww); w = ww; }
            else lines++;
            width = Math.Max(width, w);
        }
        return new PxSize(width, lines * lineH);
    }
}

/// <summary>
/// A text label (WrapWidth null — only explicit newlines break lines, the box hugs the text) or a text box
/// (WrapWidth set — lines wrap at it, alignment is relative to it, the box width equals it). v3 A.1 / Part 2.
/// </summary>
public sealed record TextAnnotation(Guid Id, AnnotationStyle Style, string Text, PxPoint Origin, double? WrapWidth = null) : IAnnotation
{
    /// <summary>The text's own layout rect (no background box): width = WrapWidth ?? ceil(natural), height ceil.</summary>
    public PxRect LayoutRect()
    {
        var m = TextMetrics.Measure(Text, Style, WrapWidth);
        double w = WrapWidth ?? Math.Ceiling(m.Width);
        return new PxRect(Origin.X, Origin.Y, Math.Max(1, w), Math.Max(1, Math.Ceiling(m.Height)));
    }

    /// <summary>Layout rect, grown by the background box's insets when it has one (Solid / Auto).</summary>
    public PxRect BoundingBox()
    {
        var r = LayoutRect();
        if (Style.TextBackgroundMode == TextBackgroundMode.None) return r;
        var inset = TextChip.Insets(Style.TextBackgroundPadding);
        return AnnotationExtensions.Inflate(r, inset.Width, inset.Height);
    }

    public IAnnotation MovedBy(double dx, double dy) => this with { Origin = Origin.Offset(dx, dy) };
    public IAnnotation WithStyle(AnnotationStyle style) => this with { Style = style };

    /// <summary>This text scaled by dragging <paramref name="corner"/> of its box by (<paramref name="dx"/>,
    /// <paramref name="dy"/>) image px — always from the text as it was at mouse-down (see <see cref="TextScale"/>).</summary>
    public TextAnnotation Scaled(TextScale.Corner corner, double dx, double dy)
    {
        var box = BoundingBox();
        var (style, wrap) = TextScale.Scaled(Style, WrapWidth, TextScale.Factor(box, corner, dx, dy));
        var c = this with { Style = style, WrapWidth = wrap };
        var now = c.BoundingBox();
        var target = TextScale.Placed(now.Size, TextScale.Anchor(corner, box), corner);
        return c with { Origin = new PxPoint(c.Origin.X + target.X - now.X, c.Origin.Y + target.Y - now.Y) };
    }

    /// <summary>Side-handle drag: the box spans [<paramref name="boxLeft"/>, <paramref name="boxRight"/>] (incl.
    /// padding); the wrap width is that minus 2 × padding, at least the font size.</summary>
    public TextAnnotation WithBoxSpan(double boxLeft, double boxRight)
    {
        double pad = Style.TextBackgroundMode == TextBackgroundMode.None ? 0 : TextChip.Insets(Style.TextBackgroundPadding).Width;
        double width = Math.Max(Style.FontSize, Math.Abs(boxRight - boxLeft) - 2 * pad);
        return this with { WrapWidth = width, Origin = new PxPoint(Math.Min(boxLeft, boxRight) + pad, Origin.Y) };
    }
}

public sealed record CounterAnnotation(Guid Id, AnnotationStyle Style, int Number, PxPoint Origin) : IAnnotation
{
    public double Diameter => Math.Max(28, Style.FontSize * 1.6);
    public PxRect BoundingBox() => new(Origin.X, Origin.Y, Diameter, Diameter);
    public IAnnotation MovedBy(double dx, double dy) => this with { Origin = Origin.Offset(dx, dy) };
    public IAnnotation WithStyle(AnnotationStyle style) => this with { Style = style };

    /// <summary>Creates a counter badge centered on <paramref name="point"/>.</summary>
    public static CounterAnnotation Centered(PxPoint point, int number, AnnotationStyle style)
    {
        double d = Math.Max(28, style.FontSize * 1.6);
        return new CounterAnnotation(Guid.NewGuid(), style, number, new PxPoint(point.X - d / 2, point.Y - d / 2));
    }
}

/// <summary>
/// Blur / Pixelate / Black-out box (v3 Part 3). Mode and strength live in the style; the patch is rendered from
/// the base image for the CURRENT frame every time (so a moved or resized redaction redacts its new region).
/// Always opaque.
/// </summary>
public sealed record RedactionAnnotation : IFramedAnnotation
{
    public Guid Id { get; init; }
    public PxRect Frame { get; init; }
    private readonly AnnotationStyle _style = AnnotationStyle.Default;
    public AnnotationStyle Style { get => _style; init => _style = value with { Opacity = 1 }; }

    public RedactionAnnotation(Guid id, AnnotationStyle style, PxRect frame) { Id = id; Style = style; Frame = frame; }

    public PxRect BoundingBox() => Frame;
    public IAnnotation MovedBy(double dx, double dy) => this with { Frame = Frame.Offset(dx, dy) };
    public IAnnotation WithStyle(AnnotationStyle style) => this with { Style = style };
    public IAnnotation WithFrame(PxRect frame) => this with { Frame = frame };

    /// <summary>The frame snapped OUTWARD to whole pixels and clipped to the image.</summary>
    public PxRect PatchRect(double imageWidth, double imageHeight)
    {
        double x0 = Math.Max(0, Math.Floor(Frame.X)), y0 = Math.Max(0, Math.Floor(Frame.Y));
        double x1 = Math.Min(imageWidth, Math.Ceiling(Frame.Right)), y1 = Math.Min(imageHeight, Math.Ceiling(Frame.Bottom));
        return x1 > x0 && y1 > y0 ? PxRect.FromLtrb(x0, y0, x1, y1) : default;
    }
}

/// <summary>Freehand marker stroke (v3 Part 3): one path, multiplied onto what's below at the pen's opacity.</summary>
public sealed record HighlighterAnnotation(Guid Id, AnnotationStyle Style, IReadOnlyList<PxPoint> Points) : IAnnotation
{
    public PxRect BoundingBox()
    {
        if (Points.Count == 0) return default;
        double l = Points.Min(p => p.X), t = Points.Min(p => p.Y), r = Points.Max(p => p.X), b = Points.Max(p => p.Y);
        double h = Style.LineWidth / 2;
        return PxRect.FromLtrb(l - h, t - h, r + h, b + h);
    }

    public IAnnotation MovedBy(double dx, double dy) => this with { Points = Points.Select(p => p.Offset(dx, dy)).ToList() };
    public IAnnotation WithStyle(AnnotationStyle style) => this with { Style = style };
}

/// <summary>A hole in the document-wide dim layer (v3 Part 3). Its shape and the dim amount live in the style.</summary>
public sealed record SpotlightAnnotation(Guid Id, AnnotationStyle Style, PxRect Frame) : IFramedAnnotation
{
    public PxRect BoundingBox() => Frame;
    public IAnnotation MovedBy(double dx, double dy) => this with { Frame = Frame.Offset(dx, dy) };
    public IAnnotation WithStyle(AnnotationStyle style) => this with { Style = style };
    public IAnnotation WithFrame(PxRect frame) => this with { Frame = frame };
}
