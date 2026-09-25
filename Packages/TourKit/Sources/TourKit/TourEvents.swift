import AppKit

/// The one-way line from the app's surfaces to the tour system. Surfaces call `post` /
/// `surfaceShown` at the moments tours care about; the app's `TourCoordinator` sets the handlers.
/// With no handler set (tests, probes, tours off) every call is a no-op, so posting is always safe.
@MainActor
public enum TourEvents {
    public static var onEvent: ((TourEvent) -> Void)?
    public static var onSurfaceShown: ((TourSurface, NSWindow) -> Void)?

    public static func post(_ event: TourEvent) { onEvent?(event) }

    /// Call right after a surface's window is on screen.
    public static func surfaceShown(_ surface: TourSurface, in window: NSWindow) {
        onSurfaceShown?(surface, window)
    }
}
