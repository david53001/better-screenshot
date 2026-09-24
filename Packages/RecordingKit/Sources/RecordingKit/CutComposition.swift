import AVFoundation

/// Turns a `CutList` into an AVComposition: the kept segments back to back, each
/// time-scaled to its speed, audio silenced where a segment is muted. The video
/// editor previews it and `TrimExporter` re-encodes it, so both match exactly.
public enum CutComposition {
    static func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    /// The composition, plus a video composition when a segment is sped up — apply
    /// both to the player item / export session. Without it, a sped-up segment followed
    /// by the next stretch of the *same* source (a split, then a speed change) makes
    /// AVAssetExportSession fail with -16364 (probed 2026-09-24, macOS 26); rendering
    /// through a video composition at a constant frame rate avoids that.
    public static func make(asset: AVAsset, cuts: CutList,
                            muteAll: Bool) async throws -> (AVMutableComposition, AVVideoComposition?) {
        let composition = try await makeComposition(asset: asset, cuts: cuts, muteAll: muteAll)
        guard cuts.segments.contains(where: { $0.speed != 1 }) else { return (composition, nil) }
        let video = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: composition)
        // The source's own frame rate (its shortest frame interval), 30…60 fps.
        let minFrame = try await asset.loadTracks(withMediaType: .video).first?.load(.minFrameDuration)
        let fps = minFrame.map { $0.isValid && $0.seconds > 0 ? 1 / $0.seconds : 30 } ?? 30
        video.frameDuration = CMTime(value: 1, timescale: CMTimeScale(min(max(fps.rounded(), 30), 60)))
        return (composition, video)
    }

    /// `muteAll` (the whole-file Mute audio box) leaves the audio out entirely, as
    /// does a list whose every segment is muted.
    static func makeComposition(asset: AVAsset, cuts: CutList, muteAll: Bool) async throws -> AVMutableComposition {
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else { throw TrimExporter.ExportError.noVideoTrack }
        let keepAudio = !muteAll && cuts.segments.contains { !$0.muted }
        let audioTracks = keepAudio ? try await asset.loadTracks(withMediaType: .audio) : []

        let composition = AVMutableComposition()
        var tracks: [(source: AVAssetTrack, range: CMTimeRange, target: AVMutableCompositionTrack)] = []
        for track in videoTracks + audioTracks {
            guard let target = composition.addMutableTrack(withMediaType: track.mediaType,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid)
            else { throw TrimExporter.ExportError.cannotExport }
            if track.mediaType == .video {
                target.preferredTransform = try await track.load(.preferredTransform)
            }
            tracks.append((track, try await track.load(.timeRange), target))
        }

        var cursor = CMTime.zero
        for segment in cuts.segments {
            let range = CMTimeRange(start: time(segment.start), end: time(segment.end))
            let length = segment.speed == 1
                ? range.duration : CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / segment.speed)
            for t in tracks {
                // Silence where muted, inserted straight at its final length.
                let covered = segment.muted && t.source.mediaType == .audio
                    ? CMTimeRange.invalid : range.intersection(t.range)
                guard covered.isValid, covered.duration > .zero else {
                    t.target.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: length))
                    continue
                }
                // Pad where the track doesn't cover the whole range (audio can start
                // or end a little before / after the video).
                let lead = covered.start - range.start
                if lead > .zero { t.target.insertEmptyTimeRange(CMTimeRange(start: cursor, duration: lead)) }
                try t.target.insertTimeRange(covered, of: t.source, at: cursor + lead)
                let tail = range.end - covered.end
                if tail > .zero {
                    t.target.insertEmptyTimeRange(CMTimeRange(start: cursor + lead + covered.duration,
                                                              duration: tail))
                }
                if segment.speed != 1 {
                    t.target.scaleTimeRange(CMTimeRange(start: cursor, duration: range.duration),
                                            toDuration: length)
                }
            }
            cursor = cursor + length
        }
        return composition
    }
}
