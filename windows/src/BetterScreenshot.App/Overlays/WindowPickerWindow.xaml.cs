using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using Canvas = System.Windows.Controls.Canvas;
using Color = System.Windows.Media.Color;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MouseButtonEventArgs = System.Windows.Input.MouseButtonEventArgs;
using MouseEventArgs = System.Windows.Input.MouseEventArgs;
using SolidColorBrush = System.Windows.Media.SolidColorBrush;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// Full-monitor overlay for interactive window picking: highlights the window under the cursor (accent fill + 3px
/// stroke + title caption) using the tested <see cref="WindowPicking.Topmost"/>; click picks, Esc cancels. Reports
/// the chosen HWND (or null). Positioned in physical pixels via MoveWindow for per-monitor DPI correctness.
/// <para>
/// Given a <see cref="FrozenScreen"/> the overlay goes opaque and paints that monitor's still under its dim, so
/// the screen holds still while you pick, and it reports the picked window's pixels cropped from the still rather
/// than leaving the caller to re-capture a window that may have changed since the shortcut fired.
/// </para>
/// </summary>
public partial class WindowPickerWindow : Window
{
    private readonly MonitorInfo _monitor;
    private readonly FrozenScreen? _frozen;
    private readonly Action<WindowPick?> _onPicked;
    private readonly IReadOnlyList<EnumeratedWindow> _windows;
    private EnumeratedWindow? _hovered;
    private bool _done;

    public WindowPickerWindow(MonitorInfo monitor, FrozenScreen? frozen, Action<WindowPick?> onPicked)
    {
        _monitor = monitor;
        _frozen = frozen;
        _onPicked = onPicked;
        InitializeComponent();

        var accent = Color.FromRgb(0xFF, 0xFF, 0xFF); // monochrome white highlight (was blue #0A84FF)
        Highlight.Fill = new SolidColorBrush(accent) { Opacity = 0.18 };
        Highlight.Stroke = new SolidColorBrush(accent);
        Highlight.StrokeThickness = 3;

        if (frozen?.For(monitor) is { } still) ShowFrozenBackdrop(still);
        // Enumerate before this overlay is shown, i.e. before the app you were using loses focus: a game that
        // minimises itself on deactivation would otherwise drop out of the list (IsIconic) and become unpickable —
        // and in freeze mode the list has to describe the same desktop the still froze.
        _windows = WindowEnum.ForPicking();
        SourceInitialized += OnInit;
        SizeChanged += (_, e) => { FrozenDim.Width = e.NewSize.Width; FrozenDim.Height = e.NewSize.Height; };
        MouseMove += OnMove;
        MouseLeftButtonUp += OnUp;
        KeyDown += OnKey;
    }

    /// <summary>Freeze mode: opaque window, the still laid out at exactly its own pixel size (physical ÷ DPI
    /// scale) anchored top-left so it maps 1:1, and a dim rectangle over it standing in for the translucent
    /// window background an opaque window can no longer provide.</summary>
    private void ShowFrozenBackdrop(BitmapSource frozen)
    {
        OverlayHelpers.MakeOpaque(this);
        FrozenImage.Source = frozen;
        FrozenImage.Width = frozen.PixelWidth / _monitor.DpiScale;
        FrozenImage.Height = frozen.PixelHeight / _monitor.DpiScale;
        FrozenImage.Visibility = Visibility.Visible;
        FrozenDim.Visibility = Visibility.Visible;
    }

    private void OnInit(object? sender, EventArgs e)
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        var b = _monitor.Bounds;
        MoveWindow(hwnd, (int)b.X, (int)b.Y, (int)b.Width, (int)b.Height, true);
        if (_frozen != null) OverlayHelpers.SquareOffCorners(hwnd);
        Activate();
        Focus();
    }

    private void OnMove(object sender, MouseEventArgs e)
    {
        var cursor = OverlayHelpers.CursorPhysical();
        var pickables = _windows.Select(w => w.Pickable).ToList();
        var hit = WindowPicking.Topmost(cursor, pickables, Environment.ProcessId);

        if (hit is { } p)
        {
            _hovered = _windows.First(w => w.Pickable.Id == p.Id);
            double dip = _monitor.DpiScale;
            double x = (p.Frame.X - _monitor.Bounds.X) / dip;
            double y = (p.Frame.Y - _monitor.Bounds.Y) / dip;
            Canvas.SetLeft(Highlight, x);
            Canvas.SetTop(Highlight, y);
            Highlight.Width = p.Frame.Width / dip;
            Highlight.Height = p.Frame.Height / dip;
            Highlight.Visibility = Visibility.Visible;

            TitleText.Text = p.Title ?? string.Empty;
            Canvas.SetLeft(TitleHost, x + 8);
            Canvas.SetTop(TitleHost, y + 8);
            TitleHost.Visibility = string.IsNullOrEmpty(p.Title) ? Visibility.Collapsed : Visibility.Visible;
        }
        else
        {
            _hovered = null;
            Highlight.Visibility = Visibility.Collapsed;
            TitleHost.Visibility = Visibility.Collapsed;
        }
    }

    private void OnUp(object sender, MouseButtonEventArgs e) => Complete(_hovered);

    private void OnKey(object sender, KeyEventArgs e)
    {
        if (e.Key == System.Windows.Input.Key.Escape) Complete(null);
    }

    private void Complete(EnumeratedWindow? picked)
    {
        if (_done) return;
        _done = true;
        Hide();
        // Freeze mode crops the frame that was enumerated *before* the overlay appeared, so a window that moved
        // or minimised in the meantime still yields the pixels you saw. A null crop (no single monitor's still
        // covers the frame — e.g. a window spanning two screens) leaves the caller to capture it live.
        WindowPick? pick = picked is { } w
            ? new WindowPick(w.Hwnd, _frozen?.Crop(w.Pickable.Frame))
            : null;
        _onPicked(pick);
        Close();
    }

    [DllImport("user32.dll")]
    private static extern bool MoveWindow(IntPtr hWnd, int x, int y, int width, int height, bool repaint);
}
