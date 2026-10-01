using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using BetterScreenshot.App.Overlays;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.Controls;

/// <summary>Where windows open: on the monitor under the pointer (v3 "Window placement").</summary>
public static class WindowPlacement
{
    /// <summary>
    /// Opens <paramref name="window"/> exactly centred in the work area of the screen under the pointer, shrunk to fit
    /// (<see cref="WindowPlacementRules"/>). With a <paramref name="kind"/> (<c>annotate</c>, <c>editVideo</c>,
    /// <c>history</c>) it reopens the way the last window of that kind was closed — the same size, or maximised when
    /// it was maximised / covering the screen — and remembers that when it closes. Call before the window is shown.
    /// </summary>
    public static void Place(Window window, PxSize defaultSize, string? kind = null, SettingsStore? store = null)
    {
        var work = WorkAreaUnderCursor();
        var visible = new PxRect(work.X, work.Y, work.Width, work.Height);
        WindowPlacementMemo? memo = kind is not null && store is not null && store.WindowPlacements.TryGetValue(kind, out var m) ? m : null;
        var (frame, maximize) = WindowPlacementRules.Opening(memo, defaultSize, new PxSize(window.MinWidth, window.MinHeight), visible);
        window.WindowStartupLocation = WindowStartupLocation.Manual;
        window.Left = frame.X;
        window.Top = frame.Y;
        window.Width = frame.Width;
        window.Height = frame.Height;
        if (maximize) window.WindowState = WindowState.Maximized;
        if (kind is null || store is null) return;
        window.Closing += (_, e) =>
        {
            if (e.Cancel) return;
            var restore = window.RestoreBounds;
            var normal = restore.IsEmpty ? new PxSize(window.ActualWidth, window.ActualHeight) : new PxSize(restore.Width, restore.Height);
            store.WindowPlacements[kind] = WindowPlacementRules.Memo(new PxSize(window.ActualWidth, window.ActualHeight), normal,
                window.WindowState == WindowState.Maximized, WorkAreaOf(window));
            try { store.Save(); }
            catch (Exception ex) when (ex is System.IO.IOException or UnauthorizedAccessException) { /* next close tries again */ }
        };
    }

    /// <summary>The work area (DIPs) of the monitor a shown window is on.</summary>
    private static PxRect WorkAreaOf(Window window)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        var screen = hwnd == IntPtr.Zero ? System.Windows.Forms.Screen.PrimaryScreen! : System.Windows.Forms.Screen.FromHandle(hwnd);
        double s = VisualTreeHelper.GetDpi(window).DpiScaleX;
        if (s <= 0) s = 1;
        var wa = screen.WorkingArea;
        return new PxRect(wa.X / s, wa.Y / s, wa.Width / s, wa.Height / s);
    }

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

    /// <summary>The work area (DIPs) of the monitor showing the centre of <paramref name="devicePixels"/> (e.g. a recording region).</summary>
    public static Rect WorkAreaFor(BetterScreenshot.Core.PxRect devicePixels)
    {
        var c = devicePixels.Center;
        var screen = System.Windows.Forms.Screen.FromPoint(new System.Drawing.Point((int)c.X, (int)c.Y));
        var m = BetterScreenshot.Platform.Screens.All().FirstOrDefault(x => x.Bounds.Contains(c));
        double s = m is { DpiScale: > 0 } ? m.DpiScale : 1;
        var wa = screen.WorkingArea;
        return new Rect(wa.X / s, wa.Y / s, wa.Width / s, wa.Height / s);
    }
}
