namespace BetterScreenshot.Core;

/// <summary>How a resizable window was last closed (v3 "Window placement"): at a size, covering the whole visible
/// screen, or full screen (macOS green button). Windows maps both <see cref="Fill"/> and <see cref="FullScreen"/> to a
/// maximised window.</summary>
public enum WindowPlacementMode { Normal, Fill, FullScreen }

/// <summary>What is remembered per window kind (<c>annotate</c>, <c>editVideo</c>, <c>history</c>): the outer size
/// outside full screen / maximised, and the mode. JSON <c>{"width":…,"height":…,"mode":"normal"|"fill"|"fullScreen"}</c>.</summary>
public sealed record WindowPlacementMemo(double Width, double Height, WindowPlacementMode Mode);

/// <summary>
/// Where an app window opens (v3 "Window placement", Mac <c>CaptureKit/WindowPlacement.swift</c>): exactly centred in
/// the visible area (work area) of the screen under the pointer, shrunk to fit; the resizable windows reopen the way
/// the last one of their kind was closed. Pure; all sizes in DIPs.
/// </summary>
public static class WindowPlacementRules
{
    /// <summary>A frame this close to the visible area's edges on both axes counts as covering it (dragged to the edges).</summary>
    public const double FillTolerance = 8;

    /// <summary><paramref name="size"/> shrunk to fit <paramref name="visible"/> and centred in it.</summary>
    public static PxRect Centred(PxSize size, PxRect visible)
    {
        double w = Math.Min(size.Width, visible.Width), h = Math.Min(size.Height, visible.Height);
        return new PxRect(visible.X + (visible.Width - w) / 2, visible.Y + (visible.Height - h) / 2, w, h);
    }

    /// <summary>
    /// The frame to open at and whether to maximise: nothing remembered → the default size, centred; a remembered
    /// size → that size (never below the minimum), centred; remembered fill / full screen → maximised, with the
    /// centred remembered size as the size it restores to.
    /// </summary>
    public static (PxRect Frame, bool Maximize) Opening(WindowPlacementMemo? remembered, PxSize defaultSize, PxSize minSize, PxRect visible)
    {
        if (remembered is null || remembered.Width <= 0 || remembered.Height <= 0)
            return (Centred(defaultSize, visible), false);
        var size = new PxSize(Math.Max(remembered.Width, minSize.Width), Math.Max(remembered.Height, minSize.Height));
        return (Centred(size, visible), remembered.Mode != WindowPlacementMode.Normal);
    }

    /// <summary>
    /// What to remember when a window closes: maximised → its restore size, mode fill; a frame covering the whole
    /// visible area (within <see cref="FillTolerance"/> on both axes) → fill; otherwise its size.
    /// </summary>
    public static WindowPlacementMemo Memo(PxSize frameSize, PxSize normalSize, bool isMaximized, PxRect visible)
    {
        if (isMaximized) return new WindowPlacementMemo(normalSize.Width, normalSize.Height, WindowPlacementMode.Fill);
        bool covers = frameSize.Width >= visible.Width - FillTolerance && frameSize.Height >= visible.Height - FillTolerance;
        return new WindowPlacementMemo(frameSize.Width, frameSize.Height, covers ? WindowPlacementMode.Fill : WindowPlacementMode.Normal);
    }
}
