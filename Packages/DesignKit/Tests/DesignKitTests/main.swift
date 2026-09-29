import TestKit
import AppKit
@testable import DesignKit

runTests("DesignKitTests", [
    TestCase("hudIsDarkWithAContinuousCornerHairlineAndFiftyPercentTint") { t in
        MainActor.assumeIsolated {
            let hud = HUDSurfaceView(frame: NSRect(x: 0, y: 0, width: 120, height: 40), cornerRadius: 12)
            let content = NSTextField(labelWithString: "1:23")
            hud.addSubview(content)
            t.equal(hud.appearance?.name, .darkAqua)
            t.equal(hud.layer?.cornerRadius, 12)
            t.equal(hud.layer?.cornerCurve, .continuous)
            t.isTrue(hud.subviews.first === hud.backdrop, "the material is the bottom-most subview")
            t.isTrue(hud.subviews.last === content, "content stays on top")
            t.equal(hud.tint.frame, hud.bounds)
            t.equal(hud.tint.layer?.borderWidth, 0.5)
            let color = hud.tint.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) }
            t.equal(color?.alphaComponent, 0.5)
            t.equal(color?.usingColorSpace(.genericGray)?.whiteComponent, 0)
            t.equal(hud.backdrop.material, .hudWindow)
            t.equal(hud.backdrop.state, .active)
            t.equal(hud.backdrop.appearance?.name, .vibrantDark)
            let docked = HUDSurfaceView(cornerRadius: 12, blending: .withinWindow, tint: 0)
            t.equal(docked.backdrop.blendingMode, .withinWindow)
            t.equal(docked.tint.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.alphaComponent }, 0)
            hud.cornerRadius = 20
            t.equal(hud.tint.layer?.cornerRadius, 20)
            t.equal(hud.tint.layer?.cornerCurve, .continuous)
        }
    },
    TestCase("continuousCornersAreNotCircular") { t in
        let rect = CGRect(x: 0, y: 0, width: 100, height: 60)
        let squircle = continuousRoundedRect(rect, radius: 12)
        let circular = CGPath(roundedRect: rect, cornerWidth: 12, cornerHeight: 12, transform: nil)
        t.equal(squircle.boundingBox, rect)
        // Along the corner's diagonal a squircle hugs the corner more than a circle.
        let probe = CGPoint(x: 3, y: 3)
        t.isTrue(squircle.contains(probe) || !circular.contains(probe), "never rounder than the circle")
        t.isFalse(squircle == circular)
        // The radius is clamped to half the short side (a capsule).
        t.equal(continuousRoundedRect(rect, radius: 100).boundingBox, rect)
    },
    TestCase("continuousCornerHelperSetsTheCurve") { t in
        let layer = CALayer()
        layer.setContinuousCorners(7)
        t.equal(layer.cornerRadius, 7)
        t.equal(layer.cornerCurve, .continuous)
    },
])
