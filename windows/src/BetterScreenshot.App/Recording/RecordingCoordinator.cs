using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using BetterScreenshot.App.Controls;
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
/// the tray icon, the timer and the floating <see cref="RecordingPillWindow"/>; on stop the finished MP4 + a
/// thumbnail go to history + the Quick Access card.
///
/// The pill (v3 A.2 + Part 5) shows from the moment a target is picked — before the countdown — until stop, cancel,
/// discard or failure, and carries the live controls: mute mic / system audio (silent track, stays in sync),
/// camera bubble show/hide, Switch Window/Area (pause → pick → letterboxed into the first frame size → resume),
/// Restart and Discard (two clicks within 3 s), Pause, Stop and collapse. Engine operations are serialised by
/// <see cref="_gate"/> because each one ends/starts ffmpeg segments. The whole flow stays on the UI thread (no
/// ConfigureAwait(false) here) so the DispatcherTimer and callbacks run on the dispatcher.
/// </summary>
public sealed class RecordingCoordinator
{
    private static readonly TimeSpan ConfirmWindow = TimeSpan.FromSeconds(3);

    private readonly SettingsStore _settings;
    private readonly RecordingEngine _engine = new();
    private readonly DispatcherTimer _timer;
    private readonly DispatcherTimer _confirmTimer;
    private readonly SemaphoreSlim _gate = new(1, 1);
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
    private RecordingPillWindow? _pill;
    private RecorderState _state = RecorderState.Idle;
    private PxRect _region;
    private PillTarget _target;
    private RecordingConfig _config = RecordingConfig.Default;
    private AudioInputs _audio = AudioInputs.None;
    private RecordingFormat _format;
    private bool _micMuted, _systemMuted;
    private PillCamera _cameraState = PillCamera.Hidden;
    private PillConfirm _confirm = PillConfirm.None;
    private bool _stopping;
    private bool _exiting;
    private bool _switching;

    public RecordingCoordinator(SettingsStore settings, Action<bool, string?> onStateChange,
        Action<bool, bool> onPauseStateChange, Action<string, BitmapSource> onFinished)
    {
        _settings = settings;
        _onStateChange = onStateChange;
        _onPauseStateChange = onPauseStateChange;
        _onFinished = onFinished;
        _timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        _timer.Tick += (_, _) =>
        {
            _onStateChange(true, _state.ElapsedString(DateTime.Now));
            UpdatePill();
        };
        _confirmTimer = new DispatcherTimer { Interval = ConfirmWindow };
        _confirmTimer.Tick += (_, _) => CancelConfirm();
        var dispatcher = Dispatcher.CurrentDispatcher;
        _engine.SegmentDied += () => dispatcher.BeginInvoke(OnSegmentDied);
    }

    /// <summary>The live segment's ffmpeg quit by itself (round 2 #1): stop the take so what was recorded is saved, and
    /// say why (StopAsync shows <see cref="RecordingEngine.LastFailure"/>). A Switch checks its own new segment and
    /// rolls back, so it is left to do that.</summary>
    private void OnSegmentDied()
    {
        if (_switching || _stopping || _state.Phase != RecorderPhase.Recording) return;
        _ = StopAsync();
    }

    public bool IsRecording => _state.Phase is RecorderPhase.Recording or RecorderPhase.Paused;

    /// <summary>Pause a running recording or resume a paused one (no-op otherwise). Gapless via segment+concat.</summary>
    public void PauseResume() => _ = PauseResumeAsync();

    private async Task PauseResumeAsync()
    {
        if (_switching) return; // the Switch picker owns pause/resume until it's done (round 2 #12)
        CancelConfirm();
        await _gate.WaitAsync();
        try
        {
            if (_state.Phase == RecorderPhase.Recording) await PauseCoreAsync();
            else if (_state.Phase == RecorderPhase.Paused) ResumeCore();
        }
        finally { _gate.Release(); }
    }

    private async Task PauseCoreAsync()
    {
        if (!_state.Transition(RecorderEvent.Pause, DateTime.Now)) return;
        _timer.Stop();
        await _engine.PauseAsync();
        _onStateChange(true, _state.ElapsedString(DateTime.Now)); // "Paused · m:ss" (frozen)
        _onPauseStateChange(true, true);
        UpdatePill();
    }

