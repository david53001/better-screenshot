using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using BetterScreenshot.App.Controls;
using BetterScreenshot.Capture;
using BetterScreenshot.Platform;
using BetterScreenshot.Recording;
// Disambiguate WPF types from the WinForms types the App project also references (for the tray NotifyIcon).
using Border = System.Windows.Controls.Border;
using Brush = System.Windows.Media.Brush;
using Button = System.Windows.Controls.Button;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;
using MessageBox = System.Windows.MessageBox;
using Orientation = System.Windows.Controls.Orientation;

namespace BetterScreenshot.App.Settings;

/// <summary>Tabbed settings (General / Shortcuts / Recording). Instant-apply: every control change
/// persists to <see cref="SettingsStore"/> immediately, so closing with ✕ never loses changes (the old
/// Save/Cancel model silently reverted hotkeys on ✕ — the "settings don't save" trap). Hotkey rebinds
/// re-register live via the <see cref="HotkeyController"/> and raise <see cref="HotkeysChanged"/> so the
/// tray menu hints stay in sync.</summary>
public partial class SettingsWindow : Window
{
    private static readonly int[] PinRadii = { 0, 4, 8, 12, 16, 20 };

    private readonly SettingsStore _settings;
    private readonly HotkeyController _hotkeys;
    private readonly Dictionary<HotkeyAction, TextBlock> _shortcutLabels = new();

    private HotkeyAction? _recordingAction;
    private Button? _recordingButton;
    private bool _loading = true;

    /// <summary>Raised after a shortcut is set or cleared (already persisted + re-registered).</summary>
    public event Action? HotkeysChanged;

    public SettingsWindow(SettingsStore settings, HotkeyController hotkeys)
    {
        _settings = settings;
        _hotkeys = hotkeys;
        InitializeComponent();
        LoadGeneral();
        LoadRecording();
        BuildShortcutRows();
        _loading = false;
        WindowThemer.ApplyDark(this);
        // The card layout sizes to content (SizeToContent=Height); clamp just under the work area so a
        // genuinely oversized window can't run past it (keeps the title-bar ✕ reachable) while leaving the
        // normal ~970px settings comfortably unclamped — no spurious outer scrollbar. The ScrollViewer only
        // kicks in on a very short screen.
        MaxHeight = SystemParameters.WorkArea.Height * 0.98;
    }

    private void LoadGeneral()
    {
        var c = _settings.Capture;
        (c.AfterCapture switch
        {
            AfterCaptureBehavior.CopyOnly => AfterCopy,
            AfterCaptureBehavior.SaveOnly => AfterSave,
            AfterCaptureBehavior.CopyAndSave => AfterBoth,
            _ => AfterOverlay,
        }).IsChecked = true;
        (c.Format == SettingsImageFormat.Jpg ? FmtJpg : FmtPng).IsChecked = true;
        (c.OverlayCorner switch
        {
            SettingsOverlayCorner.TopLeft => CornerTL,
            SettingsOverlayCorner.TopRight => CornerTR,
            SettingsOverlayCorner.BottomLeft => CornerBL,
            _ => CornerBR,
        }).IsChecked = true;
        DismissSlider.Value = OverlayDismissScale.SecondsToPosition(c.OverlayAutoDismissSeconds);
        UpdateDismissLabel();
        TempRetentionSlider.Value = TempRetentionScale.Clamp(c.TempRetentionMinutes);
        UpdateTempRetentionLabel();
        SaveDirBox.Text = _settings.SaveDirectory;
        PinRadiusCombo.SelectedIndex = Math.Max(0, Array.IndexOf(PinRadii, c.PinCornerRadius));
        PinShadowCheck.IsChecked = c.PinShadow;
        HistoryEnabledCheck.IsChecked = c.HistoryEnabled;
        (c.HistoryCap switch { 10 => Cap10, 100 => Cap100, _ => Cap50 }).IsChecked = true;
        LaunchAtLoginCheck.IsChecked = _settings.LaunchAtLogin;
        CaptureSoundCheck.IsChecked = _settings.CaptureSoundEnabled;
        FreezeScreenCheck.IsChecked = c.FreezeScreen;
    }

