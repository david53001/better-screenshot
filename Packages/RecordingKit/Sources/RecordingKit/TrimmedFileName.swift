import Foundation

/// File names for "Save as Copy": "Recording X.mp4" → "Recording X (trimmed).mp4",
/// then " 2", " 3", … on collision. Trimming a trimmed copy reuses the same stem
/// instead of stacking "(trimmed) (trimmed)".
public enum TrimmedFileName {
    public static func name(forOriginal original: String) -> String {
        candidate(forOriginal: original, attempt: 1)
    }

    /// First candidate for which `exists` is false.
    public static func unique(forOriginal original: String, exists: (String) -> Bool) -> String {
        var attempt = 1
        while exists(candidate(forOriginal: original, attempt: attempt)) { attempt += 1 }
        return candidate(forOriginal: original, attempt: attempt)
    }

    private static func candidate(forOriginal original: String, attempt: Int) -> String {
        let ns = original as NSString
        let ext = ns.pathExtension
        var stem = ns.deletingPathExtension
        // Strip an existing " (trimmed)" / " (trimmed) N" suffix.
        if let r = stem.range(of: #" \(trimmed\)( \d+)?$"#, options: .regularExpression) {
            stem.removeSubrange(r)
        }
        let base = "\(stem) (trimmed)" + (attempt > 1 ? " \(attempt)" : "")
        return ext.isEmpty ? base : "\(base).\(ext)"
    }
}
