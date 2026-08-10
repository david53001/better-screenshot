using System.Runtime.InteropServices;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
// Disambiguate WPF types from the WinForms/GDI+ ones the App project also references (tray NotifyIcon).
using Brushes = System.Windows.Media.Brushes;
using Window = System.Windows.Window;

namespace BetterScreenshot.App.Overlays;

/// <summary>Shared helpers for overlays: the monitor under the cursor, the cursor's physical position, and the
/// two tweaks a frozen (opaque) full-screen overlay needs.</summary>
internal static class OverlayHelpers
{
    private const int DwmwaWindowCornerPreference = 33;
    private const int DwmwcpDoNotRound = 1;

    /// <summary>
    /// Turns a transparent overlay into a plain opaque window — what freeze mode wants, since the frozen still
    /// covers every pixel anyway. Must be called from the window's constructor: WPF rejects an
    /// <c>AllowsTransparency</c> change once the HWND exists. This is not only cosmetic — a layered
    /// (transparent) window gets no hardware acceleration, so repainting a full 4K still on every mouse-move
    /// while dragging a selection would crawl.
    /// </summary>
    public static void MakeOpaque(Window window)
    {
        window.AllowsTransparency = false;
        window.Background = Brushes.Black;
    }

    /// <summary>
    /// Squares off a window's corners. Windows 11 rounds top-level windows, which on a screen-filling overlay
    /// leaves four notches of the *live* desktop showing through the frozen still. Safe no-op on Windows 10.
    /// </summary>
    public static void SquareOffCorners(IntPtr hwnd)
    {
        try
        {
            int preference = DwmwcpDoNotRound;
            _ = DwmSetWindowAttribute(hwnd, DwmwaWindowCornerPreference, ref preference, sizeof(int));
        }
        catch (DllNotFoundException) { }
        catch (EntryPointNotFoundException) { }
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);

    public static MonitorInfo MonitorUnderCursor()
    {
        if (GetCursorPos(out POINT p))
        {
            var cursor = new PxPoint(p.X, p.Y);
            foreach (var m in Screens.All())
                if (m.Bounds.Contains(cursor)) return m;
        }
        return Screens.Primary();
    }

    public static PxPoint CursorPhysical()
    {
        GetCursorPos(out POINT p);
        return new PxPoint(p.X, p.Y);
    }

    [DllImport("user32.dll")]
    private static extern bool GetCursorPos(out POINT lpPoint);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X, Y; }
}