    private void LoadRecording()
    {
        var r = _settings.Recording;
        (r.Format == RecordingFormat.Gif ? RecGif : RecMp4).IsChecked = true;
        (r.Fps == 60 ? Fps60 : Fps30).IsChecked = true;
        SysAudioCheck.IsChecked = r.SystemAudio;
        MicCheck.IsChecked = r.Microphone;
        CameraCheck.IsChecked = r.Camera;
        (r.CameraSize == CameraSize.Medium ? CamMedium : CamSmall).IsChecked = true;
        ClicksCheck.IsChecked = r.ClickHighlights;
        KeystrokesCheck.IsChecked = r.KeystrokeOverlay;
        (r.CountdownSeconds switch { 3 => Cd3, 5 => Cd5, 10 => Cd10, _ => Cd0 }).IsChecked = true;
    }

    private void BuildShortcutRows()
    {
        // Two-column layout (the window is 960 wide) halves the shortcut list's height so the settings
        // window fits without the outer scrollbar. Even index = left column (gutter on the right), odd =
        // right column (gutter on the left) → a centered gutter between the two columns.
        var actions = HotkeyActionInfo.All;
        for (int i = 0; i < actions.Count; i++)
        {
            var action = actions[i];
            var row = new Grid { Margin = i % 2 == 0 ? new Thickness(0, 4, 14, 4) : new Thickness(14, 4, 0, 4) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

            var titleRow = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            titleRow.Children.Add(new TextBlock
            {
                Text = action.Title(),
                FontSize = 12.5,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = (Brush)FindResource("Theme.TextW85"),
            });
            var (explanation, example) = ShortcutHelp(action);
            titleRow.Children.Add(new InfoTip
            {
                Title = action.Title(),
                Explanation = explanation,
                Example = example,
                Margin = new Thickness(6, 0, 0, 0),
            });
            Grid.SetColumn(titleRow, 0);
            row.Children.Add(titleRow);

            var label = new TextBlock
            {
                Text = _settings.Hotkeys.Combo(action)?.DisplayString ?? "(unbound)",
                FontFamily = new FontFamily("Cascadia Mono, Consolas"),
                FontSize = 12,
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center,
                Foreground = (Brush)FindResource("Theme.TextBrush"),
            };
            _shortcutLabels[action] = label;
            var chip = new Border
            {
                Child = label,
                MinWidth = 118,
                Padding = new Thickness(10, 4, 10, 4),
                CornerRadius = new CornerRadius(6),
                Background = (Brush)FindResource("Theme.ChromeBrush"),
                BorderBrush = (Brush)FindResource("Theme.BorderBrush"),
                BorderThickness = new Thickness(1),
                Margin = new Thickness(0, 0, 8, 0),
                VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(chip, 1);
            row.Children.Add(chip);

            var change = new Button
            {
                Content = "Change",
                Style = (Style)FindResource("Theme.PillButton"),
                Tag = action,
                VerticalAlignment = VerticalAlignment.Center,
            };
            change.Click += StartRecording;
            Grid.SetColumn(change, 2);
            row.Children.Add(change);

            var clear = new Button
            {
                Content = "Clear",
                Padding = new Thickness(10, 5, 10, 5),
                Margin = new Thickness(6, 0, 0, 0),
                Tag = action,
                VerticalAlignment = VerticalAlignment.Center,
            };
            clear.Click += ClearBinding;
            Grid.SetColumn(clear, 3);
            row.Children.Add(clear);

            ShortcutsPanel.Children.Add(row);
        }
    }

    /// <summary>Plain-language (explanation, example) copy for a shortcut row's info button.</summary>
    private static (string Explanation, string Example) ShortcutHelp(HotkeyAction action) => action switch
    {
        HotkeyAction.CaptureArea =>
            ("Drag a rectangle to capture just that region of the screen.",
             "Press the shortcut, then drag over the part you want to grab."),
        HotkeyAction.CaptureWindow =>
            ("Highlight and click a single window to capture just that window, cleanly.",
             "Press the shortcut, then click the window you want — the rest is ignored."),
        HotkeyAction.CaptureFullscreen =>
            ("Instantly capture your entire screen, no selection needed.",
             "One press grabs everything currently on the display."),
        HotkeyAction.CaptureText =>
            ("Select a region and copy any text (or a QR code's contents) inside it to the clipboard, using on-device text recognition (OCR).",
             "Drag over a paragraph inside an image, then paste the recognized text anywhere."),
        HotkeyAction.PinFromClipboard =>
            ("Pin the image currently on your clipboard as an always-on-top floating window.",
             "Copy an image, then press this to keep it hovering on screen while you work."),
        HotkeyAction.Record =>
            ("Start or stop a screen recording. The first press opens the record strip to pick what to capture.",
             "Press once to begin recording; press again to stop and save."),
        HotkeyAction.OpenHistory =>
            ("Open the capture history browser to find, copy, annotate or pin any of your recent captures.",
             "Press it to reopen a screenshot you took earlier without re-capturing."),
        HotkeyAction.RestoreRecentlyClosed =>
            ("Bring back the most recently dismissed Quick Access card.",
             "Closed a capture card too soon? This pops it back up."),
        HotkeyAction.PauseResumeRecording =>
            ("Pause or resume the current recording without creating a separate file — the paused time is skipped, so the video stays gapless.",
             "Pause to skip a distraction mid-recording, then resume where you left off."),
        _ => ("Runs this command.", ""),
    };

    private void StartRecording(object sender, RoutedEventArgs e)
    {
        StopRecording(); // cancel any in-progress recording
        _recordingButton = (Button)sender;
        _recordingAction = (HotkeyAction)_recordingButton.Tag;
        _recordingButton.Content = "Press keys…";
        _hotkeys.Suspend(); // don't let global hotkeys fire while capturing a combo
    }

    private void ClearBinding(object sender, RoutedEventArgs e)
    {
        var action = (HotkeyAction)((Button)sender).Tag;
        _settings.Hotkeys.Clear(action);
        _shortcutLabels[action].Text = "(unbound)";
        ApplyHotkeys();
    }

    /// <summary>Persist + re-register hotkeys after a rebind/clear, and let the app refresh the tray hints.</summary>
    private void ApplyHotkeys()
    {
        _settings.Save();
        _hotkeys.Apply(_settings.Hotkeys);
        HotkeysChanged?.Invoke();
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        if (_recordingAction is not { } action)
        {
            base.OnPreviewKeyDown(e);
            return;
        }

        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Escape) { StopRecording(); return; }

        if (ShortcutRecorder.TryBuildCombo(key, Keyboard.Modifiers) is not { } combo) return;

        if (_settings.Hotkeys.ConflictingAction(combo, excluding: action) is { } other)
        {
            MessageBox.Show(this, $"{combo.DisplayString} is already used by \"{other.Title()}\".",
                "Shortcut in use", MessageBoxButton.OK, MessageBoxImage.Warning);
            StopRecording();
            return;
        }

        _settings.Hotkeys.Set(action, combo);
        _shortcutLabels[action].Text = combo.DisplayString;
        StopRecording();
        ApplyHotkeys();
    }

    private void StopRecording()
    {
        if (_recordingButton != null) _recordingButton.Content = "Change";
        _recordingButton = null;
        _recordingAction = null;
        _hotkeys.Apply(_settings.Hotkeys);
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFolderDialog { Title = "Choose save folder" };
        if (!string.IsNullOrWhiteSpace(SaveDirBox.Text)) dialog.InitialDirectory = SaveDirBox.Text;
        if (dialog.ShowDialog(this) == true)
        {
            SaveDirBox.Text = dialog.FolderName;
            Apply();
        }
    }

    /// <summary>Instant-apply: shared handler for every General/Recording control.</summary>
    private void Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        Apply();
    }

