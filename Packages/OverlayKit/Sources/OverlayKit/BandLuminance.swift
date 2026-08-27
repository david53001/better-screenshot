import Foundation

/// Percentile luminance over the strip of pixels sitting behind the overlay buttons.
/// A mean hides bimodal bands (a white headline over a black starfield averages dark,
/// then the white glyphs land on the headline); percentiles keep both ends visible.
public enum BandLuminance {
    /// Relative luminance at percentile `p` (0...1) over an RGBA8 buffer; alpha ignored.
    /// Returns 0 for an empty/short buffer. `p` is clamped to 0...1.
    public static func percentile(rgba: [UInt8], pixelCount: Int, p: Double) -> Double {
        guard pixelCount > 0, rgba.count >= pixelCount * 4 else { return 0 }
        var lums = [Double](repeating: 0, count: pixelCount)
        for i in 0..<pixelCount {
            lums[i] = SRGB.relativeLuminance(r: rgba[i*4 + 0], g: rgba[i*4 + 1], b: rgba[i*4 + 2])
        }
        lums.sort()
        let clamped = min(max(p, 0), 1)
        let index = Int((clamped * Double(pixelCount - 1)).rounded())
        return lums[index]
    }

    /// Low/high percentile pair describing the worst backgrounds in the band.
    /// The defaults trim the outermost 10% so a handful of stray pixels can't
    /// force a heavy scrim over an otherwise uniform strip.
    public static func extremes(rgba: [UInt8], pixelCount: Int,
                                low: Double = 0.10, high: Double = 0.90)
        -> QuickAccessContrast.BandExtremes {
        QuickAccessContrast.BandExtremes(
            dark: percentile(rgba: rgba, pixelCount: pixelCount, p: low),
            bright: percentile(rgba: rgba, pixelCount: pixelCount, p: high))
    }
}
