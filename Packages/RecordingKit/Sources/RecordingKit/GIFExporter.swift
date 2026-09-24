import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum GIFExportError: Error {
    case noVideoTrack
    case destinationFailed
}

/// Post-conversion of a recorded MP4 into a looping GIF (10 fps, ≤960 px wide).
public enum GIFExporter {
    /// `progress` gets 0…1 as frames are written.
    public static func export(mp4 url: URL, to gifURL: URL,
                              fps: Int = RecordingConfig.gifFPS,
                              maxWidth: CGFloat = RecordingConfig.gifMaxWidth,
                              progress: ((Double) -> Void)? = nil) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw GIFExportError.noVideoTrack
        }
        let duration = try await asset.load(.duration).seconds
        let natural = try await track.load(.naturalSize)
        let size = GIFTiming.outputSize(source: natural, maxWidth: maxWidth)
        let times = GIFTiming.frameTimes(duration: duration, fps: fps)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        let tolerance = CMTime(seconds: 0.5 / Double(fps), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let dest = CGImageDestinationCreateWithURL(
                gifURL as CFURL, UTType.gif.identifier as CFString, times.count, nil) else {
            throw GIFExportError.destinationFailed
        }
        let gifProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(dest, gifProps as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary:
                            [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)]]
        do {
            for (i, t) in times.enumerated() {
                let cm = CMTime(seconds: t, preferredTimescale: 600)
                let image = try await generator.image(at: cm).image
                CGImageDestinationAddImage(dest, image, frameProps as CFDictionary)
                progress?(Double(i + 1) / Double(times.count))
            }
        } catch {
            // Don't leave a half-written GIF behind; the caller keeps the MP4.
            try? FileManager.default.removeItem(at: gifURL)
            throw error
        }
        guard CGImageDestinationFinalize(dest) else {
            try? FileManager.default.removeItem(at: gifURL)
            throw GIFExportError.destinationFailed
        }
    }
}
