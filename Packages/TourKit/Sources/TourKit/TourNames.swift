public extension TourID {
    /// The Help & Tours menu item (Title Case, spec §14.3 "one item per tour"). Welcome has its own
    /// item, "Take the Welcome Tour".
    var menuTitle: String {
        switch self {
        case .welcome:        return "Welcome Tour"
        case .quickAccess:    return "Quick Access Tour"
        case .editor:         return "Editor Tour"
        case .text:           return "Text Tool Tour"
        case .redaction:      return "Blur & Pixelate Tour"
        case .highlighter:    return "Highlighter Tour"
        case .spotlight:      return "Spotlight Tour"
        case .firstRecording: return "Recording Setup Tour"
        case .recordingPill:  return "Recording Controls Tour"
        case .videoEditor:    return "Video Editor Tour"
        case .settings:       return "Settings Tour"
        case .history:        return "History Tour"
        }
    }

    /// SF Symbol for that menu item (every menu item in the app has one).
    var menuSymbol: String {
        switch self {
        case .welcome:        return "hand.wave"
        case .quickAccess:    return "rectangle.on.rectangle"
        case .editor:         return "pencil.and.outline"
        case .text:           return "textformat"
        case .redaction:      return "eye.slash"
        case .highlighter:    return "highlighter"
        case .spotlight:      return "flashlight.on.fill"
        case .firstRecording: return "record.circle"
        case .recordingPill:  return "capsule"
        case .videoEditor:    return "film"
        case .settings:       return "gearshape"
        case .history:        return "clock.arrow.circlepath"
        }
    }
}
