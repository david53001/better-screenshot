import Foundation

/// A title + plain-language explanation + optional "e.g. …" example, shown by an `InfoTip`.
struct HelpText {
    let title: String
    let explanation: String
    let example: String?

    init(_ title: String, _ explanation: String, example: String? = nil) {
        self.title = title
        self.explanation = explanation
        self.example = example
    }
}

/// Per-setting and per-shortcut help copy for the Settings window's `InfoTip` (ⓘ) hover cards.
enum SettingsHelp {
    // MARK: - Settings

    static let afterCapture = HelpText(
        "After a capture",
        "What happens right after you take a screenshot.",
        example: "Both = copy to clipboard and save a file."
    )

    static let imageFormat = HelpText(
        "Image format",
        "The file format used when a screenshot is saved to disk.",
        example: "PNG keeps crisp edges and transparency; JPG makes smaller files."
    )

    static let playSound = HelpText(
        "Play a sound on capture",
        "Plays a short shutter sound whenever you take a screenshot.",
        example: "Turn this off to capture silently in a quiet room or during a call."
    )

    static let screenCorner = HelpText(
        "Screen corner",
        "Which corner of the screen the Quick Access thumbnail appears in after a capture.",
        example: "Bottom-right keeps it clear of a menu bar app in the top-left."
    )

    static let autoDismiss = HelpText(
        "Auto-dismiss after",
        "How long the Quick Access thumbnail is held on screen before it closes itself — "
            + "from 30 seconds up to 30 minutes.",
        example: "Set to 5m to keep a capture handy while you work, or ∞ to hold it "
            + "until you dismiss it yourself."
    )

    static let tempRetention = HelpText(
        "Keep cached files for",
        "When you drag a capture out, or copy one so a file path lands on the clipboard, "
            + "the app writes a temporary PNG into your system temp folder. This is how "
            + "long that file survives before it is deleted. Your History, your saved "
            + "files, and your recordings are not affected.",
        example: "Set to 30s for a quick paste-and-forget; ∞ keeps every temp file until "
            + "macOS clears the folder itself."
    )

    static let pinCornerRadius = HelpText(
        "Pin corner radius",
        "How rounded the corners are on images pinned to your screen.",
        example: "0 = square corners, 20 = a soft, pill-like rounding."
    )

    static let dropShadow = HelpText(
        "Drop shadow",
        "Adds a soft shadow behind pinned images so they stand out from whatever is behind them.",
        example: "Turn off for a flat look when pinning over a busy background."
    )

    static let rememberHistory = HelpText(
        "Remember capture history",
        "Keeps a local index of your recent screenshots and recordings so you can find them again.",
        example: "Reopen last Tuesday's screenshot from History instead of digging through Finder."
    )

    static let keepAtMost = HelpText(
        "Keep at most",
        "The maximum number of recent captures kept in History before the oldest ones drop off.",
        example: "Set to 100 if you capture often and want a longer local archive."
    )

    static let launchAtLogin = HelpText(
        "Launch at login",
        "Starts BetterScreenshot automatically in the menu bar when you sign in to your Mac.",
        example: "Turn on so your shortcuts already work right after a restart."
    )

    static let saveLocation = HelpText(
        "Save location",
        "The folder where saved screenshots and recordings are written.",
        example: "Point it at ~/Desktop/Screenshots to keep captures out of your home folder."
    )

    static let recordingFormat = HelpText(
        "Format",
        "The file format used when you save a screen recording.",
        example: "MP4 for a smaller, higher-quality video; GIF for a quick shareable loop."
    )

    static let frameRate = HelpText(
        "Frame rate",
        "How many frames per second a recording captures.",
        example: "60 fps for smoother motion, 30 fps for a smaller file."
    )

    static let microphone = HelpText(
        "Microphone",
        "Which microphone records your voice, or Off for none. If the chosen mic is "
            + "unplugged, your Mac's default mic is used instead. The record strip shows "
            + "a live level meter for it.",
        example: "Pick your AirPods or a USB mic to narrate a tutorial."
    )

