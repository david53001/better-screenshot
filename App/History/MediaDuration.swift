import AVFoundation
import ImageIO

/// Length of a saved recording, for the Quick Access badge and the History cells.
enum MediaDuration {
    /// Seconds, or nil when the file is missing or unreadable. MP4/MOV read the
    /// container header; GIFs sum their frame delays (no frames are decoded).
    static func seconds(of url: URL) async -> Double? {
        if url.pathExtension.lowercased() == "gif" { return gifSeconds(url) }
        guard let d = try? await AVURLAsset(url: url).load(.duration) else { return nil }
        return d.seconds.isFinite ? d.seconds : nil
    }

    private static func gifSeconds(_ url: URL) -> Double? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let n = CGImageSourceGetCount(src)
        guard n > 0 else { return nil }
        var total = 0.0
        for i in 0..<n {
            let props = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let unclamped = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? 0
            let clamped = (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0
            total += unclamped > 0 ? unclamped : (clamped > 0 ? clamped : 0.1)
        }
        return total
    }
}