    private void ResumeCore()
    {
        if (!_state.Transition(RecorderEvent.Resume, DateTime.Now)) return;
        _engine.Resume();
        _timer.Start();
        _onStateChange(true, _state.ElapsedString(DateTime.Now));
        _onPauseStateChange(true, false);
        UpdatePill();
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
            HudController.Show("ffmpeg not found — recording unavailable", HudIcon.Warning);
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
        TearDownOverlays();   // the pill (and, after a Restart, the overlays kept up for the new take)
        _state.Transition(RecorderEvent.Reset);
        _onStateChange(false, null);
    }

    private void BeginFullScreen()
    {
        HideStrip();
        _ = BeginAsync(OverlayHelpers.MonitorUnderCursor().Bounds, PillTarget.FullScreen);
    }

    private void BeginArea()
    {
        HideStrip();
        // Never freeze when picking a recording target: only the rectangle matters here (the recording itself is
        // live), and selecting against a stale still would just misrepresent what is about to be recorded.
        _selection.Present(freeze: false, selection =>
        {
            if (selection is { } s && !s.Region.IsEmpty) _ = BeginAsync(s.Region, PillTarget.Area);
            else AbortArm();
        });
    }

    private void BeginWindow()
    {
        HideStrip();
        _picker.Present(pick =>
        {
            if (pick is { } p && WindowEnum.FrameBounds(p.Hwnd) is { } r) _ = BeginAsync(r, PillTarget.Window);
            else AbortArm();
        });
    }

    private void AbortArm()
    {
        if (_state.Phase == RecorderPhase.Armed)
        {
            ClosePill();
            _state.Transition(RecorderEvent.Reset);
            _onStateChange(false, null);
        }
    }

    /// <summary>A target was picked: a new recording session (mute states reset; the pill appears before the countdown).</summary>
    private async Task BeginAsync(PxRect region, PillTarget target)
    {
        if (_state.Phase != RecorderPhase.Armed) return; // cancelled before we got here

        var config = _settings.Recording;
        var audio = await DshowAudioDevices.ResolveAsync(config);
        if (_state.Phase != RecorderPhase.Armed) return; // cancelled during device enumeration

        _region = region;
        _target = target;
        _config = config;
        _audio = audio;
        _micMuted = _systemMuted = false;
        _cameraState = PillCamera.Hidden;
        _confirm = PillConfirm.None;
        ShowPill();
        await StartTakeAsync();
    }

    /// <summary>Countdown (if configured) then start the engine on the current target. Shared by Begin and Restart.</summary>
    private async Task StartTakeAsync()
    {
        UpdatePill();

        // Pre-record countdown (still armed; runs before capture starts, so it is not recorded).
        if (_config.CountdownSeconds > 0)
        {
            _countdown = new CountdownOverlayWindow();
            bool proceed = await _countdown.RunAsync(_config.CountdownSeconds, _region);
            _countdown = null;
            if (!proceed) { AbortArm(); TearDownOverlays(); return; } // cancelled during countdown
            if (_state.Phase != RecorderPhase.Armed) return;
        }

        if (!_state.Transition(RecorderEvent.Begin, DateTime.Now)) { _state = RecorderState.Idle; ClosePill(); return; }

        Directory.CreateDirectory(_settings.RecordingsDirectory);
        string path = Path.Combine(_settings.RecordingsDirectory, FileNamer.Name(DateTime.Now, "mp4", "Recording"));
        await _engine.SetMutedAsync(_systemMuted, _micMuted); // applied from the first sample
        if (!_engine.Start(_config, _region, path, _audio))
        {
            _state = RecorderState.Idle;
            TearDownOverlays();
            HudController.Show(_engine.LastFailure ?? "Could not start recording", HudIcon.Warning);
            _onStateChange(false, null);
            return;
        }

        _format = _config.Format;
        _timer.Start();

        // On-screen recording overlays (captured in the video). Start after the engine so they only show while live;
        // a Restart keeps the ones already up.
        if (_config.ClickHighlights && _clicks is null) { _clicks = new ClickHighlighter(); _clicks.Start(_region); }
        if (_config.KeystrokeOverlay && _keystrokes is null) { _keystrokes = new KeystrokeOverlayWindow(); _keystrokes.Start(_region); }
        if (_config.Camera && _camera is null) _ = ShowCameraAtStartAsync();

        _onStateChange(true, _state.ElapsedString(DateTime.Now));
        _onPauseStateChange(true, false);
        UpdatePill();
    }

    // ------------------------------------------------------------------ the pill

