using System.Windows;
using System.Windows.Media.Animation;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// Shows the last global keystroke while recording (mac <c>KeystrokeOverlayController</c>): a 280×44 black@0.75 pill
/// top-center (100px from top), 20pt mono white glyph string that fades over 1.0s after each key. Fed by the
/// Platform WH_KEYBOARD_LL <see cref="KeyboardHook"/> (glyphs already formatted, incl. modifiers). Click-through so
/// it never steals input; captured because it is an on-screen window.
/// </summary>
public partial class KeystrokeOverlayWindow : Window
{
    private KeyboardHook? _hook;

    public KeystrokeOverlayWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) => RecordingOverlayInterop.MakeClickThrough(this);
    }

    public void Start(BetterScreenshot.Core.PxRect region)
    {
        // Top-centre of the monitor being recorded (round 2 #4), in device pixels.
        var mon = Controls.MonitorPlacement.MonitorFor(region);
        SourceInitialized += (_, _) => Controls.MonitorPlacement.Move(this,
            mon.Bounds.X + (mon.Bounds.Width - Width * mon.DpiScale) / 2, mon.Bounds.Y + 100 * mon.DpiScale);
        Show();
        _hook = new KeyboardHook();
        _hook.KeyDown += OnKeyDown;
    }

    private void OnKeyDown(string glyph)
    {
        if (string.IsNullOrEmpty(glyph)) return;
        Glyph.Text = glyph;
        Pill.BeginAnimation(OpacityProperty, new DoubleAnimation(1.0, 0.0, TimeSpan.FromSeconds(1.0)));
    }

    public void Stop()
    {
        if (_hook is not null)
        {
            _hook.KeyDown -= OnKeyDown;
            _hook.Dispose();
            _hook = null;
        }
        Close();
    }
}
