using System.Globalization;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using FlowDirection = System.Windows.FlowDirection;
using FontFamily = System.Windows.Media.FontFamily;
using Pen = System.Windows.Media.Pen;
using Point = System.Windows.Point;

namespace BetterScreenshot.App.Editor;

/// <summary>
/// Flattens an <see cref="EditorDocument"/> over its base image to a <see cref="BitmapSource"/> (top-left origin).
/// Draw order (v3 Parts 1–3): base → spotlight dim layer → every object in stacking order, each as ONE layer at its
/// opacity; the dim is re-applied over each redaction (redactions count as part of the picture); highlighters
/// multiply on the CPU; a text shadow renders the box + outline + letters as one shadowed group.
/// </summary>
public static class DocumentRenderer
{
    static DocumentRenderer() => TextRendering.Install();

    private static readonly FontFamily CounterFont = new("Segoe UI");

    /// <summary>Renders <paramref name="doc"/> over <paramref name="drawBase"/>. Redaction patches are always taken
    /// from <paramref name="patchSource"/> (default: the draw base) for each redaction's CURRENT frame.</summary>
    public static BitmapSource Render(EditorDocument doc, BitmapSource drawBase, IAnnotation? preview = null, BitmapSource? patchSource = null)
    {
        int w = Math.Max(1, (int)Math.Round(doc.Size.Width));
        int h = Math.Max(1, (int)Math.Round(doc.Size.Height));
        patchSource ??= drawBase;
        var items = preview is null ? doc.Annotations.ToList() : doc.Annotations.Append(preview).ToList();
        var spots = items.OfType<SpotlightAnnotation>().ToList();
        Geometry? dim = spots.Count > 0 ? DimGeometry(spots, w, h) : null;
        Brush? dimBrush = spots.Count > 0 ? Frozen(Color.FromArgb((byte)Math.Round(spots[^1].Style.SpotlightDim * 255), 0, 0, 0)) : null;

        var target = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
        var visual = new DrawingVisual();
        var dc = visual.RenderOpen();
        dc.DrawImage(drawBase, new Rect(0, 0, w, h));
        if (dim != null) dc.DrawGeometry(dimBrush, null, dim);

        void Flush()
        {
            dc.Close();
            target.Render(visual);
            visual = new DrawingVisual();
            dc = visual.RenderOpen();
        }

        foreach (var a in items)
        {
            switch (a)
            {
                case SpotlightAnnotation:
                    break; // a hole in the dim layer, drawn above
                case HighlighterAnnotation hl:
                    Flush();
                    target = MultiplyHighlighter(target, hl);
                    dc.Close();
                    visual = new DrawingVisual();
                    dc = visual.RenderOpen();
                    break;
                case TextAnnotation t when t.Style.TextShadow:
                {
                    Flush();
                    var shadowed = new DrawingVisual
                    {
                        Opacity = t.Style.Opacity,
                        Effect = ShadowEffect(t.Style.FontSize),
                    };
                    using (var sdc = shadowed.RenderOpen()) DrawText(sdc, t);
                    target.Render(shadowed);
                    break;
                }
                case RedactionAnnotation r:
                    DrawRedaction(dc, r, patchSource, w, h);
                    if (dim != null)
                    {
                        var pr = r.PatchRect(w, h);
                        dc.PushClip(new RectangleGeometry(RectOf(pr)));
                        dc.DrawGeometry(dimBrush, null, dim);
                        dc.Pop();
                    }
                    break;
                default:
                    dc.PushOpacity(Math.Clamp(a.Style.Opacity, AnnotationStyle.MinOpacity, 1));
                    Draw(dc, a);
                    dc.Pop();
                    break;
            }
        }
        dc.Close();
        target.Render(visual);
        target.Freeze();
        return target;
    }

