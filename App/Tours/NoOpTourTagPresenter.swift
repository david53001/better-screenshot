import AppKit
import TourKit

/// Stand-in until lane 7B's `TagOverlayController` is merged: shows nothing. `AppDelegate` switches its
/// `TourCoordinator` factory to the real overlay at that merge.
@MainActor
final class NoOpTourTagPresenter: TourTagPresenting {
    var onNext: (() -> Void)?
    var onSkipStep: (() -> Void)?
    var onSkipTour: (() -> Void)?

    func show(step: TourStep, body: String, number: Int, total: Int, anchor: NSView, host: NSWindow) {}
    func showCompleted() {}
    func hide() {}
}
