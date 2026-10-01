using BetterScreenshot.Core;
using Xunit;

namespace BetterScreenshot.Tests;

/// <summary>v3 "Window placement": exactly centred under the pointer, shrunk to fit, reopen as last closed.</summary>
public class WindowPlacementRulesTests
{
    private static readonly PxRect Visible = new(0, 0, 1920, 1032);   // a 1080p screen minus the taskbar
    private static readonly PxRect Second = new(1920, 0, 2560, 1400); // a monitor to the right

    [Fact]
    public void Centred_exactly_in_the_visible_area()
    {
        Assert.Equal(new PxRect(560, 216, 800, 600), WindowPlacementRules.Centred(new PxSize(800, 600), Visible));
        Assert.Equal(new PxRect(2800, 400, 800, 600), WindowPlacementRules.Centred(new PxSize(800, 600), Second));
    }

    [Fact]
    public void A_window_bigger_than_the_screen_is_shrunk_to_fit() =>
        Assert.Equal(new PxRect(0, 0, 1920, 1032), WindowPlacementRules.Centred(new PxSize(2400, 1400), Visible));

    [Fact]
    public void Nothing_remembered_opens_at_the_default_size()
    {
        var (frame, max) = WindowPlacementRules.Opening(null, new PxSize(760, 540), new PxSize(660, 360), Visible);
        Assert.Equal(new PxRect(580, 246, 760, 540), frame);
        Assert.False(max);
    }

    [Fact]
    public void A_remembered_size_reopens_centred_and_never_below_the_minimum()
    {
        var memo = new WindowPlacementMemo(1000, 700, WindowPlacementMode.Normal);
        Assert.Equal((new PxRect(460, 166, 1000, 700), false), WindowPlacementRules.Opening(memo, new PxSize(760, 540), new PxSize(660, 360), Visible));
        var tiny = new WindowPlacementMemo(300, 200, WindowPlacementMode.Normal);
        Assert.Equal(new PxSize(660, 360), WindowPlacementRules.Opening(tiny, new PxSize(760, 540), new PxSize(660, 360), Visible).Frame.Size);
    }

    [Fact]
    public void A_remembered_size_is_centred_on_whichever_screen_it_opens_on() =>
        Assert.Equal(new PxRect(2700, 350, 1000, 700),
            WindowPlacementRules.Opening(new WindowPlacementMemo(1000, 700, WindowPlacementMode.Normal), new PxSize(1, 1), new PxSize(1, 1), Second).Frame);

    [Theory]
    [InlineData(WindowPlacementMode.Fill)]
    [InlineData(WindowPlacementMode.FullScreen)]
    public void Fill_and_full_screen_reopen_maximised_restoring_to_the_centred_size(WindowPlacementMode mode)
    {
        var (frame, max) = WindowPlacementRules.Opening(new WindowPlacementMemo(1000, 700, mode), new PxSize(760, 540), new PxSize(660, 360), Visible);
        Assert.True(max);
        Assert.Equal(new PxRect(460, 166, 1000, 700), frame);
    }

    [Fact]
    public void Closing_maximised_remembers_the_restore_size_as_fill() =>
        Assert.Equal(new WindowPlacementMemo(900, 650, WindowPlacementMode.Fill),
            WindowPlacementRules.Memo(new PxSize(1920, 1032), new PxSize(900, 650), isMaximized: true, Visible));

    [Fact]
    public void Closing_dragged_to_the_edges_counts_as_fill()
    {
        Assert.Equal(WindowPlacementMode.Fill, WindowPlacementRules.Memo(new PxSize(1914, 1026), new PxSize(1914, 1026), false, Visible).Mode);
        Assert.Equal(WindowPlacementMode.Normal, WindowPlacementRules.Memo(new PxSize(1900, 1026), new PxSize(1900, 1026), false, Visible).Mode);
    }

    [Fact]
    public void Closing_at_a_size_remembers_it() =>
        Assert.Equal(new WindowPlacementMemo(1000, 700, WindowPlacementMode.Normal),
            WindowPlacementRules.Memo(new PxSize(1000, 700), new PxSize(1000, 700), false, Visible));

    [Fact]
    public void A_bad_memo_falls_back_to_the_default() =>
        Assert.Equal(new PxSize(760, 540),
            WindowPlacementRules.Opening(new WindowPlacementMemo(0, -1, WindowPlacementMode.Normal), new PxSize(760, 540), new PxSize(660, 360), Visible).Frame.Size);
}
