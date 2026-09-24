import AppKit
import AVFoundation

/// Circular live-camera preview in a floating panel. It is captured by simply
/// being on screen — no frame compositing. Drag to move.
@MainActor
public final class CameraBubbleController {
    private var panel: NSPanel?
    private var session: AVCaptureSession?

    public init() {}

    public static func ensurePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Shows the bubble near the bottom-right of `rect` (screen coords, points), fed by
    /// `deviceID` (`uniqueID`), or the default camera when that one isn't connected.
    public func show(near rect: CGRect, on screen: NSScreen, diameter: CGFloat,
                     deviceID: String? = nil) {
        guard panel == nil else { return }
        guard let device = AVCaptureDevice.connected(deviceID, else: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let margin: CGFloat = 24
        let origin = CGPoint(
            x: min(rect.maxX, screen.visibleFrame.maxX) - diameter - margin,
            y: max(rect.minY, screen.visibleFrame.minY) + margin)
        let frame = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))
        let p = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.cornerRadius = diameter / 2
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = content.bounds
        preview.videoGravity = .resizeAspectFill
        content.layer?.addSublayer(preview)
        p.contentView = content

        self.session = session
        self.panel = p
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        p.orderFrontRegardless()
    }

    public func hide() {
        session?.stopRunning()
        session = nil
        panel?.orderOut(nil)
        panel = nil
    }

    /// Whether the bubble exists (shown or hidden in place) / is on screen now.
    public var exists: Bool { panel != nil }
    public var isVisible: Bool { panel?.isVisible ?? false }

    /// Live-pill show/hide: hides or re-shows the bubble where the user dragged
    /// it. The camera stops while hidden so its light goes off. No-op until `show`.
    public func setHidden(_ hidden: Bool) {
        guard let panel, let session else { return }
        if hidden {
            panel.orderOut(nil)
            Self.sessionQueue.async { session.stopRunning() }
        } else {
            Self.sessionQueue.async { session.startRunning() }
            panel.orderFrontRegardless()
        }
    }

    /// Serial, so a quick hide → show can't run startRunning before stopRunning.
    private static let sessionQueue = DispatchQueue(label: "betterscreenshot.camera.session")
}
