using System.Diagnostics;
using System.IO;
using System.Windows.Media.Imaging;
using BetterScreenshot.App.Editor;
using BetterScreenshot.App.History;
using BetterScreenshot.App.Overlays;
using BetterScreenshot.App.Recording;
using BetterScreenshot.App.Tray;
using BetterScreenshot.Capture;
using BetterScreenshot.Core;
using BetterScreenshot.Platform;

namespace BetterScreenshot.App.Capture;

/// <summary>
/// Orchestrates the screenshot flow: selection/picker overlays → capture (via the Platform layer) → route by the
/// after-capture setting → save/copy/Quick Access card, plus Capture Text (region OCR), pins, history, and the
/// recording toggle.
/// </summary>
public sealed class CaptureCoordinator : IAppCommands
{
    private readonly SettingsStore _settings;
    private readonly Action _quit;
    private readonly HistoryService _history;
    private readonly SelectionOverlayController _selection = new();
    private readonly QuickAccessStackController _stack = new();
    private readonly PinPanelController _pins = new();
    private readonly WindowPickerController _picker = new();
    private readonly RecordingCoordinator _recording;
    private HistoryWindow? _historyWindow;

    public CaptureCoordinator(SettingsStore settings, Action quit)
    {
        _settings = settings;
        _quit = quit;
        _history = HistoryService.ForSettings(settings);
        _recording = new RecordingCoordinator(
            settings,
            (recording, elapsed) => OnRecordingStateChanged?.Invoke(recording, elapsed),
            (active, paused) => OnRecordingPauseChanged?.Invoke(active, paused),
            OnRecordingFinished);
    }

    /// <summary>Set by the app to show the settings window (which needs the hotkey controller too).</summary>
    public Action? OnOpenSettings { get; set; }

    /// <summary>Set by the app to reflect recording state (icon + elapsed timer) in the tray.</summary>
    public Action<bool, string?>? OnRecordingStateChanged { get; set; }

    /// <summary>Set by the app to reflect pause state (active?, paused?) on the tray Pause/Resume menu item.</summary>
    public Action<bool, bool>? OnRecordingPauseChanged { get; set; }

    public void CaptureFullscreen()
    {
        var monitor = Screens.Primary();
        Handle(ScreenCapture.CaptureDisplay(monitor));
    }

    public void CaptureWindow()
    {
        // Freeze first, while the app you were using still has focus — the picker overlay is what makes it lose it.
        var frozen = Freeze();
        _picker.Present(pick =>
        {
            if (pick is { } p && p.Hwnd != IntPtr.Zero) Handle(p.Frozen ?? ScreenCapture.CaptureWindow(p.Hwnd));
        }, frozen);
    }

    public void CaptureArea()
    {
        _selection.Present(_settings.Capture.FreezeScreen, selection =>
        {
            if (selection is { } s) Handle(Pixels(s));
        });
    }

    /// <summary>Capture Text (OCR + QR): drag a region; the recognized text — or a QR code's payload,
    /// which wins — lands on the clipboard. HUD confirms.</summary>
    public void CaptureText()
    {
        _selection.Present(_settings.Capture.FreezeScreen, selection =>
        {
            if (selection is { } s) _ = CaptureTextAsync(s);
        });
    }

    /// <summary>A still of every screen when "Freeze the screen" is on, else null (overlays stay see-through
    /// and the capture is taken live).</summary>
    private FrozenScreen? Freeze() => _settings.Capture.FreezeScreen ? FrozenScreen.Capture() : null;

    /// <summary>The selected pixels: cropped out of the frozen still when there is one, else captured live.</summary>
    private static BitmapSource Pixels(AreaSelection selection) =>
        selection.Frozen ?? ScreenCapture.CaptureRegion(selection.Region);

    private async Task CaptureTextAsync(AreaSelection selection)
    {
        try
        {
            var image = Pixels(selection);
            var result = await TextRecognizerService.RecognizeAsync(image);
            if (result.ClipboardString is { } text) ClipboardService.SetText(text);
            HudController.Show(result.HudMessage);
        }
        catch
        {
            // Never crash the app on a failed recognition.
            HudController.Show("Capture Text failed");
        }
    }

    private void Handle(BitmapSource image)
    {
        var (copy, save, overlay) = CaptureRouter.Decide(_settings.Capture.AfterCapture);
        if (copy) Copy(image);
        if (save) Save(image);
        // Remember every non-ephemeral capture (saved or shown) in history; copy-only captures stay transient.
        Guid? historyId = (save || overlay) ? _history.RecordScreenshot(image) : null;
        if (overlay) ShowOverlayCard(image, historyId);
    }

    private void ShowOverlayCard(BitmapSource image, Guid? historyId = null)
    {
        string dragFile = ImageIo.WriteTempPng(image, "quickaccess.png");
        var actions = new QuickAccessActions
        {
            OnCopy = () => Copy(image),
            OnSave = () => Save(image),
            OnPin = () => PinImage(image),
            OnEdit = () => Annotate(image),
        };
        _stack.Present(image, QuickAccessKind.Screenshot, actions, MapCorner(_settings.Capture.OverlayCorner),
            dragFile, _settings.Capture.OverlayAutoDismissSeconds, reason =>
            {
                OnCardDismissed(historyId, reason);
                // The temp PNG only backs drag-to-export. Keep it alive for PayloadLifetime (5 min) after the card
                // goes away so an in-flight drop into another app can still read the file, then auto-delete it. The
                // screenshot itself is preserved separately in History (its own %APPDATA% copy), so this never loses
                // the capture — it only cleans up the throwaway drag file.
                TempFiles.ScheduleDeleteContainingDir(dragFile, TempFiles.PayloadLifetime);
            });
    }

