import AppKit

/// One inspector change to a style field (e.g. "line width = 7"). The window applies it to
/// the selected objects and to the default style for new objects.
typealias StyleEdit = (inout AnnotationStyle) -> Void

enum ArrangeAction { case front, back, delete }

/// The editor's right-side panel: a heading plus titled sections chosen by `InspectorModel`
/// for the active tool / selection. Sections are rebuilt only when the list changes; value
/// changes (another selected object, undo, a live edit) just refresh the controls in place,
/// so a slider being dragged is never torn down.
///
/// To add a section: see `InspectorSection` — add a case to `makeSection(_:)` returning its
/// rows, and register a closure in `refreshers` that reads `style` back into the controls.
final class EditorInspectorView: NSVisualEffectView {
    static let width: CGFloat = 264

    /// A style edit; edits sharing a non-nil group (one slider drag, one colour-panel
    /// session) merge into one undo step.
    var onStyleEdit: ((_ edit: @escaping StyleEdit, _ group: AnyHashable?) -> Void)?
    /// A slider was released — the next edit starts a new undo step.
    var onStyleEditEnded: (() -> Void)?
    var onRecentColorsChanged: (([RGBAColor]) -> Void)?
    /// Blur ↔ Pixelate switch (changes the active tool).
    var onRedactTool: ((EditorTool) -> Void)?
    var onArrange: ((ArrangeAction) -> Void)?

    private(set) var recents: RecentColors
    private(set) var content = InspectorContent(title: "", sections: [])
    private var tool: EditorTool = .select
    private var style = AnnotationStyle.default

    private let titleLabel = NSTextField(labelWithString: "")
    private let sectionStack = NSStackView()
    /// Scrolls the sections when the window is too short for them (overlay scroller).
    private let scroll = NSScrollView()
    /// Re-read `style` / `tool` / `recents` into the current sections' controls.
    private var refreshers: [() -> Void] = []
    /// Views of the previous build, kept alive until the next run-loop turn: a rebuild can be
    /// triggered by one of their own actions (e.g. Delete empties the selection).
    private var retired: [NSView] = []

    // Kept across rebuilds: the colour panel stays attached to one well.
    private let colorWell = NSColorWell()
    /// The front Recent entry came from the colour well's current drag session.
    private var wellSessionInRecents = false