    /// <summary>The auto-dismiss slider: keep the "6s"/"Never" readout live as the user drags, then instant-apply
    /// like every other control (guarded by <see cref="_loading"/> so the initial <c>LoadGeneral</c> set doesn't save).</summary>
    private void DismissSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        UpdateDismissLabel();
        if (_loading) return;
        Apply();
    }

    /// <summary>Refresh the text beside the slider to match its current position ("6s" … "30s", or "Never").
    /// Null-guarded because the slider can coerce its value (and raise ValueChanged) during XAML parse, before
    /// the label field is assigned.</summary>
    private void UpdateDismissLabel()
    {
        if (DismissValueLabel is null) return;
        DismissValueLabel.Text = OverlayDismissScale.Label(OverlayDismissScale.PositionToSeconds(DismissSlider.Value));
    }

    /// <summary>The temp-retention slider: same live-readout + instant-apply pattern as the auto-dismiss bar.</summary>
    private void TempRetentionSlider_ValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        UpdateTempRetentionLabel();
        if (_loading) return;
        Apply();
    }

    /// <summary>Refresh the "5 min" … "30 min" readout beside the temp-retention slider. Null-guarded for the
    /// same reason as <see cref="UpdateDismissLabel"/> (the slider can raise ValueChanged during XAML parse).</summary>
    private void UpdateTempRetentionLabel()
    {
        if (TempRetentionValueLabel is null) return;
        TempRetentionValueLabel.Text = TempRetentionScale.Label(TempRetentionScale.PositionToMinutes(TempRetentionSlider.Value));
    }

    private void Apply()
    {
        _settings.Capture = new CaptureSettings
        {
            AfterCapture = AfterCopy.IsChecked == true ? AfterCaptureBehavior.CopyOnly
                : AfterSave.IsChecked == true ? AfterCaptureBehavior.SaveOnly
                : AfterBoth.IsChecked == true ? AfterCaptureBehavior.CopyAndSave
                : AfterCaptureBehavior.ShowOverlay,
            Format = FmtJpg.IsChecked == true ? SettingsImageFormat.Jpg : SettingsImageFormat.Png,
            OverlayCorner = CornerTL.IsChecked == true ? SettingsOverlayCorner.TopLeft
                : CornerTR.IsChecked == true ? SettingsOverlayCorner.TopRight
                : CornerBL.IsChecked == true ? SettingsOverlayCorner.BottomLeft
                : SettingsOverlayCorner.BottomRight,
            OverlayAutoDismissSeconds = OverlayDismissScale.PositionToSeconds(DismissSlider.Value),
            PinCornerRadius = PinRadii[Math.Max(0, PinRadiusCombo.SelectedIndex)],
            PinShadow = PinShadowCheck.IsChecked == true,
            HistoryEnabled = HistoryEnabledCheck.IsChecked == true,
            HistoryCap = Cap10.IsChecked == true ? 10 : Cap100.IsChecked == true ? 100 : 50,
            FreezeScreen = FreezeScreenCheck.IsChecked == true,
            TempRetentionMinutes = TempRetentionScale.PositionToMinutes(TempRetentionSlider.Value),
        };

        _settings.Recording = new RecordingConfig
        {
            Format = RecGif.IsChecked == true ? RecordingFormat.Gif : RecordingFormat.Mp4,
            Fps = Fps60.IsChecked == true ? 60 : 30,
            SystemAudio = SysAudioCheck.IsChecked == true,
            Microphone = MicCheck.IsChecked == true,
            Camera = CameraCheck.IsChecked == true,
            CameraSize = CamMedium.IsChecked == true ? CameraSize.Medium : CameraSize.Small,
            ClickHighlights = ClicksCheck.IsChecked == true,
            KeystrokeOverlay = KeystrokesCheck.IsChecked == true,
            CountdownSeconds = Cd3.IsChecked == true ? 3 : Cd5.IsChecked == true ? 5 : Cd10.IsChecked == true ? 10 : 0,
        };

        _settings.SaveDirectory = SaveDirBox.Text;
        _settings.LaunchAtLogin = LaunchAtLoginCheck.IsChecked == true;
        _settings.CaptureSoundEnabled = CaptureSoundCheck.IsChecked == true;
        // Push the launch-at-login choice to the OS Run key. Reconcile (not SetEnabled) is idempotent, so the
        // per-control instant-apply firing this on every settings change stays a cheap no-op unless it changed.
        StartupRegistration.Reconcile(_settings.LaunchAtLogin);
        // Temp-file retention takes effect from the next capture on (already-scheduled deletions keep their delay).
        TempFiles.Configure(_settings.Capture.TempRetentionMinutes);
        _settings.Save();
    }

    protected override void OnClosed(EventArgs e)
    {
        _hotkeys.Apply(_settings.Hotkeys); // re-arm in case the window closed mid-shortcut-recording
        base.OnClosed(e);
    }
}
