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
        RememberFrontmostApp();
        var monitor = Screens.Primary();
        var image = ScreenCapture.CaptureDisplay(monitor);
        RestoreFrontmostApp();
        Handle(image);
    }

    public void CaptureWindow()
    {
        RememberFrontmostApp();
        // Freeze first, while the app you were using still has focus — the picker overlay is what makes it lose it.
        var frozen = Freeze();
        _picker.Present(pick =>
        {
            if (pick is { } p && p.Hwnd != IntPtr.Zero)
            {
                var image = p.Frozen ?? ScreenCapture.CaptureWindow(p.Hwnd);
                RestoreFrontmostApp(); // only after the pixels are grabbed — the restored z-order must not leak in
                Handle(image);
            }
            else RestoreAfterCancel();
        }, frozen);
    }

    public void CaptureArea()
    {
        RememberFrontmostApp();
        _selection.Present(_settings.Capture.FreezeScreen, selection =>
        {
            if (selection is { } s)
            {
                var image = Pixels(s);
                RestoreFrontmostApp();
                Handle(image);
            }
            else RestoreAfterCancel();
        });
    }

    /// <summary>Capture Text (OCR + QR): drag a region; the recognized text — or a QR code's payload,
    /// which wins — lands on the clipboard. HUD confirms.</summary>
    public void CaptureText()
    {
        RememberFrontmostApp();
        TextRecognizerService.WarmUp(); // load the OCR model while the user drags (Mac v2.10.0)
        _selection.Present(_settings.Capture.FreezeScreen, selection =>
        {
            if (selection is { } s) _ = CaptureTextAsync(s);
            else RestoreAfterCancel();
        });
    }

    // ---- Return focus to the previous app (Mac v2.8.0; rules in Capture/FocusRestore.cs). Recording isn't covered.
    private readonly FocusMemory<IntPtr> _focus = new();

    private void RememberFrontmostApp()
    {
        var (hwnd, pid) = ForegroundWindow.Current();
        bool selecting = _selection.IsPresenting || _picker.IsPresenting;
        if (hwnd == IntPtr.Zero) { _focus.RecordNothing(selecting); return; }
        _focus.Record(hwnd, pid, ForegroundWindow.OwnProcessId, selecting);
    }

    private void RestoreFrontmostApp()
    {
        if (_focus.RestoreTarget(ForegroundWindow.OwnProcessId) is { } hwnd)
            ForegroundWindow.Restore(hwnd, _focus.RememberedProcessId);
    }

    /// <summary>A cancelled selection hands focus back too — unless it was cancelled BY a second capture hotkey,
    /// whose new overlay is already up and needs the keyboard.</summary>
    private void RestoreAfterCancel()
    {
        if (!_selection.IsPresenting && !_picker.IsPresenting) RestoreFrontmostApp();
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
            RestoreFrontmostApp();
            var result = await TextRecognizerService.RecognizeAsync(image);
            if (result.ClipboardString is { } text) ClipboardService.SetText(text);
            HudController.Show(result.HudMessage, result.Kind switch
            {
                RecognitionKind.None => HudIcon.Warning,
                RecognitionKind.Qr => HudIcon.Copy,
                _ => HudIcon.Text,
            });
        }
        catch
        {
            // Never crash the app on a failed recognition.
            HudController.Show("Capture Text failed", HudIcon.Warning);
        }
    }

    private void Handle(BitmapSource image)
    {
        Tours.TourEvents.Post(BetterScreenshot.Tours.TourEvent.CaptureTaken);
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
            OnEdit = () => Annotate(image),
        };
        _stack.Present(image, QuickAccessKind.Screenshot, actions, MapCorner(_settings.Capture.OverlayCorner),
            dragFile, _settings.Capture.OverlayAutoDismissSeconds, reason =>
            {
                OnCardDismissed(historyId, reason);
                // The temp PNG only backs drag-to-export. Keep it alive for PayloadLifetime (the user's "Keep temp
                // copies for" setting, 10 s … 1 hour or ∞) after the card goes away so a later drop into another app can still
                // read the file, then auto-delete it. The screenshot itself is preserved separately in History (its
                // own %APPDATA% copy), so this never loses the capture — it only cleans up the throwaway drag file.
                TempFiles.Track(dragFile);
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
        var editor = new EditorWindow(image, _settings.EditorStyle, _settings.EditorRecentColors)
        {
            PlacementStore = _settings,
            OnCopy = Copy,
            OnSave = Save,
            OnAddToStack = KeepInStack,
            StyleChanged = style => { _settings.EditorStyle = style; SaveSoon(); },
            RecentColorsChanged = colors => { _settings.EditorRecentColors = colors.ToList(); SaveSoon(); },
        };
        editor.Closed += (_, _) => FlushSave();
        editor.Show();
    }

    /// <summary>The editor's sticky style changes on every slider tick: write settings.json once it settles (500 ms)
    /// instead of on the UI thread per tick (review round 2 #18); flushed when the editor closes.</summary>
    private System.Windows.Threading.DispatcherTimer? _saveSoon;

    private void SaveSoon()
    {
        if (_saveSoon is null)
        {
            _saveSoon = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(500) };
            _saveSoon.Tick += (_, _) => { _saveSoon.Stop(); _settings.Save(); };
        }
        _saveSoon.Stop();
        _saveSoon.Start();
    }

    private void FlushSave()
    {
        if (_saveSoon is { IsEnabled: true } t) { t.Stop(); _settings.Save(); }
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
            _historyWindow = new HistoryWindow(_history, new HistoryWindowActions(Annotate, PinImage) {
                EditVideo = p => OpenVideoEditor(p, null),
                CaptureAreaChord = () => _settings.Hotkeys.Combo(HotkeyAction.CaptureArea)?.DisplayString,
            });
            _historyWindow.Closed += (_, _) => _historyWindow = null;
            Controls.WindowPlacement.Place(_historyWindow, new PxSize(760, 540), "history", _settings);
            _historyWindow.Show();
        }
        else
        {
            Controls.WindowPlacement.BringHere(_historyWindow);
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
        bool mp4 = string.Equals(Path.GetExtension(path), ".mp4", StringComparison.OrdinalIgnoreCase);
        var actions = new QuickAccessActions
        {
            OnCopy = () => ClipboardService.SetFile(path),
            OnOpen = () => OpenFile(path),
            OnReveal = () => RevealFile(path),
            OnTrim = mp4 ? () => OpenVideoEditor(path, () => _ = BringBackCardAsync(path, historyId)) : null,
        };
        // Recording cards drag the real saved file (never a temp copy) — so it is NOT scheduled for deletion.
        _stack.Present(thumbnail, QuickAccessKind.Recording, actions, MapCorner(_settings.Capture.OverlayCorner),
            path, _settings.Capture.OverlayAutoDismissSeconds, reason => OnCardDismissed(historyId, reason));
    }

    private VideoEditorWindow? _videoEditor;

    /// <summary>
    /// One video editor at a time (v3 Part 0 / Part 6). Opening a different file closes the current one (which
    /// restores its card); the same file just comes forward, chaining this caller's restore onto its close.
    /// </summary>
    public void OpenVideoEditor(string path, Action? restoreCard)
    {
        if (_videoEditor is { } open)
        {
            if (string.Equals(open.FilePath, path, StringComparison.OrdinalIgnoreCase))
            {
                if (restoreCard is not null) open.AddRestore(restoreCard);
                Controls.WindowPlacement.BringHere(open);
                return;
            }
            open.Close();
        }
        var editor = new VideoEditorWindow(path, restoreCard)
        {
            CopySaved = copy => _ = ShowNewRecordingAsync(copy),
            GifSaved = gif => _ = ShowNewRecordingAsync(gif),
        };
        editor.Closed += (_, _) => { if (_videoEditor == editor) _videoEditor = null; };
        _videoEditor = editor;
        Controls.WindowPlacement.Place(editor, new PxSize(960, 720), "editVideo", _settings);
        editor.Show();
    }

    /// <summary>The card a recording's editor restores on close: same History id, a fresh first-frame thumbnail (so an
    /// edited file shows its new first frame); no card if the file can't be read any more.</summary>
    private async Task BringBackCardAsync(string path, Guid? historyId)
    {
        if (await VideoExporter.FirstFrameAsync(path) is { } thumb) ShowRecordingCard(path, thumb, historyId);
    }

    /// <summary>An exported copy / GIF: its own History entry + card (thumbnail = its first frame).</summary>
    private async Task ShowNewRecordingAsync(string path)
    {
        if (await VideoExporter.FirstFrameAsync(path) is { } thumb) OnRecordingFinished(path, thumb);
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
    public void Quit() { FlushSave(); _quit(); }
}