    static let presetColors: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1), // red
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.04, alpha: 1), // orange
        NSColor(srgbRed: 1.00, green: 0.84, blue: 0.04, alpha: 1), // yellow
        NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1), // green
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1), // blue
        NSColor(srgbRed: 0.75, green: 0.35, blue: 0.95, alpha: 1), // purple
        NSColor.white,
        NSColor.black,
    ]
    static let presetColorNames = ["Red", "Orange", "Yellow", "Green", "Blue", "Purple", "White", "Black"]
    /// Stroke presets (px) behind Thin / Medium / Thick.
    static let strokePresets: [CGFloat] = [2, 4, 7]
    static let strokeRange: ClosedRange<Double> = 1...24
    static let fontSizes: [CGFloat] = [12, 14, 18, 24, 30, 36, 48, 64, 96]

    init(recentColors: [RGBAColor]) {
        recents = RecentColors(recentColors)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        appearance = NSAppearance(named: .vibrantDark)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = NSColor(white: 1, alpha: 0.92)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        sectionStack.orientation = .vertical
        sectionStack.alignment = .centerX
        sectionStack.spacing = 0
        sectionStack.translatesAutoresizingMaskIntoConstraints = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(sectionStack)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.documentView = doc
        addSubview(scroll)

        colorWell.target = self
        colorWell.action = #selector(wellChanged(_:))
        colorWell.toolTip = "Custom colour — opens the colour picker"
        colorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            colorWell.widthAnchor.constraint(equalToConstant: 44),
            colorWell.heightAnchor.constraint(equalToConstant: 24),
        ])

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            sectionStack.topAnchor.constraint(equalTo: doc.topAnchor),
            sectionStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            sectionStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            sectionStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Shows `content` with `style`'s values. Cheap when only values changed.
    func update(content: InspectorContent, tool: EditorTool, style: AnnotationStyle) {
        self.tool = tool
        self.style = style
        titleLabel.stringValue = content.title
        if content.sections != self.content.sections { rebuild(content.sections) }
        self.content = content
        refreshers.forEach { $0() }
    }

    // MARK: - Building

    private func rebuild(_ sections: [InspectorSection]) {
        retired = sectionStack.arrangedSubviews
        retired.forEach { $0.removeFromSuperview() }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.retired.removeAll()
            // Show the scroller briefly when the window is too short for every section.
            if let doc = self.scroll.documentView, doc.frame.height > self.scroll.contentView.bounds.height {
                self.scroll.flashScrollers()
            }
        }
        refreshers.removeAll()
        wellSessionInRecents = false

        for (i, section) in sections.enumerated() {
            if i > 0 { addFullWidth(InspectorStyle.hairline(), inset: 16) }
            let box = NSStackView()
            box.orientation = .vertical
            box.alignment = .leading
            box.spacing = 8
            box.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 14, right: 16)
            if let title = section.title { box.addArrangedSubview(InspectorStyle.caption(title)) }
            for row in makeSection(section) {
                box.addArrangedSubview(row)
                row.widthAnchor.constraint(equalToConstant: InspectorStyle.contentWidth).isActive = true
            }
            addFullWidth(box, inset: 0)
        }
    }

    private func addFullWidth(_ v: NSView, inset: CGFloat) {
        sectionStack.addArrangedSubview(v)
        v.widthAnchor.constraint(equalTo: sectionStack.widthAnchor, constant: -2 * inset).isActive = true
    }

    /// The rows of one section (each spans the content width).
    private func makeSection(_ section: InspectorSection) -> [NSView] {
        switch section {
        case .colour: return makeColourRows()
        case .stroke: return makeStrokeRows()
        case .font: return makeFontRows()
        case .background: return makeBackgroundRows()
        case .redaction: return makeRedactionRows()
        case .opacity: return makeOpacityRows()
        case .arrange: return makeArrangeRows()
        case .cropHelp, .selectHelp: return [InspectorStyle.note(section.note ?? "")]
        }
    }

    // MARK: Colour — presets, recents, custom well + eyedropper

    private func makeColourRows() -> [NSView] {
        let presets = zip(Self.presetColors, Self.presetColorNames).map { color, name -> SwatchButton in
            let b = SwatchButton(color: color, target: self, action: #selector(swatchClicked(_:)))
            b.toolTip = name
            return b
        }
        let presetRow = InspectorStyle.row(presets)
        presetRow.distribution = .equalSpacing

        let recentButtons = (0..<RecentColors.capacity).map { _ in
            SwatchButton(color: .clear, target: self, action: #selector(swatchClicked(_:)))
        }
        let recentLabel = InspectorStyle.caption("Recent")
        recentLabel.translatesAutoresizingMaskIntoConstraints = false
        recentLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        let recentRow = InspectorStyle.row([recentLabel] + recentButtons, spacing: 6, fill: true)

        let pick = NSButton(title: "Pick from Screen", target: self, action: #selector(eyedropper))
        pick.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Eyedropper")
        pick.imagePosition = .imageLeading
        pick.bezelStyle = .rounded
        pick.controlSize = .small
        pick.toolTip = "Eyedropper — click anywhere on screen to use that colour"
        let customRow = InspectorStyle.row([colorWell, pick], fill: true)

        refreshers.append { [unowned self] in
            let current = style.strokeColor
            for b in presets { b.isSelectedSwatch = RecentColors.same(RGBAColor(b.swatchColor), current) }
            let colors = recents.colors
            recentRow.isHidden = colors.isEmpty
            for (i, b) in recentButtons.enumerated() {
                b.isHidden = i >= colors.count
                guard i < colors.count else { continue }
                b.swatchColor = colors[i].nsColor
                b.toolTip = "Recent colour"
                b.isSelectedSwatch = RecentColors.same(colors[i], current)
            }
            if !RecentColors.same(RGBAColor(colorWell.color), current) { colorWell.color = current.nsColor }
        }
        return [presetRow, recentRow, customRow]
    }

    private func colourEdit(_ c: RGBAColor) -> StyleEdit {
        { s in
            s.strokeColor = c
            s.fillColor = RGBAColor(r: c.r, g: c.g, b: c.b, a: 0.25)
        }
    }

    @objc private func swatchClicked(_ sender: SwatchButton) {
        let c = RGBAColor(sender.swatchColor)
        wellSessionInRecents = false
        // A recent colour moves to the front; presets are always on show, so they aren't recorded.
        if recents.colors.contains(where: { RecentColors.same($0, c) }) { remember(c, replacingFront: false) }
        onStyleEdit?(colourEdit(c), nil)
    }

    @objc private func wellChanged(_ sender: NSColorWell) {
        let c = RGBAColor(sender.color)
        remember(c, replacingFront: wellSessionInRecents)
        wellSessionInRecents = true
        onStyleEdit?(colourEdit(c), "colourWell")
    }

    @objc private func eyedropper() {
        NSColorSampler().show { [weak self] picked in
            guard let self, let picked else { return }
            let c = RGBAColor(picked)
            self.wellSessionInRecents = false
            self.remember(c, replacingFront: false)
            self.onStyleEdit?(self.colourEdit(c), nil)
        }
    }

    private func remember(_ c: RGBAColor, replacingFront: Bool) {
        let before = recents
        recents.add(c, replacingFront: replacingFront)
        if recents != before { onRecentColorsChanged?(recents.colors) }
    }

    // MARK: Stroke — width slider + Thin / Medium / Thick

    private func makeStrokeRows() -> [NSView] {
        let slider = LabeledSliderRow(label: "Width", range: Self.strokeRange,
                                      tooltip: "Line width in image pixels") { "\(Int($0.rounded())) px" }
        slider.onChange = { [unowned self] v, finished in
            let w = CGFloat(v.rounded())
            onStyleEdit?({ $0.lineWidth = w }, "lineWidth")
            if finished { onStyleEditEnded?() }
        }
        let presets = NSSegmentedControl(labels: ["Thin", "Medium", "Thick"], trackingMode: .selectOne,
                                         target: self, action: #selector(strokePresetChosen(_:)))
        presets.segmentStyle = .rounded
        presets.controlSize = .small
        presets.segmentDistribution = .fillEqually
        for (i, w) in Self.strokePresets.enumerated() { presets.setToolTip("\(Int(w)) px", forSegment: i) }
        refreshers.append { [unowned self] in
            slider.value = Double(style.lineWidth)
            presets.selectedSegment = Self.strokePresets.firstIndex(of: style.lineWidth) ?? -1
        }
        return [slider, presets]
    }

    @objc private func strokePresetChosen(_ sender: NSSegmentedControl) {
        let w = Self.strokePresets[max(0, sender.selectedSegment)]
        onStyleEdit?({ $0.lineWidth = w }, nil)
    }

    // MARK: Font — family, size, bold/italic, alignment

    private func makeFontRows() -> [NSView] {
        let family = NSPopUpButton(frame: .zero, pullsDown: false)
        family.controlSize = .small
        family.target = self
        family.action = #selector(fontFamilyChanged(_:))
        family.toolTip = "Font"
        let menu = family.menu!
        for preset in TextFont.presets {
            let item = NSMenuItem(title: preset.label, action: nil, keyEquivalent: "")
            item.representedObject = preset.family
            item.attributedTitle = NSAttributedString(string: preset.label, attributes: [
                .font: TextFont.font(family: preset.family, size: 13, bold: false, italic: false)])
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for name in TextFont.installedFamilies {
            let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            item.representedObject = name
            menu.addItem(item)
        }

        let size = NSPopUpButton(frame: .zero, pullsDown: false)
        size.controlSize = .small
        size.target = self
        size.action = #selector(fontSizeChanged(_:))
        size.toolTip = "Font size"
        size.translatesAutoresizingMaskIntoConstraints = false
        size.widthAnchor.constraint(equalToConstant: 84).isActive = true

        let boldItalic = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "bold", accessibilityDescription: "Bold")!,
            NSImage(systemSymbolName: "italic", accessibilityDescription: "Italic")!,
        ], trackingMode: .selectAny, target: self, action: #selector(boldItalicChanged(_:)))
        boldItalic.segmentStyle = .rounded
        boldItalic.controlSize = .small
        boldItalic.setToolTip("Bold", forSegment: 0)
        boldItalic.setToolTip("Italic", forSegment: 1)
        for i in 0..<2 { boldItalic.setWidth(30, forSegment: i) }

        let align = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Align left")!,
            NSImage(systemSymbolName: "text.aligncenter", accessibilityDescription: "Align centre")!,
            NSImage(systemSymbolName: "text.alignright", accessibilityDescription: "Align right")!,
        ], trackingMode: .selectOne, target: self, action: #selector(alignmentChanged(_:)))
        align.segmentStyle = .rounded
        align.controlSize = .small
        align.segmentDistribution = .fillEqually
        align.setToolTip("Align left", forSegment: 0)
        align.setToolTip("Align centre", forSegment: 1)
        align.setToolTip("Align right", forSegment: 2)

        refreshers.append { [unowned self] in
            if let item = menu.items.first(where: { ($0.representedObject as? String) == style.fontFamily }) {
                family.select(item)
            } else {
                family.selectItem(at: 0)   // a since-uninstalled family renders as System — say so
            }
            var sizes = Self.fontSizes
            if !sizes.contains(style.fontSize) { sizes.append(style.fontSize); sizes.sort() }
            if size.itemArray.compactMap({ $0.representedObject as? CGFloat }) != sizes {
                size.removeAllItems()
                for s in sizes {
                    size.addItem(withTitle: "\(Int(s)) pt")
                    size.lastItem?.representedObject = s
                }
            }
            size.selectItem(at: sizes.firstIndex(of: style.fontSize) ?? 0)
            boldItalic.setSelected(style.fontBold, forSegment: 0)
            boldItalic.setSelected(style.fontItalic, forSegment: 1)
            align.selectedSegment = TextAlign.allCases.firstIndex(of: style.textAlignment) ?? 0
        }
        return [family, InspectorStyle.row([size, boldItalic], fill: true), align]
    }

    @objc private func fontFamilyChanged(_ sender: NSPopUpButton) {
        guard let family = sender.selectedItem?.representedObject as? String else { return }
        onStyleEdit?({ $0.fontFamily = family }, nil)
    }

    @objc private func fontSizeChanged(_ sender: NSPopUpButton) {
        guard let size = sender.selectedItem?.representedObject as? CGFloat else { return }
        onStyleEdit?({ $0.fontSize = size }, nil)
    }

    @objc private func boldItalicChanged(_ sender: NSSegmentedControl) {
        let bold = sender.isSelected(forSegment: 0), italic = sender.isSelected(forSegment: 1)
        onStyleEdit?({ $0.fontBold = bold; $0.fontItalic = italic }, nil)
    }

    @objc private func alignmentChanged(_ sender: NSSegmentedControl) {
        let a = TextAlign.allCases[max(0, sender.selectedSegment)]
        onStyleEdit?({ $0.textAlignment = a }, nil)
    }

    // MARK: Background (text) — Part 2 replaces this with None / Solid / Auto + colour, padding, radius

    private func makeBackgroundRows() -> [NSView] {
        let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(textBackgroundChanged(_:)))
        box.attributedTitle = NSAttributedString(string: "Contrasting box behind the text", attributes: [
            .foregroundColor: InspectorStyle.primaryText, .font: NSFont.systemFont(ofSize: 12)])
        box.toolTip = "A dark or light box, whichever stands out against the text colour"
        refreshers.append { [unowned self] in box.state = style.textBackground ? .on : .off }
        return [box]
    }

    @objc private func textBackgroundChanged(_ sender: NSButton) {
        let on = sender.state == .on
        onStyleEdit?({ $0.textBackground = on }, nil)
    }

    // MARK: Redaction — Blur / Pixelate (Part 3 adds Strength)

    private func makeRedactionRows() -> [NSView] {
        let seg = NSSegmentedControl(labels: ["Blur", "Pixelate"], trackingMode: .selectOne,
                                     target: self, action: #selector(redactChanged(_:)))
        seg.segmentStyle = .rounded
        seg.controlSize = .small
        seg.segmentDistribution = .fillEqually
        seg.setToolTip("Blur (B)", forSegment: 0)
        seg.setToolTip("Pixelate (P)", forSegment: 1)
        refreshers.append { [unowned self] in seg.selectedSegment = tool == .pixelate ? 1 : 0 }
        return [seg]
    }

    @objc private func redactChanged(_ sender: NSSegmentedControl) {
        onRedactTool?(sender.selectedSegment == 1 ? .pixelate : .blur)
    }

    // MARK: Opacity

    private func makeOpacityRows() -> [NSView] {
        let range = AnnotationStyle.opacityRange
        let slider = LabeledSliderRow(label: nil, range: Double(range.lowerBound * 100)...Double(range.upperBound * 100),
                                      tooltip: "How see-through the object is") { "\(Int($0.rounded()))%" }
        slider.onChange = { [unowned self] v, finished in
            let o = CGFloat(v.rounded()) / 100
            onStyleEdit?({ $0.opacity = o }, "opacity")
            if finished { onStyleEditEnded?() }
        }
        refreshers.append { [unowned self] in slider.value = Double(style.opacity * 100) }
        return [slider]
    }

    // MARK: Arrange — Front / Back / Delete

    private func makeArrangeRows() -> [NSView] {
        func button(_ title: String, _ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            b.imagePosition = .imageLeading
            b.toolTip = tip
            return b
        }
        let row = InspectorStyle.row([
            button("Front", "square.3.layers.3d.top.filled", "Bring to front ( ] )", #selector(front)),
            button("Back", "square.3.layers.3d.bottom.filled", "Send to back ( [ )", #selector(back)),
            button("Delete", "trash", "Delete (⌫)", #selector(delete)),
        ], spacing: 6)
        row.distribution = .fillEqually
        return [row]
    }

    @objc private func front() { onArrange?(.front) }
    @objc private func back() { onArrange?(.back) }
    @objc private func delete() { onArrange?(.delete) }
}
