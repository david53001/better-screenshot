import AppKit

/// A centered countdown HUD shown before recording starts. Counts down once per
/// second; click to skip (start now — said on the box); `cancel()` aborts. Uses the
/// shared dark HUD look (`RecordingHUDStyle`).
@MainActor
public final class CountdownOverlayController {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var timer: Timer?
    private var remaining = 0
    private var continuation: CheckedContinuation<Void, Never>?

    public init() {}

    /// Shows the countdown centered on `screen`; returns when it finishes, is
    /// clicked (skip), or is cancelled. Always tears the overlay down first.
    public func run(seconds: Int, on screen: NSScreen) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            self.present(seconds: seconds, on: screen)
        }
    }

    /// Aborts an in-flight countdown (no-op otherwise), resolving `run()`.
    public func cancel() { finish() }

    private func present(seconds: Int, on screen: NSScreen) {
        let side: CGFloat = 200
        let origin = NSPoint(x: screen.frame.midX - side / 2, y: screen.frame.midY - side / 2)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: NSSize(width: side, height: side)),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = ClickView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        container.onClick = { [weak self] in self?.finish() }   // click to skip
        RecordingHUDStyle.apply(to: container, cornerRadius: 24)

        let font = NSFont.monospacedDigitSystemFont(ofSize: 120, weight: .semibold)
        let label = NSTextField(labelWithString: "\(seconds)")
        label.font = font
        label.textColor = RecordingHUDStyle.primaryText
        label.alignment = .center
        let skip = NSTextField(labelWithString: "Click to start now")
        skip.font = .systemFont(ofSize: 12, weight: .medium)
        skip.textColor = RecordingHUDStyle.secondaryText
        for v in [label, skip] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        // A label draws its line box from the top of its frame, which left the digit
        // ~26pt above centre. Pin the baseline instead so the digit's cap height
        // (lining figures) is centred in the box.
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.firstBaselineAnchor.constraint(equalTo: container.centerYAnchor,
                                                 constant: (font.capHeight / 2).rounded()),
            skip.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            skip.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
        ])

        panel.contentView = container
        panel.orderFrontRegardless()

        self.panel = panel
        self.label = label
        self.remaining = seconds
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 { finish(); return }
        label?.stringValue = "\(remaining)"
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel = nil
        label = nil
        let cont = continuation; continuation = nil
        cont?.resume()
    }
}

/// A vibrancy view that reports clicks (skip the countdown).
private final class ClickView: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}