    /// <summary>One layer for all spotlights: the image minus the UNION of the holes (overlaps stay bright).</summary>
    internal static Geometry DimGeometry(IEnumerable<SpotlightAnnotation> spots, double w, double h)
    {
        Geometry holes = Geometry.Empty;
        foreach (var s in spots)
        {
            var r = RectOf(s.Frame);
            Geometry hole = s.Style.SpotlightShape == SpotlightShape.Ellipse
                ? new EllipseGeometry(r)
                : new RectangleGeometry(r);
            holes = Geometry.Combine(holes, hole, GeometryCombineMode.Union, null);
        }
        var dim = Geometry.Combine(new RectangleGeometry(new Rect(0, 0, w, h)), holes, GeometryCombineMode.Exclude, null);
        dim.Freeze();
        return dim;
    }

    private static Effect ShadowEffect(double fontSize)
    {
        var (offset, blur) = TextChip.Shadow(fontSize);
        // WPF's BlurRadius is roughly twice CoreGraphics' blur.
        var e = new DropShadowEffect { Color = Colors.Black, Opacity = 0.45, Direction = 270, ShadowDepth = offset, BlurRadius = 2 * blur, RenderingBias = RenderingBias.Quality };
        e.Freeze();
        return e;
    }

    internal static void Draw(DrawingContext dc, IAnnotation annotation)
    {
        switch (annotation)
        {
            case ArrowAnnotation a:
            {
                double headLen = Math.Max(12, a.Style.LineWidth * 3);
                var shaftEnd = ArrowGeometry.ShaftEnd(a.Start, a.End, headLen);
                var (left, right) = ArrowGeometry.HeadWings(a.Start, a.End, headLen);
                var head = new StreamGeometry();
                using (var g = head.Open())
                {
                    g.BeginFigure(Pt(a.End), true, true);
                    g.LineTo(Pt(left), true, false);
                    g.LineTo(Pt(right), true, false);
                }
                dc.DrawLine(RoundPen(a.Style), Pt(a.Start), Pt(shaftEnd));
                dc.DrawGeometry(Solid(a.Style.StrokeColor), null, head);
                break;
            }
            case LineAnnotation l:
                dc.DrawLine(RoundPen(l.Style), Pt(l.Start), Pt(l.End));
                break;
            case FilledRectangleAnnotation fr:
                dc.DrawRectangle(Solid(fr.Style.StrokeColor), null, RectOf(fr.Frame)); // solid: covers what's under it (Mac)
                break;
            case RectangleAnnotation r:
                dc.DrawRectangle(r.Filled ? Solid(r.Style.FillColor) : null, Stroke(r.Style), RectOf(r.Frame));
                break;
            case EllipseAnnotation e:
            {
                var rect = RectOf(e.Frame);
                dc.DrawEllipse(null, Stroke(e.Style), new Point(rect.X + rect.Width / 2, rect.Y + rect.Height / 2), rect.Width / 2, rect.Height / 2);
                break;
            }
            case TextAnnotation t:
                DrawText(dc, t);
                break;
            case CounterAnnotation c:
            {
                double d = c.Diameter;
                var center = new Point(c.Origin.X + d / 2, c.Origin.Y + d / 2);
                dc.DrawEllipse(Solid(c.Style.StrokeColor), null, center, d / 2, d / 2);
                var ft = new FormattedText(c.Number.ToString(CultureInfo.InvariantCulture), CultureInfo.InvariantCulture,
                    FlowDirection.LeftToRight, new Typeface(CounterFont, FontStyles.Normal, FontWeights.Bold, FontStretches.Normal),
                    d * 0.55, Brushes.White, 1.0);
                dc.DrawText(ft, new Point(center.X - ft.Width / 2, center.Y - ft.Height / 2));
                break;
            }
        }
    }

