namespace BetterScreenshot.Tours;

/// <summary>
/// BetterScreenshot's tours (Mac v3 §7.4–§7.8), strings verbatim with the doc's Windows wording (Ctrl/Shift/Alt/Enter,
/// "tray icon", "your PC", Explorer). E = Explain (Next), T = Try (advances on the event).
/// </summary>
public static class TourCatalog
{
    private static TourStep E(string anchor, string title, string body, TourEvent? requires = null, TagPlacement placement = TagPlacement.Automatic) =>
        new(anchor, title, body, null, requires, placement);

    private static TourStep T(string anchor, string title, string body, TourEvent advanceOn, TourEvent? requires = null, TagPlacement placement = TagPlacement.Automatic) =>
        new(anchor, title, body, advanceOn, requires, placement);

    public static readonly Tour Welcome = new(TourId.Welcome, TourSurface.Welcome, TourTrigger.ByApp, new[]
    {
        E("menuBar.icon", "Your tray icon", "Everything lives here: captures, recordings, History and Settings."),
        E("welcome.shortcuts", "Capture shortcuts",
            "{shortcut:captureArea} area, {shortcut:captureWindow} window, {shortcut:captureFullscreen} full screen — in any app."),
        T("welcome.captureArea", "Take a screenshot", "Press {shortcut:captureArea} now and drag across anything on screen.", TourEvent.CaptureTaken),
    }, HandsOverTo: TourId.QuickAccess);

    public static readonly Tour QuickAccess = new(TourId.QuickAccess, TourSurface.QuickAccess, TourTrigger.Shown(TourSurface.QuickAccess), new[]
    {
        E("quickAccess.card", "Your screenshot", "Each capture waits here as a card until you use it or close it."),
        T("quickAccess.card", "Drag it anywhere", "Drag the card into any app — a chat, an email, a folder.", TourEvent.Action("quickAccess.dragged")),
        E("quickAccess.actions", "Copy, Edit, Save", "Copy it, Edit it, or Save it to your Screenshots folder.", placement: TagPlacement.Left),
        T("quickAccess.edit", "Mark it up", "Click Edit to draw arrows, add text or blur things out.", TourEvent.Action("quickAccess.edit"), placement: TagPlacement.Left),
    }, HandsOverTo: TourId.Editor);

    public static readonly Tour Editor = new(TourId.Editor, TourSurface.Editor, TourTrigger.Shown(TourSurface.Editor), new[]
    {
        T("editor.toolbar", "Draw an arrow", "Pick the Arrow (A) in this bar, then drag on the image. Hover any tool for its key.", TourEvent.AnnotationAdded("arrow")),
        T("editor.inspector.colour", "Pick a colour", "Click any swatch. It colours what’s selected and what you draw next.", TourEvent.StyleChanged("strokeColor")),
        E("editor.inspector.stroke", "Width and opacity", "Set the line width. Opacity, just below, makes it see-through."),
        E("editor.zoom", "Zoom", "Pinch or Ctrl+scroll to zoom. Ctrl+0 fits the image, Ctrl+1 shows it at real size."),
        E("editor.actions", "Finish up", "Copy it, Save it, or Stack it bottom-right. Done closes; ⓘ replays this tour."),
    });

    public static readonly Tour Text = new(TourId.Text, TourSurface.Editor, TourTrigger.On(TourEvent.ToolSelected("text")), new[]
    {
        T("editor.canvas", "Click to type", "Click anywhere on the image, type, then press Enter.", TourEvent.AnnotationAdded("text")),
        E("editor.canvas", "Or drag a box", "Drag instead of clicking to make a text box — the words wrap inside it."),
        T("editor.canvas", "Resize your text", "Drag a round corner of the text to make it bigger or smaller.", TourEvent.Action("editor.textScaled"), requires: TourEvent.AnnotationAdded("text")),
        E("editor.inspector.styles", "Styles", "One click gives your text a ready-made look."),
        E("editor.inspector.background", "Background", "Put a box behind the text: Solid in any colour, or Auto for contrast.", placement: TagPlacement.Below),
        E("editor.inspector.effects", "Effects", "An outline or shadow keeps text readable on busy images."),
    });

    public static readonly Tour Redaction = new(TourId.Redaction, TourSurface.Editor, TourTrigger.On(TourEvent.Action("editor.redactionToolChosen")), new[]
    {
        T("editor.canvas", "Hide something", "Drag over anything private — it’s hidden when you let go.", TourEvent.Action("editor.redactionAdded")),
        T("editor.inspector.strength", "Change the strength", "Drag the Strength slider until it can’t be read.", TourEvent.StyleChanged("strength"), placement: TagPlacement.Below),
        E("editor.inspector.redaction", "Three ways to hide", "Switch any time. Black-out is the safest — nothing can be recovered."),
    });

    public static readonly Tour Highlighter = new(TourId.Highlighter, TourSurface.Editor, TourTrigger.On(TourEvent.ToolSelected("highlighter")), new[]
    {
        T("editor.canvas", "Highlight something", "Drag across text like a marker pen. Hold Shift for a straight line.", TourEvent.AnnotationAdded("highlighter")),
        E("editor.inspector.highlighterStroke", "Marker width", "Pick Thin, Medium or Thick. The marker keeps its own colour and width."),
    });

