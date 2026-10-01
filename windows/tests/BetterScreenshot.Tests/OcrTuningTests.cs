using BetterScreenshot.Capture;

namespace BetterScreenshot.Tests;

/// <summary>Port of the Mac TextRecognizerTests language + upscale cases (v2.10.0).</summary>
public class OcrTuningTests
{
    private static readonly string[] Supported = { "en-US", "fr-FR", "ro-RO", "de-DE" };

    [Fact]
    public void Languages_map_preferred_onto_supported()
    {
        Assert.Equal(new[] { "en-US", "ro-RO" }, OcrTuning.RecognitionLanguages(new[] { "en-RO", "ro-RO" }, Supported));
        // Unsupported languages drop; duplicates collapse; order is kept.
        Assert.Equal(new[] { "fr-FR", "en-US" }, OcrTuning.RecognitionLanguages(new[] { "hu-HU", "fr-CA", "en-GB", "en-US" }, Supported));
    }

    [Fact]
    public void Languages_fall_back_to_english()
    {
        Assert.Equal(new[] { "en-US" }, OcrTuning.RecognitionLanguages(new[] { "hu-HU" }, new[] { "en-US", "fr-FR" }));
        Assert.Equal(new[] { "en-US" }, OcrTuning.RecognitionLanguages(Array.Empty<string>(), new[] { "en-US" }));
    }

    [Fact]
    public void Exact_tag_wins_over_same_code()
    {
        Assert.Equal(new[] { "en-GB" }, OcrTuning.RecognitionLanguages(new[] { "en-GB" }, new[] { "en-US", "en-GB" }));
    }

    [Theory]
    [InlineData(800, 400, 1)]       // 2x: untouched
    [InlineData(1600, 400, 1)]      // denser than 2x: untouched
    [InlineData(400, 400, 2)]       // 1x display
    [InlineData(600, 400, 4.0 / 3)] // 1.5x
    [InlineData(400, 0, 1)]         // degenerate
    public void Upscale_factor_brings_density_to_two(int px, double dip, double expected) =>
        Assert.Equal(expected, OcrTuning.UpscaleFactor(px, dip), 9);

    [Theory]
    [InlineData(2, 1000, 500, 10000, 2)]
    [InlineData(2, 6000, 500, 10000, 10000.0 / 6000)]
    [InlineData(2, 12000, 500, 10000, 1)]
    public void Upscale_is_clamped_to_the_engine_limit(double f, int w, int h, int max, double expected) =>
        Assert.Equal(expected, OcrTuning.ClampToMaxDimension(f, w, h, max), 9);
}
