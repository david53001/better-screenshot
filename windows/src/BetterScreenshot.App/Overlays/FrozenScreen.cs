using System.Windows;
using System.Windows.Media.Imaging;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// A still of every monitor, grabbed the instant a capture shortcut fires — before any overlay window has been
/// shown and so before the app you were using loses focus. The selection / window-picker overlays paint their
/// monitor's still as an opaque backdrop (the screen appears "frozen") and the capture is cropped straight out of
/// it, never re-grabbed from the live screen. That is what stops a full-screen game from pausing to its menu, or a
/// video player from showing its controls, in the moment between the keypress and the capture: what you get is
/// exactly what was on screen when you pressed the shortcut.
/// </summary>
public sealed class FrozenScreen
{
    private readonly List<(MonitorInfo Monitor, BitmapSource Image)> _stills;

    private FrozenScreen(List<(MonitorInfo, BitmapSource)> stills) => _stills = stills;

    /// <summary>
    /// Grabs a still of every monitor. Never throws: a monitor that fails to capture is simply left out, and the
    /// callers then behave exactly as if freeze were off for it (live overlay, live capture).
    /// </summary>
    public static FrozenScreen Capture()
    {
        var stills = new List<(MonitorInfo, BitmapSource)>();
        foreach (var monitor in Screens.All())
        {
            try { stills.Add((monitor, ScreenCapture.CaptureDisplay(monitor))); }
            catch { /* skip this monitor — it falls back to the live path */ }
        }
        return new FrozenScreen(stills);
    }

    /// <summary>This monitor's still, or null if it wasn't captured.</summary>
    public BitmapSource? For(MonitorInfo monitor)
    {
        foreach (var (m, image) in _stills)
            if (m.DeviceName == monitor.DeviceName) return image;
        return null;
    }

    /// <summary>
    /// Crops an absolute physical-pixel rect (e.g. a window's frame) out of the still of the monitor that
    /// <em>fully</em> contains it. Returns null when no single monitor's still covers the whole rect — the
    /// caller must then capture live, since a partial crop would silently lose part of the target.
    /// </summary>
    public BitmapSource? Crop(PxRect physical)
    {
        foreach (var (monitor, image) in _stills)
        {
            var local = physical.Offset(-monitor.Bounds.X, -monitor.Bounds.Y);
            if (local.X < 0 || local.Y < 0 || local.Right > image.PixelWidth || local.Bottom > image.PixelHeight)
                continue;
            if (Crop(image, monitor, physical) is { } cropped) return cropped;
        }
        return null;
    }

    /// <summary>
    /// Crops a physical-pixel rect out of one monitor's still, clamped to the still. Null if nothing lands inside
    /// (or the crop fails) — the caller falls back to a live capture.
    /// </summary>
    public static BitmapSource? Crop(BitmapSource still, MonitorInfo monitor, PxRect physical)
    {
        var size = new PxSize(still.PixelWidth, still.PixelHeight);
        if (SelectionMath.ToSnapshotRect(physical, monitor.Bounds, size) is not { } r) return null;
        try
        {
            var cropped = new CroppedBitmap(still, new Int32Rect((int)r.X, (int)r.Y, (int)r.Width, (int)r.Height));
            // Copy the pixels out rather than handing back the crop itself: a CroppedBitmap is only a window onto
            // its source, so returning it would pin the whole full-screen still in memory for as long as the
            // capture lives on (Quick Access card, history, a pin, the editor).
            var detached = new WriteableBitmap(cropped);
            detached.Freeze();
            return detached;
        }
        catch
        {
            return null;
        }
    }
}
