import AppKit

/// Every size, colour and string of the tour tag (spec §14.3, the owner's mock
/// `docs/superpowers/specs/assets/2026-09-25-tour-tag-mock.png`). One place, so the Windows port
/// (`docs/MAC-TO-WINDOWS-PARITY-v3.md` §7.3) copies the numbers from here.
public enum TagStyle {
    // MARK: Colour
    /// The tour colour — accent red #FF453A — for the outline box, the leader line and the tag.
    public static let tourRed = NSColor(srgbRed: 255 / 255, green: 69 / 255, blue: 58 / 255, alpha: 1)
    /// The dim laid over the rest of the host window (black at this alpha).
    public static let dimAlpha: CGFloat = 0.2

    // MARK: Outline box + leader
    /// Gap between the highlighted control and the inner edge of the outline.
    public static let boxPadding: CGFloat = 4
    /// Outline thickness; drawn outside the padding (it covers 4–6 pt outside the control).
    public static let boxStroke: CGFloat = 2
    /// Corner radius of the outline's inner edge.
    public static let boxRadius: CGFloat = 6
    public static let leaderWidth: CGFloat = 2
    /// Gap between the outline's outer edge and the tag, spanned by the leader line.
    public static let leaderLength: CGFloat = 24
    /// The tag never comes closer than this to the edges of the screen's visible frame.
    public static let screenMargin: CGFloat = 8

    // MARK: Tag bubble
    public static let tagRadius: CGFloat = 12
    public static let tagMaxWidth: CGFloat = 260
    public static let tagMinWidth: CGFloat = 200
    public static let tagPaddingX: CGFloat = 12
    public static let tagPaddingTop: CGFloat = 10
    public static let tagPaddingBottom: CGFloat = 10
    public static let titleBodyGap: CGFloat = 2
    public static let bodyFooterGap: CGFloat = 8
    public static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    public static let bodyFont = NSFont.systemFont(ofSize: 12)
    public static let bodyMaxLines = 2
    public static let footerFont = NSFont.systemFont(ofSize: 11, weight: .medium)
    public static let buttonFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    public static let footerHeight: CGFloat = 20
    public static let buttonHeight: CGFloat = 20
    public static let buttonPaddingX: CGFloat = 8
    public static let buttonGap: CGFloat = 4
    /// White at this alpha: the step counter and the "Skip tour" link.
    public static let secondaryTextAlpha: CGFloat = 0.8

    // MARK: Strings
    public static let nextTitle = "Next"
    public static let doneTitle = "Done"
    public static let skipStepTitle = "Skip step"
    public static let skipTourTitle = "Skip tour"
    public static let completedTitle = "Done"

    /// "2 of 7".
    public static func counter(_ number: Int, of total: Int) -> String { "\(number) of \(total)" }

    /// The Explain step's primary button: "Next", or "Done" on the last step.
    public static func nextButtonTitle(number: Int, total: Int) -> String {
        number >= total ? doneTitle : nextTitle
    }

    /// What VoiceOver reads when a tag appears.
    public static func announcement(title: String, body: String, number: Int, total: Int) -> String {
        "\(title). \(body) Step \(number) of \(total)."
    }
}
