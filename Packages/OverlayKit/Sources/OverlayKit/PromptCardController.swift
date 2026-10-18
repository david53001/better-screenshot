import AppKit
import DesignKit

/// A small floating question card in a screen corner, like a macOS notification banner: the app
/// icon, a title, a line of text and up to two buttons, on the app's dark floating surface
/// (`HUDSurfaceView`). Used once, for "Open BetterScreenshot at login?" (`App/MenuBar/
/// LaunchAtLoginPromptController.swift`).
///
/// It never takes focus: a borderless `.nonactivatingPanel` that can't become key, whose buttons
/// take the first click — so typing in the frontmost app is never interrupted. All text is white
/// on a surface held at least at the default opacity (`minimumOpacity`), ≥ 4.86:1 over a white
/// page; the primary button is white with near-black text, the secondary one an outline (the tour
/// tag's button pair). Calling `show` again while it's up replaces the content in place.
@MainActor
public final class PromptCardController {
    public struct Action {
        public var title: String
        public var isPrimary: Bool
        public var handler: () -> Void

        public init(_ title: String, primary: Bool = false, handler: @escaping () -> Void) {
            self.title = title
            self.isPrimary = primary
            self.handler = handler
        }
    }

    public enum Corner { case topRight, bottomRight }

    public static let width: CGFloat = 360
    static let cornerRadius: CGFloat = 16
    static let padding: CGFloat = 14
    static let iconSize: CGFloat = 36
    /// Distance from the screen's visible frame (below the menu bar, beside the Dock).
    static let screenMargin: CGFloat = 12

    /// Every prompt card window on screen right now. Screenshot filters leave these out, so the card
    /// can never end up in the user's capture.
    public static var allWindowNumbers: [Int] {
        NSApp.windows.compactMap { $0 as? PromptCardPanel }.filter(\.isVisible).map(\.windowNumber)
    }

    /// The card's window. It exists from `init` (the app registers it with its recording gate
    /// before it is first shown), and only gets a window number once shown.
    public let window: NSPanel
    private let surface = HUDSurfaceView(cornerRadius: PromptCardController.cornerRadius)

    public init() {
        let panel = PromptCardPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                                    styleMask: [.nonactivatingPanel, .borderless],
                                    backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true   // the one soft system shadow of a floating element
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        surface.minimumOpacity = UIOpacity.defaultValue
        panel.contentView = surface
        window = panel
    }

    public var isVisible: Bool { window.isVisible }

    /// Shows (or updates in place) the card in `corner` of `screen`'s visible frame. No actions =
    /// a confirmation line only.
    public func show(title: String, message: String?, actions: [Action],
                     on screen: NSScreen, corner: Corner) {
        for view in surface.subviews where view !== surface.backdrop && view !== surface.tint {
            view.removeFromSuperview()
        }
        let content = makeContent(title: title, message: message, actions: actions)
        let height = (content.fittingSize.height + 2 * Self.padding).rounded(.up)
        let size = NSSize(width: Self.width, height: height)
        surface.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: Self.padding),
            content.topAnchor.constraint(equalTo: surface.topAnchor, constant: Self.padding),
        ])

        let vf = screen.visibleFrame
        let x = vf.maxX - size.width - Self.screenMargin
        let y = corner == .topRight ? vf.maxY - size.height - Self.screenMargin : vf.minY + Self.screenMargin
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        surface.frame = NSRect(origin: .zero, size: size)
        window.orderFrontRegardless()
        window.invalidateShadow()
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: [title, message].compactMap { $0 }.joined(separator: " "),
            .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    public func hide() {
        window.orderOut(nil)
    }

    private func makeContent(title: String, message: String?, actions: [Action]) -> NSView {
        let textWidth = Self.width - 2 * Self.padding - Self.iconSize - 12

        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = HUDSurfaceView.primaryText
        titleLabel.preferredMaxLayoutWidth = textWidth
        var texts: [NSView] = [titleLabel]
        if let message {
            let body = NSTextField(wrappingLabelWithString: message)
            body.font = .systemFont(ofSize: 12)
            // Full white, not the 80 % secondary: that measures 3.8:1 over a white page.
            body.textColor = HUDSurfaceView.primaryText
            body.preferredMaxLayoutWidth = textWidth
            texts.append(body)
        }
        let textStack = NSStackView(views: texts)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: Self.iconSize).isActive = true
        icon.heightAnchor.constraint(equalToConstant: Self.iconSize).isActive = true
        icon.setAccessibilityElement(false)

        let top = NSStackView(views: [icon, textStack])
        top.orientation = .horizontal
        top.alignment = message == nil ? .centerY : .top   // a lone line sits level with the icon
        top.spacing = 12

        var rows: [NSView] = [top]
        if !actions.isEmpty {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            let buttons = actions.map { PromptCardButton(action: $0) }
            let row = NSStackView(views: [spacer] + buttons)
            row.orientation = .horizontal
            row.spacing = 8
            rows.append(row)
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        for row in rows.dropFirst() {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: Self.width - 2 * Self.padding).isActive = true
        return stack
    }
}

/// Its own class so `allWindowNumbers` can find it. Never key: the card must not take focus.
final class PromptCardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A 24 pt button: white fill + near-black title (primary) or a white outline + white title
/// (secondary), continuous 6 pt corners, hover and press feedback, and it takes the first click
/// (the card's window is never key).
final class PromptCardButton: NSButton {
    private let isPrimary: Bool
    private let handler: () -> Void
    private var hovering = false { didSet { needsDisplay = true } }

    init(action: PromptCardController.Action) {
        isPrimary = action.isPrimary
        handler = action.handler
        super.init(frame: .zero)
        title = action.title
        isBordered = false
        wantsLayer = true
        layer?.setContinuousCorners(6)
        layer?.borderWidth = isPrimary ? 0 : 1
        // Near-black on white: ≈ 18:1. White on the card's surface: ≥ 4.86:1 (see the controller).
        let colour = isPrimary ? NSColor(white: 0.1, alpha: 1) : HUDSurfaceView.primaryText
        attributedTitle = NSAttributedString(string: action.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: colour])
        target = self
        self.action = #selector(clicked)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 24).isActive = true
        let width = attributedTitle.size().width.rounded(.up) + 2 * 12
        widthAnchor.constraint(equalToConstant: max(width, 72)).isActive = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
        setAccessibilityLabel(action.title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let pressed = isHighlighted
        if isPrimary {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(pressed ? 0.75 : hovering ? 0.88 : 1).cgColor
        } else {
            layer?.backgroundColor = NSColor.white.withAlphaComponent(pressed ? 0.16 : hovering ? 0.08 : 0).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(0.55).cgColor
        }
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func clicked() { handler() }
}
