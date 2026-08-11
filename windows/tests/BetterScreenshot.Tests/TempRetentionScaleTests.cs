using BetterScreenshot.Capture;
using Xunit;

namespace BetterScreenshot.Tests;

public class TempRetentionScaleTests
{
    [Fact]
    public void RangeIsFiveToThirtyMinutes()
    {
        Assert.Equal(5, TempRetentionScale.MinMinutes);
        Assert.Equal(30, TempRetentionScale.MaxMinutes);
        Assert.Equal(5, TempRetentionScale.DefaultMinutes); // default preserves the previous fixed 5-minute behavior
    }

    [Theory]
    [InlineData(5, 5)]
    [InlineData(17, 17)]
    [InlineData(30, 30)]
    [InlineData(4, 5)]      // below the bar's floor
    [InlineData(0, 5)]      // a missing/zero legacy value must never mean "delete immediately"
    [InlineData(-9, 5)]
    [InlineData(31, 30)]    // above the bar's ceiling
    [InlineData(600, 30)]
    public void ClampKeepsValuesInRange(int minutes, int expected)
    {
        Assert.Equal(expected, TempRetentionScale.Clamp(minutes));
    }

    [Theory]
    [InlineData(5.0, 5)]
    [InlineData(12.0, 12)]
    [InlineData(30.0, 30)]
    [InlineData(12.4, 12)]  // slider positions are doubles; round to the nearest whole minute
    [InlineData(12.5, 13)]
    [InlineData(29.6, 30)]
    [InlineData(3.2, 5)]    // and clamp, so a coerced slider value can't escape the range
    [InlineData(44.0, 30)]
    public void PositionToMinutesRoundsAndClamps(double position, int expected)
    {
        Assert.Equal(expected, TempRetentionScale.PositionToMinutes(position));
    }

    [Theory]
    [InlineData(5, "5 min")]
    [InlineData(17, "17 min")]
    [InlineData(30, "30 min")]
    [InlineData(99, "30 min")] // the readout can never claim a retention the app won't honor
    public void LabelReadsAsMinutes(int minutes, string expected)
    {
        Assert.Equal(expected, TempRetentionScale.Label(minutes));
    }

    [Theory]
    [InlineData(5)]
    [InlineData(6)]
    [InlineData(19)]
    [InlineData(30)]
    public void SliderRoundTripIsLossless(int minutes)
    {
        // What the slider shows for a persisted value must persist back to that same value.
        Assert.Equal(minutes, TempRetentionScale.PositionToMinutes(minutes));
    }
}
