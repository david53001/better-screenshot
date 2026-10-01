using BetterScreenshot.Core;

namespace BetterScreenshot.Tests;

/// <summary>Port of the Mac OverlayKit SRGB / BandLuminance / AspectFillMap / QuickAccessContrast tests (v2.9.0).</summary>
public class QuickAccessContrastTests
{
    private static byte[] HalfWhiteHalfBlack(int n)
    {
        var buf = new byte[n * 8];
        for (int i = 0; i < n * 4; i++) buf[i] = 255;
        for (int i = n; i < 2 * n; i++) buf[i * 4 + 3] = 255;
        return buf;
    }

    /// <summary>Luminance of <paramref name="bg"/> after the scrim is composited over it (gamma-encoded space).</summary>
    private static double Composited(double bg, bool scrimIsWhite, double alpha)
    {
        double x = Srgb.Encode(bg), s = scrimIsWhite ? 1.0 : 0.0;
        return Srgb.Expand(x * (1 - alpha) + s * alpha);
    }

    /// <summary>The plan lands ≥ 4.5:1 on BOTH ends of the band unless the alpha saturated.</summary>
    private static void AssertReadable(BandExtremes e)
    {
        var plan = QuickAccessContrast.Plan(e);
        if (plan.ScrimAlpha >= QuickAccessContrast.MaxScrimAlpha) return;
        double glyph = Srgb.RelativeLuminance(plan.Colors.GlyphArgb);
        foreach (var bg in new[] { e.Dark, e.Bright })
        {
            double ratio = Srgb.ContrastRatio(Composited(bg, plan.Colors.ScrimIsWhite, plan.ScrimAlpha), glyph);
            Assert.True(ratio >= 4.5 - 1e-6, $"bg {bg} of {e} gave {ratio}:1 at alpha {plan.ScrimAlpha}");
        }
    }

    // ---- sRGB / WCAG primitives

    [Theory]
    [InlineData(0.0)] [InlineData(0.002)] [InlineData(0.04045)] [InlineData(0.1)] [InlineData(0.5)] [InlineData(0.9)] [InlineData(1.0)]
    public void Srgb_expand_encode_round_trip(double c) => Assert.Equal(c, Srgb.Encode(Srgb.Expand(c)), 6);

    [Fact]
    public void Srgb_relative_luminance_endpoints()
    {
        Assert.Equal(1.0, Srgb.RelativeLuminance(255, 255, 255), 9);
        Assert.Equal(0.0, Srgb.RelativeLuminance(0, 0, 0), 9);
    }

    [Fact]
    public void Srgb_contrast_white_on_black_is_21_and_symmetric()
    {
        Assert.Equal(21.0, Srgb.ContrastRatio(1.0, 0.0), 9);
        Assert.Equal(Srgb.ContrastRatio(0.2, 0.7), Srgb.ContrastRatio(0.7, 0.2), 12);
        Assert.Equal(1.0, Srgb.ContrastRatio(0.4, 0.4), 12);
    }

    // ---- BandLuminance

    [Fact]
    public void Percentile_all_white_is_one_and_all_black_is_zero()
    {
        var white = Enumerable.Repeat((byte)255, 40).ToArray();
        var black = new byte[40];
        for (int i = 0; i < 10; i++) black[i * 4 + 3] = 255;
        foreach (var p in new[] { 0.0, 0.1, 0.5, 0.9, 1.0 })
        {
            Assert.Equal(1.0, BandLuminance.Percentile(white, 10, p), 9);
            Assert.Equal(0.0, BandLuminance.Percentile(black, 10, p), 9);
        }
    }

    [Fact]
    public void Percentile_bimodal_splits_low_and_high()
    {
        var buf = HalfWhiteHalfBlack(50);
        Assert.Equal(0.0, BandLuminance.Percentile(buf, 100, 0.10), 9);
        Assert.Equal(1.0, BandLuminance.Percentile(buf, 100, 0.90), 9);
    }

