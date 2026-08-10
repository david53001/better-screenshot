using BetterScreenshot.Capture;
using Xunit;

namespace BetterScreenshot.Tests;

public class CaptureSettingsTests
{
    [Fact]
    public void Defaults()
    {
        var d = CaptureSettings.Default;
        Assert.Equal(AfterCaptureBehavior.ShowOverlay, d.AfterCapture);
        Assert.Equal(SettingsImageFormat.Png, d.Format);
        Assert.Equal(SettingsOverlayCorner.BottomRight, d.OverlayCorner);
        Assert.Equal(6, d.OverlayAutoDismissSeconds);
        Assert.Equal(8, d.PinCornerRadius);
        Assert.True(d.PinShadow);
        Assert.True(d.HistoryEnabled);
        Assert.Equal(50, d.HistoryCap);
        Assert.True(d.FreezeScreen);
    }

    [Fact]
    public void RoundTripsAllFields()
    {
        var s = CaptureSettings.Default with
        {
            AfterCapture = AfterCaptureBehavior.CopyAndSave,
            Format = SettingsImageFormat.Jpg,
            OverlayCorner = SettingsOverlayCorner.TopLeft,
            OverlayAutoDismissSeconds = 12,
            PinCornerRadius = 3,
            PinShadow = false,
            HistoryEnabled = false,
            HistoryCap = 200,
            FreezeScreen = false,
        };
        var round = CaptureSettings.FromDictionary(s.ToDictionary());
        Assert.Equal(s, round);
    }

    [Fact]
    public void UnknownKeysFallBackToDefaults()
    {
        var round = CaptureSettings.FromDictionary(new Dictionary<string, string>());
        Assert.Equal(CaptureSettings.Default, round);
    }
}
