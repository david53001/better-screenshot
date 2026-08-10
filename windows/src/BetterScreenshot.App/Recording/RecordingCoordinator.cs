using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BetterScreenshot.App.Overlays;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;

namespace BetterScreenshot.App.Recording;

/// <summary>
/// Orchestrates screen recording (mac <c>RecordingCoordinator</c>): a smart <see cref="RecorderState"/> machine
/// driven by the single Ctrl+Shift+5 <see cref="Toggle"/> — idle shows the record strip (armed), armed cancels,
/// recording stops. The strip's target buttons pick full screen / area / window; all three reduce to one
/// desktop-relative pixel region handed to the ffmpeg <see cref="RecordingEngine"/>. A 1s DispatcherTimer drives
/// the tray icon + timer; on stop the finished MP4 + a thumbnail go to history + the Quick Access card.
///
/// Gapless pause/resume is Task 7.3 (the record strip has no pause yet). The whole flow stays on the UI thread
/// (no ConfigureAwait(false) here) so the DispatcherTimer and callbacks run on the dispatcher.
/// </summary>
public sealed class RecordingCoordinator
{
    private readonly SettingsStore _settings;
    private readonly RecordingEngine _engine = new();
    private readonly DispatcherTimer _timer;
    private readonly Action<bool, string?> _onStateChange;
    private readonly Action<bool, bool> _onPauseStateChange;
    private readonly Action<string, BitmapSource> _onFinished;
    private readonly SelectionOverlayController _selection = new();
    private readonly WindowPickerController _picker = new();

    private RecordStripWindow? _strip;
    private CountdownOverlayWindow? _countdown;
    private ClickHighlighter? _clicks;
    private KeystrokeOverlayWindow? _keystrokes;
    private CameraBubbleWindow? _camera;
    private RecorderState _state = RecorderState.Idle;
    private PxRect _region;
    private RecordingFormat _format;
    private bool _stopping;
    private bool _exiting;

    public RecordingCoordinator(SettingsStore settings, Action<bool, string?> onStateChange,
        Action<bool, bool> onPauseStateChange, Action<string, BitmapSource> onFinished)
    {
        _settings = settings;
        _onStateChange = onStateChange;
        _onPauseStateChange = onPauseStateChange;
        _onFinished = onFinished;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (_, _) => _onStateChange(true, _state.ElapsedString(DateTime.Now));
    }

    public bool IsRecording => _state.Phase is RecorderPhase.Recording or RecorderPhase.Paused;
    private bool IsPaused => _state.Phase == RecorderPhase.Paused;

    /// <summary>Pause a running recording or resume a paused one (no-op otherwise). Gapless via segment+concat.</summary>
    public void PauseResume() => _ = PauseResumeAsync();

    private async Task PauseResumeAsync()
    {
        switch (_state.Phase)
        {
            case RecorderPhase.Recording:
                if (!_state.Transition(RecorderEvent.Pause, DateTime.Now)) return;
                _timer.Stop();
                await _engine.PauseAsync();
                _onStateChange(true, _state.ElapsedString(DateTime.Now)); // "Paused · m:ss" (frozen)
                _onPauseStateChange(true, true);
                break;
            case RecorderPhase.Paused:
                if (!_state.Transition(RecorderEvent.Resume, DateTime.Now)) return;
                _engine.Resume();
                _timer.Start();
                _onStateChange(true, _state.ElapsedString(DateTime.Now));
                _onPauseStateChange(true, false);
                break;
        }
    }

    /// <summary>The Ctrl+Shift+5 entry point: idle → strip · armed → cancel · recording/paused → stop.</summary>
    public void Toggle()
    {
        switch (_state.Phase)
        {
            case RecorderPhase.Idle: Arm(); break;
            case RecorderPhase.Armed: CancelStrip(); break;
            case RecorderPhase.Recording:
            case RecorderPhase.Paused: _ = StopAsync(); break;
            case RecorderPhase.Finishing: break; // busy — ignore
        }
    }

    private void Arm()
    {
        if (!FfmpegRunner.IsAvailable())
        {
            HudController.Show("ffmpeg not found — recording unavailable");
            return;
        }
        if (!_state.Transition(RecorderEvent.Arm)) return;
        _strip = new RecordStripWindow(_settings)
        {
            OnFullScreen = BeginFullScreen,
            OnArea = BeginArea,
            OnWindow = BeginWindow,
            OnCancel = CancelStrip,
        };
        _strip.Show();
    }

    private void HideStrip()
    {
        _strip?.Close();
        _strip = null;
    }

    private void CancelStrip()
    {
        // Any in-flight area-selection / window-picker overlay self-cancels on Esc; resetting the state here means
        // its completion callback (which checks for the Armed phase) will no-op if it still arrives.
        HideStrip();
        _countdown?.Cancel(); // abort a running pre-record countdown too
        _state.Transition(RecorderEvent.Reset);
        _onStateChange(false, null);
    }

    private void BeginFullScreen()
    {
        HideStrip();
        _ = BeginAsync(OverlayHelpers.MonitorUnderCursor().Bounds);
    }

