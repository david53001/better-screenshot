import Foundation

/// Mic level meter math (pure): `AVCaptureAudioChannel.averagePowerLevel` (dBFS)
/// → a 0…1 bar with a fast-attack / slow-release feel.
public enum MicLevel {
    /// Quietest level that lights the meter; a quiet room (measured -88…-64 dBFS on a
    /// MacBook Air mic) stays dark, speech (~-35…-20) lights about half.
    public static let floorDecibels: Float = -60
    /// How much the bar may fall per update (~20 ms), so speech reads as a steady bar.
    public static let release = 0.06

    public static func fraction(decibels: Float) -> Double {
        guard decibels.isFinite else { return 0 }
        return min(max(Double((decibels - floorDecibels) / -floorDecibels), 0), 1)
    }

    public static func smoothed(previous: Double, target: Double) -> Double {
        target >= previous ? target : max(target, previous - release)
    }

    /// How many of `count` meter segments are lit.
    public static func litSegments(fraction: Double, count: Int) -> Int {
        min(max(Int((fraction * Double(count)).rounded()), 0), count)
    }
}
