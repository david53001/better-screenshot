namespace BetterScreenshot.Core;

/// <summary>
/// WCAG 2.x sRGB primitives (port of the Mac <c>OverlayKit/SRGB.swift</c>). Contrast is only meaningful on
/// <i>linear</i> light, so every luminance here gamma-expands first — weighting the encoded bytes directly
/// overstates dark pixels.
/// </summary>
public static class Srgb
{
    /// <summary>Gamma-expand one sRGB-encoded channel (0..1) to linear.</summary>
    public static double Expand(double c) => c <= 0.04045 ? c / 12.92 : Math.Pow((c + 0.055) / 1.055, 2.4);

    /// <summary>Inverse of <see cref="Expand"/>.</summary>
    public static double Encode(double linear) =>
        linear <= 0.0031308 ? linear * 12.92 : 1.055 * Math.Pow(linear, 1.0 / 2.4) - 0.055;

    /// <summary>WCAG 2.x relative luminance (0..1) of an sRGB byte triple.</summary>
    public static double RelativeLuminance(byte r, byte g, byte b) =>
        0.2126 * Expand(r / 255.0) + 0.7152 * Expand(g / 255.0) + 0.0722 * Expand(b / 255.0);

    /// <summary>Relative luminance of a packed 0xAARRGGBB colour (alpha ignored).</summary>
    public static double RelativeLuminance(uint argb) =>
        RelativeLuminance((byte)(argb >> 16), (byte)(argb >> 8), (byte)argb);

    /// <summary>WCAG contrast ratio (1..21) between two relative luminances.</summary>
    public static double ContrastRatio(double a, double b) => (Math.Max(a, b) + 0.05) / (Math.Min(a, b) + 0.05);
}

/// <summary>
/// Percentile luminance over the strip of pixels behind the Quick Access buttons (port of
/// <c>BandLuminance.swift</c>). A mean hides bimodal bands — a white headline over a black starfield averages
/// dark, then white glyphs land on the headline — percentiles keep both ends visible.
/// Buffers are tightly packed 32-bit BGRA (WPF <c>Bgra32</c>); alpha is ignored.
/// </summary>
public static class BandLuminance
{
    /// <summary>Relative luminance at percentile <paramref name="p"/> (clamped to 0..1). 0 for an empty/short buffer.</summary>
    public static double Percentile(ReadOnlySpan<byte> bgra, int pixelCount, double p)
    {
        if (pixelCount <= 0 || bgra.Length < pixelCount * 4) return 0;
        var lums = new double[pixelCount];
        for (int i = 0; i < pixelCount; i++)
            lums[i] = Srgb.RelativeLuminance(bgra[i * 4 + 2], bgra[i * 4 + 1], bgra[i * 4]);
        Array.Sort(lums);
        double clamped = Math.Clamp(double.IsNaN(p) ? 0 : p, 0, 1);
        int index = (int)Math.Round(clamped * (pixelCount - 1), MidpointRounding.AwayFromZero);
        return lums[index];
    }

    /// <summary>Low/high percentile pair describing the worst backgrounds in the band. The defaults trim the
    /// outermost 10 % so a handful of stray pixels can't force a heavy scrim over an otherwise uniform strip.</summary>
    public static BandExtremes Extremes(ReadOnlySpan<byte> bgra, int pixelCount, double low = 0.10, double high = 0.90) =>
        new(Percentile(bgra, pixelCount, low), Percentile(bgra, pixelCount, high));
}

/// <summary>
/// Card-space ↔ image-pixel-space mapping for a full-bleed aspect-fill (<c>Stretch="UniformToFill"</c>)
/// thumbnail (port of <c>AspectFillMap.swift</c>). Sampling the pixels behind the button row means knowing
/// which part of the source the card actually shows — aspect-fill crops one axis away entirely.
/// </summary>
public static class AspectFillMap
{
    /// <summary>Maps a rect in card space to the source-image PIXEL rect drawn into it. Both spaces are
    /// top-left origin. Returns an empty rect for degenerate inputs.</summary>
    public static PxRect SourceRect(PxSize cardSize, PxSize imagePixelSize, PxRect cardRect)
    {
        if (cardSize.Width <= 0 || cardSize.Height <= 0 || imagePixelSize.Width <= 0 || imagePixelSize.Height <= 0
            || cardRect.Width <= 0 || cardRect.Height <= 0) return default;

        // Aspect-fill scales until both axes are covered, then centres the overflow.
        double scale = Math.Max(cardSize.Width / imagePixelSize.Width, cardSize.Height / imagePixelSize.Height);
        double offsetX = (cardSize.Width - imagePixelSize.Width * scale) / 2;
        double offsetY = (cardSize.Height - imagePixelSize.Height * scale) / 2;

        double minX = (cardRect.X - offsetX) / scale, minY = (cardRect.Y - offsetY) / scale;
        double maxX = (cardRect.Right - offsetX) / scale, maxY = (cardRect.Bottom - offsetY) / scale;

        // Clamp: a card rect can hang off the edge, but there are no pixels out there.
        double x0 = Math.Clamp(minX, 0, imagePixelSize.Width), y0 = Math.Clamp(minY, 0, imagePixelSize.Height);
        double x1 = Math.Clamp(maxX, 0, imagePixelSize.Width), y1 = Math.Clamp(maxY, 0, imagePixelSize.Height);
        return new PxRect(x0, y0, x1 - x0, y1 - y0);
    }
}