    private void BeginArea()
    {
        HideStrip();
        // Never freeze when picking a recording target: only the rectangle matters here (the recording itself is
        // live), and selecting against a stale still would just misrepresent what is about to be recorded.
        _selection.Present(freeze: false, selection =>
        {
            if (selection is { } s && !s.Region.IsEmpty) _ = BeginAsync(s.Region);
            else AbortArm();
        });
    }

    private void BeginWindow()
    {
        HideStrip();
        _picker.Present(pick =>
        {
            if (pick is { } p && WindowEnum.FrameBounds(p.Hwnd) is { } r) _ = BeginAsync(r);
            else AbortArm();
        });
    }

    private void AbortArm()
    {
        if (_state.Phase == RecorderPhase.Armed)
        {
            _state.Transition(RecorderEvent.Reset);
            _onStateChange(false, null);
        }
    }

    private async Task BeginAsync(PxRect region)
    {
        if (_state.Phase != RecorderPhase.Armed) return; // cancelled before we got here

        var config = _settings.Recording;
        Directory.CreateDirectory(_settings.RecordingsDirectory);
        string path = Path.Combine(_settings.RecordingsDirectory, FileNamer.Name(DateTime.Now, "mp4", "Recording"));
        var audio = await DshowAudioDevices.ResolveAsync(config);
        if (_state.Phase != RecorderPhase.Armed) return; // cancelled during device enumeration

        // Pre-record countdown (still armed; runs before capture starts, so it is not recorded).
        if (config.CountdownSeconds > 0)
        {
            _countdown = new CountdownOverlayWindow();
            bool proceed = await _countdown.RunAsync(config.CountdownSeconds);
            _countdown = null;
            if (!proceed) { AbortArm(); return; } // cancelled during countdown
            if (_state.Phase != RecorderPhase.Armed) return;
        }

        if (!_state.Transition(RecorderEvent.Begin, DateTime.Now)) { _state = RecorderState.Idle; return; }

        if (!_engine.Start(config, region, path, audio))
        {
            _state = RecorderState.Idle;
            HudController.Show("Could not start recording");
            _onStateChange(false, null);
            return;
        }

        _region = region;
        _format = config.Format;
        _timer.Start();

        // On-screen recording overlays (captured in the video). Start after the engine so they only show while live.
        if (config.ClickHighlights) { _clicks = new ClickHighlighter(); _clicks.Start(); }
        if (config.KeystrokeOverlay) { _keystrokes = new KeystrokeOverlayWindow(); _keystrokes.Start(); }
        if (config.Camera) { _camera = new CameraBubbleWindow(config.CameraSize.Diameter(), region); _ = _camera.StartAsync(); }

        _onStateChange(true, _state.ElapsedString(DateTime.Now));
        _onPauseStateChange(true, false);
    }

    private void TearDownOverlays()
    {
        _clicks?.Stop();
        _clicks = null;
        _keystrokes?.Stop();
        _keystrokes = null;
        _camera?.Stop();
        _camera = null;
    }

    /// <summary>
    /// App is quitting: best-effort finalize an in-progress recording so the file isn't lost. Pumps the dispatcher
    /// (so the async stop's continuations can run on this thread) up to a ~3s deadline. GIF conversion and the
    /// Quick Access card are skipped — the MP4 is saved by the engine, which is the important part.
    /// </summary>
    public void StopForExit()
    {
        if (!IsRecording) return;
        _exiting = true;

        var frame = new DispatcherFrame();
        _ = StopAsync().ContinueWith(_ => frame.Continue = false, TaskScheduler.FromCurrentSynchronizationContext());

        var deadline = new DispatcherTimer { Interval = TimeSpan.FromSeconds(3) };
        deadline.Tick += (_, _) => { deadline.Stop(); frame.Continue = false; };
        deadline.Start();

        Dispatcher.PushFrame(frame);
        deadline.Stop();
    }

    private async Task StopAsync()
    {
        if (_stopping) return;
        _stopping = true;
        try
        {
            _timer.Stop();
            _state.Transition(RecorderEvent.Finish);
            TearDownOverlays();

            var thumb = CaptureThumb(_region);
            string? path = await _engine.StopAsync();

            _state = RecorderState.Idle;
            _onStateChange(false, null);
            _onPauseStateChange(false, false);

            if (path is null) return;

            // GIF: convert the finished MP4 (skipped when quitting — keep the MP4 so nothing is lost).
            if (!_exiting && _format == RecordingFormat.Gif)
            {
                HudController.Show("Converting to GIF…");
                string gifPath = Path.ChangeExtension(path, ".gif");
                path = await GifExporter.ConvertAsync(path, gifPath) ?? path;
            }

            if (!_exiting)
                _onFinished(path, thumb);
        }
        finally
        {
            _stopping = false;
        }
    }

    private static BitmapSource CaptureThumb(PxRect region)
    {
        try
        {
            return ScreenCapture.CaptureRegion(region);
        }
        catch
        {
            var blank = new WriteableBitmap(2, 2, 96, 96, PixelFormats.Bgra32, null);
            blank.Freeze();
            return blank;
        }
    }
}
