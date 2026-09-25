import SwiftUI
import CaptureKit
import RecordingKit
import TourKit

/// Closures the Shortcuts card needs from the app layer (AppDelegate owns the
/// rebind transaction because it touches HotKeyManager + menu + persistence).
struct ShortcutActions {
    /// Bind combo (nil = clear) to action. Returns an error message, or nil on success.
    var update: (HotkeyCombo?, HotkeyAction) -> String?
    var restoreDefaults: () -> Void
    /// true while a recorder well is active → suspend all hotkeys.
    var recordingChanged: (Bool) -> Void
}

/// Settings → Startup → "Tours & tips" (v3 spec §14.9). `TourCoordinator` owns the keys.
struct TourSettingsActions {
    /// `firstUseToursEnabled` (absent = off).
    var isEnabled: () -> Bool
    var setEnabled: (Bool) -> Void
    /// Clears which tours were seen or paused — never who counts as a new user.
    var resetAll: () -> Void
}

/// The whole Settings screen: a pure-black, 960pt-wide, single-scroll three-column
/// masonry of titled cards built from the JVoice monochrome controls. Every control
/// writes straight through to `store` (instant-apply) via the `bind`/`bindRec` helpers.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let shortcuts: ShortcutActions
    let clearHistory: () -> Void
    let tours: TourSettingsActions

    // Launch-at-login has no store keypath — SMAppService is its source of truth,
    // mirrored into a guarded @State (writes back only on an actual user flip).
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    // Tours: same idea — TourCoordinator's UserDefaults key is the source of truth.
    @State private var toursEnabled = false
    @State private var toursWereReset = false
    @State private var confirmingClear = false
    // Shortcuts: at most one row records at a time; switching rows re-renders the
    // previous well with isRecording=false, stopping its monitor.
    @State private var recordingAction: HotkeyAction?
    @State private var shortcutStatus = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                HStack(alignment: .top, spacing: SettingsTheme.Metrics.gutter) {
                    columnA
                    columnB
                    columnC
                }
                .tourAnchor("settings.cards")
                shortcutsCard
                    .tourAnchor("settings.shortcuts")
                footer
            }
            .padding(SettingsTheme.Metrics.outerMargin)
            .frame(width: SettingsTheme.Metrics.windowWidth, alignment: .leading)
            .background(SettingsTheme.windowBG)
        }
        .background(SettingsTheme.windowBG)
    }

    // MARK: - Header / footer

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("BetterScreenshot")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Text("Capture & recording preferences — hover the ⓘ next to any setting for a plain-language explanation and example.")
                .font(.system(size: 11.5))
                .foregroundColor(SettingsTheme.subLabel)
        }
    }

    private var footer: some View {
        Text("Changes apply immediately.")
            .font(.system(size: 11))
            .foregroundColor(SettingsTheme.subLabel)
    }

    // MARK: - Columns

    private var columnA: some View {
        VStack(spacing: SettingsTheme.Metrics.cardGap) {
            captureCard
            overlayCard
            startupCard
        }
        .frame(width: SettingsTheme.Metrics.columnWidth)
    }

    // Recording is split into two cards (what to record | what shows in the video) and
    // the short cards fill in under them, so the three columns end at about the same
    // height instead of leaving a tall black gap beside one long Recording card.
    // (Startup and Pin to Screen swapped columns when Startup gained "Tours & tips".)
    private var columnB: some View {
        VStack(spacing: SettingsTheme.Metrics.cardGap) {
            recordingCard
            pinCard
        }
        .frame(width: SettingsTheme.Metrics.columnWidth)
    }

    private var columnC: some View {
        VStack(spacing: SettingsTheme.Metrics.cardGap) {
            inTheVideoCard
            historyCard
            saveLocationCard
        }
        .frame(width: SettingsTheme.Metrics.columnWidth)
    }

    // MARK: - Column A cards

    private var captureCard: some View {
        DarkSection("CAPTURE") {
            VStack(alignment: .leading, spacing: 14) {
                segmentedField("After a capture", SettingsHelp.afterCapture, tipAnchor: "settings.tip",
                               selection: bind(\.afterCapture),
                               segments: [(value: .showOverlay, label: "Overlay"),
                                          (value: .copyOnly, label: "Copy"),
                                          (value: .saveOnly, label: "Save"),
                                          (value: .copyAndSave, label: "Both")])
                segmentedField("Image format", SettingsHelp.imageFormat,
                               selection: bind(\.format),
                               segments: [(value: .png, label: "PNG"),
                                          (value: .jpg, label: "JPG")])
                switchRow("Play a sound on capture", SettingsHelp.playSound,
                          isOn: bind(\.playSound))
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Keep cached files for", SettingsHelp.tempRetention)
                    MonoSlider(
                        position: Binding(
                            get: { TempFileRetentionScale.secondsToPosition(store.settings.tempRetentionSeconds) },
                            set: { store.settings.tempRetentionSeconds = TempFileRetentionScale.positionToSeconds($0)
                                   store.persist() }),
                        range: TempFileRetentionScale.minPosition...TempFileRetentionScale.neverPosition,
                        valueLabel: { TempFileRetentionScale.label(TempFileRetentionScale.positionToSeconds($0)) })
                }
            }
        }
    }

    private var overlayCard: some View {
        DarkSection("QUICK ACCESS OVERLAY") {
            VStack(alignment: .leading, spacing: 14) {
                segmentedField("Screen corner", SettingsHelp.screenCorner,
                               selection: bind(\.overlayCorner),
                               segments: [(value: .topLeft, label: "↖"),
                                          (value: .topRight, label: "↗"),
                                          (value: .bottomLeft, label: "↙"),
                                          (value: .bottomRight, label: "↘")])
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Auto-dismiss after", SettingsHelp.autoDismiss)
                    MonoSlider(
                        position: Binding(
                            get: { OverlayDismissScale.secondsToPosition(store.settings.overlayAutoDismissSeconds) },
                            set: { store.settings.overlayAutoDismissSeconds = OverlayDismissScale.positionToSeconds($0)
                                   store.persist() }),
                        range: OverlayDismissScale.minPosition...OverlayDismissScale.neverPosition,
                        valueLabel: { OverlayDismissScale.label(OverlayDismissScale.positionToSeconds($0)) })
                }
            }
        }
    }

    private var pinCard: some View {
        DarkSection("PIN TO SCREEN") {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Corner radius", SettingsHelp.pinCornerRadius)
                    MonoComboField(selection: bind(\.pinCornerRadius),
                                   options: [(value: 0, label: "0 pt"),
                                             (value: 4, label: "4 pt"),
                                             (value: 8, label: "8 pt"),
                                             (value: 12, label: "12 pt"),
                                             (value: 16, label: "16 pt"),
                                             (value: 20, label: "20 pt")])
                }
                switchRow("Drop shadow", SettingsHelp.dropShadow, isOn: bind(\.pinShadow))
            }
        }
    }

    // MARK: - History / startup / save location

    private var historyCard: some View {
        DarkSection("HISTORY") {
            VStack(alignment: .leading, spacing: 14) {
                switchRow("Remember capture history", SettingsHelp.rememberHistory,
                          sub: "Keep a local index of recent captures",
                          isOn: bind(\.historyEnabled))
                segmentedField("Keep at most", SettingsHelp.keepAtMost,
                               selection: bind(\.historyCap),
                               segments: [(value: 10, label: "10"),
                                          (value: 50, label: "50"),
                                          (value: 100, label: "100")],
                               disabled: !store.settings.historyEnabled)
                VStack(alignment: .leading, spacing: 6) {
                    Button("Clear History…") { confirmingClear = true }
                        .buttonStyle(.pill)
                    Text("Stores full-resolution copies — several MB each.")
                        .font(SettingsTheme.Font.rowSubLabel)
                        .foregroundColor(SettingsTheme.subLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .confirmationDialog("Clear all capture history?",
                                    isPresented: $confirmingClear, titleVisibility: .visible) {
                    Button("Clear History", role: .destructive) { clearHistory() }
                } message: {
                    Text("Removes every remembered capture and its stored copies. Saved recording files on disk are not deleted.")
                }
            }
        }
    }

    private var startupCard: some View {
        DarkSection("STARTUP") {
            VStack(alignment: .leading, spacing: 14) {
                switchRow("Launch at login", SettingsHelp.launchAtLogin,
                          sub: "Start BetterScreenshot when you sign in",
                          isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        guard newValue != LaunchAtLogin.isEnabled else { return }
                        LaunchAtLogin.setEnabled(newValue)
                        launchAtLogin = LaunchAtLogin.isEnabled   // revert if it failed
                    }
                    .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
                Rectangle().fill(SettingsTheme.border).frame(height: 1)
                toursRow
            }
        }
    }

    /// "Tours & tips" (spec §14.9): the switch is `firstUseToursEnabled` (new users: their answer to
    /// "Want a quick tour?"; everyone else: off until they turn it on here).
    private var toursRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Tours & tips", SettingsHelp.toursAndTips)
            HStack(alignment: .center, spacing: 8) {
                Text("Show me around the first time I use each part")
                    .font(SettingsTheme.Font.rowTitle)
                    .foregroundColor(SettingsTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(get: { toursEnabled },
                                         set: { toursEnabled = $0; tours.setEnabled($0) }))
                    .toggleStyle(.mono)
                    .labelsHidden()
            }
            HStack(spacing: 10) {
                Button("Reset All Tours") {
                    tours.resetAll()
                    toursWereReset = true
                }
                .buttonStyle(.pill)
                if toursWereReset {
                    Text("Tours reset")
                        .font(SettingsTheme.Font.rowSubLabel)
                        .foregroundColor(SettingsTheme.label)
                }
            }
        }
        .onAppear {
            toursEnabled = tours.isEnabled()
            toursWereReset = false
        }
    }

    private var saveLocationCard: some View {
        DarkSection("SAVE LOCATION") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Where saved captures & recordings are written")
                    .font(SettingsTheme.Font.rowSubLabel)
                    .foregroundColor(SettingsTheme.subLabel)
                MonoPathField(path: store.saveDirectory.path)
                Button("Browse…") { chooseFolder() }
                    .buttonStyle(.pill)
            }
        }
    }

    // MARK: - Recording cards

    /// What gets recorded: file format, timing and the sources (the record strip's menus).
    private var recordingCard: some View {
        DarkSection("RECORDING") {
            VStack(alignment: .leading, spacing: 14) {
                segmentedField("Format", SettingsHelp.recordingFormat,
                               selection: bindRec(\.format),
                               segments: [(value: .mp4, label: "MP4"),
                                          (value: .gif, label: "GIF")])
                segmentedField("Frame rate", SettingsHelp.frameRate,
                               selection: bindRec(\.fps),
                               segments: [(value: 30, label: "30"),
                                          (value: 60, label: "60")])
                segmentedField("Countdown before recording", SettingsHelp.countdown,
                               selection: bindRec(\.countdownSeconds),
                               segments: [(value: 0, label: "Off"),
                                          (value: 3, label: "3s"),
                                          (value: 5, label: "5s"),
                                          (value: 10, label: "10s")])
                Rectangle().fill(SettingsTheme.border).frame(height: 1)
                sourceMenus
                segmentedField("Camera size", SettingsHelp.cameraSize,
                               selection: bindRec(\.cameraSize),
                               segments: [(value: .small, label: "Small"),
                                          (value: .medium, label: "Medium")],
                               disabled: !store.recording.camera)
            }
        }
    }

    /// What is drawn into the video on top of the screen.
    private var inTheVideoCard: some View {
        DarkSection("IN THE VIDEO") {
            VStack(alignment: .leading, spacing: 14) {
                // Same name and choices as the record strip's Mouse cursor menu.
                VStack(alignment: .leading, spacing: 6) {
                    fieldLabel("Mouse cursor", SettingsHelp.showCursor)
                    MonoComboField(selection: bindRec(\.showsCursor),
                                   options: [(value: true, label: "Shown"),
                                             (value: false, label: "Hidden")])
                }
                switchRow("Highlight mouse clicks", SettingsHelp.highlightClicks,
                          isOn: bindRec(\.clickHighlights))
                keystrokeRow
                switchRow("Show recording controls in the video", SettingsHelp.controlsInRecording,
                          isOn: bindRec(\.controlsInRecording))
            }
        }
    }

    /// Microphone / System audio / Camera menus — the same choices and persisted values
    /// as the record strip's source columns. GIFs are silent, so the audio menus dim.
    private var sourceMenus: some View {
        let mics = AudioInputCatalog().snapshot()
        let cameras = CameraCatalog().snapshot()
        let isGIF = store.recording.format == .gif
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Microphone", SettingsHelp.microphone)
                MonoComboField(
                    selection: Binding(
                        get: { mics.choice(enabled: store.recording.microphone,
                                           saved: store.recording.microphoneDeviceID) },
                        set: { store.recording.setMicrophone($0); store.persist() }),
                    options: mics.options.map { (value: $0.choice, label: $0.title) })
                    .disabled(isGIF).opacity(isGIF ? 0.4 : 1)
            }
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("System audio", SettingsHelp.systemAudio)
                MonoComboField(selection: bindRec(\.systemAudioMode),
                               options: SystemAudioMode.allCases.map { (value: $0, label: $0.title) })
                    .disabled(isGIF).opacity(isGIF ? 0.4 : 1)
                if isGIF {
                    Text("GIFs have no sound. Switch Format to MP4 to record audio.")
                        .font(SettingsTheme.Font.rowSubLabel)
                        .foregroundColor(SettingsTheme.subLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Camera", SettingsHelp.camera)
                MonoComboField(
                    selection: Binding(
                        get: { cameras.choice(enabled: store.recording.camera,
                                              saved: store.recording.cameraDeviceID) },
                        set: { store.recording.setCamera($0); store.persist() }),
                    options: cameras.options.map { (value: $0.choice, label: $0.title) })
            }
        }
    }

    /// "Show keystrokes" keeps the Accessibility-permission gate: turning it on
    /// prompts for trust and only sticks once macOS actually grants it.
    private var keystrokeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            switchRow("Show keystrokes", SettingsHelp.showKeystrokes, isOn: Binding(
                get: { store.recording.keystrokeOverlay },
                set: { newValue in
                    if newValue && !KeystrokeOverlayController.hasPermission {
                        KeystrokeOverlayController.requestPermission()
                        store.recording.keystrokeOverlay = KeystrokeOverlayController.hasPermission
                    } else {
                        store.recording.keystrokeOverlay = newValue
                    }
                    store.persist()
                }))
            Text("Showing keystrokes needs the Accessibility permission.")
                .font(SettingsTheme.Font.rowSubLabel)
                .foregroundColor(SettingsTheme.subLabel)
        }
    }

    // MARK: - Keyboard shortcuts (full-width)

    private var shortcutsCard: some View {
        DarkSection("KEYBOARD SHORTCUTS") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Click a shortcut, then press the new key combination (Esc cancels). Hover the ⓘ on any row to see what that shortcut does.")
                    .font(SettingsTheme.Font.rowSubLabel)
                    .foregroundColor(SettingsTheme.subLabel)
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    shortcutRow(action)
                }
                Rectangle().fill(SettingsTheme.border).frame(height: 1).padding(.vertical, 2)
                HStack {
                    Button("Restore Defaults") {
                        shortcuts.restoreDefaults()
                        shortcutStatus = ""
                    }
                    .buttonStyle(.pill)
                    Spacer()
                    if !shortcutStatus.isEmpty {
                        Text(shortcutStatus)
                            .font(SettingsTheme.Font.rowSubLabel)
                            .foregroundColor(SettingsTheme.label)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onDisappear { setRecording(nil) }
    }

    private func shortcutRow(_ action: HotkeyAction) -> some View {
        HStack(spacing: 10) {
            Text(action.title)
                .font(.system(size: 12.5))
                .foregroundColor(SettingsTheme.textPrimary)
            InfoTip(help: help(for: action))
            if store.failedActions.contains(action) {
                Text("couldn't register")
                    .font(SettingsTheme.Font.rowSubLabel)
                    .foregroundColor(SettingsTheme.subLabel)
            }
            Spacer(minLength: 8)
            // The recorder well is both the combo chip and the control (click to
            // record; it outlines on hover); it reuses the live-rebind machinery as-is.
            ShortcutRecorderField(
                combo: store.bindings.combo(for: action),
                isRecording: Binding(
                    get: { recordingAction == action },
                    set: { setRecording($0 ? action : nil) }),
                onCombo: { combo in
                    shortcutStatus = shortcuts.update(combo, action) ?? ""
                })
                .frame(width: 130, height: 22)
            Button("Clear") {
                shortcutStatus = shortcuts.update(nil, action) ?? ""
            }
            .buttonStyle(.pill)
            .disabled(store.bindings.combo(for: action) == nil)
        }
    }

    /// Tracks which row is recording; suspends/resumes hotkeys on transitions.
    private func setRecording(_ action: HotkeyAction?) {
        let wasRecording = recordingAction != nil
        recordingAction = action
        let isRecording = action != nil
        if wasRecording != isRecording { shortcuts.recordingChanged(isRecording) }
    }

    private func help(for action: HotkeyAction) -> HelpText {
        switch action {
        case .captureArea:           return SettingsHelp.captureArea
        case .captureWindow:         return SettingsHelp.captureWindow
        case .captureFullscreen:     return SettingsHelp.captureFullscreen
        case .captureText:           return SettingsHelp.captureText
        case .pinFromClipboard:      return SettingsHelp.pinFromClipboard
        case .record:                return SettingsHelp.record
        case .openHistory:           return SettingsHelp.openHistory
        case .restoreRecentlyClosed: return SettingsHelp.restoreRecentlyClosed
        case .pauseResumeRecording:  return SettingsHelp.pauseResumeRecording
        }
    }

    // MARK: - Row idioms

    /// Field label ("11.5 semibold") + its ⓘ tip, for the "label above a control" idiom.
    /// `tipAnchor`: a tour anchor on this row's ⓘ (the Settings tour points at one of them).
    private func fieldLabel(_ text: String, _ help: HelpText, tipAnchor: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(SettingsTheme.Font.fieldLabel)
                .foregroundColor(SettingsTheme.label)
            if let tipAnchor {
                InfoTip(help: help).tourAnchor(tipAnchor)
            } else {
                InfoTip(help: help)
            }
        }
    }

    /// A field label above a full-width segmented control.
    @ViewBuilder
    private func segmentedField<T: Hashable>(
        _ text: String, _ help: HelpText, tipAnchor: String? = nil,
        selection: Binding<T>, segments: [(value: T, label: String)],
        disabled: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(text, help, tipAnchor: tipAnchor)
            SegmentedControl(selection: selection, segments: segments)
                .disabled(disabled)
                .opacity(disabled ? 0.4 : 1)
        }
    }

    /// A row title (+ optional sub-label) with ⓘ on the left and a trailing mono switch.
    private func switchRow(_ title: String, _ help: HelpText,
                           sub: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(SettingsTheme.Font.rowTitle)
                        .foregroundColor(SettingsTheme.textPrimary)
                    InfoTip(help: help)
                }
                if let sub {
                    Text(sub)
                        .font(SettingsTheme.Font.rowSubLabel)
                        .foregroundColor(SettingsTheme.subLabel)
                }
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .toggleStyle(.mono)
                .labelsHidden()
        }
    }

    // MARK: - Instant-apply bindings (write-through + persist; no appear-time write-back)

    private func bind<V>(_ keyPath: WritableKeyPath<CaptureSettings, V>) -> Binding<V> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { store.settings[keyPath: keyPath] = $0; store.persist() })
    }

    private func bindRec<V>(_ keyPath: WritableKeyPath<RecordingConfig, V>) -> Binding<V> {
        Binding(get: { store.recording[keyPath: keyPath] },
                set: { store.recording[keyPath: keyPath] = $0; store.persist() })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.saveDirectory = url; store.persist()
        }
    }
}