    public static readonly Tour Spotlight = new(TourId.Spotlight, TourSurface.Editor, TourTrigger.On(TourEvent.ToolSelected("spotlight")), new[]
    {
        T("editor.canvas", "Spotlight something", "Drag over what matters — everything else dims. Hold Alt for an ellipse.", TourEvent.AnnotationAdded("spotlight")),
        E("editor.inspector.spotlightDim", "Dim outside", "Set how dark everything outside your spotlights gets.", placement: TagPlacement.Below),
    });

    public static readonly Tour FirstRecording = new(TourId.FirstRecording, TourSurface.RecordStrip, TourTrigger.Shown(TourSurface.RecordStrip), new[]
    {
        E("strip.targets", "What to record", "Full Screen records this screen, Area a part you drag, Window just one window."),
        E("strip.output", "Format and frame rate", "MP4 has sound; GIF is a silent loop. 60 FPS is smoother, 30 makes smaller files."),
        T("strip.microphoneColumn", "Pick a microphone", "Click Microphone, then pick a mic or Off. Once it’s on, a meter shows it hears you.", TourEvent.MenuOpened("strip.microphone")),
        T("strip.systemAudio", "Record your PC’s sound", "Click System audio to choose: Off, or all apps.", TourEvent.MenuOpened("strip.systemAudio")),
        E("strip.hint", "Camera, cursor and hints", "Point at any control — Camera, Mouse cursor — and this line explains it."),
        T("strip.targets", "Start recording", "Click Full Screen, Area or Window to start. The recording controls come next.", TourEvent.ChoiceMade("strip.targets")),
    }, HandsOverTo: TourId.RecordingPill);

    public static readonly Tour RecordingPill = new(TourId.RecordingPill, TourSurface.RecordingPill, TourTrigger.Shown(TourSurface.RecordingPill), new[]
    {
        E("pill.timer", "Recording time", "How long you’ve been recording. Drag the pill anywhere you like."),
        E("pill.mic", "Mute the mic", "Click Mic to mute it, and again to unmute. The video stays in sync."),
        E("pill.restart", "Restart or discard", "Restart starts over; Discard, next to it, deletes it. Both need a second click."),
        E("pill.pause", "Pause", "Pauses the recording. Press it again to carry on."),
        T("pill.stop", "Stop when done", "Press Stop when you’re finished. Your video then opens in a card.", TourEvent.Action("recording.stopped")),
    });

    public static readonly Tour VideoEditor = new(TourId.VideoEditor, TourSurface.VideoEditor, TourTrigger.Shown(TourSurface.VideoEditor), new[]
    {
        E("video.preview", "Preview", "Plays only the parts you keep. Click it, or press Space, to play."),
        E("video.timeline", "The timeline", "Click to move the playhead. Drag a part’s yellow edge to trim it.", placement: TagPlacement.Above),
        T("video.timeline", "Split the clip", "Click the timeline to place the playhead, then press S or click Split.", TourEvent.Action("video.split"), placement: TagPlacement.Above),
        T("video.timeline", "Delete a part", "Click a part to select it, then press Delete to cut it out.", TourEvent.Action("video.segmentDeleted"), requires: TourEvent.Action("video.split"), placement: TagPlacement.Above),
        E("video.segment", "Selected part", "Change its speed or mute just this part. Right-click a part for the same.", placement: TagPlacement.Right),
        E("video.saveCopy", "Save a copy", "Saves the edit as a new file. The ▾ menu exports a GIF instead."),
        E("video.replace", "Replace the original", "Overwrites the recording with this edit, then reloads it for more changes."),
    });

    public static readonly Tour Settings = new(TourId.Settings, TourSurface.Settings, TourTrigger.Shown(TourSurface.Settings), new[]
    {
        E("settings.cards", "Your settings", "Related settings share a card. Changes apply right away."),
        E("settings.tip", "Tips on every row", "Hover any ⓘ for a plain explanation of that setting and an example.", placement: TagPlacement.Above),
        E("settings.opacity", "Opacity", "Watch the app turn see-through, then solid. Drag to choose; Default resets it."),
        E("settings.shortcuts", "Keyboard shortcuts", "Click any shortcut, then press new keys to change it. Esc cancels."),
    });

    public static readonly Tour History = new(TourId.History, TourSurface.History, TourTrigger.Shown(TourSurface.History), new[]
    {
        E("history.grid", "Your capture history", "Every screenshot and recording you take is kept here, newest first."),
        T("history.item", "Select a capture", "Click any capture to select it. Double-click opens it instead.", TourEvent.Action("history.selected")),
        E("history.item", "Several at once", "Ctrl-click or Shift-click to add more, then drag them into any app together."),
        E("history.actions", "Actions", "Copy, annotate, pin, edit a video, show in Explorer or delete. Right-click works too."),
    });

    public static readonly IReadOnlyList<Tour> All = new[]
    {
        Welcome, QuickAccess, Editor, Text, Redaction, Highlighter, Spotlight, FirstRecording, RecordingPill, VideoEditor, Settings, History,
    };

    public static Tour Get(TourId id) => All.First(t => t.Id == id);

    /// <summary>The HotkeyAction raw values a <c>{shortcut:…}</c> placeholder may name.</summary>
    public static readonly IReadOnlySet<string> ShortcutNames = new HashSet<string>
    {
        "captureArea", "captureWindow", "captureFullscreen", "captureText", "pinFromClipboard", "record",
        "openHistory", "restoreRecentlyClosed", "pauseResumeRecording",
    };
}
