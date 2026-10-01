using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace BetterScreenshot.App.Controls;

/// <summary>
/// Window traits for HUD panels that float over the app being recorded (Mac non-activating <c>NSPanel</c>): never
/// take focus (clicks land without activating BetterScreenshot), stay out of Alt+Tab, and optionally stay out of
/// screen captures (<c>WDA_EXCLUDEFROMCAPTURE</c>, Windows 10 2004+ — honoured by gdigrab's BitBlt and by Desktop
/// Duplication).
/// </summary>
public static class FloatingPanel
{
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_TRANSPARENT = 0x00000020;
    private const int WM_MOUSEACTIVATE = 0x0021;
    private const int MA_NOACTIVATE = 3;
    private const uint WDA_NONE = 0x0;
    private const uint WDA_EXCLUDEFROMCAPTURE = 0x11;

    /// <summary>Call from <c>SourceInitialized</c>. <paramref name="clickThrough"/> also lets the mouse fall through.</summary>
    public static void MakeNonActivating(Window window, bool clickThrough = false)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        int ex = GetWindowLong(hwnd, GWL_EXSTYLE) | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW;
        if (clickThrough) ex |= WS_EX_TRANSPARENT;
        SetWindowLong(hwnd, GWL_EXSTYLE, ex);
        HwndSource.FromHwnd(hwnd)?.AddHook((IntPtr h, int msg, IntPtr w, IntPtr l, ref bool handled) =>
        {
            if (msg != WM_MOUSEACTIVATE) return IntPtr.Zero;
            handled = true;
            return MA_NOACTIVATE;
        });
    }

    /// <summary>Keep the window out of (true) or in (false) screenshots and recordings. False if the OS refused.</summary>
    public static bool ExcludeFromCapture(Window window, bool exclude)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        return hwnd != IntPtr.Zero && SetWindowDisplayAffinity(hwnd, exclude ? WDA_EXCLUDEFROMCAPTURE : WDA_NONE);
    }

    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr hwnd, int index, int value);
    [DllImport("user32.dll")] private static extern bool SetWindowDisplayAffinity(IntPtr hwnd, uint affinity);
}
