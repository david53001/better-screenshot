using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using Point = System.Windows.Point;
using Rect = System.Windows.Rect;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MouseButtonEventArgs = System.Windows.Input.MouseButtonEventArgs;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// One full-monitor dimmed overlay for drag-to-select area capture; the dragged selection is punched clear of the
/// dim, matching the macOS overlay. Positioned in physical pixels via MoveWindow (correct under per-monitor DPI);
/// reports the selection as a top-left physical-pixel rect (or null on cancel).
/// <para>
/// Given a frozen still of its monitor (see <see cref="FrozenScreen"/>) the overlay becomes opaque and paints that
/// still 1:1 underneath the dim, and reports the selected pixels cropped from it — so what you select is what was
/// on screen when the shortcut fired, even if the app behind it reacted to losing focus.
/// </para>
/// </summary>
public partial class SelectionOverlayWindow : Window
{
    private readonly MonitorInfo _monitor;
    private readonly BitmapSource? _frozen;
    private readonly Action<AreaSelection?> _onResult;
    private Point? _start;
    private bool _dragging;
    private bool _completed;

    public SelectionOverlayWindow(MonitorInfo monitor, BitmapSource? frozen, Action<AreaSelection?> onResult)
    {
        _monitor = monitor;
        _frozen = frozen;
        _onResult = onResult;
        InitializeComponent();
        if (frozen != null) ShowFrozenBackdrop(frozen);
        SourceInitialized += OnSourceInitialized;
        SizeChanged += (_, e) => FullRectGeometry.Rect = new Rect(0, 0, e.NewSize.Width, e.NewSize.Height);
        MouseLeftButtonDown += OnMouseDown;
        MouseMove += OnMouseMove;
        MouseLeftButtonUp += OnMouseUp;
        KeyDown += OnKeyDown;
    }

    /// <summary>The monitor this overlay covers (the controller focuses the one under the cursor).</summary>
    public MonitorInfo Monitor => _monitor;

    /// <summary>Grab keyboard focus so Escape cancels; only one of the per-monitor overlays gets this.</summary>
    public void ActivateForKeyboard()
    {
        Activate();
        Focus();
    }

    /// <summary>Tears the overlay down without firing the result callback (the controller closes the set).</summary>
    public void Dismiss()
    {
        if (_completed) return;
        _completed = true;
        Hide();
        Close();
    }

    /// <summary>
    /// Freeze mode: go opaque (the still covers everything) and lay the still out at exactly its own pixel size —
    /// physical pixels ÷ DPI scale — anchored top-left, so it maps 1:1 onto the screen it was taken from. Sizing
    /// it to the still rather than to the window matters on a rig whose real framebuffer is smaller than the
    /// monitor's reported bounds; stretching to fill would skew the frozen picture.
    /// </summary>
    private void ShowFrozenBackdrop(BitmapSource frozen)
    {
        OverlayHelpers.MakeOpaque(this);
        FrozenImage.Source = frozen;
        FrozenImage.Width = frozen.PixelWidth / _monitor.DpiScale;
        FrozenImage.Height = frozen.PixelHeight / _monitor.DpiScale;
        FrozenImage.Visibility = Visibility.Visible;
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        var b = _monitor.Bounds;
        MoveWindow(hwnd, (int)b.X, (int)b.Y, (int)b.Width, (int)b.Height, true);
        if (_frozen != null) OverlayHelpers.SquareOffCorners(hwnd);
    }

    private void OnMouseDown(object sender, MouseButtonEventArgs e)
    {
        _start = e.GetPosition(RootCanvas);
        _dragging = true;
        CaptureMouse();
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        if (!_dragging || _start is not { } start) return;
        var current = e.GetPosition(RootCanvas);
        var rect = SelectionMath.Normalize(new PxPoint(start.X, start.Y), new PxPoint(current.X, current.Y));
        // Physical wall: mouse capture keeps delivering points past the monitor edge — keep the selection on-screen.
        rect = SelectionMath.ClampToBounds(rect, RootCanvas.ActualWidth, RootCanvas.ActualHeight);

        SelectionGeometry.Rect = new Rect(rect.X, rect.Y, rect.Width, rect.Height);
        Canvas.SetLeft(SelRect, rect.X);
        Canvas.SetTop(SelRect, rect.Y);
        SelRect.Width = rect.Width;
        SelRect.Height = rect.Height;
        SelRect.Visibility = Visibility.Visible;

        long pw = (long)Math.Round(rect.Width * _monitor.DpiScale);
        long ph = (long)Math.Round(rect.Height * _monitor.DpiScale);
        DimLabel.Text = $"{pw} × {ph}";
        double labelY = rect.Y - 24 >= 0 ? rect.Y - 24 : rect.Y + 4;
        Canvas.SetLeft(DimLabelHost, rect.X);
        Canvas.SetTop(DimLabelHost, labelY);
        DimLabelHost.Visibility = Visibility.Visible;
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (!_dragging || _start is not { } start) { Complete(null); return; }
        _dragging = false;
        ReleaseMouseCapture();

        var current = e.GetPosition(RootCanvas);
        var dip = SelectionMath.Normalize(new PxPoint(start.X, start.Y), new PxPoint(current.X, current.Y));
        dip = SelectionMath.ClampToBounds(dip, RootCanvas.ActualWidth, RootCanvas.ActualHeight);
        var physical = SelectionMath.DipToPhysical(dip, _monitor.Bounds, _monitor.DpiScale);
        Complete(physical.Width >= 1 && physical.Height >= 1 ? physical : null);
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == System.Windows.Input.Key.Escape) Complete(null);
    }

    private void Complete(PxRect? result)
    {
        if (_completed) return;
        _completed = true;
        Hide(); // clear the dim overlay before the caller captures the screen
        // In freeze mode the pixels come straight out of the still — a null crop (nothing landed inside it)
        // leaves the caller to capture live, exactly as if freeze were off.
        var selection = result is { } r
            ? new AreaSelection(r, _frozen is null ? null : FrozenScreen.Crop(_frozen, _monitor, r))
            : (AreaSelection?)null;
        _onResult(selection);
        Close();
    }

    [DllImport("user32.dll")]
    private static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);
}
