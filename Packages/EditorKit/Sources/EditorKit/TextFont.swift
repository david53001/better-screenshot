import AppKit

/// Resolves a text annotation's font from its style. Four presets map to the
/// system font's designs; anything else is an installed font family name.
public enum TextFont {
    public static let system = "System"
    public static let rounded = "System Rounded"
    public static let serif = "System Serif"
    public static let mono = "System Mono"

    /// (family value, menu label) for the presets, in menu order.
    public static let presets: [(family: String, label: String)] = [
        (system, "System"), (rounded, "Rounded"), (serif, "Serif"), (mono, "Mono"),
    ]

    /// Installed families for the font menu (presets excluded — they aren't real families).
    public static var installedFamilies: [String] {
        NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
    }

    /// Never fails: an unknown or uninstalled family falls back to the system font,
    /// so a document or sticky style naming a since-removed font still renders.
    public static func font(family: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        let design: NSFontDescriptor.SystemDesign?
        switch family {
        case system: design = .default
        case rounded: design = .rounded
        case serif: design = .serif
        case mono: design = .monospaced
        default: design = nil
        }
        if let design {
            var desc = NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular).fontDescriptor
            desc = desc.withDesign(design) ?? desc
            if italic { desc = desc.withSymbolicTraits(desc.symbolicTraits.union(.italic)) }
            return NSFont(descriptor: desc, size: size) ?? .systemFont(ofSize: size)
        }
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        // A family may lack the exact face (e.g. no italic): drop italic, then bold.
        for t in [traits, traits.subtracting(.italicFontMask), []] {
            if let f = NSFontManager.shared.font(withFamily: family, traits: t, weight: 5, size: size) {
                return f
            }
        }
        return font(family: system, size: size, bold: bold, italic: italic)
    }
}