public enum ContrastTone { Dark, Light }

/// <summary>Glyph + hover/pressed pill colours (0xAARRGGBB) for one tone, and which scrim colour serves it.</summary>
public readonly record struct ContrastColors(uint GlyphArgb, uint HoverArgb, uint PressedArgb, bool ScrimIsWhite);

/// <summary>The darkest and brightest backgrounds the button row has to survive (relative luminances).</summary>
public readonly record struct BandExtremes(double Dark, double Bright);

/// <summary>A glyph tone plus the scrim strength (0..1, held FLAT across the button row) that makes it readable.</summary>
public readonly record struct ContrastPlan(ContrastTone Tone, ContrastColors Colors, double ScrimAlpha);

/// <summary>
/// Guaranteed Quick Access button contrast (port of the Mac v2.9.0 <c>QuickAccessContrast.swift</c>): for each
/// glyph tone solve, in closed form, the scrim alpha that lifts the glyph to <see cref="TargetContrastRatio"/>
/// against the WORST background in the band, pick the cheaper tone, clamp to [min, max].
/// </summary>
public static class QuickAccessContrast
{
    public const double TargetContrastRatio = 4.5;
    /// <summary>Aesthetic floor; keeps the familiar look on already-dark shots.</summary>
    public const double MinScrimAlpha = 0.18;
    /// <summary>Never fully hide the picture.</summary>
    public const double MaxScrimAlpha = 0.85;

    public static ContrastColors Palette(ContrastTone tone) => tone switch
    {
        ContrastTone.Dark => new ContrastColors(0xFF18181A, 0x24000000, 0x3D000000, ScrimIsWhite: true),
        _ => new ContrastColors(0xFFF4F4F6, 0x2BFFFFFF, 0x45FFFFFF, ScrimIsWhite: false),
    };

    /// <summary>Minimum scrim alpha so a background of luminance <paramref name="backgroundLuminance"/>, under a
    /// white/black scrim, reaches the target ratio against a glyph of luminance <paramref name="glyphLuminance"/>.
    /// 0 when already sufficient; <see cref="MaxScrimAlpha"/> when unreachable.</summary>
    public static double RequiredScrimAlpha(double backgroundLuminance, double glyphLuminance, bool scrimIsWhite)
    {
        // The scrim composites in gamma-encoded space, so solve there and treat the background as an
        // equivalent gray of that encoded value.
        double x = Srgb.Encode(backgroundLuminance);
        double alpha;
        if (scrimIsWhite)
        {
            // A white scrim serves a dark glyph: push the background UP past Lmin.
            double target = Srgb.Encode(TargetContrastRatio * (glyphLuminance + 0.05) - 0.05);
            if (target > 1) return MaxScrimAlpha; // even pure white isn't bright enough
            if (x >= 1) return 0;
            alpha = (target - x) / (1 - x);
        }
        else
        {
            // A black scrim serves a light glyph: push the background DOWN below Lmax.
            double limit = (glyphLuminance + 0.05) / TargetContrastRatio - 0.05;
            if (limit <= 0) return MaxScrimAlpha; // even pure black isn't dark enough
            if (x <= 0) return 0;
            alpha = 1 - Srgb.Encode(limit) / x;
        }
        return Math.Clamp(alpha, 0, MaxScrimAlpha);
    }

    /// <summary>Picks the tone that needs the LESS aggressive scrim over the whole band, so both the darkest and
    /// the brightest pixel behind the buttons stay readable. Ties go to light glyphs (the long-standing look).</summary>
    public static ContrastPlan Plan(BandExtremes extremes)
    {
        var light = Palette(ContrastTone.Light);
        var dark = Palette(ContrastTone.Dark);
        // Light glyphs are hurt by the brightest pixel, dark glyphs by the darkest.
        double aLight = RequiredScrimAlpha(extremes.Bright, Srgb.RelativeLuminance(light.GlyphArgb), light.ScrimIsWhite);
        double aDark = RequiredScrimAlpha(extremes.Dark, Srgb.RelativeLuminance(dark.GlyphArgb), dark.ScrimIsWhite);
        bool useLight = aLight <= aDark;
        double alpha = Math.Clamp(useLight ? aLight : aDark, MinScrimAlpha, MaxScrimAlpha);
        return new ContrastPlan(useLight ? ContrastTone.Light : ContrastTone.Dark, useLight ? light : dark, alpha);
    }
}
