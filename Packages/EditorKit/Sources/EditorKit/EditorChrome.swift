import AppKit

// Custom AppKit views backing the annotation editor chrome: the floating glass
// tool-pill buttons, the side panel's colour swatches and labelled rows, and a
// clip view that centres the canvas inside its scroll view. All are manual /
// visually verified (headless probes), matching the project's UI testing norm.

/// A single icon tool in the floating toolbar pill. Draws its own rounded
/// hover / selected background and tints an SF Symbol template image.
final class IconToolButton: NSButton {
    let tool: EditorTool
    var isSelectedTool = false { didSet { updateTint(); needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(tool: EditorTool, symbol: String, tip: String, target: AnyObject?, action: Selector) {
        self.tool = tool
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        bezelStyle = .shadowlessSquare
        imagePosition = .imageOnly
        focusRingType = .none
        title = ""
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)?
            .withSymbolConfiguration(cfg)
        image?.isTemplate = true
        toolTip = tip
        setAccessibilityLabel(tip)
        self.target = target
        self.action = action
        updateTint()
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 38),
            heightAnchor.constraint(equalToConstant: 38),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateTint() {
        contentTintColor = isSelectedTool ? .white : NSColor(white: 1, alpha: 0.82)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor? = isSelectedTool ? .controlAccentColor
                         : (hovering ? NSColor(white: 1, alpha: 0.13) : nil)
        if let bg {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 9, yRadius: 9)
            bg.setFill(); path.fill()
        }
        super.draw(dirtyRect)
    }
}

/// A round colour swatch in the inspector, with a selection ring.
final class SwatchButton: NSButton {
    var swatchColor: NSColor { didSet { needsDisplay = true } }
    var isSelectedSwatch = false { didSet { needsDisplay = true } }

    init(color: NSColor, target: AnyObject?, action: Selector) {
        self.swatchColor = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        isBordered = false
        bezelStyle = .shadowlessSquare
        focusRingType = .none
        title = ""
        self.target = target
        self.action = action
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = 16
        let circle = NSRect(x: (bounds.width - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
        swatchColor.setFill(); NSBezierPath(ovalIn: circle).fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        let outline = NSBezierPath(ovalIn: circle); outline.lineWidth = 1; outline.stroke()
        if isSelectedSwatch {
            NSColor.white.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            ring.lineWidth = 2; ring.stroke()
        }
    }
}

// MARK: - Side-panel building blocks (dark HUD, 8pt grid, controls 22–28pt tall)

enum InspectorStyle {
    /// Width of the panel's content column (panel width minus 16pt padding each side).
    static let contentWidth: CGFloat = EditorInspectorView.width - 32
    /// The one label column every labelled row uses ("Width", "Padding", "Opacity"…), so all
    /// slider tracks start at the same x.
    static let labelWidth: CGFloat = 56
    /// Colour swatches: 22pt hit areas on an 8-column grid 8pt apart (8 × 22 + 7 × 8 = 232).
    static let swatchSize: CGFloat = 22
    static let swatchGap: CGFloat = 8
    /// In-row captions of the colour rows ("RECENT", "CUSTOM") span two swatch columns, so what
    /// follows them starts on the third column.
    static let swatchCaptionWidth: CGFloat = 2 * swatchSize + swatchGap
    static let primaryText = NSColor(white: 1, alpha: 0.88)
    static let secondaryText = NSColor(white: 1, alpha: 0.55)

    /// Small uppercase caption — section titles ("COLOUR") and in-row labels ("RECENT").
    static func caption(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text.uppercased())
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = NSColor(white: 1, alpha: 0.45)
        return l
    }

    /// Regular 12pt label for a row ("Width").
    static func rowLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12)
        l.textColor = primaryText
        return l
    }

    /// Wrapping explanatory text.
    static func note(_ text: String) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = .systemFont(ofSize: 12)
        l.textColor = NSColor(white: 1, alpha: 0.62)
        l.preferredMaxLayoutWidth = contentWidth
        return l
    }

    /// A horizontal row; `fill` adds a flexible spacer after the views (left-aligned row).
    static func row(_ views: [NSView], spacing: CGFloat = 8, fill: Bool = false) -> NSStackView {
        let r = NSStackView(views: views)
        r.orientation = .horizontal
        r.alignment = .centerY
        r.spacing = spacing
        if fill {
            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            r.addArrangedSubview(spacer)
        }
        return r
    }

    static func hairline() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.10).cgColor
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }
}

/// "Label  ———●———  value" — a slider with an optional leading label (in the shared
/// `InspectorStyle.labelWidth` column) and a live value readout.
/// `onChange(value, finished)`: `finished` is false while the knob is dragged.
final class LabeledSliderRow: NSStackView {
    let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let format: (Double) -> String
    var onChange: ((Double, Bool) -> Void)?

