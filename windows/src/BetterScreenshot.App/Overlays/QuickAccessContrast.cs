using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.Core;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;
using Size = System.Windows.Size;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// The Quick Access card's guaranteed-contrast controls (Mac v2.9.0). The pure maths lives in
/// <see cref="BetterScreenshot.Core.QuickAccessContrast"/>; this class samples the pixels that are actually drawn
/// behind the button row (aspect-fill aware, at device resolution) and turns the resulting
/// <see cref="ContrastPlan"/> into brushes. The scrim holds <see cref="ContrastPlan.ScrimAlpha"/> FLAT from the
/// row's top edge to the card's bottom â€” the 4.5:1 guarantee holds only while the scrimmed region âŠ‡ the sampled
/// region, so never narrow the scrim or widen the sample without redoing that argument.
/// </summary>
internal sealed class ContrastPalette
{
    /// <summary>Height (DIPs) of the soft fade ABOVE the row's top edge; purely cosmetic â€” it never sits under a glyph.</summary>
    public const double FadeAbove = 16;
    private const double ScreenMargin = 0.05;

    public Brush Glyph { get; }
    public Brush Hover { get; }
    public Brush Pressed { get; }
    public Brush Scrim { get; }
    public ContrastPlan Plan { get; }

    private ContrastPalette(ContrastPlan plan, double scrimHeight)
    {
        Plan = plan;
        Glyph = Frozen(plan.Colors.GlyphArgb);
        Hover = Frozen(plan.Colors.HoverArgb);
        Pressed = Frozen(plan.Colors.PressedArgb);
        byte tone = plan.Colors.ScrimIsWhite ? (byte)0xFF : (byte)0x00;
        // +0.05 absorbs WPF's byte-quantised alpha and the bitmap filtering of the drawn thumbnail (measured on a busy
        // photo: the exact alpha landed at 4.41:1 on screen, the margin lifts it past 4.5:1). Rounded UP, never down.
        byte a = (byte)Math.Ceiling(Math.Min(QuickAccessContrast.MaxScrimAlpha, plan.ScrimAlpha + ScreenMargin) * 255);
        var scrim = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(0, 1) };
        double flatFrom = scrimHeight > 0 ? Math.Clamp(FadeAbove / scrimHeight, 0, 1) : 0;
        scrim.GradientStops.Add(new GradientStop(Color.FromArgb(0, tone, tone, tone), 0));
        scrim.GradientStops.Add(new GradientStop(Color.FromArgb(a, tone, tone, tone), flatFrom));
        scrim.GradientStops.Add(new GradientStop(Color.FromArgb(a, tone, tone, tone), 1));
        scrim.Freeze();
        Scrim = scrim;
    }

    /// <summary>Plans the palette for a button row occupying <paramref name="rowRect"/> (card DIPs) on a card of
    /// <paramref name="cardSize"/> showing <paramref name="image"/> with UniformToFill. <paramref name="deviceScale"/>
    /// is the monitor's DPI scale: the band is sampled at device resolution, because downsampling box-filters a
    /// white headline into its surround and would under-state the bright end.</summary>
    public static ContrastPalette ForButtonRow(BitmapSource image, Size cardSize, Rect rowRect, double deviceScale, double scrimHeight)
    {
        var extremes = SampleBand(image, cardSize, rowRect, deviceScale);
        return new ContrastPalette(QuickAccessContrast.Plan(extremes), scrimHeight);
    }

    internal static BandExtremes SampleBand(BitmapSource image, Size cardSize, Rect rowRect, double deviceScale)
    {
        try
        {
            var srcRect = AspectFillMap.SourceRect(new PxSize(cardSize.Width, cardSize.Height),
                new PxSize(image.PixelWidth, image.PixelHeight),
                new PxRect(rowRect.X, rowRect.Y, rowRect.Width, rowRect.Height));
            if (srcRect.IsEmpty) return new BandExtremes(0, 0);

            int x0 = (int)Math.Floor(srcRect.X), y0 = (int)Math.Floor(srcRect.Y);
            int x1 = Math.Min(image.PixelWidth, (int)Math.Ceiling(srcRect.Right));
            int y1 = Math.Min(image.PixelHeight, (int)Math.Ceiling(srcRect.Bottom));
            if (x1 <= x0 || y1 <= y0) return new BandExtremes(0, 0);
            var bgra = new FormatConvertedBitmap(new CroppedBitmap(image, new Int32Rect(x0, y0, x1 - x0, y1 - y0)),
                PixelFormats.Bgra32, null, 0);
            int w = bgra.PixelWidth, h = bgra.PixelHeight;
            var src = new byte[w * h * 4];
            bgra.CopyPixels(src, w * 4, 0);

            // Never box-filter the band below what's on screen (that averages a white headline into its surround
            // and under-states the bright end). Instead POINT-sample the untouched source pixels on a grid of at
            // least 2Ã— the device pixels the row covers: source pixels are at least as extreme as the filtered
            // pixels WPF draws, so the plan is conservative, and the cost stays bounded for 4K captures.
            int gw = Math.Min(w, (int)Math.Ceiling(rowRect.Width * deviceScale * 2));
            int gh = Math.Min(h, (int)Math.Ceiling(rowRect.Height * deviceScale * 2));
            gw = Math.Max(1, gw); gh = Math.Max(1, gh);
            var px = new byte[gw * gh * 4];
            for (int gy = 0; gy < gh; gy++)
            {
                int sy = Math.Min(h - 1, (int)((gy + 0.5) * h / gh));
                for (int gx = 0; gx < gw; gx++)
                {
                    int sx = Math.Min(w - 1, (int)((gx + 0.5) * w / gw));
                    Buffer.BlockCopy(src, (sy * w + sx) * 4, px, (gy * gw + gx) * 4, 4);
                }
            }
            return BandLuminance.Extremes(px, gw * gh);
        }
        catch
        {
            // Unreadable source: assume the worst bimodal band so the plan still guarantees contrast.
            return new BandExtremes(0, 1);
        }
    }

    private static SolidColorBrush Frozen(uint argb)
    {
        var b = new SolidColorBrush(Color.FromArgb((byte)(argb >> 24), (byte)(argb >> 16), (byte)(argb >> 8), (byte)argb));
        b.Freeze();
        return b;
    }
}
