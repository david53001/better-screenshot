using BetterScreenshot.Capture;
using Xunit;

namespace BetterScreenshot.Tests;

public class OverlayDismissScaleTests
{
    [Theory]
    [InlineData(0, 31)]    // Never (persisted as 0) -> the far ("Never") end of the bar
    [InlineData(-5, 31)]   // any non-positive value is treated as Never
    [InlineData(6, 6)]     // default
    [InlineData(10, 10)]
    [InlineData(2, 2)]     // min finite
    [InlineData(30, 30)]   // max finite
    [InlineData(1, 2)]     // below min clamps up
    [InlineData(100, 30)]  // above max clamps down
    public void SecondsToPosition_maps_and_clamps(int seconds, int expectedPosition) =>
        Assert.Equal(expectedPosition, OverlayDismissScale.SecondsToPosition(seconds));

    [Theory]
    [InlineData(31, 0)]    // far end -> Never
    [InlineData(31.4, 0)]  // anything at/after the Never stop -> Never
    [InlineData(6, 6)]
    [InlineData(2, 2)]
    [InlineData(30, 30)]
    [InlineData(2.4, 2)]   // rounds to the nearest whole second
    [InlineData(29.6, 30)]
    [InlineData(1, 2)]     // below min clamps up (defensive; the slider never goes here)
    public void PositionToSeconds_maps_rounds_and_clamps(double position, int expectedSeconds) =>
        Assert.Equal(expectedSeconds, OverlayDismissScale.PositionToSeconds(position));

    [Theory]
    [InlineData(0, "∞")]
    [InlineData(-1, "∞")]
    [InlineData(6, "6s")]
    [InlineData(30, "30s")]
    public void Label_reads_never_or_seconds(int seconds, string expected) =>
        Assert.Equal(expected, OverlayDismissScale.Label(seconds));

    [Theory]
    [InlineData(0)]  // Never survives a position round-trip
    [InlineData(2)]
    [InlineData(6)]
    [InlineData(10)]
    [InlineData(30)]
    public void RoundTrips_through_position(int seconds) =>
        Assert.Equal(seconds, OverlayDismissScale.PositionToSeconds(OverlayDismissScale.SecondsToPosition(seconds)));
}