    init(label: String?, labelWidth: CGFloat = InspectorStyle.labelWidth, range: ClosedRange<Double>,
         tooltip: String, format: @escaping (Double) -> String) {
        slider = NSSlider(value: range.lowerBound, minValue: range.lowerBound,
                          maxValue: range.upperBound, target: nil, action: nil)
        self.format = format
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 8
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.toolTip = tooltip
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        valueLabel.textColor = InspectorStyle.secondaryText
        valueLabel.alignment = .right
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.widthAnchor.constraint(equalToConstant: 40).isActive = true
        if let label {
            let l = InspectorStyle.rowLabel(label)
            l.toolTip = tooltip
            l.translatesAutoresizingMaskIntoConstraints = false
            l.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
            addArrangedSubview(l)
        }
        addArrangedSubview(slider)
        addArrangedSubview(valueLabel)
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    var value: Double {
        get { slider.doubleValue }
        set { slider.doubleValue = newValue; valueLabel.stringValue = format(newValue) }
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        valueLabel.stringValue = format(sender.doubleValue)
        let type = NSApp.currentEvent?.type
        let tracking = type == .leftMouseDown || type == .leftMouseDragged
        onChange?(sender.doubleValue, !tracking)
    }
}

/// A checkbox drawn for the dark panel: the system one's unchecked box is a near-black square on
/// the near-black HUD (≈ #3a3a3a on #232323), so this one has a visible outline. Behaves like an
/// ordinary switch button (state, action, accessibility).
final class InspectorCheckbox: NSButton {
    private static let box: CGFloat = 14, gap: CGFloat = 6
    private var titleText: NSAttributedString {
        NSAttributedString(string: title, attributes: [.foregroundColor: InspectorStyle.primaryText,
                                                       .font: NSFont.systemFont(ofSize: 12)])
    }

    init(title: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        setButtonType(.switch)
        self.title = title
        self.target = target
        self.action = action
        focusRingType = .none
    }
    required init?(coder: NSCoder) { fatalError() }

    override var state: NSControl.StateValue { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize {
        let t = titleText.size()
        return NSSize(width: ceil(Self.box + Self.gap + t.width) + 2, height: max(18, ceil(t.height)))
    }

    override func draw(_ dirtyRect: NSRect) {
        let b = Self.box
        let r = NSRect(x: 1, y: (bounds.height - b) / 2, width: b, height: b)
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5)
        if state == .on {
            NSColor.controlAccentColor.setFill(); path.fill()
            // Checkmark, in unit coordinates of the box (y up), mapped for either flip.
            let tick = NSBezierPath()
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
                NSPoint(x: r.minX + x * b, y: isFlipped ? r.maxY - y * b : r.minY + y * b)
            }
            tick.move(to: p(0.25, 0.52)); tick.line(to: p(0.43, 0.32)); tick.line(to: p(0.76, 0.70))
            tick.lineWidth = 1.8; tick.lineCapStyle = .round; tick.lineJoinStyle = .round
            NSColor.white.setStroke(); tick.stroke()
        } else {
            NSColor(white: 1, alpha: 0.06).setFill(); path.fill()
            NSColor(white: 1, alpha: 0.55).setStroke(); path.lineWidth = 1; path.stroke()
        }
        if isHighlighted { NSColor(white: 1, alpha: 0.15).setFill(); path.fill() }
        let t = titleText
        t.draw(at: NSPoint(x: r.maxX + Self.gap, y: (bounds.height - t.size().height) / 2))
    }
}

/// A one-click text style in the side panel's Styles section, drawn as a small preview of the
/// look it applies (its box colour, font and text colour). The active look gets an accent ring.
final class TextPresetChip: NSButton {
    let preset: TextStylePreset
    var isActivePreset = false { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(preset: TextStylePreset, target: AnyObject?, action: Selector) {
        self.preset = preset
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        bezelStyle = .shadowlessSquare
        focusRingType = .none
        title = ""
        toolTip = preset.tooltip
        setAccessibilityLabel(preset.displayName)
        self.target = target
        self.action = action
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let look = preset.look
        let chip = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 6, yRadius: 6)
        (look.box?.color.nsColor ?? NSColor(white: 1, alpha: 0.06)).setFill()
        chip.fill()
        if hovering { NSColor(white: 1, alpha: 0.10).setFill(); chip.fill() }
        (isActivePreset ? NSColor.controlAccentColor : NSColor(white: 1, alpha: 0.16)).setStroke()
        chip.lineWidth = isActivePreset ? 2 : 1
        chip.stroke()
        // Title keeps the user's colour, so its preview uses the panel's text colour.
        let text = NSAttributedString(string: preset.displayName, attributes: [
            .font: TextFont.font(family: look.family, size: preset == .title ? 15 : 12,
                                 bold: look.bold, italic: false),
            .foregroundColor: look.color?.nsColor ?? NSColor(white: 1, alpha: 0.92)])
        let size = text.size()
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }
}

/// Top-left-origin container so the panel's sections start at the top of its scroll view.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Keeps the document view centred when it is smaller than the visible area,
/// so the screenshot floats in the middle of the neutral backdrop.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if rect.width > doc.frame.width {
            rect.origin.x = (doc.frame.width - rect.width) / 2
        }
        if rect.height > doc.frame.height {
            rect.origin.y = (doc.frame.height - rect.height) / 2
        }
        return rect
    }
}
