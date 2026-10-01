using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>v3 §4.9 Opacity setting + Part 9 surfaces: the stored value, the curve, and the contrast contract.</summary>
public class UiOpacityTests
{
    [Fact]
    public void SettingDefaultsRoundTripsAndClamps()
    {
        Assert.Equal(0.5, CaptureSettings.Default.UiOpacity);
        var d = (CaptureSettings.Default with { UiOpacity = 0.25 }).ToDictionary();
        Assert.Equal("0.25", d["uiOpacity"]);
        Assert.Equal(0.25, CaptureSettings.FromDictionary(d).UiOpacity);
        Assert.Equal(1, CaptureSettings.FromDictionary(new Dictionary<string, string> { ["uiOpacity"] = "7" }).UiOpacity);
        Assert.Equal(0, CaptureSettings.FromDictionary(new Dictionary<string, string> { ["uiOpacity"] = "-2" }).UiOpacity);
        Assert.Equal(0.5, CaptureSettings.FromDictionary(new Dictionary<string, string> { ["uiOpacity"] = "junk" }).UiOpacity);
        Assert.Equal(0.5, CaptureSettings.FromDictionary(new Dictionary<string, string> { ["uiOpacity"] = "NaN" }).UiOpacity);
        Assert.Equal(0.5, CaptureSettings.FromDictionary(new Dictionary<string, string>()).UiOpacity);
    }

    [Fact]
    public void CurveHitsItsAnchors()
    {
        Assert.Equal(0.15, UiOpacity.WindowLayerAlpha(0), 6);
        Assert.Equal(0.52, UiOpacity.WindowLayerAlpha(0.5), 6);
        Assert.Equal(1.0, UiOpacity.WindowLayerAlpha(1), 6);
        Assert.Equal(0.335, UiOpacity.WindowLayerAlpha(0.25), 6); // linear between anchors
        Assert.Equal(0.04, UiOpacity.CardFillAlpha(0.5), 6);
        Assert.Equal(0.03, UiOpacity.CardFillAlpha(-1), 6);
        Assert.Equal(0.05, UiOpacity.CardFillAlpha(9), 6);
        Assert.Equal(0.85, UiOpacity.PanelAlpha(0.5), 6);
        Assert.Equal(UiOpacity.HudAlpha(0.5), UiOpacity.HudAlpha(double.NaN), 6);
        Assert.True(UiOpacity.HudIsSolid(1));
        Assert.False(UiOpacity.HudIsSolid(0.99));
    }

    /// <summary>The contract (the ratios, not the Mac alphas): white HUD text over a white page ≥ 4.5:1 at the default
    /// (80 %-white secondary ≥ 3:1) and ≥ 3:1 at Transparent; solid at Opaque.</summary>
    [Fact]
    public void HudTextMeetsTheContrastContract()
    {
        Assert.True(UiOpacity.HudTextContrast(0.5) >= 4.5);
        Assert.True(UiOpacity.HudTextContrast(0.5, textAlpha: 0.8) >= 3);
        Assert.True(UiOpacity.HudTextContrast(0) >= 3);
        Assert.True(UiOpacity.HudTextContrast(1) >= 12);
        Assert.True(UiOpacity.HudTextContrast(0, backdropLuminance: 0) >= 12); // over a black page it's dark anyway
        for (double v = 0; v <= 1.0001; v += 0.05) Assert.True(UiOpacity.HudTextContrast(v) >= 3, $"at {v}");
    }
}
