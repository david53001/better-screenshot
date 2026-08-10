using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using Xunit;

namespace BetterScreenshot.Tests;

public class SelectionMathTests
{
    [Fact]
    public void NormalizeHandlesAnyDragDirection()
    {
        Assert.Equal(new PxRect(10, 20, 40, 30), SelectionMath.Normalize(new PxPoint(50, 50), new PxPoint(10, 20)));
    }

    [Fact]
    public void DipToPhysicalOnPrimaryAt100Percent()
    {
        var phys = SelectionMath.DipToPhysical(new PxRect(10, 20, 100, 50), new PxRect(0, 0, 1920, 1080), 1.0);
        Assert.Equal(new PxRect(10, 20, 100, 50), phys);
    }

    [Fact]
    public void DipToPhysicalOnScaledSecondaryMonitor()
    {
        // Secondary monitor at physical (1920,0), 150% scale.
        var phys = SelectionMath.DipToPhysical(new PxRect(10, 20, 100, 50), new PxRect(1920, 0, 2560, 1440), 1.5);
        Assert.Equal(new PxRect(1920 + 15, 30, 150, 75), phys);
    }

    [Fact]
    public void ClampToBoundsLeavesAnInsideRectUntouched()
    {
        Assert.Equal(new PxRect(10, 20, 100, 50), SelectionMath.ClampToBounds(new PxRect(10, 20, 100, 50), 1500, 1080));
    }

    [Fact]
    public void ClampToBoundsTrimsARectThatRunsPastTheRightAndBottomEdges()
    {
        // A drag that runs off the bottom-right of a 1500×1080 screen is trimmed to the edge.
        var clamped = SelectionMath.ClampToBounds(new PxRect(1400, 1000, 400, 300), 1500, 1080);
        Assert.Equal(new PxRect(1400, 1000, 100, 80), clamped);
    }

    [Fact]
    public void ClampToBoundsTrimsNegativeOrigin()
    {
        // Dragging up-and-left past the top-left corner clamps the origin to (0,0).
        var clamped = SelectionMath.ClampToBounds(PxRect.FromLtrb(-50, -30, 200, 100), 1500, 1080);
        Assert.Equal(new PxRect(0, 0, 200, 100), clamped);
    }

    [Fact]
    public void ToSnapshotRectOnThePrimaryMonitorIsTheRectItself()
    {
        var r = SelectionMath.ToSnapshotRect(new PxRect(10, 20, 100, 50), new PxRect(0, 0, 1920, 1080), new PxSize(1920, 1080));
        Assert.Equal(new PxRect(10, 20, 100, 50), r);
    }

    [Fact]
    public void ToSnapshotRectSubtractsTheMonitorOrigin()
    {
        // A selection on the secondary monitor at physical (1920,0) is image-local (10,20) in that monitor's still.
        var r = SelectionMath.ToSnapshotRect(new PxRect(1930, 20, 100, 50), new PxRect(1920, 0, 2560, 1440), new PxSize(2560, 1440));
        Assert.Equal(new PxRect(10, 20, 100, 50), r);
    }

    [Fact]
    public void ToSnapshotRectRoundsFractionalDipConversions()
    {
        // DIP→physical at 150% yields fractions; the crop rounds them exactly like a live BitBlt capture does
        // (Math.Round), so a frozen crop and a live grab of the same selection come out the same size.
        var r = SelectionMath.ToSnapshotRect(new PxRect(10.4, 20.6, 100.6, 50.4), new PxRect(0, 0, 1920, 1080), new PxSize(1920, 1080));
        Assert.Equal(new PxRect(10, 21, 101, 50), r);
    }

    [Fact]
    public void ToSnapshotRectClampsToAStillShorterThanTheReportedBounds()
    {
        // Stretched-resolution rig: the monitor reports 1920×1080 but the real framebuffer (and so the still)
        // is 1600×900 — a selection running past it is trimmed rather than reading outside the image.
        var r = SelectionMath.ToSnapshotRect(new PxRect(1500, 800, 300, 200), new PxRect(0, 0, 1920, 1080), new PxSize(1600, 900));
        Assert.Equal(new PxRect(1500, 800, 100, 100), r);
    }

    [Fact]
    public void ToSnapshotRectIsNullWhenTheRectMissesTheStillEntirely()
    {
        Assert.Null(SelectionMath.ToSnapshotRect(new PxRect(1700, 950, 200, 100), new PxRect(0, 0, 1920, 1080), new PxSize(1600, 900)));
    }
}