    [Fact]
    public void Percentile_empty_or_short_buffer_is_zero()
    {
        Assert.Equal(0.0, BandLuminance.Percentile(Array.Empty<byte>(), 0, 0.5), 9);
        Assert.Equal(0.0, BandLuminance.Percentile(Enumerable.Repeat((byte)255, 8).ToArray(), 4, 0.5), 9);
    }

    [Fact]
    public void Percentile_clamps_p_out_of_range()
    {
        var buf = HalfWhiteHalfBlack(50);
        Assert.Equal(0.0, BandLuminance.Percentile(buf, 100, -3), 9);
        Assert.Equal(1.0, BandLuminance.Percentile(buf, 100, 7), 9);
    }

    [Fact]
    public void Extremes_on_bimodal_band_sees_both_ends()
    {
        var e = BandLuminance.Extremes(HalfWhiteHalfBlack(50), 100);
        Assert.Equal(0.0, e.Dark, 9);
        Assert.Equal(1.0, e.Bright, 9);
    }

    [Fact]
    public void Percentile_reads_bgra_channel_order()
    {
        // Pure blue in BGRA = (255,0,0,255) → luminance 0.0722; pure red = (0,0,255,255) → 0.2126.
        Assert.Equal(0.0722, BandLuminance.Percentile(new byte[] { 255, 0, 0, 255 }, 1, 0.5), 4);
        Assert.Equal(0.2126, BandLuminance.Percentile(new byte[] { 0, 0, 255, 255 }, 1, 0.5), 4);
    }

    // ---- AspectFillMap

    [Fact]
    public void AspectFill_matching_aspect_is_pure_scale()
    {
        var r = AspectFillMap.SourceRect(new PxSize(200, 100), new PxSize(400, 200), new PxRect(0, 50, 200, 50));
        Assert.Equal(0, r.X, 9); Assert.Equal(100, r.Y, 9); Assert.Equal(400, r.Width, 9); Assert.Equal(100, r.Height, 9);
    }

    [Fact]
    public void AspectFill_wide_image_crops_sides()
    {
        var r = AspectFillMap.SourceRect(new PxSize(200, 200), new PxSize(400, 100), new PxRect(0, 0, 200, 200));
        Assert.Equal(150, r.X, 9); Assert.Equal(100, r.Width, 9); Assert.Equal(0, r.Y, 9); Assert.Equal(100, r.Height, 9);
    }

    [Fact]
    public void AspectFill_tall_image_crops_top_and_bottom()
    {
        var r = AspectFillMap.SourceRect(new PxSize(200, 200), new PxSize(100, 400), new PxRect(0, 0, 200, 200));
        Assert.Equal(150, r.Y, 9); Assert.Equal(100, r.Height, 9); Assert.Equal(0, r.X, 9); Assert.Equal(100, r.Width, 9);
    }

    [Fact]
    public void AspectFill_bottom_band_maps_to_bottom_of_image()
    {
        var r = AspectFillMap.SourceRect(new PxSize(200, 200), new PxSize(400, 400), new PxRect(0, 170, 200, 30));
        Assert.Equal(340, r.Y, 9); Assert.Equal(400, r.Bottom, 9); Assert.Equal(400, r.Width, 9);
    }

    [Fact]
    public void AspectFill_clamps_rect_outside_the_card()
    {
        var r = AspectFillMap.SourceRect(new PxSize(200, 200), new PxSize(200, 200), new PxRect(-50, 150, 300, 200));
        Assert.Equal(0, r.X, 9); Assert.Equal(200, r.Right, 9); Assert.Equal(150, r.Y, 9); Assert.Equal(200, r.Bottom, 9);
    }

    [Fact]
    public void AspectFill_degenerate_sizes_are_empty()
    {
        var unit = new PxRect(0, 0, 10, 10);
        Assert.True(AspectFillMap.SourceRect(new PxSize(0, 0), new PxSize(100, 100), unit).IsEmpty);
        Assert.True(AspectFillMap.SourceRect(new PxSize(100, 100), new PxSize(0, 0), unit).IsEmpty);
        Assert.True(AspectFillMap.SourceRect(new PxSize(100, 100), new PxSize(100, 100), default).IsEmpty);
    }

    // ---- Palette + guaranteed-contrast plan

