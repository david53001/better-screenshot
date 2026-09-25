import TestKit
import AppKit
@testable import RecordingKit

let recordingHUDStyleTests: [TestCase] = [
    TestCase("hudUsesTheSharedDarkLook") { t in
        MainActor.assumeIsolated {
            let hud = RecordingHUDStyle.makeBackground(cornerRadius: 12)
            t.equal(hud.material, .hudWindow)
            t.equal(hud.state, .active)
            t.equal(hud.appearance?.name, .vibrantDark)
            t.equal(hud.layer?.cornerRadius, 12)
            t.equal(hud.layer?.borderWidth, 1)
            t.equal(hud.layer?.borderColor.flatMap { NSColor(cgColor: $0)?.alphaComponent }, 0.1)
        }
    },
    TestCase("hudTintIsFortyPercentBlackBeneathContent") { t in
        MainActor.assumeIsolated {
            let hud = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
            let content = NSTextField(labelWithString: "1:23")
            hud.addSubview(content)
            RecordingHUDStyle.apply(to: hud, cornerRadius: 20)
            let tint = hud.subviews.first as? RecordingHUDStyle.TintView
            t.notNil(tint, "the tint is the bottom-most subview")
            t.isTrue(hud.subviews.last === content, "content stays on top")
            t.equal(tint?.frame, hud.bounds)
            let color = tint?.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }
            t.equal(color?.alphaComponent, 0.4)
            t.equal(color?.usingColorSpace(.genericGray)?.whiteComponent, 0)
        }
    },
]
