using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using Border = System.Windows.Controls.Border;
using Point = System.Windows.Point;

namespace BetterScreenshot.App.Tours;

/// <summary>
/// Finds a tour anchor (<c>AutomationProperties.AutomationId</c> = the §7.2 anchor id) in a window's visual tree and
/// measures it in screen DIPs. An element that isn't visible (or has no size) counts as missing.
/// </summary>
public static class TourAnchors
{
    public static void Set(DependencyObject element, string id) => AutomationProperties.SetAutomationId(element, id);

    public static FrameworkElement? Find(Window? window, string id)
    {
        if (window is null || !window.IsVisible || window.WindowState == WindowState.Minimized) return null;
        return Find((DependencyObject)window, id);
    }

    private static FrameworkElement? Find(DependencyObject node, string id)
    {
        if (node is FrameworkElement fe)
        {
            if (!fe.IsVisible) return null; // a hidden parent hides the whole subtree
            if (AutomationProperties.GetAutomationId(fe) == id && fe.ActualWidth > 0 && fe.ActualHeight > 0) return fe;
        }
        int n = VisualTreeHelper.GetChildrenCount(node);
        for (int i = 0; i < n; i++)
            if (Find(VisualTreeHelper.GetChild(node, i), id) is { } hit) return hit;
        return null;
    }

    public static bool IsPresent(Window? window, string id) => Find(window, id) is not null;

    /// <summary>The element's bounds in screen DIPs (null when it isn't connected to a window).</summary>
    public static Rect? ScreenRect(FrameworkElement element)
    {
        if (PresentationSource.FromVisual(element) is not { CompositionTarget: { } target }) return null;
        try
        {
            var a = element.PointToScreen(new Point(0, 0));
            var b = element.PointToScreen(new Point(element.ActualWidth, element.ActualHeight));
            var m = target.TransformFromDevice;
            return new Rect(m.Transform(a), m.Transform(b));
        }
        catch (InvalidOperationException) { return null; }
    }

    /// <summary>The window's frame in screen DIPs.</summary>
    public static Rect? WindowRect(Window window)
    {
        if (!window.IsVisible || PresentationSource.FromVisual(window) is not { CompositionTarget: { } target }) return null;
        var m = target.TransformFromDevice;
        var hwnd = new System.Windows.Interop.WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero) return null;
        // The visible frame (GetWindowRect includes the invisible resize borders on Windows 10/11).
        if (DwmGetWindowAttribute(hwnd, 9 /* DWMWA_EXTENDED_FRAME_BOUNDS */, out var r, System.Runtime.InteropServices.Marshal.SizeOf<RECT>()) != 0
            && !GetWindowRect(hwnd, out r)) return null;
        return new Rect(m.Transform(new Point(r.Left, r.Top)), m.Transform(new Point(r.Right, r.Bottom)));
    }

    /// <summary>The control's own corner radius (a Border, or a same-size rounded Border right inside it); 0 = square.</summary>
    public static double CornerRadius(FrameworkElement element)
    {
        if (element is Border b) return b.CornerRadius.TopLeft;
        var inner = FirstBorder(element, 3);
        return inner is not null && Math.Abs(inner.ActualWidth - element.ActualWidth) < 2 && Math.Abs(inner.ActualHeight - element.ActualHeight) < 2
            ? inner.CornerRadius.TopLeft
            : 0;
    }

    private static Border? FirstBorder(DependencyObject node, int depth)
    {
        if (depth == 0) return null;
        int n = VisualTreeHelper.GetChildrenCount(node);
        for (int i = 0; i < n; i++)
        {
            var c = VisualTreeHelper.GetChild(node, i);
            if (c is Border b) return b;
            if (FirstBorder(c, depth - 1) is { } deeper) return deeper;
        }
        return null;
    }

    /// <summary>Whether the element's direct parent is a bar at least 3× as wide as tall (tag goes vertical first).</summary>
    public static bool ParentIsBar(FrameworkElement element) =>
        VisualTreeHelper.GetParent(element) is FrameworkElement p && p.ActualHeight > 0 && p.ActualWidth >= 3 * p.ActualHeight;

    /// <summary>Focused element is editable text (Return/Esc pass through to it).</summary>
    public static bool IsEditable(object? focused) => focused switch
    {
        System.Windows.Controls.TextBox t => !t.IsReadOnly,
        System.Windows.Controls.RichTextBox r => !r.IsReadOnly,
        System.Windows.Controls.PasswordBox => true,
        _ => false,
    };

    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    [System.Runtime.InteropServices.DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);

    [System.Runtime.InteropServices.DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out RECT value, int size);
}
