using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// The result of an interactive window pick: the chosen window, plus its pixels already cropped from the frozen
/// still when freeze mode was on. A null <paramref name="Frozen"/> means the caller must capture the window live.
/// </summary>
public readonly record struct WindowPick(IntPtr Hwnd, BitmapSource? Frozen);

/// <summary>Shows the interactive window picker on the monitor under the cursor and returns the chosen window.</summary>
public sealed class WindowPickerController
{
    /// <summary>
    /// Presents the picker. Pass a <paramref name="frozen"/> still (grabbed before this call, while the app you
    /// were using still had focus) to hold the screen still during picking and take the capture from it.
    /// </summary>
    public void Present(Action<WindowPick?> onPicked, FrozenScreen? frozen = null)
    {
        var monitor = OverlayHelpers.MonitorUnderCursor();
        var window = new WindowPickerWindow(monitor, frozen, pick =>
            System.Windows.Application.Current.Dispatcher.BeginInvoke(
                DispatcherPriority.Background, new Action(() => onPicked(pick))));
        window.Show();
    }
}
