/// The data every tour is made of. Design: `docs/superpowers/specs/2026-09-24-betterscreenshot-editor-recording-v3-design.md`
/// §14 (Part 7) and §14.9 (new users only, asked first).

/// Every tour. Raw values are persisted (UserDefaults `toursSeen` / `toursPaused`) — never rename one.
public enum TourID: String, CaseIterable, Codable, Sendable {
    case welcome, quickAccess, editor, text, redaction, highlighter, spotlight,
         firstRecording, recordingPill, videoEditor, settings, history
}

/// A window or panel a tour runs on. The app reports each one as it appears
/// (`TourEvents.surfaceShown`), with the window the tags attach to.
public enum TourSurface: String, CaseIterable, Sendable {
    case welcome, quickAccess, editor, recordStrip, recordingPill, videoEditor, settings, history
}

/// Something the user did that a Try step can wait for. Surfaces post these through `TourEvents`;
/// names are plain strings so surfaces need nothing else from TourKit.
public enum TourEvent: Hashable, Sendable {
    /// A screenshot was taken (any capture mode).
    case captureTaken
    /// Editor: a tool was chosen — `EditorTool.rawValue` ("arrow", "text", "blur", "highlighter"…).
    case toolSelected(String)
    /// Editor: an object was drawn — named like the tool that draws it ("arrow", "text"…).
    case annotationAdded(String)
    /// Editor: a style field was changed from the side panel ("strokeColor", "strength", "textScale"…).
    case styleChanged(String)
    /// The pop-up menu or dropdown of the control with this tour anchor was opened.
    case menuOpened(String)
    /// A choice was made in the control (or its menu) with this tour anchor.
    case choiceMade(String)
    /// Anything else, named "<surface>.<verb>": "quickAccess.edit", "quickAccess.dragged",
    /// "recording.started", "recording.stopped", "pill.micMuted", "video.split", "video.segmentDeleted"…
    case action(String)
}

/// One highlighted control and one short tag.
public struct TourStep: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// "This is X" — advances when the user presses Next.
        case explain
        /// "Do X" — advances by itself when `advanceOn` is posted; Skip step is always offered.
        case tryIt(advanceOn: TourEvent)
    }

    /// The tour anchor of the control this step points at (`NSView.tourAnchor`), "<surface>.<name>",
    /// e.g. "editor.inspector.colour".
    public let anchor: String
    public let kind: Kind
    /// At most 4 words.
    public let title: String
    /// At most 20 words, 1–2 short sentences; Try steps start with a verb. `{shortcut:<HotkeyAction
    /// raw value>}` (e.g. `{shortcut:captureArea}`) is replaced with the user's current key combo.
    public let body: String

    public init(anchor: String, kind: Kind, title: String, body: String) {
        self.anchor = anchor
        self.kind = kind
        self.title = title
        self.body = body
    }
}

/// What starts a tour automatically (only for users with first-use tours on — spec §14.9).
public enum TourTrigger: Equatable, Sendable {
    /// The first time this surface appears.
    case surfaceShown(TourSurface)
    /// The first time this event is posted (e.g. `.toolSelected("text")` for the Text tour).
    case event(TourEvent)
    /// Never by itself: the app starts it (Welcome, after "Show Me Around") or another tour hands over.
    case startedByApp
}

public struct Tour: Equatable, Sendable {
    public let id: TourID
    /// Bump after a big UI change so users with first-use tours on see it once more.
    public let version: Int
    /// The surface whose window the tags attach to.
    public let surface: TourSurface
    public let trigger: TourTrigger
    public let steps: [TourStep]
    /// The tour that starts when this one finishes (Welcome → Quick Access → Editor).
    public let handsOverTo: TourID?

    public init(id: TourID, version: Int = 1, surface: TourSurface, trigger: TourTrigger,
                steps: [TourStep], handsOverTo: TourID? = nil) {
        self.id = id
        self.version = version
        self.surface = surface
        self.trigger = trigger
        self.steps = steps
        self.handsOverTo = handsOverTo
    }
}
