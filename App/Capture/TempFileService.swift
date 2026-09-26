import Foundation
import CaptureKit

/// Cleans up the temp PNGs the app writes for drag-out and for putting a real file path on
/// the clipboard (`$TMPDIR/BetterScreenshot-<UUID>/…png`).
///
/// This replaces the per-file `DispatchQueue.asyncAfter` timers that used to schedule each
/// directory's deletion: those died with the process, so every quit left a directory behind
/// forever. A sweep at launch clears whatever previous runs orphaned, and a repeating sweep
/// re-reads the retention setting each tick so a change applies without a restart.
@MainActor
final class TempFileService {
    private let settings: SettingsStore
    private var timer: Timer?

    /// The shortest retention stop is 10s, so the sweep has to run far more often than the
    /// window itself for a capture to disappear roughly on time.
    private static let sweepInterval: TimeInterval = 5

    init(settings: SettingsStore) {
        self.settings = settings
        sweep()   // clear directories orphaned by earlier runs
        let timer = Timer(timeInterval: Self.sweepInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sweep() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sweep() {
        TempImageWriter.cleanExpired(
            olderThan: TempFileRetentionScale.maxAge(
                forSeconds: settings.settings.tempRetentionSeconds))
    }
}