    [Fact]
    public void Palette_for_tone()
    {
        var d = QuickAccessContrast.Palette(ContrastTone.Dark);
        Assert.Equal(0xFF18181Au, d.GlyphArgb); Assert.Equal(0x24000000u, d.HoverArgb);
        Assert.Equal(0x3D000000u, d.PressedArgb); Assert.True(d.ScrimIsWhite);
        var l = QuickAccessContrast.Palette(ContrastTone.Light);
        Assert.Equal(0xFFF4F4F6u, l.GlyphArgb); Assert.Equal(0x2BFFFFFFu, l.HoverArgb);
        Assert.Equal(0x45FFFFFFu, l.PressedArgb); Assert.False(l.ScrimIsWhite);
    }

    [Fact]
    public void Required_alpha_white_bg_under_light_glyph_is_about_056()
    {
        double glyph = Srgb.RelativeLuminance(QuickAccessContrast.Palette(ContrastTone.Light).GlyphArgb);
        Assert.InRange(QuickAccessContrast.RequiredScrimAlpha(1.0, glyph, scrimIsWhite: false), 0.55, 0.58);
        Assert.Equal(0.0, QuickAccessContrast.RequiredScrimAlpha(0.0, glyph, scrimIsWhite: false), 9);
    }

    [Fact]
    public void Required_alpha_black_bg_under_dark_glyph_is_about_050()
    {
        double glyph = Srgb.RelativeLuminance(QuickAccessContrast.Palette(ContrastTone.Dark).GlyphArgb);
        Assert.InRange(QuickAccessContrast.RequiredScrimAlpha(0.0, glyph, scrimIsWhite: true), 0.48, 0.52);
        Assert.Equal(0.0, QuickAccessContrast.RequiredScrimAlpha(1.0, glyph, scrimIsWhite: true), 9);
    }

    [Fact]
    public void Plan_keeps_light_glyphs_on_a_dark_band_with_min_alpha()
    {
        var plan = QuickAccessContrast.Plan(new BandExtremes(0.0, 0.03));
        Assert.Equal(ContrastTone.Light, plan.Tone);
        Assert.Equal(QuickAccessContrast.MinScrimAlpha, plan.ScrimAlpha, 9);
    }

    [Fact]
    public void Plan_uniform_white_band_picks_dark_glyph_with_min_alpha()
    {
        var plan = QuickAccessContrast.Plan(new BandExtremes(1.0, 1.0));
        Assert.Equal(ContrastTone.Dark, plan.Tone);
        Assert.Equal(QuickAccessContrast.MinScrimAlpha, plan.ScrimAlpha, 9);
    }

    [Theory]
    [InlineData(0.0, 0.0)] [InlineData(1.0, 1.0)] [InlineData(0.02, 1.0)] [InlineData(0.05, 0.20)]
    [InlineData(0.30, 0.50)] [InlineData(0.50, 0.90)]
    public void Plan_stays_within_alpha_bounds(double dark, double bright)
    {
        double a = QuickAccessContrast.Plan(new BandExtremes(dark, bright)).ScrimAlpha;
        Assert.InRange(a, QuickAccessContrast.MinScrimAlpha, QuickAccessContrast.MaxScrimAlpha);
    }

    [Theory]
    [InlineData(0.0, 0.0)] [InlineData(1.0, 1.0)] [InlineData(0.05, 0.20)] [InlineData(0.20, 0.80)]
    [InlineData(0.30, 0.50)] [InlineData(0.50, 0.90)]
    public void Plan_guarantees_contrast_across_bands(double dark, double bright) =>
        AssertReadable(new BandExtremes(dark, bright));

    [Fact]
    public void Plan_regression_starfield_with_white_headline()
    {
        // The measured Mac failure: near-black band + a white headline at button height (mean 0.201 → white
        // glyphs that vanished on the headline). The plan must hold 4.5:1 on both ends.
        AssertReadable(new BandExtremes(0.02, 1.0));
        Assert.True(QuickAccessContrast.Plan(new BandExtremes(0.02, 1.0)).ScrimAlpha > QuickAccessContrast.MinScrimAlpha);
    }
}
