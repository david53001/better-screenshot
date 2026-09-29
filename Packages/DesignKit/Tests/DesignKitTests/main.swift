import TestKit
import AppKit
@testable import DesignKit

runTests("DesignKitTests", [
    TestCase("hudIsDarkWithAContinuousCornerHairlineAndFortyPercentTint") { t in
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
            t.equal(color?.alphaComponent, 0.4)
            t.equal(color?.usingColorSpace(.genericGray)?.whiteComponent, 0)
            if !hud.usesGlass {
                let blur = hud.backdrop as? NSVisualEffectView
                t.equal(blur?.material, .hudWindow)
                t.equal(blur?.state, .active)
                t.equal(blur?.appearance?.name, .vibrantDark)
            }
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
