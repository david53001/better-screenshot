import CoreGraphics
import Foundation

public struct EditorDocument {
    public let baseImage: CGImage
    public private(set) var annotations: [any Annotation] = []

    public var size: CGSize { CGSize(width: baseImage.width, height: baseImage.height) }

    public init(baseImage: CGImage) { self.baseImage = baseImage }

    public mutating func add(_ a: any Annotation) { annotations.append(a) }

    public mutating func remove(id: UUID) { annotations.removeAll { $0.id == id } }

    public func index(of id: UUID) -> Int? { annotations.firstIndex { $0.id == id } }

    public mutating func move(id: UUID, by delta: CGVector) {
        guard let i = index(of: id) else { return }
        annotations[i] = annotations[i].moved(by: delta)
    }

    public mutating func replace(id: UUID, with a: any Annotation) {
        guard let i = index(of: id) else { return }
        annotations[i] = a
    }

    public mutating func bringToFront(id: UUID) {
        guard let i = index(of: id) else { return }
        let a = annotations.remove(at: i); annotations.append(a)
    }

    public mutating func sendToBack(id: UUID) {
        guard let i = index(of: id) else { return }
        let a = annotations.remove(at: i); annotations.insert(a, at: 0)
    }

    /// Topmost (last-drawn) annotation under the point.
    public func topmostHit(at point: CGPoint) -> UUID? {
        for a in annotations.reversed() where a.hitTest(point) { return a.id }
        return nil
    }

    /// IDs of every annotation whose bounding box overlaps `rect` — used by the
    /// select tool's marquee (rubber-band) drag to pick multiple objects.
    public func ids(intersecting rect: CGRect) -> [UUID] {
        annotations.filter { $0.boundingBox().intersects(rect) }.map(\.id)
    }

    public func nextCounterNumber() -> Int {
        annotations.filter { $0 is CounterAnnotation }.count + 1
    }

    /// Returns a new document cropped to `rect` (top-left image coords), annotations offset to match.
    public func cropped(to rect: CGRect) -> EditorDocument? {
        let r = rect.integral
        let bounds = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        let clamped = r.intersection(bounds)
        guard clamped.width >= 1, clamped.height >= 1,
              let newBase = baseImage.cropping(to: clamped) else { return nil }
        var d = EditorDocument(baseImage: newBase)
        let delta = CGVector(dx: -clamped.minX, dy: -clamped.minY)
        for a in annotations {
            var moved = a.moved(by: delta)
            // A redaction renders from the base image, so it follows the base into the crop.
            if var r = moved as? RedactionAnnotation { r.source = newBase; moved = r }
            d.add(moved)
        }
        return d
    }
}
