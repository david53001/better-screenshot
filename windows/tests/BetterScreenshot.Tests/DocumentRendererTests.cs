using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Editor;
using BetterScreenshot.Core;
using BetterScreenshot.Editor;
using Xunit;

namespace BetterScreenshot.Tests;

public class DocumentRendererTests
{
    private static BitmapSource SolidBase(int w, int h, byte r, byte g, byte b)
    {
        int stride = w * 4;
        var px = new byte[h * stride];
        for (int i = 0; i < w * h; i++) { int s = i * 4; px[s] = b; px[s + 1] = g; px[s + 2] = r; px[s + 3] = 255; }
        return BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, stride);
    }

    private static BitmapSource TwoTone(int w, int h) // top half red, bottom half blue
    {
        int stride = w * 4;
        var px = new byte[h * stride];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
            {
                int s = y * stride + x * 4;
                bool top = y < h / 2;
                px[s] = (byte)(top ? 0 : 255); // B
                px[s + 1] = 0;                 // G
                px[s + 2] = (byte)(top ? 255 : 0); // R
                px[s + 3] = 255;
            }
        return BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, stride);
    }

    private static (byte R, byte G, byte B, byte A) Pixel(BitmapSource bmp, int x, int y)
    {
        var conv = bmp.Format == PixelFormats.Bgra32 ? bmp : new FormatConvertedBitmap(bmp, PixelFormats.Bgra32, null, 0);
        var one = new byte[4];
        conv.CopyPixels(new Int32Rect(x, y, 1, 1), one, 4, 0);
        return (one[2], one[1], one[0], one[3]);
    }

    private static readonly AnnotationStyle OpaqueRed = AnnotationStyle.Default with { StrokeColor = new RGBAColor(1, 0, 0, 1), FillColor = new RGBAColor(1, 0, 0, 1) };

    [Fact]
    public void RendersFilledRectInRed()
    {
        var doc = new EditorDocument(new PxSize(100, 100));
        doc.Add(new FilledRectangleAnnotation(Guid.NewGuid(), OpaqueRed, new PxRect(20, 20, 40, 40)));
        var outImg = DocumentRenderer.Render(doc, SolidBase(100, 100, 255, 255, 255));
        var p = Pixel(outImg, 40, 40);
        Assert.True(p.R > 150 && p.G < 120 && p.B < 120, $"expected red, got {p.R},{p.G},{p.B}");
    }

    [Fact]
    public void PreservesBaseImageOrientation()
    {
        var outImg = DocumentRenderer.Render(new EditorDocument(new PxSize(40, 40)), TwoTone(40, 40));
        var top = Pixel(outImg, 20, 5);
        var bottom = Pixel(outImg, 20, 35);
        Assert.True(top.R > 150 && top.B < 100, $"top should be red, got {top.R},{top.G},{top.B}");
        Assert.True(bottom.B > 150 && bottom.R < 100, $"bottom should be blue, got {bottom.R},{bottom.G},{bottom.B}");
    }

    [Fact]
    public void ArrowShaftDoesNotBleedPastHead()
    {
        var doc = new EditorDocument(new PxSize(120, 60));
        doc.Add(new ArrowAnnotation(Guid.NewGuid(), AnnotationStyle.Default, new PxPoint(10, 30), new PxPoint(90, 30)));
        var outImg = DocumentRenderer.Render(doc, SolidBase(120, 60, 255, 255, 255));
        var pastTip = Pixel(outImg, 105, 30);
        Assert.True(pastTip.R > 200 && pastTip.G > 200 && pastTip.B > 200, $"past tip should be white, got {pastTip.R},{pastTip.G},{pastTip.B}");
        var onShaft = Pixel(outImg, 40, 30);
        Assert.True(onShaft.R > 150 && onShaft.G < 130, $"shaft should be red, got {onShaft.R},{onShaft.G},{onShaft.B}");
    }

    [Fact]
    public void RendersPreviewOnTopWithoutMutatingDocument()
    {
        var doc = new EditorDocument(new PxSize(60, 60));
        var preview = new FilledRectangleAnnotation(Guid.NewGuid(), OpaqueRed, new PxRect(10, 10, 40, 40));
        var outImg = DocumentRenderer.Render(doc, SolidBase(60, 60, 255, 255, 255), preview);
        Assert.True(Pixel(outImg, 30, 30).R > 150);
        Assert.Empty(doc.Annotations); // preview must not be added to the document
    }

    [Fact]
    public void TextWithBackgroundPaintsChipBehindGlyphs()
    {
        // Opaque black chip behind white text on a white base: the chip's left padding (no glyph there) must be dark.
        var style = AnnotationStyle.Default with { StrokeColor = new RGBAColor(1, 1, 1, 1), TextBackgroundMode = TextBackgroundMode.Solid, TextBackgroundColor = new RGBAColor(0, 0, 0, 1) };
        var doc = new EditorDocument(new PxSize(200, 80));
        doc.Add(new TextAnnotation(Guid.NewGuid(), style, "Hi", new PxPoint(40, 30)));
        var outImg = DocumentRenderer.Render(doc, SolidBase(200, 80, 255, 255, 255));
        var pad = Pixel(outImg, 37, 36); // inside the box, left of the first glyph (origin.X = 40, box starts at 34)
        Assert.True(pad.R < 60 && pad.G < 60 && pad.B < 60, $"expected dark chip, got {pad.R},{pad.G},{pad.B}");
    }

    [Fact]
    public void TextWithoutBackgroundLeavesBaseVisible()
    {
        // Same geometry, no chip: the spot where a chip would be must stay the base color (the default = no box).
        var style = AnnotationStyle.Default with { StrokeColor = new RGBAColor(1, 0, 0, 1), TextBackgroundMode = TextBackgroundMode.None };
        var doc = new EditorDocument(new PxSize(200, 80));
        doc.Add(new TextAnnotation(Guid.NewGuid(), style, "Hi", new PxPoint(40, 30)));
        var outImg = DocumentRenderer.Render(doc, SolidBase(200, 80, 255, 255, 255));
        var pad = Pixel(outImg, 36, 36);
        Assert.True(pad.R > 200 && pad.G > 200 && pad.B > 200, $"expected white base, got {pad.R},{pad.G},{pad.B}");
    }
}
