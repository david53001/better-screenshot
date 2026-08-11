using System.Threading;
using System.Windows;
using BetterScreenshot.App.Capture;
using BetterScreenshot.App.Onboarding;
using BetterScreenshot.App.Settings;
using BetterScreenshot.App.Tray;
using BetterScreenshot.Platform;

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

    // Single-instance guard: a tray agent must only run once per user session, otherwise a second
    // launch spawns a duplicate tray icon and its global-hotkey registration (RegisterHotKey) fails
    // because the first instance already owns those combos. Held for the process lifetime.
    private Mutex? _instanceMutex;
    private bool _ownsInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Dev-only UI gallery (see UiPreview): no mutex/tray/hotkeys, coexists with a live instance.
        if (e.Args.Length >= 1 && e.Args[0] == "--ui-preview")
        {
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

        _settings = SettingsStore.Load();
        // Keep the Windows "run at sign-in" registration honest: refresh the Run key to this exe's current path
        // (repairs a stale entry after the app is moved/republished) or clear it if the flag was turned off.
        StartupRegistration.Reconcile(_settings.LaunchAtLogin);
        // How long clipboard/drag temp PNGs survive is a user setting; apply it before the first capture can run.
        TempFiles.Configure(_settings.Capture.TempRetentionMinutes);
        _commands = new CaptureCoordinator(_settings, Shutdown);
        _tray = new TrayIcon(_commands, _settings.Hotkeys);
        _hotkeys = new HotkeyController(_commands);
        _hotkeys.Apply(_settings.Hotkeys);
        _commands.OnOpenSettings = ShowSettings;
        _commands.OnRecordingStateChanged = _tray.SetRecordingState;
        _commands.OnRecordingPauseChanged = _tray.SetPauseState;

        if (!_settings.FirstRunComplete)
        {
            new WelcomeWindow().ShowDialog();
            _settings.FirstRunComplete = true;
            _settings.Save();
        }
    }

    private SettingsWindow? _settingsWindow;

    private void ShowSettings()
    {
        if (_settingsWindow != null) { _settingsWindow.Activate(); return; }
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
