import CoreGraphics
import Foundation

/// Canvas zoom maths (pure). *Magnification* `m` = view points per image pixel — the inverse
/// of the canvas's `scale`. *Percent* is per **screen** pixel: 100% = one image pixel per
/// screen pixel, i.e. `m · backingScale == 1` (so on a Retina screen 100% is m = 0.5).
public enum ZoomMath {
    public static let maxPercent: CGFloat = 800
    /// ⌘+ / ⌘− step through these (percent).
    public static let stops: [CGFloat] = [10, 25, 50, 75, 100, 150, 200, 300, 400, 600, 800]

    public static func percent(magnification m: CGFloat, backingScale: CGFloat) -> CGFloat {
        m * backingScale * 100
    }

    public static func magnification(percent: CGFloat, backingScale: CGFloat) -> CGFloat {
        percent / 100 / max(backingScale, 1)
    }

    /// "Fit": the whole image inside `available` (view points), but never larger than 100% — the
    /// capture's real on-screen size — so a screenshot never opens enlarged (and soft).
    public static func fitMagnification(imageSize: CGSize, available: CGSize, backingScale: CGFloat) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let m = min(available.width / imageSize.width, available.height / imageSize.height,
                    magnification(percent: 100, backingScale: backingScale))
        return max(m, 0.01)
    }

    /// The image's size at 100%, in points: one image pixel per screen pixel.
    public static func pointSize(pixels: CGSize, backingScale: CGFloat) -> CGSize {
        let s = max(backingScale, 1)
        return CGSize(width: pixels.width / s, height: pixels.height / s)
    }

    /// Allowed range: from fit (or 100% if fit is larger) up to `maxPercent`.
    public static func clamp(_ m: CGFloat, fit: CGFloat, backingScale: CGFloat) -> CGFloat {
        let lo = min(fit, magnification(percent: 100, backingScale: backingScale))
        let hi = magnification(percent: maxPercent, backingScale: backingScale)
        return min(max(m, lo), hi)
    }

    /// The next stop above (zoom in) or below (zoom out) `percent`.
    public static func steppedPercent(from percent: CGFloat, zoomIn: Bool) -> CGFloat {
        if zoomIn { return stops.first { $0 > percent * 1.001 } ?? maxPercent }
        return stops.last { $0 < percent * 0.999 } ?? stops[0]
    }

    /// True when `m` is (within rounding) the fit magnification.
    public static func isFit(_ m: CGFloat, fit: CGFloat) -> Bool {
        abs(m - fit) <= fit * 0.005
    }

    /// New visible-rect origin (canvas-document coordinates) that keeps `anchor` — a point in
    /// document coordinates at the old magnification, e.g. under the pointer — on the same
    /// spot of the screen after zooming from `old` to `new`.
    public static func anchoredOrigin(anchor: CGPoint, visibleOrigin: CGPoint,
                                      from old: CGFloat, to new: CGFloat) -> CGPoint {
        let k = new / old
        return CGPoint(x: anchor.x * k - (anchor.x - visibleOrigin.x),
                       y: anchor.y * k - (anchor.y - visibleOrigin.y))
    }

    /// Zoom control title: "Fit · 57%" in fit mode, else "150%".
    public static func label(percent: CGFloat, isFit: Bool) -> String {
        let p = "\(Int(percent.rounded()))%"
        return isFit ? "Fit · \(p)" : p
    }
}
