using BetterScreenshot.Capture;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>v3 §4.2: the Mac's "Keep cached files for" stops — 10 s · 30 s · 5 min · 10 min · 30 min · 1 hour · ∞.</summary>
public class TempRetentionScaleTests
{
    [Fact]
    public void TheMacStops()
    {
        Assert.Equal(new[] { 10, 30, 300, 600, 1800, 3600, 0 }, TempRetentionScale.StopsSeconds);
        Assert.Equal(300, TempRetentionScale.DefaultSeconds); // the old fixed 5 minutes
        Assert.Equal(0, TempRetentionScale.NeverSeconds);
        Assert.Equal(6, TempRetentionScale.MaxPosition);
    }

    [Theory]
    [InlineData(0, 10, "10 s")]
    [InlineData(1, 30, "30 s")]
    [InlineData(2, 300, "5 min")]
    [InlineData(3, 600, "10 min")]
    [InlineData(4, 1800, "30 min")]
    [InlineData(5, 3600, "1 hour")]
    [InlineData(6, 0, "∞")]
    public void PositionsSecondsAndLabelsRoundTrip(int position, int seconds, string label)
    {
        Assert.Equal(seconds, TempRetentionScale.PositionToSeconds(position));
        Assert.Equal(position, TempRetentionScale.SecondsToPosition(seconds));
        Assert.Equal(label, TempRetentionScale.Label(seconds));
    }

    [Theory]
    [InlineData(-1.2, 10)]  // off the ends clamps
    [InlineData(9, 0)]
    [InlineData(2.4, 300)]  // a dragged thumb snaps to the nearest stop
    [InlineData(2.6, 600)]
    public void PositionsClampAndRound(double position, int seconds) =>
        Assert.Equal(seconds, TempRetentionScale.PositionToSeconds(position));

    [Theory]
    [InlineData(0, 0)]       // ∞ stays ∞
    [InlineData(-5, 300)]    // nonsense → default
    [InlineData(1, 10)]      // hand-edited values snap to the nearest stop
    [InlineData(45, 30)]
    [InlineData(250, 300)]
    [InlineData(7200, 3600)]
    public void StoredValuesSnapToAStop(int stored, int expected) =>
        Assert.Equal(expected, TempRetentionScale.Normalize(stored));

    [Theory]
    [InlineData(5, 300)]     // the old Windows 5–30 minute bar → the nearest stop
    [InlineData(7, 300)]
    [InlineData(12, 600)]
    [InlineData(22, 1800)]
    [InlineData(30, 1800)]
    [InlineData(0, 300)]
    public void LegacyMinutesMapToTheNearestStop(int minutes, int seconds) =>
        Assert.Equal(seconds, TempRetentionScale.FromLegacyMinutes(minutes));

    [Fact]
    public void LifetimeIsNullForInfinity()
    {
        Assert.Null(TempRetentionScale.Lifetime(0));
        Assert.Equal(TimeSpan.FromMinutes(5), TempRetentionScale.Lifetime(300));
        Assert.Equal(TimeSpan.FromSeconds(10), TempRetentionScale.Lifetime(10));
    }
}
