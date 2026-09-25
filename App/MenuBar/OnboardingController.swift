import AppKit
import CaptureKit

/// First-run setup window. The app needs exactly one permission — Screen
/// Recording — and a grant only takes effect after a relaunch. This window
/// collapses that dance into a single button: request → System Settings opens
/// at the right pane → poll until the switch flips → relaunch automatically →
/// confirm with a hotkey cheat-sheet (read from the live bindings).
@MainActor
final class OnboardingController: NSWindowController {
    enum State { case needsPermission, waiting, allSet }

    private static let relaunchFlagKey = "RelaunchedAfterPermissionGrant"
    /// Every state uses the same content height, so the window doesn't jump
    /// between steps; a state that needs more (many bound shortcuts) grows it.
    private static let contentHeight: CGFloat = 380
    private let bindings: () -> HotkeyBindings

    /// True exactly once: on the launch right after the permission relaunch.
    static func consumeRelaunchFlag() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: relaunchFlagKey) else { return false }
        defaults.removeObject(forKey: relaunchFlagKey)
        return true
    }

    private var pollTimer: Timer?

    init(bindings: @escaping () -> HotkeyBindings = { .defaults }) {
        self.bindings = bindings
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 100),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ state: State) {
        render(state)
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Poll from the moment the window is up, so even a user who flips the
        // switch on their own (without our button) gets the auto-relaunch.
        if state != .allSet { startPolling() }
    }

    // MARK: - States

    private func render(_ state: State) {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 38, left: 36, bottom: 28, right: 36)
        stack.translatesAutoresizingMaskIntoConstraints = false

        switch state {
        case .needsPermission:
            stack.addArrangedSubview(appIconView())
            stack.addArrangedSubview(titleLabel("Welcome to BetterScreenshot"))
            stack.addArrangedSubview(bodyLabel(
                "Capture, annotate, and share screenshots — right from your menu bar."))
            stack.setCustomSpacing(22, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(bodyLabel(
                "macOS asks for one permission: Screen Recording. Click the button, "
                + "turn on BetterScreenshot in System Settings, and the app will "
                + "restart itself — that's it."))
            stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
            stack.addArrangedSubview(primaryButton("Enable Screen Recording",
                                                   action: #selector(enableTapped)))
        case .waiting:
            stack.addArrangedSubview(appIconView())
            stack.addArrangedSubview(titleLabel("Waiting for permission…"))
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            stack.addArrangedSubview(spinner)
            stack.addArrangedSubview(bodyLabel(
                "In System Settings → Privacy & Security → Screen Recording, "
                + "turn on BetterScreenshot.\nThe app restarts automatically "
                + "the moment it's enabled."))
        case .allSet:
            let check = NSImageView()
            check.image = NSImage(systemSymbolName: "checkmark.circle.fill",
                                  accessibilityDescription: "Ready")?
                .withSymbolConfiguration(.init(pointSize: 50, weight: .regular))
            check.contentTintColor = .systemGreen
            stack.addArrangedSubview(check)
            stack.addArrangedSubview(titleLabel("You're all set!"))
            stack.addArrangedSubview(bodyLabel(
                "BetterScreenshot lives in your menu bar. Capture any time with:"))
            stack.setCustomSpacing(14, after: stack.arrangedSubviews.last!)
            let rows = HotkeyCheatSheet.rows(for: bindings())
            if !rows.isEmpty {
                stack.addArrangedSubview(shortcutGrid(rows))
                stack.setCustomSpacing(18, after: stack.arrangedSubviews.last!)
            }
            stack.addArrangedSubview(primaryButton("Start Capturing",
                                                   action: #selector(startCapturing)))
        }

        let content = NSView()
        content.addSubview(stack)
        let height = max(Self.contentHeight, stack.fittingSize.height)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            content.widthAnchor.constraint(equalToConstant: 440),
            content.heightAnchor.constraint(equalToConstant: height),
        ])
        window?.contentView = content
        window?.setContentSize(NSSize(width: 440, height: height))
    }

    // MARK: - Pieces

    private func appIconView() -> NSImageView {
        let v = NSImageView()
        v.image = NSApp.applicationIconImage
        v.imageScaling = .scaleProportionallyUpOrDown
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 72),
            v.heightAnchor.constraint(equalToConstant: 72),
        ])
        return v
    }

    private func titleLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 19, weight: .bold)
        l.alignment = .center
        return l
    }

    private func bodyLabel(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabelColor
        l.alignment = .center
        l.preferredMaxLayoutWidth = 360
        return l
    }

    private func primaryButton(_ title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .large
        b.keyEquivalent = "\r"
        return b
    }

    /// Two aligned columns: shortcuts right-aligned against descriptions left-aligned.
    private func shortcutGrid(_ rows: [HotkeyCheatSheet.Row]) -> NSGridView {
        let grid = NSGridView(views: rows.map { row -> [NSView] in
            let keys = NSTextField(labelWithString: row.keys)
            keys.font = .systemFont(ofSize: 13, weight: .semibold)
            let name = NSTextField(labelWithString: row.description)
            name.font = .systemFont(ofSize: 13)
            name.textColor = .secondaryLabelColor
            return [keys, name]
        })
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading
        grid.columnSpacing = 14
        grid.rowSpacing = 7
        return grid
    }

    // MARK: - Actions

    @objc private func enableTapped() {
        PermissionManager.requestScreenRecordingPermission()
        // Give the system prompt a beat to appear, then open the exact pane
        // behind it (covers the case where the one-time prompt was already used).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            PermissionManager.openScreenRecordingSettings()
        }
        render(.waiting)
    }

    @objc private func startCapturing() { close() }

    // MARK: - Poll → relaunch

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self,
                                         selector: #selector(pollPermission),
                                         userInfo: nil, repeats: true)
    }

    @objc private func pollPermission() {
        guard PermissionManager.hasScreenRecordingPermission else { return }
        pollTimer?.invalidate(); pollTimer = nil
        UserDefaults.standard.set(true, forKey: Self.relaunchFlagKey)
        PermissionManager.relaunchApp()
    }
}
