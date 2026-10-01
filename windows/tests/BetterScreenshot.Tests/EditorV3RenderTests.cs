using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Editor;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;

namespace BetterScreenshot.Tests;

/// <summary>Ports of the Mac render tests for v3 Parts 1–3: opacity layers, redaction strength + re-render from the
/// base, black-out, highlighter multiply, spotlight dim layer, text v2 (box, outline, decorations, shadow).</summary>
public class EditorV3RenderTests
{
    private static BitmapSource Solid(int w, int h, byte r, byte g, byte b)
    {
        var px = new byte[w * h * 4];
        for (int i = 0; i < px.Length; i += 4) { px[i] = b; px[i + 1] = g; px[i + 2] = r; px[i + 3] = 255; }
        var bmp = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, w * 4);
        bmp.Freeze();
        return bmp;
    }

    private static BitmapSource Noise(int w, int h, int seed = 3)
    {
        var rnd = new Random(seed);
        var px = new byte[w * h * 4];
        rnd.NextBytes(px);
        for (int i = 3; i < px.Length; i += 4) px[i] = 255;
        var bmp = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, w * 4);
        bmp.Freeze();
        return bmp;
    }

    private static (byte R, byte G, byte B) Px(BitmapSource bmp, int x, int y)
    {
        var conv = new FormatConvertedBitmap(bmp, PixelFormats.Bgra32, null, 0);
        var one = new byte[4];
        conv.CopyPixels(new Int32Rect(x, y, 1, 1), one, 4, 0);
        return (one[2], one[1], one[0]);
    }

    private static EditorDocument Doc(int w, int h, params IAnnotation[] a) => new(new PxSize(w, h), a);

    // ---- Opacity (§1.6)

    [Fact]
    public void HalfOpacityFilledRectBlendsWithBase()
    {
        var st = AnnotationStyle.Default with { StrokeColor = new RGBAColor(1, 0, 0, 1), Opacity = 0.5 };
        var outImg = DocumentRenderer.Render(Doc(60, 60, new FilledRectangleAnnotation(Guid.NewGuid(), st, new PxRect(10, 10, 40, 40))), Solid(60, 60, 255, 255, 255));
        var p = Px(outImg, 30, 30);
        Assert.InRange((int)p.R, 250, 255);
        Assert.InRange((int)p.G, 122, 134);
        Assert.InRange((int)p.B, 122, 134);
    }

    [Fact]
    public void TranslucentArrowDoesNotDoubleUpWhereShaftMeetsHead()
    {
        var st = AnnotationStyle.Default with { StrokeColor = new RGBAColor(1, 0, 0, 1), LineWidth = 12, Opacity = 0.5 };
        var outImg = DocumentRenderer.Render(Doc(100, 100, new ArrowAnnotation(Guid.NewGuid(), st, new PxPoint(20, 50), new PxPoint(80, 50))), Solid(100, 100, 255, 255, 255));
        Assert.Equal(Px(outImg, 35, 50), Px(outImg, 51, 50));
    }

    // ---- Redactions (§3.5)

    private static double Variance(BitmapSource bmp, PxRect r)
    {
        var vals = new List<double>();
        for (int y = (int)r.Y; y < r.Bottom; y++) for (int x = (int)r.X; x < r.Right; x++) vals.Add(Px(bmp, x, y).R);
        double mean = vals.Average();
        return vals.Sum(v => (v - mean) * (v - mean)) / vals.Count;
    }

    [Fact]
    public void HigherBlurStrengthLeavesLessDetail()
    {
        var src = ImageConvert.ToArgbImage(Noise(400, 400));
        var region = new PxRect(120, 140, 160, 120);
        double last = double.MaxValue;
        foreach (int radius in new[] { 2, 6, 12, 24, 40 })
        {
            var patch = Redactor.Blur(src, region, radius)!;
            var vals = new List<double>();
            for (int y = 0; y < patch.Height; y++) for (int x = 0; x < patch.Width; x++) vals.Add(patch.Get(x, y).R);
            double mean = vals.Average(), v = vals.Sum(q => (q - mean) * (q - mean)) / vals.Count;
            Assert.True(v < last, $"radius {radius}: variance {v} not below {last}");
            last = v;
        }
    }

    [Fact]
    public void BiggerPixelsLeaveLessDetail()
    {
        var src = ImageConvert.ToArgbImage(Noise(400, 400));
        var region = new PxRect(120, 140, 160, 120);
        double last = double.MaxValue;
        foreach (int block in new[] { 4, 8, 16, 32, 48 })
        {
            var p = Redactor.Pixelate(src, region, block)!;
            double sum = 0; int n = 0;
            for (int y = 0; y < p.Height; y++) for (int x = 1; x < p.Width; x++) { sum += Math.Abs(p.Get(x, y).R - p.Get(x - 1, y).R); n++; }
            double mad = sum / n;
            Assert.True(mad < last, $"block {block}: {mad} not below {last}");
            last = mad;
        }
    }

    [Fact]
    public void MovedRedactionRedactsItsNewRegion()
    {
        var noise = Noise(200, 150);
        foreach (var mode in new[] { RedactionMode.Blur, RedactionMode.Pixelate })
        {
            var r = new RedactionAnnotation(Guid.NewGuid(), AnnotationStyle.Default with { RedactionMode = mode }, new PxRect(10, 10, 30, 20));
            DocumentRenderer.Render(Doc(200, 150, r), noise);
            var moved = (RedactionAnnotation)r.MovedBy(60, 50);
            var outImg = DocumentRenderer.Render(Doc(200, 150, moved), noise);
            var argb = ImageConvert.ToArgbImage(noise);
            var fresh = mode == RedactionMode.Blur ? Redactor.Blur(argb, new PxRect(70, 60, 30, 20), 12)! : Redactor.Pixelate(argb, new PxRect(70, 60, 30, 20), 12)!;
            var got = Px(outImg, 75, 65);
            var want = fresh.Get(5, 5);
            Assert.InRange(Math.Abs(got.R - want.R), 0, 2);
        }
    }

    [Fact]
    public void ResizedRedactionIsRenderedNotStretched()
    {
        var noise = Noise(200, 150);
        var r = new RedactionAnnotation(Guid.NewGuid(), AnnotationStyle.Default with { RedactionMode = RedactionMode.Pixelate, PixelSize = 4 }, new PxRect(10, 10, 20, 20));
        DocumentRenderer.Render(Doc(200, 150, r), noise);
        var resized = (RedactionAnnotation)r.WithFrame(new PxRect(10, 10, 60, 50));
        var patch = DocumentRenderer.Patch(resized, noise, resized.PatchRect(200, 150))!;
        Assert.Equal(60, patch.PixelWidth);
        Assert.Equal(50, patch.PixelHeight);
    }

    [Fact]
    public void PatchIsCachedUntilFrameOrStrengthChanges()
    {
        var noise = Noise(100, 100);
        var r = new RedactionAnnotation(Guid.NewGuid(), AnnotationStyle.Default, new PxRect(10, 10, 30, 30));
        var a = DocumentRenderer.Patch(r, noise, r.PatchRect(100, 100));
        Assert.Same(a, DocumentRenderer.Patch(r, noise, r.PatchRect(100, 100)));
        var stronger = (RedactionAnnotation)r.WithStyle(r.Style with { BlurRadius = 30 });
        Assert.NotSame(a, DocumentRenderer.Patch(stronger, noise, stronger.PatchRect(100, 100)));
    }

    [Fact]
    public void BlackoutIsSolidBlackAndSnapsOutward()
    {
        var r = new RedactionAnnotation(Guid.NewGuid(), AnnotationStyle.Default with { RedactionMode = RedactionMode.Blackout }, new PxRect(20.4, 10.6, 30, 20));
        var outImg = DocumentRenderer.Render(Doc(100, 60, r), Solid(100, 60, 255, 255, 255));
        for (int y = 10; y < 31; y++) for (int x = 20; x < 51; x++) Assert.Equal((0, 0, 0), (Px(outImg, x, y).R, Px(outImg, x, y).G, Px(outImg, x, y).B));
    }

    [Fact]
    public void RedactionFollowsTheBaseIntoACrop()
    {
        var noise = Noise(100, 100);
        var doc = Doc(100, 100, new RedactionAnnotation(Guid.NewGuid(), AnnotationStyle.Default with { RedactionMode = RedactionMode.Pixelate }, new PxRect(40, 40, 20, 20)));
        var cropped = doc.Cropped(new PxRect(30, 30, 50, 50));
        var croppedBase = new CroppedBitmap(noise, new Int32Rect(30, 30, 50, 50));
        var outImg = DocumentRenderer.Render(cropped, croppedBase);
        Assert.Equal(50, outImg.PixelWidth);
        var r = (RedactionAnnotation)cropped.Annotations[0];
        Assert.Equal(new PxRect(10, 10, 20, 20), r.Frame);
    }

    // ---- Highlighter (§3.5)

    private static BitmapSource Bands()
    {
        // White image, black band x 20..40, mid-grey band x 60..80.
        int w = 100, h = 100;
        var px = new byte[w * h * 4];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                byte v = x is >= 20 and < 40 ? (byte)0 : x is >= 60 and < 80 ? (byte)128 : (byte)255;
                int i = (y * w + x) * 4;
                px[i] = v; px[i + 1] = v; px[i + 2] = v; px[i + 3] = 255;
            }
        var bmp = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, w * 4);
        bmp.Freeze();
        return bmp;
    }

    private static HighlighterAnnotation Stroke(double opacity, params PxPoint[] pts) =>
        new(Guid.NewGuid(), AnnotationStyle.Default with { StrokeColor = new RGBAColor(1, 1, 0, 1), LineWidth = 20, Opacity = opacity }, pts);

    [Fact]
    public void HighlighterMultipliesSoTextUnderneathStaysReadable()
    {
        var outImg = DocumentRenderer.Render(Doc(100, 100, Stroke(1, new PxPoint(5, 50), new PxPoint(95, 50))), Bands());
        var white = Px(outImg, 10, 50);
        Assert.True(white.R >= 245 && white.G >= 245 && white.B < 10, $"white → {white}");
        var black = Px(outImg, 30, 50);
        Assert.True(black.R < 10 && black.G < 10 && black.B < 10);
        var grey = Px(outImg, 70, 50);
        Assert.InRange(Math.Abs(grey.R - 128), 0, 4);
        Assert.InRange(Math.Abs(grey.G - 128), 0, 4);
        Assert.True(grey.B < 10);
    }

    [Fact]
    public void HighlighterOpacityFadesTheTint()
    {
        var outImg = DocumentRenderer.Render(Doc(100, 100, Stroke(0.4, new PxPoint(5, 50), new PxPoint(95, 50))), Bands());
        Assert.InRange((int)Px(outImg, 10, 50).B, 150, 156);
        Assert.True(Px(outImg, 30, 50).R < 10);
    }

    [Fact]
    public void SelfCrossingStrokeDoesNotDarkenTwice()
    {
        var once = DocumentRenderer.Render(Doc(100, 100, Stroke(0.4, new PxPoint(5, 50), new PxPoint(95, 50))), Bands());
        var crossed = DocumentRenderer.Render(Doc(100, 100, Stroke(0.4, new PxPoint(5, 50), new PxPoint(95, 50), new PxPoint(95, 10), new PxPoint(10, 90))), Bands());
        Assert.Equal(Px(once, 50, 50), Px(crossed, 50, 50));
    }

    // ---- Spotlight (§3.5)

    private static SpotlightAnnotation Spot(PxRect r, double dim = 0.6, SpotlightShape shape = SpotlightShape.Rectangle) =>
        new(Guid.NewGuid(), AnnotationStyle.Default with { SpotlightDim = dim, SpotlightShape = shape }, r);

    [Fact]
    public void InsideUnchangedOutsideDarkenedByTheDimAmount()
    {
        var white = Solid(100, 100, 255, 255, 255);
        var outImg = DocumentRenderer.Render(Doc(100, 100, Spot(new PxRect(20, 20, 40, 40))), white);
        Assert.Equal(255, Px(outImg, 40, 40).R);
        Assert.InRange((int)Px(outImg, 5, 5).R, 99, 105);
        var light = DocumentRenderer.Render(Doc(100, 100, Spot(new PxRect(20, 20, 40, 40), 0.3)), white);
        Assert.InRange((int)Px(light, 5, 5).R, 176, 182);
    }

    [Fact]
    public void EllipseSpotlightDimsTheBoxCorners()
    {
        var outImg = DocumentRenderer.Render(Doc(100, 100, Spot(new PxRect(20, 20, 40, 40), shape: SpotlightShape.Ellipse)), Solid(100, 100, 255, 255, 255));
        Assert.True(Px(outImg, 22, 22).R < 150);
        Assert.Equal(255, Px(outImg, 40, 40).R);
    }

    [Fact]
    public void SeveralSpotlightsMakeOneLayerWithSeveralHoles()
    {
        var outImg = DocumentRenderer.Render(Doc(100, 100, Spot(new PxRect(10, 10, 40, 40)), Spot(new PxRect(30, 30, 40, 40))), Solid(100, 100, 255, 255, 255));
        Assert.Equal(255, Px(outImg, 40, 40).R);     // overlap stays bright
        Assert.InRange((int)Px(outImg, 90, 5).R, 99, 105); // outside dimmed once
    }

    [Fact]
    public void OtherObjectsStayBrightAboveTheDim()
    {
        var box = new FilledRectangleAnnotation(Guid.NewGuid(), AnnotationStyle.Default with { StrokeColor = new RGBAColor(1, 0, 0, 1) }, new PxRect(70, 70, 20, 20));
        var outImg = DocumentRenderer.Render(Doc(100, 100, box, Spot(new PxRect(10, 10, 30, 30))), Solid(100, 100, 255, 255, 255));
        var p = Px(outImg, 80, 80);
        Assert.True(p.R > 245 && p.G < 10, $"red box dimmed: {p}");
    }

    [Fact]
    public void RedactionsOutsideTheSpotlightAreDimmedToo()
    {
        var black = new RedactionAnnotation(Guid.NewGuid(), AnnotationStyle.Default with { RedactionMode = RedactionMode.Pixelate }, new PxRect(70, 70, 20, 20));
        var outImg = DocumentRenderer.Render(Doc(100, 100, black, Spot(new PxRect(10, 10, 30, 30))), Solid(100, 100, 255, 255, 255));
        Assert.InRange((int)Px(outImg, 80, 80).R, 99, 105);
    }

    // ---- Text v2 rendering (§2.4)

    private static TextAnnotation Text(AnnotationStyle s, string text = "Hello", double x = 60, double y = 40) => new(Guid.NewGuid(), s, text, new PxPoint(x, y));

    [Fact]
    public void SolidBackgroundFillsTheBoxWithItsColour()
    {
        var blue = new RGBAColor(0, 0, 1, 1);
        var t = Text(AnnotationStyle.Default with { TextBackgroundMode = TextBackgroundMode.Solid, TextBackgroundColor = blue, TextBackgroundCornerRadius = 0 });
        var outImg = DocumentRenderer.Render(Doc(300, 120, t), Solid(300, 120, 255, 255, 255));
        var box = t.BoundingBox();
        var inside = Px(outImg, (int)box.X + 3, (int)(box.Y + box.Height / 2));
        Assert.True(inside.B > 240 && inside.R < 15, $"inside {inside}");
        var outside = Px(outImg, (int)box.X - 3, (int)(box.Y + box.Height / 2));
        Assert.True(outside.R > 240 && outside.B > 240);
    }

    [Fact]
    public void AutoBackgroundKeepsTheContrastingChip()
    {
        var t = Text(AnnotationStyle.Default with { StrokeColor = RGBAColor.White, TextBackgroundMode = TextBackgroundMode.Auto, TextBackgroundCornerRadius = 0 });
        var outImg = DocumentRenderer.Render(Doc(300, 120, t), Solid(300, 120, 255, 255, 255));
        var box = t.BoundingBox();
        var p = Px(outImg, (int)box.X + 2, (int)box.Y + 2);
        Assert.InRange((int)p.R, 0x18 - 3, 0x18 + 3);
    }

    [Fact]
    public void PaddingAndCornerRadiusShapeTheBox()
    {
        var square = Text(AnnotationStyle.Default with { TextBackgroundMode = TextBackgroundMode.Solid, TextBackgroundColor = RGBAColor.Black, TextBackgroundPadding = 20, TextBackgroundCornerRadius = 0 });
        var round = square with { Style = square.Style with { TextBackgroundCornerRadius = 20 } };
        var white = Solid(300, 160, 255, 255, 255);
        var b = square.BoundingBox();
        Assert.True(Px(DocumentRenderer.Render(Doc(300, 160, square), white), (int)b.X, (int)b.Y).R < 20);
        Assert.True(Px(DocumentRenderer.Render(Doc(300, 160, round), white), (int)b.X, (int)b.Y).R > 235);
    }

    private static (int Left, int Right, int Bottom) Ink(BitmapSource bmp, Func<(byte R, byte G, byte B), bool> isInk)
    {
        int l = int.MaxValue, r = -1, bottom = -1;
        var conv = new FormatConvertedBitmap(bmp, PixelFormats.Bgra32, null, 0);
        int w = conv.PixelWidth, h = conv.PixelHeight;
        var px = new byte[w * h * 4];
        conv.CopyPixels(px, w * 4, 0);
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int i = (y * w + x) * 4;
                if (!isInk((px[i + 2], px[i + 1], px[i]))) continue;
                l = Math.Min(l, x); r = Math.Max(r, x); bottom = Math.Max(bottom, y);
            }
        return (l, r, bottom);
    }

    [Fact]
    public void OutlineWidensTheInkInItsColour()
    {
        var plain = Text(AnnotationStyle.Default with { StrokeColor = RGBAColor.Black, FontSize = 40 });
        var outlined = plain with { Style = plain.Style with { TextOutline = true, TextOutlineColor = new RGBAColor(1, 0, 0, 1), TextOutlineWidth = 4 } };
        var white = Solid(400, 160, 255, 255, 255);
        bool AnyInk((byte R, byte G, byte B) p) => p.R < 200 || p.G < 200 || p.B < 200;
        var a = Ink(DocumentRenderer.Render(Doc(400, 160, plain), white), AnyInk);
        var b = Ink(DocumentRenderer.Render(Doc(400, 160, outlined), white), AnyInk);
        Assert.True(a.Left - b.Left >= 3 && b.Right - a.Right >= 3 && b.Bottom > a.Bottom, $"{a} vs {b}");
        var redEdge = Ink(DocumentRenderer.Render(Doc(400, 160, outlined), white), p => p.R > 200 && p.G < 60 && p.B < 60);
        Assert.True(redEdge.Right >= 0);
    }

    [Fact]
    public void UnderlineAddsInkBelowTheBaseline()
    {
        var plain = Text(AnnotationStyle.Default with { StrokeColor = RGBAColor.Black, FontSize = 40 }, "ace");
        var under = plain with { Style = plain.Style with { TextUnderline = true } };
        var white = Solid(300, 160, 255, 255, 255);
        bool AnyInk((byte R, byte G, byte B) p) => p.R < 200;
        Assert.True(Ink(DocumentRenderer.Render(Doc(300, 160, under), white), AnyInk).Bottom > Ink(DocumentRenderer.Render(Doc(300, 160, plain), white), AnyInk).Bottom);
    }

    [Fact]
    public void StrikethroughCrossesTheGapsBetweenLetters()
    {
        var t = Text(AnnotationStyle.Default with { StrokeColor = RGBAColor.Black, FontSize = 40, TextStrikethrough = true }, "i   i   i");
        var outImg = DocumentRenderer.Render(Doc(400, 160, t), Solid(400, 160, 255, 255, 255));
        var conv = new FormatConvertedBitmap(outImg, PixelFormats.Bgra32, null, 0);
        int w = conv.PixelWidth, h = conv.PixelHeight;
        var px = new byte[w * h * 4];
        conv.CopyPixels(px, w * 4, 0);
        var layout = t.LayoutRect();
        bool found = false;
        for (int y = (int)layout.Y; y < layout.Bottom && !found; y++)
        {
            int run = 0, best = 0;
            for (int x = (int)layout.X; x < layout.Right; x++) { run = px[(y * w + x) * 4 + 2] < 128 ? run + 1 : 0; best = Math.Max(best, run); }
            found = best >= layout.Width * 0.7;
        }
        Assert.True(found);
    }

    [Fact]
    public void ShadowFallsBelowTheText()
    {
        var t = Text(AnnotationStyle.Default with { StrokeColor = RGBAColor.Black, FontSize = 48, TextShadow = true }, "HH");
        var outImg = DocumentRenderer.Render(Doc(300, 200, t), Solid(300, 200, 255, 255, 255));
        var noShadow = DocumentRenderer.Render(Doc(300, 200, t with { Style = t.Style with { TextShadow = false } }), Solid(300, 200, 255, 255, 255));
        bool AnyInk((byte R, byte G, byte B) p) => p.R < 250;
        var withS = Ink(outImg, AnyInk);
        var without = Ink(noShadow, AnyInk);
        Assert.True(withS.Bottom > without.Bottom, $"shadow bottom {withS.Bottom} vs {without.Bottom}");
    }

    [Fact]
    public void TextLayoutIsExactAndBoxWidthEqualsWrapWidth()
    {
        TextRendering.Install();
        var t = new TextAnnotation(Guid.NewGuid(), AnnotationStyle.Default, "one two three four five six seven", new PxPoint(10, 10), 120);
        Assert.Equal(120, t.LayoutRect().Width);
        Assert.True(t.LayoutRect().Height > 2.5 * AnnotationStyle.Default.FontSize);
        var mono = TextRendering.Measure("iiiiiiiiii", AnnotationStyle.Default with { FontFamily = TextFont.Mono }, null);
        var sys = TextRendering.Measure("iiiiiiiiii", AnnotationStyle.Default, null);
        Assert.True(mono.Width >= 1.3 * sys.Width);
        Assert.Equal(TextRendering.Family(TextFont.System).Source, TextRendering.Family("No Such Font 123").Source);
    }
}
