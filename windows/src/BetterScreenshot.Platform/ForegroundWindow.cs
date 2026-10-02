using System.Runtime.InteropServices;

namespace BetterScreenshot.Platform;

/// <summary>
/// Reads and restores the foreground window for "return focus to the previous app after a screenshot"
/// (the rules are pure, in <c>BetterScreenshot.Capture.FocusMemory</c>).
/// </summary>
public static class ForegroundWindow
{
    public static int OwnProcessId { get; } = Environment.ProcessId;

    /// <summary>The current foreground window and the id of the process that owns it (0 when unknown).</summary>
    public static (IntPtr Hwnd, int ProcessId) Current()
    {
        IntPtr hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return (IntPtr.Zero, 0);
        GetWindowThreadProcessId(hwnd, out uint pid);
        return (hwnd, (int)pid);
    }

    /// <summary>Reactivates <paramref name="hwnd"/> if it still exists and isn't already foreground. We are the
    /// foreground process at this moment (our overlay just closed), which satisfies the foreground lock; if
    /// Windows refuses anyway, attach to the current foreground thread's input queue and retry once. With
    /// <paramref name="expectedProcessId"/>, a handle that now belongs to another process (closed and reused) is left alone.</summary>
    public static bool Restore(IntPtr hwnd, int? expectedProcessId = null)
    {
        if (hwnd == IntPtr.Zero || !IsWindow(hwnd)) return false;
        if (expectedProcessId is { } want)
        {
            GetWindowThreadProcessId(hwnd, out uint owner);
            if (owner != (uint)want) return false;
        }
        if (GetForegroundWindow() == hwnd) return true;
        if (IsIconic(hwnd)) return false; // a minimised window wasn't what the user was looking at; don't pop it up
        if (SetForegroundWindow(hwnd)) return true;

        uint fgThread = GetWindowThreadProcessId(GetForegroundWindow(), out _);
        uint ourThread = GetCurrentThreadId();
        if (fgThread == 0 || fgThread == ourThread) return false;
        if (!AttachThreadInput(ourThread, fgThread, true)) return false;
        try { return SetForegroundWindow(hwnd); }
        finally { AttachThreadInput(ourThread, fgThread, false); }
    }

    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
}
