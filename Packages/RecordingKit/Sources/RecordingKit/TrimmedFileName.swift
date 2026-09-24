import Foundation

/// File names for the video editor's exports, next to the original:
/// Save as Copy "Recording X.mp4" → "Recording X (trimmed).mp4"; Export as GIF →
/// "Recording X (edited).gif"; then " 2", " 3", … on collision. Editing an export
/// reuses the same stem instead of stacking "(trimmed) (trimmed)" / "(trimmed) (edited)".
public enum TrimmedFileName {
    public static let trimmed = "trimmed"
    public static let edited = "edited"

    /// `ext` nil keeps the original's extension.
    public static func name(forOriginal original: String, suffix: String = trimmed,
                            ext: String? = nil) -> String {
        candidate(forOriginal: original, suffix: suffix, ext: ext, attempt: 1)
    }

    /// First candidate for which `exists` is false.
    public static func unique(forOriginal original: String, suffix: String = trimmed,
                              ext: String? = nil, exists: (String) -> Bool) -> String {
        var attempt = 1
        while exists(candidate(forOriginal: original, suffix: suffix, ext: ext, attempt: attempt)) {
            attempt += 1
        }
        return candidate(forOriginal: original, suffix: suffix, ext: ext, attempt: attempt)
    }

    private static func candidate(forOriginal original: String, suffix: String, ext: String?,
                                  attempt: Int) -> String {
        let ns = original as NSString
        let ext = ext ?? ns.pathExtension
        var stem = ns.deletingPathExtension
        // Strip an existing " (trimmed)" / " (edited)" suffix, with or without " N".
        if let r = stem.range(of: #" \((trimmed|edited)\)( \d+)?$"#, options: .regularExpression) {
            stem.removeSubrange(r)
        }
        let base = "\(stem) (\(suffix))" + (attempt > 1 ? " \(attempt)" : "")
        return ext.isEmpty ? base : "\(base).\(ext)"
    }
}
