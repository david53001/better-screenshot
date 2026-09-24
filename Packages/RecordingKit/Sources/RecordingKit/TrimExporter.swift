import AVFoundation

/// Lossless (passthrough — no re-encode) trim / mute export of an MP4 recording.
/// Passthrough cuts land on the source's frames as stored; AVFoundation writes an
/// edit list so playback starts at the requested time.
public enum TrimExporter {
    public enum ExportError: Error { case cannotExport, noVideoTrack, failed(Error?) }

    /// Writes the `range` part of `source` (nil = whole file) to `destination`,
    /// which must not exist yet. `muted` drops every audio track.
    public static func export(source: URL, range: TrimRange?, muted: Bool,
                              to destination: URL) async throws {
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
        session.shouldOptimizeForNetworkUse = false
        if #available(macOS 15, *) {
            do { try await session.export(to: destination, as: .mp4) }
            catch { throw ExportError.failed(error) }
        } else {
            session.outputURL = destination
            session.outputFileType = .mp4
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously { cont.resume() }
            }
            guard session.status == .completed else { throw ExportError.failed(session.error) }
        }
    }

    /// "Save as Copy": exports next to `source` as "<stem> (trimmed).mp4" (uniquified).
    @discardableResult
    public static func exportCopy(source: URL, range: TrimRange?, muted: Bool) async throws -> URL {
        let dir = source.deletingLastPathComponent()
        let name = TrimmedFileName.unique(forOriginal: source.lastPathComponent) {
            FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
        }
        let dest = dir.appendingPathComponent(name)
        try await export(source: source, range: range, muted: muted, to: dest)
        return dest
    }

    /// "Replace Original": exports to a temp file on the same volume, then swaps it
    /// in atomically — the original is untouched unless the export fully succeeds.
    public static func replaceOriginal(source: URL, range: TrimRange?, muted: Bool) async throws {
        let fm = FileManager.default
        let tempDir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                 appropriateFor: source, create: true)
        defer { try? fm.removeItem(at: tempDir) }
        let temp = tempDir.appendingPathComponent(source.lastPathComponent)
        try await export(source: source, range: range, muted: muted, to: temp)
        _ = try fm.replaceItemAt(source, withItemAt: temp)
    }
}
