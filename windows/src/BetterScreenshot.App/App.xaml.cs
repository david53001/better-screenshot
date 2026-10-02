using System.Threading;
using System.Windows;
using BetterScreenshot.App.Capture;
using BetterScreenshot.App.Onboarding;
using BetterScreenshot.App.Settings;
using BetterScreenshot.App.Tours;
using BetterScreenshot.App.Tray;
using BetterScreenshot.Capture;
using BetterScreenshot.Platform;
using BetterScreenshot.Tours;

namespace BetterScreenshot.App;

/// <summary>
/// Application entry point. BetterScreenshot is a tray agent: it has no main window and stays alive
/// until the user quits from the tray menu (ShutdownMode = OnExplicitShutdown). Later Phase-3 tasks wire the
/// hotkey host and the real capture/recording coordinators into the command surface.
/// </summary>
public partial class App : System.Windows.Application
{
    private SettingsStore _settings = null!;
    private TrayIcon _tray = null!;
    private HotkeyController _hotkeys = null!;
    private CaptureCoordinator _commands = null!;
    private TourCoordinator _tours = null!;
    private WelcomeWindow? _welcome;

    /// <summary>The id the audience classifier expects (Windows has one real app; §7.1 signal 1 always passes).</summary>
    public const string AppId = "BetterScreenshot.Windows";

    // Single-instance guard: a tray agent must only run once per user session, otherwise a second
    // launch spawns a duplicate tray icon and its global-hotkey registration (RegisterHotKey) fails
    // because the first instance already owns those combos. Held for the process lifetime.
    private Mutex? _instanceMutex;
    private bool _ownsInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        InstallCrashGuards();
        // An accent change in Windows Settings arrives as ImmersiveColorSet (General): re-read it on next use.
        Microsoft.Win32.SystemEvents.UserPreferenceChanged += (_, a) =>
        {
            if (a.Category is Microsoft.Win32.UserPreferenceCategory.General or Microsoft.Win32.UserPreferenceCategory.Color)
                Controls.SystemAccent.Invalidate();
        };
        Controls.Surfaces.Set(Core.UiOpacity.Default); // surface brushes exist before any window loads

        // Perf harness workload (REVAMP section 6.1): 20 off-screen capture/card/editor cycles, then exit.
        if (PerfProbe.IsRequest(e.Args))
        {
            PerfProbe.Run(this, e.Args);
            return;
        }

        // Headless screenshot mode (see PreviewRenderer): every window off-screen → PNGs → exit.
        if (PreviewRenderer.IsRenderRequest(e.Args))
        {
            PreviewRenderer.Run(this, e.Args);
            return;
        }

