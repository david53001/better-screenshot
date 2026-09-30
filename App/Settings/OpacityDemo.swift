import AppKit
import DesignKit

/// The Settings tour's Opacity step: while its tag shows, the Opacity slider sweeps slowly to
/// Transparent, to Opaque and back (`OpacityDemoPath`), and every window and panel follows live.
/// It writes only `SettingsStore.opacityPreview` — never the saved setting — and clears it when the
/// step leaves. Dragging the slider (or Default) clears the preview, which ends the demo on the spot.
@MainActor
final class OpacityDemo {
    static let anchor = "settings.opacity"

    private let store: SettingsStore
    private var timer: Timer?
    private var startedAt = Date()
    private var start = 0.5

    init(store: SettingsStore) { self.store = store }

    func setRunning(_ on: Bool) {
        if on, timer == nil { begin() } else if !on { end() }
    }

    private func begin() {
        startedAt = Date()
        start = store.settings.uiOpacity
        store.opacityPreview = start
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)   // keeps running while the slider tracks a drag
        self.timer = timer
    }

    private func tick() {
        // The user took over (dragged the slider or pressed Default): their value stands.
        guard store.opacityPreview != nil else { return end() }
        store.opacityPreview = OpacityDemoPath.value(at: Date().timeIntervalSince(startedAt), from: start)
    }

    private func end() {
        timer?.invalidate()
        timer = nil
        store.opacityPreview = nil
    }
}
