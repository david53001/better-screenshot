import AppKit
import SwiftUI

/// A rounded rectangle with continuous (squircle) corners, for shapes drawn by hand —
/// `NSBezierPath(roundedRect:xRadius:yRadius:)` makes circular corners.
public func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    RoundedRectangle(cornerRadius: max(0, min(radius, min(rect.width, rect.height) / 2)), style: .continuous)
        .path(in: rect).cgPath
}

public extension NSBezierPath {
    /// `continuousRoundedRect` as a bezier path (AppKit drawing).
    convenience init(continuousRoundedRect rect: CGRect, radius: CGFloat) {
        self.init(cgPath: continuousRoundedRect(rect, radius: radius))
    }
}
