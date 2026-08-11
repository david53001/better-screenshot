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
        Assert.Equal(5, d.TempRetentionMinutes);
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
            TempRetentionMinutes = 22,
        };
        var round = CaptureSettings.FromDictionary(s.ToDictionary());
        Assert.Equal(s, round);
    }

    [Theory]
    [InlineData("0", 5)]     // a zero/blank legacy value must not mean "delete the temp copy instantly"
    [InlineData("1", 5)]
    [InlineData("45", 30)]   // nor can a hand-edited settings.json leave temp files around past the 30-min end
    [InlineData("oops", 5)]  // unparseable → the default
    public void TempRetentionMinutesIsClampedOnRead(string persisted, int expected)
    {
        var round = CaptureSettings.FromDictionary(new Dictionary<string, string> { ["tempRetentionMinutes"] = persisted });
        Assert.Equal(expected, round.TempRetentionMinutes);
    }

    [Fact]
    public void UnknownKeysFallBackToDefaults()
    {
        var round = CaptureSettings.FromDictionary(new Dictionary<string, string>());
        Assert.Equal(CaptureSettings.Default, round);
    }
}
