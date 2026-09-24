import Foundation

/// AVFoundation settings-dictionary keys, isolated so the pure model (and its
/// tests) don't import AVFoundation. Values match AVVideoSettings.h constants.
public enum AVKey {
    public static let codec = "AVVideoCodecKey"
    public static let width = "AVVideoWidthKey"
    public static let height = "AVVideoHeightKey"
    public static let compression = "AVVideoCompressionPropertiesKey"
    public static let bitRate = "AverageBitRate"
}

public enum RecordingFormat: String, CaseIterable { case mp4, gif }
public enum CameraSize: String, CaseIterable {
    case small, medium
    /// Bubble diameter in points.
    public var diameter: CGFloat { self == .small ? 160 : 240 }
}

/// User-facing recording preferences. Pure; persisted as a string dictionary
/// (same convention as CaptureSettings).
public struct RecordingConfig: Equatable {
    public var format: RecordingFormat
    public var fps: Int                  // 30 or 60
    public var systemAudio: Bool
    public var microphone: Bool
    public var camera: Bool
    public var cameraSize: CameraSize
    public var clickHighlights: Bool
    public var keystrokeOverlay: Bool
    public var countdownSeconds: Int     // 0 = off; otherwise 3 / 5 / 10
    /// Whether the floating stop/pause controls appear in the recorded video.
    /// Off = they're excluded from the capture (still visible on screen).
    public var controlsInRecording: Bool

    public static let gifFPS = 10
    public static let gifMaxWidth: CGFloat = 960

    public static let `default` = RecordingConfig(
        format: .mp4, fps: 30, systemAudio: true, microphone: false,
        camera: false, cameraSize: .small, clickHighlights: true,
        keystrokeOverlay: false, countdownSeconds: 0, controlsInRecording: false)

    public init(format: RecordingFormat, fps: Int, systemAudio: Bool, microphone: Bool,
                camera: Bool, cameraSize: CameraSize, clickHighlights: Bool,
                keystrokeOverlay: Bool, countdownSeconds: Int, controlsInRecording: Bool = false) {
        self.format = format
        self.fps = fps
        self.systemAudio = systemAudio
        self.microphone = microphone
        self.camera = camera
        self.cameraSize = cameraSize
        self.clickHighlights = clickHighlights
        self.keystrokeOverlay = keystrokeOverlay
        self.countdownSeconds = countdownSeconds
        self.controlsInRecording = controlsInRecording
    }

    /// H.264 AVAssetWriter video settings. Bitrate heuristic w·h·fps·0.12,
    /// clamped to 2–40 Mbps.
    public func videoSettings(width: Int, height: Int) -> [String: Any] {
        let rate = min(max(Int(Double(width) * Double(height) * Double(fps) * 0.12),
                           2_000_000), 40_000_000)
        return [
            AVKey.codec: "avc1",
            AVKey.width: width,
            AVKey.height: height,
            AVKey.compression: [AVKey.bitRate: rate] as [String: Any],
        ]
    }

    // MARK: - Persistence

    public var dictionary: [String: String] {
        ["format": format.rawValue,
         "fps": String(fps),
         "systemAudio": systemAudio ? "true" : "false",
         "microphone": microphone ? "true" : "false",
         "camera": camera ? "true" : "false",
         "cameraSize": cameraSize.rawValue,
         "clickHighlights": clickHighlights ? "true" : "false",
         "keystrokeOverlay": keystrokeOverlay ? "true" : "false",
         "countdownSeconds": String(countdownSeconds),
         "controlsInRecording": controlsInRecording ? "true" : "false"]
    }

    public init(dictionary: [String: String]) {
        let d = RecordingConfig.default
        self.format = RecordingFormat(rawValue: dictionary["format"] ?? "") ?? d.format
        let fps = Int(dictionary["fps"] ?? "")
        self.fps = (fps == 30 || fps == 60) ? fps! : d.fps
        self.systemAudio = (dictionary["systemAudio"] ?? "\(d.systemAudio)") == "true"
        self.microphone = (dictionary["microphone"] ?? "\(d.microphone)") == "true"
        self.camera = (dictionary["camera"] ?? "\(d.camera)") == "true"
        self.cameraSize = CameraSize(rawValue: dictionary["cameraSize"] ?? "") ?? d.cameraSize
        self.clickHighlights = (dictionary["clickHighlights"] ?? "\(d.clickHighlights)") == "true"
        self.keystrokeOverlay = (dictionary["keystrokeOverlay"] ?? "\(d.keystrokeOverlay)") == "true"
        let cd = Int(dictionary["countdownSeconds"] ?? "")
        self.countdownSeconds = (cd == 3 || cd == 5 || cd == 10) ? cd! : 0
        self.controlsInRecording = (dictionary["controlsInRecording"] ?? "\(d.controlsInRecording)") == "true"
    }
}