    private void ShowPill()
    {
        if (_pill is not null) return;
        _pill = new RecordingPillWindow(WindowPlacement.WorkAreaFor(_region),
            RecordingPillLayout.ParseAnchor(_settings.RecordingPillAnchor), excludeFromCapture: !_config.ControlsInRecording);
        _pill.ItemClicked += OnPillItem;
        _pill.Moved += p =>
        {
            _settings.RecordingPillAnchor = RecordingPillLayout.FormatAnchor(p);
            _settings.Save();
        };
        UpdatePill();
        _pill.Show();
    }

    private void ClosePill()
    {
        CancelConfirm(update: false);
        _pill?.Close();
        _pill = null;
    }

    private PillState CurrentPillState() => new()
    {
        Phase = _state.Phase switch
        {
            RecorderPhase.Recording => PillPhase.Recording,
            RecorderPhase.Paused => PillPhase.Paused,
            _ => PillPhase.Countdown,
        },
        Elapsed = _state.Elapsed(DateTime.Now),
        MicTrack = _config.Microphone && _audio.MicrophoneDevice is not null,
        MicMuted = _micMuted,
        SystemTrack = _config.SystemAudio && _audio.SystemAudioDevice is not null,
        SystemMuted = _systemMuted,
        Camera = _cameraState,
        Target = _target,
        Confirm = _confirm,
        Collapsed = _settings.RecordingPillCollapsed,
    };

    private void UpdatePill() => _pill?.Apply(CurrentPillState());

    private void OnPillItem(PillItemId id)
    {
        switch (id)
        {
            case PillItemId.Mic: _ = ToggleMuteAsync(mic: true); break;
            case PillItemId.SystemAudio: _ = ToggleMuteAsync(mic: false); break;
            case PillItemId.Camera: _ = ToggleCameraAsync(); break;
            case PillItemId.Switch: _ = SwitchTargetAsync(); break;
            case PillItemId.Restart: Confirm(PillConfirm.Restart, () => _ = RestartAsync()); break;
            case PillItemId.Discard: Confirm(PillConfirm.Discard, () => _ = DiscardAsync()); break;
            case PillItemId.PauseResume: PauseResume(); break;
            case PillItemId.Stop:
                CancelConfirm();
                if (_state.Phase == RecorderPhase.Armed) CancelStrip(); // Stop during the countdown cancels
                else _ = StopAsync();
                break;
            case PillItemId.Chevron:
                CancelConfirm(update: false);
                _settings.RecordingPillCollapsed = !_settings.RecordingPillCollapsed;
                _settings.Save();
                UpdatePill();
                break;
        }
    }

    /// <summary>Restart/Discard: the first click arms a 3 s red "Restart?"/"Discard?" capsule, a second click within it acts.
    /// Deliberately not a dialog — a modal would steal focus from the app being recorded.</summary>
    private void Confirm(PillConfirm which, Action act)
    {
        if (_confirm == which)
        {
            CancelConfirm(update: false);
            act();
            return;
        }
        _confirm = which;
        _confirmTimer.Stop();
        _confirmTimer.Start();
        UpdatePill();
    }

    private void CancelConfirm(bool update = true)
    {
        _confirmTimer.Stop();
        if (_confirm == PillConfirm.None) return;
        _confirm = PillConfirm.None;
        if (update) UpdatePill();
    }

    /// <summary>Mute keeps the track (silence, stays in sync). The countdown already accepts it — applied from the first sample.</summary>
    private async Task ToggleMuteAsync(bool mic)
    {
        if (mic) _micMuted = !_micMuted;
        else _systemMuted = !_systemMuted;
        UpdatePill();
        if (!IsRecording) return; // countdown: applied when the engine starts
        await _gate.WaitAsync();
        try { await _engine.SetMutedAsync(_systemMuted, _micMuted); }
        finally { _gate.Release(); }
    }

    /// <summary>A camera start or stop is in flight: further Camera clicks wait for it (round 2 #3 — a second click
    /// used to start a second MediaCapture and leave the light on).</summary>
    private bool _cameraBusy;

    private async Task ToggleCameraAsync()
    {
        if (_cameraBusy) return;
        _cameraBusy = true;
        try
        {
            if (_camera is { } cam)
            {
                bool hide = _cameraState == PillCamera.Showing;
                bool ok = await cam.SetHiddenAsync(hide);
                if (_camera != cam) return; // torn down meanwhile
                _cameraState = hide ? PillCamera.Hidden : ok ? PillCamera.Showing : PillCamera.NoCamera;
                UpdatePill();
                return;
            }
            await ShowNewCameraAsync();
        }
        finally { _cameraBusy = false; }
    }