    /// <summary>Box → outline pass → letters (decorations are text attributes, not outlined).</summary>
    internal static void DrawText(DrawingContext dc, TextAnnotation t)
    {
        var s = t.Style;
        var layout = t.LayoutRect();
        if (s.TextBackgroundMode != TextBackgroundMode.None)
        {
            var box = RectOf(t.BoundingBox());
            double r = Math.Min(s.TextBackgroundCornerRadius, Math.Min(box.Width / 2, box.Height / 2));
            var fill = s.TextBackgroundMode == TextBackgroundMode.Auto ? TextChip.AutoColor(s.StrokeColor) : s.TextBackgroundColor;
            dc.DrawRoundedRectangle(Solid(fill), null, box, r, r);
        }
        var ft = TextRendering.Format(t.Text, s, t.WrapWidth ?? layout.Width + 1, Solid(s.StrokeColor));
        if (t.WrapWidth is null) ft.MaxTextWidth = layout.Width + 1;
        var origin = new Point(layout.X, layout.Y);
        if (s.TextOutline)
        {
            var geometry = ft.BuildGeometry(origin);
            var pen = new Pen(Solid(s.TextOutlineColor), 2 * s.TextOutlineWidth) { LineJoin = PenLineJoin.Round };
            dc.DrawGeometry(null, pen, geometry);
        }
        dc.DrawText(ft, origin);
    }

    // ---- Redactions: rendered from the base for the CURRENT frame, cached per base image + object.

    private sealed record PatchKey(PxRect Rect, RedactionMode Mode, double Strength);
    private static readonly ConditionalWeakTable<BitmapSource, Dictionary<Guid, (PatchKey Key, BitmapSource? Patch)>> PatchCache = new();

    private static void DrawRedaction(DrawingContext dc, RedactionAnnotation r, BitmapSource source, int w, int h)
    {
        var rect = r.PatchRect(w, h);
        if (rect.IsEmpty) return;
        if (r.Style.RedactionMode == RedactionMode.Blackout)
        {
            dc.DrawRectangle(Brushes.Black, null, RectOf(rect));
            return;
        }
        if (Patch(r, source, rect) is { } patch) dc.DrawImage(patch, RectOf(rect));
    }

    /// <summary>The redaction patch for <paramref name="r"/> at <paramref name="rect"/> (cached; exposed for tests).</summary>
    public static BitmapSource? Patch(RedactionAnnotation r, BitmapSource source, PxRect rect)
    {
        var key = new PatchKey(rect, r.Style.RedactionMode, r.Style.RedactionStrength);
        var table = PatchCache.GetOrCreateValue(source);
        lock (table)
            if (table.TryGetValue(r.Id, out var hit) && hit.Key == key) return hit.Patch;

        BitmapSource? patch = null;
        int strength = (int)Math.Round(r.Style.RedactionStrength);
        // Read the real image around the box (blur needs up to 3σ of context), clipped to the image.
        int margin = r.Style.RedactionMode == RedactionMode.Blur ? (int)Math.Ceiling(3.0 * strength) : 0;
        int ex0 = Math.Max(0, (int)rect.X - margin), ey0 = Math.Max(0, (int)rect.Y - margin);
        int ex1 = Math.Min(source.PixelWidth, (int)rect.Right + margin), ey1 = Math.Min(source.PixelHeight, (int)rect.Bottom + margin);
        if (ex1 - ex0 >= 1 && ey1 - ey0 >= 1)
        {
            var sub = ImageConvert.ToArgbImage(new CroppedBitmap(source, new Int32Rect(ex0, ey0, ex1 - ex0, ey1 - ey0)));
            var local = new PxRect(rect.X - ex0, rect.Y - ey0, rect.Width, rect.Height);
            var argb = r.Style.RedactionMode == RedactionMode.Pixelate
                ? Redactor.Pixelate(sub, local, strength)
                : Redactor.Blur(sub, local, strength);
            if (argb != null)
            {
                patch = ImageConvert.ToBitmapSource(argb);
                patch.Freeze();
            }
        }
        lock (table) table[r.Id] = (key, patch);
        return patch;
    }

    // ---- Highlighter: multiply on the CPU (WPF has no blend modes).

