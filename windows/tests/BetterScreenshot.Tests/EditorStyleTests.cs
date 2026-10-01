using BetterScreenshot.Editor;
using Xunit;

namespace BetterScreenshot.Tests;

public class EditorStyleTests
{
    [Fact]
    public void ColorComponentsAndAlpha()
    {
        var c = new RGBAColor(1.0, 0.5, 0.25, 1.0);
        Assert.Equal(1.0, c.R);
        Assert.Equal(0.5, c.G);
        Assert.Equal(0.25, c.B);
        Assert.Equal(0.25, c.WithAlpha(0.25).A);
        Assert.Equal(new RGBAColor(1, 1, 1, 1), RGBAColor.FromBytes(255, 255, 255));
    }

    [Fact]
    public void DefaultRedIsThePresetRedSwatch()
    {
        var d = AnnotationStyle.Default;
        Assert.Equal(new RGBAColor(1.0, 0.27, 0.23, 1.0), d.StrokeColor);
        Assert.Equal(ColorPresets.Swatches[0].Color, d.StrokeColor);
        Assert.Equal(0.25, d.FillColor.A);
        Assert.Equal(4, d.LineWidth);
        Assert.Equal(24, d.FontSize);
    }

    private const string Base = "{\"strokeColor\":{\"r\":1,\"g\":1,\"b\":1,\"a\":1},\"fillColor\":{\"r\":1,\"g\":1,\"b\":1,\"a\":0.25},\"lineWidth\":4,\"fontSize\":24";

    [Fact]
    public void OldDefaultRedDecodesAsThePresetRed()
    {
        const string legacy = "{\"strokeColor\":{\"r\":1,\"g\":0.23,\"b\":0.19,\"a\":1},\"fillColor\":{\"r\":1,\"g\":0.23,\"b\":0.19,\"a\":0.25},\"lineWidth\":4,\"fontSize\":24}";
        var s = AnnotationStyle.FromJson(legacy);
        Assert.Equal(AnnotationStyle.DefaultRed, s.StrokeColor);
        Assert.Equal(AnnotationStyle.DefaultRed.WithAlpha(0.25), s.FillColor);
    }

    [Fact]
    public void RoundTripsThroughJson()
    {
        var s = AnnotationStyle.Default with { StrokeColor = new RGBAColor(0.04, 0.52, 1.0, 1.0), LineWidth = 7, FontSize = 36 };
        Assert.Equal(s, AnnotationStyle.FromJson(s.ToJson()));
    }

    [Fact]
    public void LegacyStyleDecodesEveryNewFieldToItsDefault()
    {
        var s = AnnotationStyle.FromJson(Base + "}");
        Assert.Equal(TextFont.System, s.FontFamily);
        Assert.True(s.FontBold);
        Assert.False(s.FontItalic);
        Assert.Equal(TextAlign.Left, s.TextAlignment);
        Assert.Equal(1, s.Opacity);
        Assert.Equal(TextBackgroundMode.None, s.TextBackgroundMode);
        Assert.Equal(RedactionMode.Blur, s.RedactionMode);
        Assert.Equal(12, s.BlurRadius);
        Assert.Equal(12, s.PixelSize);
        Assert.Equal(HighlighterPen.Default, s.HighlighterPen);
        Assert.Equal(SpotlightShape.Rectangle, s.SpotlightShape);
        Assert.Equal(0.6, s.SpotlightDim);
    }

    [Fact]
    public void LegacyWindowsTextChipMapsToAuto()
    {
        var chip = AnnotationStyle.FromJson(Base + ",\"textBackground\":{\"r\":0,\"g\":0,\"b\":0,\"a\":0.6}}");
        Assert.Equal(TextBackgroundMode.Auto, chip.TextBackgroundMode);
        Assert.Equal(new RGBAColor(0, 0, 0, 0.8), chip.TextBackgroundColor);
        Assert.Equal(TextBackgroundMode.Auto, AnnotationStyle.FromJson(Base + ",\"textBackground\":true}").TextBackgroundMode);
        Assert.Equal(TextBackgroundMode.None, AnnotationStyle.FromJson(Base + ",\"textBackground\":false}").TextBackgroundMode);
    }

    [Fact]
    public void BackgroundModeWinsOverTheLegacyBool_unknownModeFallsBack()
    {
        string J(string mode) => Base + ",\"textBackground\":true,\"textBackgroundMode\":\"" + mode + "\"}";
        Assert.Equal(TextBackgroundMode.Solid, AnnotationStyle.FromJson(J("solid")).TextBackgroundMode);
        Assert.Equal(TextBackgroundMode.None, AnnotationStyle.FromJson(J("none")).TextBackgroundMode);
        Assert.Equal(TextBackgroundMode.Auto, AnnotationStyle.FromJson(J("sparkly")).TextBackgroundMode);
    }

    [Fact]
    public void EveryFieldRoundTrips()
    {
        var s = AnnotationStyle.Default with
        {
            FontFamily = "Georgia", FontBold = false, FontItalic = true, TextAlignment = TextAlign.Right, Opacity = 0.5,
            TextBackgroundMode = TextBackgroundMode.Solid, TextBackgroundColor = new RGBAColor(0.1, 0.2, 0.3, 0.4),
            TextBackgroundPadding = 12, TextBackgroundCornerRadius = 9, TextUnderline = true, TextStrikethrough = true,
            TextOutline = true, TextOutlineColor = new RGBAColor(0, 0, 0, 1), TextOutlineWidth = 5, TextShadow = true,
            RedactionMode = RedactionMode.Blackout, BlurRadius = 30, PixelSize = 20,
            HighlighterPen = new HighlighterPen(new RGBAColor(0, 1, 0, 1), 32, 0.7), SpotlightShape = SpotlightShape.Ellipse, SpotlightDim = 0.3,
        };
        Assert.Equal(s, AnnotationStyle.FromJson(s.ToJson()));
    }

    [Fact]
    public void DecodeClampsRangedFieldsAndUnknownEnums()
    {
        var s = AnnotationStyle.FromJson(Base + ",\"opacity\":0,\"textBackgroundPadding\":-5,\"textBackgroundCornerRadius\":999," +
            "\"textOutlineWidth\":0,\"blurRadius\":500,\"pixelSize\":0,\"redactionMode\":\"smudge\",\"spotlightDim\":1," +
            "\"highlighterPen\":{\"color\":{\"r\":1,\"g\":1,\"b\":0,\"a\":1},\"width\":100,\"opacity\":0}}");
        Assert.Equal(0.1, s.Opacity);
        Assert.Equal(0, s.TextBackgroundPadding);
        Assert.Equal(40, s.TextBackgroundCornerRadius);
        Assert.Equal(1, s.TextOutlineWidth);
        Assert.Equal(40, s.BlurRadius);
        Assert.Equal(4, s.PixelSize);
        Assert.Equal(RedactionMode.Blur, s.RedactionMode);
        Assert.Equal(0.9, s.SpotlightDim);
        Assert.Equal(48, s.HighlighterPen.Width);
        Assert.Equal(0.1, s.HighlighterPen.Opacity);
    }
}
