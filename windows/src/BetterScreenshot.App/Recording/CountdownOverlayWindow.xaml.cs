using System.Windows;
using System.Windows.Threading;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// The pre-record countdown HUD (mac <c>CountdownOverlayController</c>): a 200×200 dark rounded pill with a 120pt
/// monospaced-digit that ticks down once per second, centered on the primary screen. <see cref="RunAsync"/> resolves
/// <c>true</c> when the countdown completes or the user clicks to skip, and <c>false</c> when <see cref="Cancel"/>
/// aborts it (e.g. Ctrl+Shift+5 during the countdown). It runs before recording starts, so it is not captured.
/// </summary>
public partial class CountdownOverlayWindow : Window
{
    private DispatcherTimer? _timer;
    private TaskCompletionSource<bool>? _tcs;
    private int _remaining;

    public CountdownOverlayWindow()
    {
        InitializeComponent();
        MouseDown += (_, _) => Finish(true); // click anywhere to skip → start now
    }

    /// <summary>Shows the countdown for <paramref name="seconds"/>; resolves true to proceed, false if cancelled.</summary>
    public Task<bool> RunAsync(int seconds, BetterScreenshot.Core.PxRect region)
    {
        _tcs = new TaskCompletionSource<bool>();
        _remaining = seconds;
        Digit.Text = seconds.ToString();
        // Centred on the monitor being recorded (round 2 #4), placed in device pixels before it first paints.
        var mon = Controls.MonitorPlacement.MonitorFor(region);
        SourceInitialized += (_, _) => Controls.MonitorPlacement.Move(this,
            mon.Bounds.X + (mon.Bounds.Width - Width * mon.DpiScale) / 2,
            mon.Bounds.Y + (mon.Bounds.Height - Height * mon.DpiScale) / 2);
        Show();

        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (_, _) =>
        {
            _remaining--;
            if (_remaining <= 0) Finish(true);
            else Digit.Text = _remaining.ToString();
        };
        _timer.Start();
        return _tcs.Task;
    }

    /// <summary>Aborts an in-flight countdown (no-op otherwise), resolving <see cref="RunAsync"/> with false.</summary>
    public void Cancel() => Finish(false);

    private void Finish(bool proceed)
    {
        if (_tcs is null) return; // already finished
        _timer?.Stop();
        _timer = null;
        var tcs = _tcs;
        _tcs = null;
        Close();
        tcs.TrySetResult(proceed);
    }
}