    /// <summary>Only ✕-closed / evicted cards are restorable; deliberate actions (save/edit/pin) are not.</summary>
    private void OnCardDismissed(Guid? historyId, DismissReason reason)
    {
        if (historyId is { } id && reason is DismissReason.Closed or DismissReason.Evicted)
            _history.NoteClosed(id);
    }

    private static Corner MapCorner(SettingsOverlayCorner corner) => corner switch
    {
        SettingsOverlayCorner.TopLeft => Corner.TopLeft,
        SettingsOverlayCorner.TopRight => Corner.TopRight,
        SettingsOverlayCorner.BottomLeft => Corner.BottomLeft,
        _ => Corner.BottomRight,
    };

    private void Save(BitmapSource image)
    {
        bool jpg = _settings.Capture.Format == SettingsImageFormat.Jpg;
        string ext = jpg ? "jpg" : "png";
        string path = Path.Combine(_settings.SaveDirectory, FileNamer.Name(DateTime.Now, ext));
        if (jpg) ImageIo.SaveJpg(image, path); else ImageIo.SavePng(image, path);
    }

    private static void Copy(BitmapSource image) => ClipboardService.SetImage(image);

    public void PinFromClipboard()
    {
        if (System.Windows.Clipboard.ContainsImage())
        {
            var image = System.Windows.Clipboard.GetImage();
            if (image != null) PinImage(image);
        }
    }

    private void PinImage(BitmapSource image)
    {
        var style = new PinStyle(_settings.Capture.PinCornerRadius, _settings.Capture.PinShadow);
        var actions = new PinActions(() => Copy(image), () => Save(image));
        _pins.Pin(image, style, actions);
    }

    /// <summary>Opens the annotation editor on the image, wiring copy/save/stack and sticky-style persistence.</summary>
    private void Annotate(BitmapSource image)
    {
        var editor = new EditorWindow(image, _settings.EditorStyle)
        {
            OnCopy = Copy,
            OnSave = Save,
            OnAddToStack = KeepInStack,
            StyleChanged = style => { _settings.EditorStyle = style; _settings.Save(); },
        };
        editor.Show();
    }

    /// <summary>Editor "Stack" button: record the flattened edit in history and re-enter the Quick Access flow.</summary>
    private void KeepInStack(BitmapSource image)
    {
        var id = _history.RecordScreenshot(image);
        ShowOverlayCard(image, id);
    }

    /// <summary>Restore Recently Closed: bring back the newest ✕-closed card that still exists in history.</summary>
    public void RestoreRecentlyClosed()
    {
        var entry = _history.PopRestorable();
        if (entry is null) return;
        var image = _history.LoadImage(entry);
        if (image != null) ShowOverlayCard(image, entry.Id);
    }

    /// <summary>Shows the capture-history browser (a single reused window), reloading its grid each time.</summary>
    public void OpenHistory()
    {
        if (_historyWindow is null)
        {
            _historyWindow = new HistoryWindow(_history, new HistoryWindowActions(Annotate, PinImage));
            _historyWindow.Closed += (_, _) => _historyWindow = null;
            _historyWindow.Show();
        }
        else
        {
            _historyWindow.Activate();
        }
    }

    /// <summary>Start/stop a screen recording (record strip → target picking).</summary>
    public void ToggleRecording() => _recording.Toggle();

    /// <summary>Pause or resume the active recording (gapless via segment+concat).</summary>
    public void PauseResumeRecording() => _recording.PauseResume();

    /// <summary>A finished recording: record it in history and show a Quick Access recording card.</summary>
    private void OnRecordingFinished(string path, BitmapSource thumbnail)
    {
        Guid? id = _history.RecordRecording(path, thumbnail);
        ShowRecordingCard(path, thumbnail, id);
    }

    private void ShowRecordingCard(string path, BitmapSource thumbnail, Guid? historyId)
    {
        var actions = new QuickAccessActions
        {
            OnCopy = () => ClipboardService.SetFile(path),
            OnOpen = () => OpenFile(path),
            OnReveal = () => RevealFile(path),
        };
        // Recording cards drag the real saved file (never a temp copy) — so it is NOT scheduled for deletion.
        _stack.Present(thumbnail, QuickAccessKind.Recording, actions, MapCorner(_settings.Capture.OverlayCorner),
            path, _settings.Capture.OverlayAutoDismissSeconds, reason => OnCardDismissed(historyId, reason));
    }

    private static void OpenFile(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
        catch { /* best-effort: no default handler */ }
    }

    private static void RevealFile(string path)
    {
        try { Process.Start(new ProcessStartInfo("explorer.exe", HistoryService.ExplorerSelectArgs(path)) { UseShellExecute = true }); }
        catch { /* best-effort */ }
    }

    /// <summary>Called on app exit: best-effort finalize an in-progress recording so it isn't lost.</summary>
    public void StopRecordingForExit() => _recording.StopForExit();

    public void OpenSettings() => OnOpenSettings?.Invoke();
    public void Quit() => _quit();
}
