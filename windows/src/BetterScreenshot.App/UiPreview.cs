using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Editor;
using BetterScreenshot.App.Onboarding;
using BetterScreenshot.App.Overlays;
using BetterScreenshot.App.Recording;
using BetterScreenshot.App.Settings;
using BetterScreenshot.App.Tray;
using BetterScreenshot.Platform;
using Application = System.Windows.Application;
using Color = System.Windows.Media.Color;
using Point = System.Windows.Point;

namespace BetterScreenshot.App;

/// <summary>
/// Dev-only window gallery: `BetterScreenshot.exe --ui-preview &lt;name&gt;` opens one window with sample
/// data and NO hotkeys / NO single-instance mutex, so the themed UI can be screenshotted even while a
/// real instance is running. Settings are in-memory defaults — nothing is persisted from a preview.
///
/// Like the shipped app it stays <b>resident in the tray</b> under <see cref="ShutdownMode.OnExplicitShutdown"/>:
/// closing a preview window (e.g. Settings) returns to the tray instead of quitting the whole process — the
/// preview used to run under OnLastWindowClose, which made "close Settings" read as "close the whole app".
/// Reopen Settings or Quit from the tray icon.
///
/// Names: settings (default) | editor | quickaccess | welcome | strip.
/// </summary>
internal static class UiPreview
{
    // Held for the process lifetime so the tray icon + command surface aren't garbage-collected.
    private static TrayIcon? _tray;
    private static PreviewCommands? _commands;

    public static void Show(string name)
    {
        // Resident like the real tray agent: a closed window must not tear down the process.
        Application.Current.ShutdownMode = ShutdownMode.OnExplicitShutdown;
        _commands = new PreviewCommands(name);
        _tray = new TrayIcon(_commands, new SettingsStore().Hotkeys);
        Application.Current.Exit += (_, _) => _tray?.Dispose(); // remove the tray icon cleanly on Quit
        _commands.OpenInitialWindow();
    }

    /// <summary>Tray-facing command surface for the preview: reopen Settings and Quit cleanly. The
    /// capture/recording/history actions are no-ops — a static preview has no live pipeline behind them.</summary>
    internal sealed class PreviewCommands : IAppCommands
    {
        private readonly string _name;
        private SettingsWindow? _settingsWindow;

        public PreviewCommands(string name) => _name = name;

        /// <summary>Opens the window the preview was launched for (settings by default).</summary>
        public void OpenInitialWindow()
        {
            switch (_name)
            {
                case "editor":
                    new EditorWindow(SampleImage(900, 560)).Show();
                    break;
                case "quickaccess":
                    var qa = new QuickAccessWindow(SampleImage(400, 224), QuickAccessKind.Screenshot,
                        new QuickAccessActions(), dragFile: null);
                    qa.MoveTo(320, 280);
                    qa.Show();
                    break;
                case "welcome":
                    new WelcomeWindow().Show();
                    break;
                case "strip":
                    new RecordStripWindow(new SettingsStore()).Show();
                    break;
                default: // "settings", "shortcuts" (the Shortcuts card is in the same scroll)
                    OpenSettings();
                    break;
            }
        }

        public void OpenSettings()
        {
            if (_settingsWindow != null) { _settingsWindow.Activate(); return; }
            _settingsWindow = new SettingsWindow(new SettingsStore(), new HotkeyController(this));
            _settingsWindow.Closed += (_, _) => _settingsWindow = null;
            _settingsWindow.Show();
        }

        public void Quit() => Application.Current.Shutdown();

        // No live capture/recording/history surface behind a static preview.
        public void CaptureArea() { }
        public void CaptureWindow() { }
        public void CaptureFullscreen() { }
        public void CaptureText() { }
        public void ToggleRecording() { }
        public void PauseResumeRecording() { }
        public void PinFromClipboard() { }
        public void OpenHistory() { }
        public void RestoreRecentlyClosed() { }
    }

    /// <summary>A recognizable sample bitmap (diagonal gradient + a light panel) for thumbnails/canvas.</summary>
    internal static BitmapSource SampleImage(int width, int height)
    {
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            var gradient = new LinearGradientBrush(
                Color.FromRgb(0x3A, 0x5F, 0x9E), Color.FromRgb(0x7A, 0x4F, 0x8E),
                new Point(0, 0), new Point(1, 1));
            dc.DrawRectangle(gradient, null, new Rect(0, 0, width, height));
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(0x66, 0xFF, 0xFF, 0xFF)), null,
                new Rect(width * 0.12, height * 0.18, width * 0.5, height * 0.4), 12, 12);
        }
        var bmp = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bmp.Render(visual);
        bmp.Freeze();
        return bmp;
    }
}
