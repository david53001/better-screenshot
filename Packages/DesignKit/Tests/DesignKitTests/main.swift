import TestKit
import AppKit
@testable import DesignKit

runTests("DesignKitTests", [
    TestCase("hudIsDarkWithAContinuousCornerHairlineAndTheDefaultTint") { t in
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
            t.equal(color?.alphaComponent, 0.42)
            t.equal(color?.usingColorSpace(.genericGray)?.whiteComponent, 0)
            t.equal(hud.backdrop.material, .hudWindow)
            t.equal(hud.backdrop.state, .active)
            t.equal(hud.backdrop.appearance?.name, .vibrantDark)
            let docked = HUDSurfaceView(cornerRadius: 12, blending: .withinWindow, placement: .docked)
            t.equal(docked.backdrop.blendingMode, .withinWindow)
            t.equal(docked.tint.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.alphaComponent }, 0)
            t.equal(docked.backdrop.alphaValue, 0.85)
            hud.cornerRadius = 20
            t.equal(hud.tint.layer?.cornerRadius, 20)
            t.equal(hud.tint.layer?.cornerCurve, .continuous)
        }
    },
    TestCase("opacityDemoSweepsDownToTransparentUpToOpaqueAndBack") { t in
        let v = { (time: Double) in OpacityDemoPath.value(at: time, from: 0.5) }
        t.approxEqual(v(0), 0.5)
        t.approxEqual(v(0.6 + 2.4 + 0.4), 0)          // holding at Transparent
        t.approxEqual(v(0.6 + 2.4 + 0.8 + 3.2 + 0.4), 1)  // holding at Opaque
        t.approxEqual(v(OpacityDemoPath.period - 0.5), 0.5)
        t.approxEqual(v(OpacityDemoPath.period), 0.5)   // loops
        // Slow and continuous: never jumps more than 0.05 in 1/60 s, always inside 0…1.
        var last = v(0)
        for i in 1...Int(OpacityDemoPath.period * 60) {
            let now = v(Double(i) / 60)
            t.isTrue(abs(now - last) <= 0.05 && now >= 0 && now <= 1, "step at frame \(i)")
            last = now
        }
        t.approxEqual(OpacityDemoPath.value(at: 1, from: 9), OpacityDemoPath.value(at: 1, from: 1))   // clamps
    },
    TestCase("opacityCurveIsPiecewiseLinearThroughItsThreePointsAndClamps") { t in
        func f(_ v: Double) -> Double { OpacityCurve.value(at: v, transparent: 0.2, standard: 0.4, opaque: 1) }
        t.approxEqual(f(0), 0.2); t.approxEqual(f(0.25), 0.3); t.approxEqual(f(0.5), 0.4); t.approxEqual(f(0.75), 0.7); t.approxEqual(f(1), 1)
        t.approxEqual(f(-3), 0.2); t.approxEqual(f(7), 1); t.approxEqual(f(.nan), 0.4)
    },
    TestCase("floatingHUDTintKeepsTheReadabilityFloorAndGoesSolid") { t in
        let standard = OpacityCurve.hudFill(0.5, .floating)
        t.equal(standard, HUDFill(backdropAlpha: 1, tintAlpha: 0.42, tintWhite: 0))
        // Clamp: at 0 the tint never drops under 0.22 (white text ≈ 3.15:1 over a white page;
        // 0.20 measured 3.02:1) — never the bare blur (2.13:1).
        let clear = OpacityCurve.hudFill(0, .floating)
        t.equal(clear, HUDFill(backdropAlpha: 1, tintAlpha: 0.22, tintWhite: 0))
        t.isTrue(OpacityCurve.hudFill(-1, .floating).tintAlpha >= 0.22)
        // Solid: an opaque dark grey, not black.
        t.equal(OpacityCurve.hudFill(1, .floating), HUDFill(backdropAlpha: 1, tintAlpha: 1, tintWhite: 0.13))
        // More opacity never means less tint.
        var last = 0.0
        for step in 0...20 {
            let a = OpacityCurve.hudFill(Double(step) / 20, .floating).tintAlpha
            t.isTrue(a >= last, "monotonic at \(step)"); last = a
        }
    },
    TestCase("dockedPanelsFadeTheirBlurInsteadOfTinting") { t in
        t.equal(OpacityCurve.hudFill(0.5, .docked), HUDFill(backdropAlpha: 0.85, tintAlpha: 0, tintWhite: 0))
        t.equal(OpacityCurve.hudFill(0, .docked), HUDFill(backdropAlpha: 0.5, tintAlpha: 0, tintWhite: 0))
        t.equal(OpacityCurve.hudFill(1, .docked), HUDFill(backdropAlpha: 1, tintAlpha: 1, tintWhite: 0.13))
    },
    TestCase("windowsAndCardsFollowTheSetting") { t in
        // Clamp: never the bare material at 0 (dark Settings over white measured 2.77:1 there).
        t.approxEqual(OpacityCurve.windowSolid(0), 0.15); t.approxEqual(OpacityCurve.windowSolid(0.5), 0.52)
        t.approxEqual(OpacityCurve.windowSolid(1), 1)
        t.approxEqual(OpacityCurve.cardFill(0), 0.03); t.approxEqual(OpacityCurve.cardFill(0.5), Design.cardFill)
        t.approxEqual(OpacityCurve.cardFill(1), 0.05)
        for step in 0...10 { t.isTrue(OpacityCurve.cardFill(Double(step) / 10) <= 0.05, "cards stay faint") }
    },
    TestCase("surfacesApplyTheSettingLive") { t in
        MainActor.assumeIsolated {
            let hud = HUDSurfaceView(cornerRadius: 12)
            let backdrop = WindowMaterial.make()
            let solid = backdrop.subviews.first as? SolidFillView
            t.equal(backdrop.material, .popover)
            t.approxEqual(solid?.alpha ?? -1, 0.52)
            UIOpacity.shared.value = 1
            t.equal(hud.tint.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.alphaComponent }, 1)
            t.approxEqual(solid?.alpha ?? -1, 1)
            UIOpacity.shared.value = 0
            t.equal(hud.tint.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.alphaComponent }, 0.22)
            t.approxEqual(solid?.alpha ?? -1, 0.15)
            UIOpacity.shared.value = UIOpacity.defaultValue
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
