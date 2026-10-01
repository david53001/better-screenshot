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
        Assert.Equal(300, d.TempRetentionSeconds);
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
            TempRetentionSeconds = 1800,
        };
        var round = CaptureSettings.FromDictionary(s.ToDictionary());
        Assert.Equal(s, round);
    }

    [Theory]
    [InlineData("tempRetentionSeconds", "0", 0)]        // ∞
    [InlineData("tempRetentionSeconds", "45", 30)]      // a hand-edited value snaps to a stop
    [InlineData("tempRetentionSeconds", "oops", 300)]   // unparseable → the default
    [InlineData("tempRetentionMinutes", "5", 300)]      // a settings.json from the old 5–30 minute bar
    [InlineData("tempRetentionMinutes", "12", 600)]
    [InlineData("tempRetentionMinutes", "30", 1800)]
    public void TempRetentionIsReadOntoAStop(string key, string persisted, int expected)
    {
        var round = CaptureSettings.FromDictionary(new Dictionary<string, string> { [key] = persisted });
        Assert.Equal(expected, round.TempRetentionSeconds);
    }

    [Fact]
    public void TheNewKeyWinsOverTheLegacyOne()
    {
        var round = CaptureSettings.FromDictionary(new Dictionary<string, string>
        {
            ["tempRetentionMinutes"] = "30", ["tempRetentionSeconds"] = "10",
        });
        Assert.Equal(10, round.TempRetentionSeconds);
        Assert.DoesNotContain("tempRetentionMinutes", round.ToDictionary().Keys);
    }

    [Fact]
    public void UnknownKeysFallBackToDefaults()
    {
        var round = CaptureSettings.FromDictionary(new Dictionary<string, string>());
        Assert.Equal(CaptureSettings.Default, round);
    }
}
