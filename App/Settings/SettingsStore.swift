import Foundation
import CaptureKit
import RecordingKit
import EditorKit

final class SettingsStore: ObservableObject {
    @Published var settings: CaptureSettings
    @Published var saveDirectory: URL
    @Published var bindings: HotkeyBindings
    /// Actions whose combo macOS refused to register (not persisted).
    @Published var failedActions: Set<HotkeyAction> = []
    @Published var recording: RecordingConfig
    /// The annotation editor's sticky default style (color + sizes).
    @Published var editorStyle: AnnotationStyle
    /// The editor's "Recent" colours, newest first (JSON under `editorRecentColors`).
    @Published var editorRecentColors: [RGBAColor]

    private let defaults = UserDefaults.standard

    init() {
        let dict = defaults.dictionary(forKey: "captureSettings") as? [String: String] ?? [:]
        self.settings = dict.isEmpty ? .default : CaptureSettings(dictionary: dict)
        if let saved = defaults.url(forKey: "saveDirectory") {
            self.saveDirectory = saved
        } else {
            // Default to wherever macOS screenshots normally go (the
            // com.apple.screencapture `location`), falling back to ~/Desktop.
            self.saveDirectory = SettingsStore.systemScreenshotLocation()
        }
        if let dict = defaults.dictionary(forKey: "hotkeyBindings") as? [String: String] {
            self.bindings = HotkeyBindings(dictionary: dict)
        } else {
            self.bindings = .defaults
        }
        let recDict = defaults.dictionary(forKey: "recordingConfig") as? [String: String] ?? [:]
        self.recording = recDict.isEmpty ? .default : RecordingConfig(dictionary: recDict)
        if let data = defaults.data(forKey: "editorDefaultStyle"),
           let decoded = try? JSONDecoder().decode(AnnotationStyle.self, from: data) {
            self.editorStyle = decoded
        } else {
            self.editorStyle = .default
        }
        self.editorRecentColors = defaults.data(forKey: "editorRecentColors")
            .flatMap { try? JSONDecoder().decode([RGBAColor].self, from: $0) } ?? []
    }

    func persist() {
        defaults.set(settings.dictionary, forKey: "captureSettings")
        defaults.set(saveDirectory, forKey: "saveDirectory")
        defaults.set(bindings.dictionary, forKey: "hotkeyBindings")
        defaults.set(recording.dictionary, forKey: "recordingConfig")
    }

    func persistEditorStyle() {
        if let data = try? JSONEncoder().encode(editorStyle) {
            defaults.set(data, forKey: "editorDefaultStyle")
        }
    }

    func persistEditorRecentColors() {
        if let data = try? JSONEncoder().encode(editorRecentColors) {
            defaults.set(data, forKey: "editorRecentColors")
        }
    }

    /// The user's macOS screenshot folder, or ~/Desktop if it isn't customized.
    static func systemScreenshotLocation() -> URL {
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
        guard let raw = UserDefaults(suiteName: "com.apple.screencapture")?
                .string(forKey: "location"), !raw.isEmpty else { return desktop }
        let path = (raw as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir),
              isDir.boolValue else { return desktop }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
