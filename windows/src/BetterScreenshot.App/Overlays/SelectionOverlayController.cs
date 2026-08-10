using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.Overlays;

/// <summary>
/// The result of an area selection: the chosen physical-pixel rect, plus its pixels already cropped from the
/// frozen still when freeze mode was on. A null <paramref name="Frozen"/> means the caller must capture the
/// live screen for that rect (freeze off, or the still didn't cover it).
/// </summary>
public readonly record struct AreaSelection(PxRect Region, BitmapSource? Frozen);

/// <summary>
/// Shows the area-selection overlay on every monitor (like the macOS version) and returns the chosen physical rect.
/// The first window to complete or cancel wins and tears the whole set down; presenting again while a selection is
/// open cancels the previous one instead of stacking overlays.
/// </summary>
public sealed class SelectionOverlayController
{
    private List<SelectionOverlayWindow>? _windows;
    private Action<AreaSelection?>? _completion;
    private FrozenScreen? _frozen;

    /// <summary>
    /// Presents the overlay; <paramref name="completion"/> is invoked (after the overlays are torn down and the
    /// screen repainted) with the selection, or null if cancelled. With <paramref name="freeze"/> the screen is
    /// grabbed *now* — before any overlay is shown, so before the focused app can react — and the overlays paint
    /// that still, so the selection is taken from what was on screen at this instant.
    /// </summary>
    public void Present(bool freeze, Action<AreaSelection?> completion)
    {
        // Re-entry guard: a second capture hotkey during an open selection cancels it (fires the old
        // completion with null) rather than stacking a second set of dim overlays.
        var openStill = _frozen; // keep the in-flight still: re-grabbing now would bake this overlay's dim into it
        Cancel();

        _frozen = freeze ? openStill ?? FrozenScreen.Capture() : null;
        _completion = completion;
        var windows = new List<SelectionOverlayWindow>();
        _windows = windows;
        foreach (var m in Screens.All())
            windows.Add(new SelectionOverlayWindow(m, _frozen?.For(m), Finish));
        foreach (var w in windows) w.Show();

        // Give keyboard focus (for Escape) to the overlay on the monitor the user is looking at.
        var cursorMonitor = OverlayHelpers.MonitorUnderCursor();
        foreach (var w in windows)
            if (w.Monitor.DeviceName == cursorMonitor.DeviceName) w.ActivateForKeyboard();
    }

    /// <summary>Dismisses an in-flight selection (if any), firing its completion with null.</summary>
    public void Cancel() => Finish(null);

    private void Finish(AreaSelection? result)
    {
        var completion = _completion;
        var windows = _windows;
        _completion = null;
        _windows = null;
        _frozen = null;
        if (windows != null)
            foreach (var w in windows) w.Dismiss();
        if (completion is null) return;
        // Defer to Background priority so the (now hidden) overlays are fully gone before the caller captures.
        System.Windows.Application.Current.Dispatcher.BeginInvoke(
            DispatcherPriority.Background, new Action(() => completion(result)));
    }
}