    private static RenderTargetBitmap MultiplyHighlighter(RenderTargetBitmap target, HighlighterAnnotation hl)
    {
        int w = target.PixelWidth, h = target.PixelHeight;
        var bb = hl.BoundingBox();
        int x0 = Math.Clamp((int)Math.Floor(bb.X), 0, w), y0 = Math.Clamp((int)Math.Floor(bb.Y), 0, h);
        int x1 = Math.Clamp((int)Math.Ceiling(bb.Right), 0, w), y1 = Math.Clamp((int)Math.Ceiling(bb.Bottom), 0, h);
        int bw = x1 - x0, bh = y1 - y0;
        if (bw <= 0 || bh <= 0 || hl.Points.Count == 0) return target;

        // Coverage mask: the whole path in opaque white, stroked ONCE (self-overlaps count once).
        var maskVisual = new DrawingVisual();
        using (var mdc = maskVisual.RenderOpen())
        {
            mdc.PushTransform(new TranslateTransform(-x0, -y0));
            var pen = new Pen(Brushes.White, hl.Style.LineWidth) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round };
            if (hl.Points.Count == 1)
                mdc.DrawEllipse(Brushes.White, null, Pt(hl.Points[0]), hl.Style.LineWidth / 2, hl.Style.LineWidth / 2);
            else
                mdc.DrawGeometry(null, pen, Polyline(hl.Points));
            mdc.Pop();
        }
        var mask = new RenderTargetBitmap(bw, bh, 96, 96, PixelFormats.Pbgra32);
        mask.Render(maskVisual);
        var maskPx = new byte[bw * bh * 4];
        mask.CopyPixels(maskPx, bw * 4, 0);

        var px = new byte[w * h * 4];
        target.CopyPixels(px, w * 4, 0);
        var c = hl.Style.StrokeColor;
        double opacity = Math.Clamp(hl.Style.Opacity, AnnotationStyle.MinOpacity, 1);
        double fr = 1 - Math.Clamp(c.R, 0, 1), fg = 1 - Math.Clamp(c.G, 0, 1), fb = 1 - Math.Clamp(c.B, 0, 1);
        for (int y = 0; y < bh; y++)
        {
            for (int x = 0; x < bw; x++)
            {
                double coverage = maskPx[(y * bw + x) * 4 + 3] / 255.0;
                if (coverage <= 0) continue;
                double k = opacity * coverage;
                int i = ((y0 + y) * w + x0 + x) * 4; // BGRA, premultiplied — multiply keeps it premultiplied
                px[i] = (byte)Math.Round(px[i] * (1 - k * fb));
                px[i + 1] = (byte)Math.Round(px[i + 1] * (1 - k * fg));
                px[i + 2] = (byte)Math.Round(px[i + 2] * (1 - k * fr));
            }
        }
        var merged = BitmapSource.Create(w, h, 96, 96, PixelFormats.Pbgra32, null, px, w * 4);
        merged.Freeze();
        var next = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
        var v = new DrawingVisual();
        using (var vdc = v.RenderOpen()) vdc.DrawImage(merged, new Rect(0, 0, w, h));
        next.Render(v);
        return next;
    }

    internal static Geometry Polyline(IReadOnlyList<PxPoint> points)
    {
        var g = new StreamGeometry();
        using (var ctx = g.Open())
        {
            ctx.BeginFigure(Pt(points[0]), false, false);
            for (int i = 1; i < points.Count; i++) ctx.LineTo(Pt(points[i]), true, true);
        }
        g.Freeze();
        return g;
    }

    private static Pen RoundPen(AnnotationStyle style) => new(Solid(style.StrokeColor), style.LineWidth)
    {
        StartLineCap = PenLineCap.Round,
        EndLineCap = PenLineCap.Round,
        LineJoin = PenLineJoin.Round,
    };

    private static Pen Stroke(AnnotationStyle style) => new(Solid(style.StrokeColor), style.LineWidth);

    internal static Brush Solid(RGBAColor c) =>
        Frozen(Color.FromArgb(B(c.A), B(c.R), B(c.G), B(c.B)));

    private static byte B(double v) => (byte)Math.Round(Math.Clamp(v, 0, 1) * 255);

    private static Brush Frozen(Color c)
    {
        var b = new SolidColorBrush(c);
        b.Freeze();
        return b;
    }

    private static Point Pt(PxPoint p) => new(p.X, p.Y);
    internal static Rect RectOf(PxRect r) => new(r.X, r.Y, Math.Max(0, r.Width), Math.Max(0, r.Height));
}
