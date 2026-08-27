import Foundation

public enum ContrastTone: Equatable { case dark, light }

public struct ContrastPalette: Equatable {
    public let glyphARGB: UInt32
    public let hoverARGB: UInt32
    public let pressedARGB: UInt32
    public let scrimIsWhite: Bool
}

public enum QuickAccessContrast {
    /// The darkest and brightest backgrounds the button row has to survive.
    public struct BandExtremes: Equatable {
        public let dark: Double      // low-percentile relative luminance
        public let bright: Double    // high-percentile relative luminance
        public init(dark: Double, bright: Double) {
            self.dark = dark
            self.bright = bright
        }
    }

    public static let lightThreshold = 0.58

    /// Mean Rec.709 relative luminance (0...1) of an RGBA byte buffer; alpha ignored. 0 if empty.
    public static func averageLuminance(rgba: [UInt8], pixelCount: Int) -> Double {
        guard pixelCount > 0, rgba.count >= pixelCount * 4 else { return 0 }
        var sum = 0.0
        for i in 0..<pixelCount {
            let r = Double(rgba[i*4 + 0]) / 255.0
            let g = Double(rgba[i*4 + 1]) / 255.0
            let b = Double(rgba[i*4 + 2]) / 255.0
            sum += 0.2126*r + 0.7152*g + 0.0722*b
        }
        return sum / Double(pixelCount)
    }

    /// A light strip (> 0.58) wants DARK controls; otherwise LIGHT controls.
    public static func tone(forLuminance avg: Double) -> ContrastTone {
        avg > lightThreshold ? .dark : .light
    }

    public static func palette(for tone: ContrastTone) -> ContrastPalette {
        switch tone {
        case .dark:  return ContrastPalette(glyphARGB: 0xFF18181A, hoverARGB: 0x24000000, pressedARGB: 0x3D000000, scrimIsWhite: true)
        case .light: return ContrastPalette(glyphARGB: 0xFFF4F4F6, hoverARGB: 0x2BFFFFFF, pressedARGB: 0x45FFFFFF, scrimIsWhite: false)
        }
    }
}
