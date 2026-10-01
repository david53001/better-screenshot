using System.Runtime.InteropServices;

namespace BetterScreenshot.Platform;

/// <summary>
/// Windows virtual desktops (the port of the Mac's "open on the active Space", §4.11): the documented
/// <c>IVirtualDesktopManager</c> can tell whether one of our windows is on the desktop the user is looking at and move
/// it there. The current desktop's id is read from a window known to be on it — the foreground window. Every call is
/// best-effort: on a failure (no shell, COM error) the window is simply left where it is.
/// </summary>
public static class VirtualDesktops
{
    /// <summary>
    /// If <paramref name="hwnd"/> (a window of this process) sits on another virtual desktop, moves it to the one in
    /// view and returns true; false when it was already here or nothing could be done.
    /// </summary>
    public static bool BringToCurrent(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return false;
        try
        {
            var manager = (IVirtualDesktopManager)new VirtualDesktopManagerClass();
            if (manager.IsWindowOnCurrentVirtualDesktop(hwnd) != 0) return false;
            if (CurrentDesktopId(manager) is not { } desktop) return false;
            manager.MoveWindowToDesktop(hwnd, ref desktop);
            return true;
        }
        catch (Exception ex) when (ex is COMException or InvalidCastException or NotSupportedException or ArgumentException)
        {
            return false;
        }
    }

    /// <summary>The id of the desktop in view, or null. Public for the smoke test.</summary>
    public static Guid? CurrentDesktopId()
    {
        try { return CurrentDesktopId((IVirtualDesktopManager)new VirtualDesktopManagerClass()); }
        catch (Exception ex) when (ex is COMException or InvalidCastException) { return null; }
    }

    /// <summary>The id of the desktop in view: a throwaway 1×1 window shown off-screen is put on it by Windows (the
    /// foreground window can be the taskbar, which belongs to every desktop); the foreground window is the fallback.</summary>
    private static Guid? CurrentDesktopId(IVirtualDesktopManager manager)
    {
        var parameters = new System.Windows.Interop.HwndSourceParameters("BetterScreenshot.DesktopProbe", 1, 1)
        {
            PositionX = -32000, PositionY = -32000,
            WindowStyle = unchecked((int)0x90000000),  // WS_POPUP | WS_VISIBLE
            ExtendedWindowStyle = 0x08000080,          // WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW (no taskbar button)
        };
        using (var probe = new System.Windows.Interop.HwndSource(parameters))
        {
            if (DesktopIdOf(manager, probe.Handle) is { } id) return id;
        }
        return DesktopIdOf(manager, GetForegroundWindow());
    }

    private static Guid? DesktopIdOf(IVirtualDesktopManager manager, IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return null;
        try
        {
            var id = manager.GetWindowDesktopId(hwnd);
            return id == Guid.Empty ? null : id;
        }
        catch (COMException)
        {
            return null; // the taskbar / desktop have no desktop of their own
        }
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [ComImport, Guid("AA509086-5CA9-4C25-8F95-589D3C07B48A")]
    private class VirtualDesktopManagerClass { }

    [ComImport, Guid("A5CD92FF-29BE-454C-8D04-D82879FB3F1B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IVirtualDesktopManager
    {
        int IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow);
        Guid GetWindowDesktopId(IntPtr topLevelWindow);
        void MoveWindowToDesktop(IntPtr topLevelWindow, ref Guid desktopId);
    }
}
