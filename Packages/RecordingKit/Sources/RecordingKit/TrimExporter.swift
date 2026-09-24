import AVFoundation

/// Exports the video editor's edit of an MP4 recording. A plain start/end trim (one
/// contiguous stretch at 1×) stays lossless passthrough — cuts land on the source's
/// frames as stored and AVFoundation writes an edit list so playback starts at the
/// requested time. Anything else (a middle cut, a speed change, a per-segment mute) is
/// re-encoded (H.264, highest quality) so every cut lands exactly on its frame.
public enum TrimExporter {
    public enum ExportError: Error { case cannotExport, noVideoTrack, failed(Error?) }
    /// 0…1, called from a background task.
    public typealias Progress = @Sendable (Double) -> Void

    /// True when exporting `cuts` means re-encoding (slower; shows a progress bar).
    public static func needsReencode(_ cuts: CutList) -> Bool { cuts.passthrough == nil }

    /// Writes the edit of `source` to `destination`, which must not exist yet.
    /// `muted` (the whole-file Mute audio box) drops every audio track.
    public static func export(source: URL, cuts: CutList, muted: Bool, to destination: URL,
                              progress: Progress? = nil) async throws {
        if let plain = cuts.passthrough {
            let range = plain.range.isNoOp(duration: cuts.duration) ? nil : plain.range
            try await export(source: source, range: range, muted: muted || plain.muted,
                             to: destination, progress: progress)
            return
        }
        let (composition, video) = try await CutComposition.make(asset: AVURLAsset(url: source),
                                                                 cuts: cuts, muteAll: muted)
        guard let session = AVAssetExportSession(asset: composition,
                                                 presetName: AVAssetExportPresetHighestQuality)
        else { throw ExportError.cannotExport }
        session.videoComposition = video
        session.audioTimePitchAlgorithm = .spectral
        try await run(session, to: destination, progress: progress)
    }

    /// Passthrough export of the `range` part of `source` (nil = whole file).
    public static func export(source: URL, range: TrimRange?, muted: Bool,
                              to destination: URL, progress: Progress? = nil) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration)
        let timeRange = range.map {
            CMTimeRange(start: CMTime(seconds: $0.start, preferredTimescale: 600),
                        end: CMTime(seconds: $0.end, preferredTimescale: 600))
        } ?? CMTimeRange(start: .zero, duration: duration)

        let exportAsset: AVAsset
        var sessionRange: CMTimeRange?
        if muted {
            // Video-only composition of just the kept range.
            let composition = AVMutableComposition()
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard !videoTracks.isEmpty else { throw ExportError.noVideoTrack }
            for track in videoTracks {
                guard let dst = composition.addMutableTrack(withMediaType: .video,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid)
                else { throw ExportError.cannotExport }
                try dst.insertTimeRange(timeRange, of: track, at: .zero)
                dst.preferredTransform = try await track.load(.preferredTransform)
            }
            exportAsset = composition
        } else {
            exportAsset = asset
            sessionRange = timeRange
        }

        guard let session = AVAssetExportSession(asset: exportAsset,
                                                 presetName: AVAssetExportPresetPassthrough)
        else { throw ExportError.cannotExport }
        if let sessionRange { session.timeRange = sessionRange }
        try await run(session, to: destination, progress: progress)
    }

    private static func run(_ session: AVAssetExportSession, to destination: URL,
                            progress: Progress?) async throws {
        session.shouldOptimizeForNetworkUse = false
        if #available(macOS 15, *) {
            let watcher = Task {
                for await state in session.states(updateInterval: 0.1) {
                    if case .exporting(let p) = state { progress?(p.fractionCompleted) }
                }
            }
            defer { watcher.cancel() }
            do { try await session.export(to: destination, as: .mp4) }
            catch { throw ExportError.failed(error) }
        } else {
            session.outputURL = destination
            session.outputFileType = .mp4
            let poller = Task {
                while !Task.isCancelled {
                    progress?(Double(session.progress))
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            defer { poller.cancel() }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { cont.resume() }
            }
            guard session.status == .completed else { throw ExportError.failed(session.error) }
        }
        progress?(1)
    }

    /// "Save as Copy": exports next to `source` as "<stem> (trimmed).mp4" (uniquified).
    @discardableResult
    public static func exportCopy(source: URL, cuts: CutList, muted: Bool,
                                  progress: Progress? = nil) async throws -> URL {
        let dest = uniqueSibling(of: source, suffix: TrimmedFileName.trimmed, ext: nil)
        try await export(source: source, cuts: cuts, muted: muted, to: dest, progress: progress)
        return dest
    }

    /// "Replace Original": exports to a temp file on the same volume, then swaps it
    /// in atomically — the original is untouched unless the export fully succeeds.
    public static func replaceOriginal(source: URL, cuts: CutList, muted: Bool,
                                       progress: Progress? = nil) async throws {
        let fm = FileManager.default
        let tempDir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: source, create: true)
        defer { try? fm.removeItem(at: tempDir) }
        let temp = tempDir.appendingPathComponent(source.lastPathComponent)
        try await export(source: source, cuts: cuts, muted: muted, to: temp, progress: progress)
        _ = try fm.replaceItemAt(source, withItemAt: temp)
    }

    /// "Export as GIF": renders the edit to a temporary MP4, then converts it with
    /// `GIFExporter` (10 fps, ≤ 960 px wide) to "<stem> (edited).gif" next to `source`.
    @discardableResult
    public static func exportGIF(source: URL, cuts: CutList, progress: Progress? = nil) async throws -> URL {
        let fm = FileManager.default
        // Temp root, not a "BetterScreenshot-" folder: the app's temp-file sweeper
        // only clears those, so it can't delete this mid-export.
        let temp = fm.temporaryDirectory.appendingPathComponent("VideoEdit-\(UUID().uuidString).mp4")
        defer { try? fm.removeItem(at: temp) }
        try await export(source: source, cuts: cuts, muted: true, to: temp) { progress?($0 * 0.5) }
        let dest = uniqueSibling(of: source, suffix: TrimmedFileName.edited, ext: "gif")
        try await GIFExporter.export(mp4: temp, to: dest) { progress?(0.5 + $0 * 0.5) }
        return dest
    }

    private static func uniqueSibling(of source: URL, suffix: String, ext: String?) -> URL {
        let dir = source.deletingLastPathComponent()
        let name = TrimmedFileName.unique(forOriginal: source.lastPathComponent, suffix: suffix, ext: ext) {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        return dir.appendingPathComponent(name)
    }
}
