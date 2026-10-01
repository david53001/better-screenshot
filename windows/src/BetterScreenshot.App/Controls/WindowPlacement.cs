using System.Windows;
using BetterScreenshot.App.Overlays;

namespace BetterScreenshot.App.Controls;

/// <summary>Where windows open: on the monitor under the pointer (v3 "Window placement").</summary>
public static class WindowPlacement
{
    /// <summary>The work area (DIPs) of the monitor under the pointer — for a window that isn't shown yet, in
    /// that monitor's own DPI.</summary>
    public static Rect WorkAreaUnderCursor(Window? _ = null)
    {
        var m = OverlayHelpers.MonitorUnderCursor();
        var screen = System.Windows.Forms.Screen.FromPoint(new System.Drawing.Point((int)(m.Bounds.X + 1), (int)(m.Bounds.Y + 1)));
        var wa = screen.WorkingArea;
        double s = m.DpiScale > 0 ? m.DpiScale : 1;
        return new Rect(wa.X / s, wa.Y / s, wa.Width / s, wa.Height / s);
    }
}
