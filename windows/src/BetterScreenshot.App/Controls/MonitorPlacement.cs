using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.Controls;

/// <summary>
/// Puts a window on a given monitor in DEVICE pixels — the recording overlays (camera bubble, click rings, keystrokes,
/// countdown) follow the monitor being recorded, not the primary one (review round 2 #4). WPF's Left/Top are DIPs of
/// the window's current monitor, which is wrong across monitors with different scaling; SetWindowPos isn't. The
/// window first hops onto the target monitor (so WPF handles the DPI change there), then gets its exact rect.
/// </summary>
public static class MonitorPlacement
{
    /// <summary>The monitor showing the centre of <paramref name="devicePixels"/> (the primary when none does).</summary>
    public static MonitorInfo MonitorFor(PxRect devicePixels)
    {
        var c = devicePixels.Center;
        foreach (var m in Screens.All())
            if (m.Bounds.Contains(c)) return m;
        return Screens.Primary();
    }

    /// <summary>The working area (device pixels) of the monitor showing the centre of <paramref name="devicePixels"/>.</summary>
    public static PxRect WorkAreaFor(PxRect devicePixels)
    {
        var c = devicePixels.Center;
        var wa = System.Windows.Forms.Screen.FromPoint(new System.Drawing.Point((int)c.X, (int)c.Y)).WorkingArea;
        return new PxRect(wa.X, wa.Y, wa.Width, wa.Height);
    }

    /// <summary>Moves <paramref name="window"/> (its HWND must exist — call from SourceInitialized or later) to the
    /// device-pixel rect. A null size keeps the window's DIP size at the target monitor's scale.</summary>
    public static void Move(Window window, double x, double y, double? width = null, double? height = null)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return;
        // Hop first: the DPI change (if any) is applied while the window is still small and at the target origin.
        SetWindowPos(hwnd, IntPtr.Zero, (int)Math.Round(x), (int)Math.Round(y), 0, 0, NoSize | NoZOrder | NoActivate);
        if (width is { } w && height is { } h)
            SetWindowPos(hwnd, IntPtr.Zero, (int)Math.Round(x), (int)Math.Round(y), (int)Math.Round(w), (int)Math.Round(h),
                NoZOrder | NoActivate);
    }

    private const uint NoSize = 0x0001, NoZOrder = 0x0004, NoActivate = 0x0010;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
}
