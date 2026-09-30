import Foundation

public enum AfterCaptureBehavior: String, Equatable, CaseIterable {
    case copyOnly, saveOnly, copyAndSave, showOverlay
}

public enum SettingsImageFormat: String, Equatable, CaseIterable {
    case png, jpg
}

public enum OverlayCorner: String, Equatable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

public struct CaptureSettings: Equatable {
    public var afterCapture: AfterCaptureBehavior
    public var format: SettingsImageFormat
    public var overlayCorner: OverlayCorner
    public var overlayAutoDismissSeconds: Int
    public var pinCornerRadius: Int
    public var pinShadow: Bool
    public var historyEnabled: Bool
    public var historyCap: Int
    /// How long the temp PNG written for a drag-out / clipboard file path survives in
    /// `$TMPDIR/BetterScreenshot-<UUID>/`. 0 == keep forever (the ∞ stop).
    public var tempRetentionSeconds: Int
    public var playSound: Bool
    /// Capture Text rebuilds math from the pixels (x², H₂O, √, fractions,
    /// display equations). Off is faster: Vision's text, laid out, nothing more.
    public var captureTextMath: Bool

    public static let `default` = CaptureSettings(
        afterCapture: .showOverlay, format: .png,
        overlayCorner: .bottomRight, overlayAutoDismissSeconds: 0)

    public var dictionary: [String: String] {
        ["afterCapture": afterCapture.rawValue,
         "format": format.rawValue,
         "overlayCorner": overlayCorner.rawValue,
         "overlayAutoDismissSeconds": String(overlayAutoDismissSeconds),
         "pinCornerRadius": String(pinCornerRadius),
         "pinShadow": pinShadow ? "true" : "false",
         "historyEnabled": historyEnabled ? "true" : "false",
         "historyCap": String(historyCap),
         "tempRetentionSeconds": String(tempRetentionSeconds),
         "playSound": playSound ? "1" : "0",
         "captureTextMath": captureTextMath ? "1" : "0"]
    }

    public init(afterCapture: AfterCaptureBehavior, format: SettingsImageFormat,
                overlayCorner: OverlayCorner, overlayAutoDismissSeconds: Int,
                pinCornerRadius: Int = 8, pinShadow: Bool = true,
                historyEnabled: Bool = true, historyCap: Int = 50,
                tempRetentionSeconds: Int = 300,
                playSound: Bool = true, captureTextMath: Bool = true) {
        self.afterCapture = afterCapture
        self.format = format
        self.overlayCorner = overlayCorner
        self.overlayAutoDismissSeconds = overlayAutoDismissSeconds
        self.pinCornerRadius = pinCornerRadius
        self.pinShadow = pinShadow
        self.historyEnabled = historyEnabled
        self.historyCap = historyCap
        self.tempRetentionSeconds = tempRetentionSeconds
        self.playSound = playSound
        self.captureTextMath = captureTextMath
    }

    public init(dictionary: [String: String]) {
        let d = CaptureSettings.default
        self.afterCapture = AfterCaptureBehavior(rawValue: dictionary["afterCapture"] ?? "") ?? d.afterCapture
        self.format = SettingsImageFormat(rawValue: dictionary["format"] ?? "") ?? d.format
        self.overlayCorner = OverlayCorner(rawValue: dictionary["overlayCorner"] ?? "") ?? d.overlayCorner
        let rawAutoDismiss = Int(dictionary["overlayAutoDismissSeconds"] ?? "") ?? d.overlayAutoDismissSeconds
        // Snap to the slider's stop table so a legacy persisted value (e.g. an older
        // build's 6s default) resolves to a stop the Settings slider can show.
        self.overlayAutoDismissSeconds = OverlayDismissScale.snap(rawAutoDismiss)
        self.pinCornerRadius = Int(dictionary["pinCornerRadius"] ?? "") ?? d.pinCornerRadius
        self.pinShadow = dictionary["pinShadow"].map { $0 == "true" } ?? d.pinShadow
        self.historyEnabled = dictionary["historyEnabled"].map { $0 == "true" } ?? d.historyEnabled
        let rawHistoryCap = Int(dictionary["historyCap"] ?? "") ?? d.historyCap
        // Snap to the allowed option set so a legacy persisted value (e.g. an
        // older build's default of 200) still resolves to a value the
        // Settings UI's 10/50/100 control can show as selected.
        self.historyCap = [10, 50, 100].min(by: { abs($0 - rawHistoryCap) < abs($1 - rawHistoryCap) }) ?? 50
        let rawRetention = Int(dictionary["tempRetentionSeconds"] ?? "") ?? d.tempRetentionSeconds
        // Snap to the slider's stop table, same as overlayAutoDismissSeconds above.
        self.tempRetentionSeconds = TempFileRetentionScale.snap(rawRetention)
        self.playSound = (dictionary["playSound"] ?? "1") != "0"
        self.captureTextMath = (dictionary["captureTextMath"] ?? "1") != "0"
    }
}