    static let systemAudio = HelpText(
        "System audio",
        "The sound your Mac plays — videos, calls, music, alerts — recorded along with "
            + "the screen. \"All apps except BetterScreenshot\" leaves out this app's own "
            + "sounds, like its capture sound. GIF recordings never have sound.",
        example: "All apps to capture a video call's audio along with the screen."
    )

    static let camera = HelpText(
        "Camera",
        "Shows your webcam in a round bubble on screen while you record, so it ends up "
            + "in the video. Pick which camera (including an iPhone via Continuity Camera), "
            + "or Off.",
        example: "Turn on for a face-cam picture-in-picture during a walkthrough video."
    )

    static let showCursor = HelpText(
        "Mouse cursor",
        "Shown draws the mouse pointer into the recording as it moves. Hidden gives a clean "
            + "video without the pointer.",
        example: "Choose Hidden when recording a slideshow or video you won't be clicking through."
    )

    static let cameraSize = HelpText(
        "Camera size",
        "The size of the camera bubble overlay in the recording.",
        example: "Medium is easier to see on a large display; Small takes up less of the frame."
    )

    static let highlightClicks = HelpText(
        "Highlight mouse clicks",
        "Draws a brief ring around the cursor whenever you click, so viewers can follow along.",
        example: "Handy when recording a click-through demo of an app."
    )

    static let showKeystrokes = HelpText(
        "Show keystrokes",
        "Displays the keys you press as an on-screen overlay during a recording. Requires Accessibility permission.",
        example: "Great for tutorials that rely on keyboard shortcuts."
    )

    static let countdown = HelpText(
        "Countdown before recording",
        "Adds a short on-screen countdown before a recording actually starts, giving you time to get ready.",
        example: "Choose 3s to switch to the right window before capture begins."
    )

    static let controlsInRecording = HelpText(
        "Show recording controls in the video",
        "While recording, a floating pill with the timer, Pause and Stop is always on screen. Off: it's left out of the video itself. On: it's recorded like any other window.",
        example: "Leave off for clean tutorials; window recordings never include it either way."
    )

    // MARK: - Shortcuts

    static let captureArea = HelpText(
        "Capture Area",
        "Drag to select a rectangular region of the screen to capture.",
        example: "Default ⇧⌘4 — drag around a dialog box to grab just that part of the screen."
    )

    static let captureWindow = HelpText(
        "Capture Window",
        "Captures a single window you click on, without needing to select its exact bounds.",
        example: "Default ⇧⌘8 — click a Safari window to capture just that window, edges included."
    )

    static let captureFullscreen = HelpText(
        "Capture Full Screen",
        "Captures the entire screen in one shot.",
        example: "Default ⇧⌘6 — grabs everything currently on your display."
    )

    static let captureText = HelpText(
        "Capture Text",
        "Selects a region and reads any text or QR code in it using on-device OCR, copying the result instead of an image.",
        example: "Default ⇧⌘7 — grab a paragraph from a PDF and paste it as editable text."
    )

    static let pinFromClipboard = HelpText(
        "Pin from Clipboard",
        "Pins whatever image is currently on your clipboard so it floats on top of your other windows.",
        example: "Copy an image from a chat app, then pin it to compare it side-by-side while you work."
    )

    static let record = HelpText(
        "Start/Stop Recording",
        "Starts a new screen recording, or stops the one in progress.",
        example: "Default ⇧⌘5 — press once to start recording, press again to stop and save."
    )

    static let openHistory = HelpText(
        "Open History",
        "Opens the History window listing your recent screenshots and recordings.",
        example: "Jump back to a screenshot from ten minutes ago without hunting through Finder."
    )

    static let restoreRecentlyClosed = HelpText(
        "Restore Recently Closed",
        "Brings back the Quick Access thumbnail for the last capture you dismissed.",
        example: "Accidentally closed a screenshot's thumbnail? This brings it right back."
    )

    static let pauseResumeRecording = HelpText(
        "Pause/Resume Recording",
        "Pauses the current recording without stopping it, or resumes a paused recording.",
        example: "Pause while you switch to a different app, then resume when you're back on screen."
    )
}