        // Dev-only UI gallery (see UiPreview): no mutex/tray/hotkeys, coexists with a live instance.
        if (e.Args.Length >= 1 && e.Args[0] == "--ui-preview")
        {
            // A throwaway profile, so a gallery window that saves (Settings, the strip) never touches the real one.
            if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable(Platform.SettingsStore.DirectoryOverrideVariable)))
                Environment.SetEnvironmentVariable(Platform.SettingsStore.DirectoryOverrideVariable,
                    System.IO.Path.Combine(System.IO.Path.GetTempPath(), "BetterScreenshot-preview-" + Environment.ProcessId));
            _startupComplete = true; // dev gallery: a failing window is logged, the rest still render
            UiPreview.Show(e.Args.Length > 1 ? e.Args[1] : "settings");
            return;
        }

        _instanceMutex = new Mutex(initiallyOwned: true, @"Local\BetterScreenshot.SingleInstance", out _ownsInstance);
        if (!_ownsInstance)
        {
            // Another instance is already live (in the tray). Exit quietly without touching the tray or hotkeys.
            Shutdown();
            return;
        }

        // Who gets tours (§7.1 Step 1): classify once, before anything writes settings.json.
        var signals = SettingsStore.AudienceSignals();
        _settings = SettingsStore.Load();
        // An unreadable settings.json (round 2 #7) is not a new user and must not be overwritten at launch: no
        // classification save, no Run-key reconcile from default values, no Welcome.
        if (_settings.LoadFailed)
        {
            _settings.TourAudience = TourAudience.Store(TourAudienceKind.Existing);
            Overlays.HudController.Show("Couldn't read your settings — using defaults (details in error.log)", Overlays.HudIcon.Warning);
        }
        else if (_settings.TourAudience is null)
        {
            var audience = TourAudience.Classify(new AudienceSignals(AppId, signals.Keys, signals.FolderHasContent, false), AppId);
            _settings.TourAudience = TourAudience.Store(audience);
            _settings.Save();
        }
        // Keep the Windows "run at sign-in" registration honest: refresh the Run key to this exe's current path
        // (repairs a stale entry after the app is moved/republished) or clear it if the flag was turned off.
        if (!_settings.LoadFailed) StartupRegistration.Reconcile(_settings.LaunchAtLogin);
        // How long clipboard/drag temp PNGs survive is a user setting; apply it before the first capture can run.
        TempFiles.Configure(_settings.Capture.TempRetentionSeconds);
        // v3 §4.2: the launch sweep removes expired payload folders a previous run left (off the UI thread).
        _ = Task.Run(() => TempFiles.SweepOrphans());
        // A take the last run never finished (crash / kill): join its parts into the Recordings folder (round 2 #2).
        string recordingsDir = _settings.RecordingsDirectory;
        _ = Task.Run(() => Recording.RecordingEngine.RecoverOrphansAsync(recordingsDir)).ContinueWith(t =>
        {
            if (t.Status == TaskStatus.RanToCompletion && t.Result > 0)
                Overlays.HudController.Show(t.Result == 1 ? "Recovered an interrupted recording to your Recordings folder"
                    : $"Recovered {t.Result} interrupted recordings to your Recordings folder", Overlays.HudIcon.Done);
        }, TaskScheduler.FromCurrentSynchronizationContext());
        Controls.Surfaces.Set(_settings.Capture.UiOpacity);
        _commands = new CaptureCoordinator(_settings, Shutdown);
        _tray = new TrayIcon(_commands, _settings.Hotkeys);
        _hotkeys = new HotkeyController(_commands);
        _hotkeys.Apply(_settings.Hotkeys);
        _commands.OnOpenSettings = ShowSettings;
        _commands.OnRecordingStateChanged = _tray.SetRecordingState;
        _commands.OnRecordingPauseChanged = _tray.SetPauseState;

        _tours = new TourCoordinator(_settings, ShortcutText)
        {
            OpenSurface = OpenTourSurface,
            Hud = message => Overlays.HudController.Show(message),
            OnFinished = id => { if (id == TourId.Welcome) _welcome?.Close(); },
            // Settings tour step 3 ("Opacity") runs the live slider demo while its tag shows.
            OnStepShown = (id, step) => { if (id == TourId.Settings && step == 2) _settingsWindow?.StartOpacityDemo(); },
            OnStepLeft = () => _settingsWindow?.StopOpacityDemo(),
        };
        _tours.Install();
        _tray.AddHelpMenu(id => TourEvents.Replay(id, null), () => Overlays.HudController.Show(_tours.ResetAll()));

        WritePerfReadyLog(e.Args);
        _startupComplete = true;

        var stored = TourAudience.Parse(_settings.TourAudience);
        bool answered = _settings.TourQuestionAnswered == true;
        if (!_settings.FirstRunComplete || TourRules.ShouldOpenWelcomeOnLaunch(stored, answered, permissionGranted: true))
            ShowWelcome();
    }

    /// <summary>The Welcome window: asks the tour question only for a new user who hasn't answered.</summary>
    private void ShowWelcome()
    {
        if (_welcome is not null) { Controls.WindowPlacement.BringHere(_welcome); return; }
        bool ask = TourRules.ShouldAskQuestion(TourAudience.Parse(_settings.TourAudience), _settings.TourQuestionAnswered == true);
        _welcome = new WelcomeWindow(_settings.Hotkeys, ask);
        _welcome.Answered += yes =>
        {
            _settings.FirstUseToursEnabled = yes;
            _settings.TourQuestionAnswered = true;
            _settings.Save();
            if (yes) TourEvents.Replay(TourId.Welcome, _welcome);
        };
        _welcome.Closed += (_, _) =>
        {
            _welcome = null;
            if (!_settings.FirstRunComplete)
            {
                _settings.FirstRunComplete = true;
                _settings.Save();
            }
        };
        _welcome.Show();
    }

    private bool OpenTourSurface(TourSurface surface)
    {
        switch (surface)
        {
            case TourSurface.Welcome: ShowWelcome(); return true;
            case TourSurface.Settings: ShowSettings(); return true;
            case TourSurface.History: _commands.OpenHistory(); return true;
            default: return false;
        }
    }

    /// <summary>A tour body's <c>{shortcut:…}</c>: the user's current combo, or the action's title when unbound.</summary>
    private string? ShortcutText(string name)
    {
        if (!Enum.TryParse<HotkeyAction>(name, ignoreCase: true, out var action) || !string.Equals(name, char.ToLowerInvariant(action.ToString()[0]) + action.ToString()[1..], StringComparison.Ordinal))
            return null;
        return _settings.Hotkeys.Combo(action)?.DisplayString ?? action.Title();
    }

    /// <summary>
    /// A tray agent must not die because one window hit a bug (review round 1 #1/#6): a UI-thread exception is logged to
    /// <see cref="ErrorLog"/> and reported with a HUD, and the app keeps running (an active recording keeps going);
    /// unobserved task exceptions are logged and observed; anything else that is truly fatal is at least logged.
    /// </summary>
    private bool _startupComplete;
    private DateTime _lastCrashToast = DateTime.MinValue;

    private void InstallCrashGuards()
    {
        DispatcherUnhandledException += (_, args) =>
        {
            args.Handled = true;
            if (!_startupComplete)
            {
                // A half-started tray app would hold the single-instance mutex with no tray or hotkeys, and every
                // relaunch would exit quietly (round 2 #9): log it and quit so the next launch starts clean.
                ErrorLog.Write("Unhandled exception during startup — quitting", args.Exception);
                Shutdown(1);
                return;
            }
            ErrorLog.Write("Unhandled UI exception (recovered)", args.Exception);
            // A repeating fault (a timer tick, a layout pass) logs every time but toasts at most every 10 s.
            if (DateTime.UtcNow - _lastCrashToast < TimeSpan.FromSeconds(10)) return;
            _lastCrashToast = DateTime.UtcNow;
            try { Overlays.HudController.Show("Something went wrong — details in error.log", Overlays.HudIcon.Warning); }
            catch (Exception) { /* the HUD itself failed; the log has it */ }
        };
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            ErrorLog.Write("Unobserved task exception", args.Exception);
            args.SetObserved();
        };
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            ErrorLog.Write("Fatal unhandled exception", args.ExceptionObject as Exception);
    }

    /// <summary><c>--perf-ready-log &lt;file&gt;</c> (perf harness only): once the tray + hotkeys are up, write the
    /// milliseconds since process start, at the first idle moment after startup.</summary>
    private void WritePerfReadyLog(string[] args)
    {
        int i = Array.IndexOf(args, "--perf-ready-log");
        if (i < 0 || i + 1 >= args.Length) return;
        string path = args[i + 1];
        Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.ApplicationIdle, () =>
        {
            var ms = (DateTime.Now - System.Diagnostics.Process.GetCurrentProcess().StartTime).TotalMilliseconds;
            try { System.IO.File.WriteAllText(path, ((int)ms).ToString(System.Globalization.CultureInfo.InvariantCulture)); }
            catch (System.IO.IOException) { }
            catch (UnauthorizedAccessException) { }
        });
    }

    private SettingsWindow? _settingsWindow;

    private void ShowSettings()
    {
        if (_settingsWindow != null) { Controls.WindowPlacement.BringHere(_settingsWindow); return; }
        _settingsWindow = new SettingsWindow(_settings, _hotkeys);
        _settingsWindow.HotkeysChanged += () => _tray.UpdateShortcuts(_settings.Hotkeys);
        _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        _settingsWindow.Show();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _commands?.StopRecordingForExit(); // best-effort finalize an in-progress recording before we tear down
        _hotkeys?.Dispose();
        _tray?.Dispose();
        if (_ownsInstance)
        {
            _instanceMutex?.ReleaseMutex();
            _instanceMutex?.Dispose();
        }
        base.OnExit(e);
    }
}
