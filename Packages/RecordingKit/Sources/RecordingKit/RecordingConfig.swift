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

/// Which system audio a recording captures (the "System audio" menu).
public enum SystemAudioMode: String, CaseIterable {
    case off
    case all
    /// Every app except BetterScreenshot itself (`excludesCurrentProcessAudio`).
    case allExceptSelf = "excludeSelf"

    public var excludesOwnAudio: Bool { self == .allExceptSelf }

    /// Menu title, shared by the record strip and Settings.
    public var title: String {
        switch self {
        case .off: return "Off"
        case .all: return "All apps"
        case .allExceptSelf: return "All apps except BetterScreenshot"
        }
    }
}

/// User-facing recording preferences. Pure; persisted as a string dictionary
/// (same convention as CaptureSettings).
public struct RecordingConfig: Equatable {
    public var format: RecordingFormat
    public var fps: Int                  // 30 or 60
    public var systemAudioMode: SystemAudioMode
    public var microphone: Bool
    /// `AVCaptureDevice.uniqueID` of the chosen mic; nil = system default. A saved
    /// device that isn't connected falls back to the default (`DeviceList.resolvedID`).
    public var microphoneDeviceID: String?
    public var camera: Bool
    /// `AVCaptureDevice.uniqueID` of the chosen camera; nil = system default.
    public var cameraDeviceID: String?
    public var cameraSize: CameraSize
    public var clickHighlights: Bool
    public var keystrokeOverlay: Bool
    public var countdownSeconds: Int     // 0 = off; otherwise 3 / 5 / 10
    /// Whether the floating stop/pause controls appear in the recorded video.
    /// Off = they're excluded from the capture (still visible on screen).
    public var controlsInRecording: Bool
    /// Whether the mouse pointer is drawn into the video (`SCStreamConfiguration.showsCursor`).
    public var showsCursor: Bool

    /// The pre-v3 on/off view of `systemAudioMode`. Turning it on from Off picks All apps.
    public var systemAudio: Bool {
        get { systemAudioMode != .off }
        set { if newValue != systemAudio { systemAudioMode = newValue ? .all : .off } }
    }

    public static let gifFPS = 10
    public static let gifMaxWidth: CGFloat = 960

    public static let `default` = RecordingConfig(
        format: .mp4, fps: 30, systemAudio: true, microphone: false,
        camera: false, cameraSize: .small, clickHighlights: true,
        keystrokeOverlay: false, countdownSeconds: 0, controlsInRecording: false)

    public init(format: RecordingFormat, fps: Int, systemAudio: Bool, microphone: Bool,
                camera: Bool, cameraSize: CameraSize, clickHighlights: Bool,
                keystrokeOverlay: Bool, countdownSeconds: Int, controlsInRecording: Bool = false,
                showsCursor: Bool = true) {
        self.format = format
        self.fps = fps
        self.systemAudioMode = systemAudio ? .all : .off
        self.microphone = microphone
        self.microphoneDeviceID = nil
        self.camera = camera
        self.cameraDeviceID = nil
        self.cameraSize = cameraSize
        self.clickHighlights = clickHighlights
        self.keystrokeOverlay = keystrokeOverlay
        self.countdownSeconds = countdownSeconds
        self.controlsInRecording = controlsInRecording
        self.showsCursor = showsCursor
    }

    /// Applies a Microphone menu choice. Off keeps the last device id.
    public mutating func setMicrophone(_ choice: DeviceChoice) {
        switch choice {
        case .off: microphone = false
        case .device(let id): microphone = true; microphoneDeviceID = id
        }
    }

    /// Applies a Camera menu choice. Off keeps the last device id.
    public mutating func setCamera(_ choice: DeviceChoice) {
        switch choice {
        case .off: camera = false
        case .device(let id): camera = true; cameraDeviceID = id
        }
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

    /// The pre-v3 `systemAudio` Bool is still written so an older build reads a sensible value.
    public var dictionary: [String: String] {
        var d = ["format": format.rawValue,
                 "fps": String(fps),
                 "systemAudio": systemAudio ? "true" : "false",
                 "systemAudioMode": systemAudioMode.rawValue,
                 "microphone": microphone ? "true" : "false",
                 "camera": camera ? "true" : "false",
                 "cameraSize": cameraSize.rawValue,
                 "clickHighlights": clickHighlights ? "true" : "false",
                 "keystrokeOverlay": keystrokeOverlay ? "true" : "false",
                 "countdownSeconds": String(countdownSeconds),
                 "controlsInRecording": controlsInRecording ? "true" : "false",
                 "showsCursor": showsCursor ? "true" : "false"]
        if let microphoneDeviceID { d["microphoneDeviceID"] = microphoneDeviceID }
        if let cameraDeviceID { d["cameraDeviceID"] = cameraDeviceID }
        return d
    }

    public init(dictionary: [String: String]) {
        let d = RecordingConfig.default
        self.format = RecordingFormat(rawValue: dictionary["format"] ?? "") ?? d.format
        let fps = Int(dictionary["fps"] ?? "")
        self.fps = (fps == 30 || fps == 60) ? fps! : d.fps
        // v3 menus: "systemAudioMode" wins; older settings only have the "systemAudio" Bool.
        self.systemAudioMode = SystemAudioMode(rawValue: dictionary["systemAudioMode"] ?? "")
            ?? ((dictionary["systemAudio"] ?? "\(d.systemAudio)") == "true" ? .all : .off)
        self.microphone = (dictionary["microphone"] ?? "\(d.microphone)") == "true"
        self.microphoneDeviceID = dictionary["microphoneDeviceID"].flatMap { $0.isEmpty ? nil : $0 }
        self.camera = (dictionary["camera"] ?? "\(d.camera)") == "true"
        self.cameraDeviceID = dictionary["cameraDeviceID"].flatMap { $0.isEmpty ? nil : $0 }
        self.cameraSize = CameraSize(rawValue: dictionary["cameraSize"] ?? "") ?? d.cameraSize
        self.clickHighlights = (dictionary["clickHighlights"] ?? "\(d.clickHighlights)") == "true"
        self.keystrokeOverlay = (dictionary["keystrokeOverlay"] ?? "\(d.keystrokeOverlay)") == "true"
        let cd = Int(dictionary["countdownSeconds"] ?? "")
        self.countdownSeconds = (cd == 3 || cd == 5 || cd == 10) ? cd! : 0
        self.controlsInRecording = (dictionary["controlsInRecording"] ?? "\(d.controlsInRecording)") == "true"
        self.showsCursor = (dictionary["showsCursor"] ?? "\(d.showsCursor)") == "true"
    }
}