    private async Task ShowCameraAtStartAsync()
    {
        if (_cameraBusy) return;
        _cameraBusy = true;
        try { await ShowNewCameraAsync(); }
        finally { _cameraBusy = false; }
    }

    /// <summary>Camera off at start (or first show): create the bubble — same size setting, same corner rule as at start.</summary>
    private async Task ShowNewCameraAsync()
    {
        int generation = _overlayGeneration;
        var cameras = await CameraDevices.ListAsync();
        // Stopped / discarded / cancelled while the cameras were listed: never turn the webcam on (round 1 #5).
        if (generation != _overlayGeneration) return;
        if (cameras.ResolvedId(_config.CameraDeviceId) is not { } deviceId)
        {
            _cameraState = PillCamera.NoCamera;
            UpdatePill();
            return;
        }
        var cam = new CameraBubbleWindow(_config.CameraSize.Diameter(), _region) { DeviceId = deviceId };
        _camera = cam;
        var result = await cam.StartAsync();
        if (_camera != cam) { cam.Stop(); return; } // torn down meanwhile
        _cameraState = result switch
        {
            CameraBubbleWindow.StartResult.Started => PillCamera.Showing,
            CameraBubbleWindow.StartResult.Denied => PillCamera.Denied,
            _ => PillCamera.NoCamera,
        };
        if (result != CameraBubbleWindow.StartResult.Started) _camera = null;
        UpdatePill();
    }

