using BetterScreenshot.Core;

namespace BetterScreenshot.Capture;

/// <summary>Pure math for the area-selection overlay: normalize two drag points and map window DIPs to physical pixels.</summary>
public static class SelectionMath
{
    /// <summary>Smallest positive rect spanning two points.</summary>
    public static PxRect Normalize(PxPoint a, PxPoint b) =>
        PxRect.FromLtrb(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Max(a.X, b.X), Math.Max(a.Y, b.Y));

    /// <summary>
    /// Clamps a rect to the box [0,width] × [0,height] — the "physical wall" for a drag that runs past the edge
    /// (mouse capture keeps delivering points outside the window). Keeps the selection inside the screen/image so
    /// a capture can never spill off it. Returns a zero-size rect if the input is entirely outside the box.
    /// </summary>
    public static PxRect ClampToBounds(PxRect rect, double width, double height)
    {
        double left = Math.Clamp(rect.X, 0, width);
        double top = Math.Clamp(rect.Y, 0, height);
        double right = Math.Clamp(rect.Right, 0, width);
        double bottom = Math.Clamp(rect.Bottom, 0, height);
        return PxRect.FromLtrb(left, top, right, bottom);
    }

    /// <summary>
    /// Convert a selection rect in window DIP coordinates to physical screen pixels, given the window's monitor
    /// physical bounds (top-left origin) and DPI scale (physical = logical × scale).
    /// </summary>
    public static PxRect DipToPhysical(PxRect dipRect, PxRect monitorPhysical, double dpiScale) =>
        new(monitorPhysical.X + dipRect.X * dpiScale,
            monitorPhysical.Y + dipRect.Y * dpiScale,
            dipRect.Width * dpiScale,
            dipRect.Height * dpiScale);

    /// <summary>
    /// Maps an absolute physical-pixel rect onto a frozen still of one monitor: subtracts the monitor origin
    /// (the still's pixel (0,0) is the monitor's top-left), rounds to whole pixels the same way a live BitBlt
    /// capture does, and clamps to the still's size — the still can be *smaller* than the monitor's reported
    /// bounds when a game or a "stretched" resolution leaves the real framebuffer short. Returns null when
    /// nothing of the rect lands inside the still; the caller should then capture the live screen instead.
    /// </summary>
    public static PxRect? ToSnapshotRect(PxRect physical, PxRect monitorBounds, PxSize snapshotSize)
    {
        var local = new PxRect(
            Math.Round(physical.X - monitorBounds.X),
            Math.Round(physical.Y - monitorBounds.Y),
            Math.Round(physical.Width),
            Math.Round(physical.Height));
        var clamped = ClampToBounds(local, snapshotSize.Width, snapshotSize.Height);
        return clamped.IsEmpty ? null : clamped;
    }
}