    /// <summary>
    /// Switch Window… / Switch Area… (v3 Part 5): pause so the picker isn't recorded (its time is cut), pick with the
    /// same picker used to start, re-point the session (the next segment is letterboxed into the first frame size),
    /// resume if we paused, and hand focus back — to the picked window, or to whatever was frontmost (area / Esc).
    /// </summary>
    private async Task SwitchTargetAsync()
    {
        if (_target == PillTarget.FullScreen || _switching || !IsRecording) return;
        CancelConfirm();
        _switching = true;
        try
        {
            var before = ForegroundWindow.Current().Hwnd;
            bool pausedByUs = false;
            await _gate.WaitAsync();
            try
            {
                if (_state.Phase == RecorderPhase.Recording) { await PauseCoreAsync(); pausedByUs = true; }
            }
            finally { _gate.Release(); }

            (PxRect Region, IntPtr Hwnd)? picked = null;
            if (_target == PillTarget.Window)
            {
                var tcs = new TaskCompletionSource<WindowPick?>();
                _picker.Present(p => tcs.TrySetResult(p));
                if (await tcs.Task is { } p && WindowEnum.FrameBounds(p.Hwnd) is { } r) picked = (r, p.Hwnd);
            }
            else
            {
                var tcs = new TaskCompletionSource<AreaSelection?>();
                _selection.Present(freeze: false, s => tcs.TrySetResult(s));
                if (await tcs.Task is { } s && !s.Region.IsEmpty) picked = (s.Region, IntPtr.Zero);
            }
            if (!IsRecording) return; // stopped / discarded meanwhile

            await _gate.WaitAsync();
            try
            {
                var previous = _region;
                // A window partly off-screen: record the part ffmpeg can grab (gdigrab rejects rects past the desktop).
                var desktop = System.Windows.Forms.SystemInformation.VirtualScreen;
                if (picked is { } raw)
                {
                    var clamped = raw.Region.Intersection(new PxRect(desktop.X, desktop.Y, desktop.Width, desktop.Height));
                    picked = clamped.IsEmpty ? null : (clamped, raw.Hwnd);
                }
                if (picked is { } pick)
                {
                    _engine.Retarget(pick.Region);
                    _region = pick.Region;
                }
                if (pausedByUs && _state.Phase == RecorderPhase.Paused)
                {
                    bool started;
                    try { ResumeCore(); started = picked is null || await _engine.SegmentAliveAsync(TimeSpan.FromSeconds(1.2)); }
                    catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception or IOException)
                    {
                        ErrorLog.Write("Switch target failed to start", ex);
                        started = false;
                    }
                    if (!started)
                    {
                        // ffmpeg rejected the new target (it fails asynchronously, round 1 #3): keep the old one.
                        await _engine.PauseAsync();
                        _engine.Retarget(previous);
                        _region = previous;
                        HudController.Show(_target == PillTarget.Window
                            ? "Couldn't switch — still recording the previous window"
                            : "Couldn't switch — still recording the previous area", HudIcon.Warning);
                        try { _engine.Resume(); }
                        catch (Exception ex) when (ex is InvalidOperationException or System.ComponentModel.Win32Exception or IOException)
                        {
                            ErrorLog.Write("Couldn't resume the previous target", ex);
                        }
                    }
                }
            }
            finally { _gate.Release(); }

            ForegroundWindow.Restore(picked is { Hwnd: var h } && h != IntPtr.Zero ? h : before);
        }
        finally
        {
            _switching = false;
            UpdatePill();
        }
    }

    /// <summary>Restart: delete what's recorded so far and start over on the current target with the same settings —
    /// countdown included. The pill, camera bubble and click/keystroke overlays stay up; mute states carry over.</summary>
    private async Task RestartAsync()
    {
        if (!IsRecording) return;
        await _gate.WaitAsync();
        try
        {
            if (!IsRecording) return; // stopped while we waited for the gate (round 1 #4): nothing to restart
            _timer.Stop();
            await _engine.DiscardAsync();
            _state = RecorderState.Idle;
            _state.Transition(RecorderEvent.Arm);
            _onStateChange(false, null);
            _onPauseStateChange(false, false);
        }
        finally { _gate.Release(); }
        await StartTakeAsync();
    }

    /// <summary>Discard: stop, delete the file — no Quick Access card, no History entry — and say so.</summary>
    private async Task DiscardAsync()
    {
        if (!IsRecording) return;
        await _gate.WaitAsync();
        try
        {
            if (!IsRecording) return; // already stopped and saved while we waited (round 1 #4): don't claim a discard
            _timer.Stop();
            _state.Transition(RecorderEvent.Finish);
            TearDownOverlays();
            await _engine.DiscardAsync();
            _state = RecorderState.Idle;
            _onStateChange(false, null);
            _onPauseStateChange(false, false);
        }
        finally { _gate.Release(); }
        HudController.Show("Recording discarded");
    }

    /// <summary>Bumped whenever the overlays are torn down, so an await that started before can tell it's stale.</summary>
    private int _overlayGeneration;

    private void TearDownOverlays()
    {
        _overlayGeneration++;
        _clicks?.Stop();
        _clicks = null;
        _keystrokes?.Stop();
        _keystrokes = null;
        _camera?.Stop();
        _camera = null;
        ClosePill();
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
        Tours.TourEvents.Post(BetterScreenshot.Tours.TourEvent.Action("recording.stopped"));
        if (_stopping) return;
        _stopping = true;
        string? path = null;
        BitmapSource? thumb = null;
        bool toGif = false;
        await _gate.WaitAsync();
        try
        {
            if (!IsRecording)
            {
                // A Restart held the gate and is now counting down again: this Stop was meant for it (round 2 #13).
                if (_state.Phase == RecorderPhase.Armed) CancelStrip();
                return; // discarded / restarted meanwhile
            }
            _timer.Stop();
            _state.Transition(RecorderEvent.Finish);
            TearDownOverlays();

            thumb = CaptureThumb(_region);
            try { path = await _engine.StopAsync(); }
            catch (Exception ex)
            {
                // Never leave the recorder stuck in Finishing (round 2 #9): log, tell, and fall through to Idle.
                ErrorLog.Write("Stopping the recording failed", ex);
                HudController.Show("Recording failed — details in error.log", HudIcon.Warning);
                return;
            }
            finally
            {
                _state = RecorderState.Idle;
                _onStateChange(false, null);
                _onPauseStateChange(false, false);
            }

            // Never vanish silently (round 1 #2, round 2 #1): a failure is shown whether or not a file came out of it.
            if (_engine.LastFailure is { } why) HudController.Show(why, HudIcon.Warning);
            if (path is null) return;
            toGif = !_exiting && _format == RecordingFormat.Gif;
        }
        finally
        {
            // Released BEFORE the GIF conversion (round 2 #6): it can take minutes, and a new take started meanwhile
            // must be stoppable, pausable and switchable.
            _gate.Release();
            _stopping = false;
        }
        if (path is null) return;

        // GIF: convert the finished MP4 (skipped when quitting — keep the MP4 so nothing is lost).
        if (toGif)
        {
            var hud = HudController.ShowProgress("Converting to GIF…");
            try
            {
                string gifPath = Path.ChangeExtension(path, ".gif");
                path = await GifExporter.ConvertAsync(path, gifPath,
                    f => hud.Update($"Converting to GIF… {f * 100:0}%")) ?? path;
            }
            finally { hud.Close(); }
        }

        if (!_exiting)
            _onFinished(path, thumb!);
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
