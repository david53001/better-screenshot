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
    /// Blur / Pixelate / Black-out switch: the window makes an active redaction tool follow it
    /// (the switch also converts the selected redactions, through `onStyleEdit`).
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
    /// Arrange (Front / Back / Delete) sits below the scroll area: right under the sections
    /// when they fit, pinned to the panel's bottom when they scroll — so Delete never scrolls away.
    private let footer = NSStackView()
    private var withFooter: [NSLayoutConstraint] = []
    private var withoutFooter: [NSLayoutConstraint] = []
    /// Single-slider sections: no caption, the slider row carries the name in its label column.
    private static let inlineLabelled: Set<InspectorSection> = [.opacity, .strength, .spotlightDim]
    /// Re-read `style` / `tool` / `recents` into the current sections' controls.
    private var refreshers: [() -> Void] = []
    /// Views of the previous build, kept alive until the next run-loop turn: a rebuild can be
    /// triggered by one of their own actions (e.g. Delete empties the selection).
    private var retired: [NSView] = []

    // Kept across rebuilds: the colour panel stays attached to one well.
    private let colorWell = NSColorWell()
    /// Text: the colour of the box behind the text, and of the outline.
    private let backgroundWell = NSColorWell()
    private let outlineWell = NSColorWell()
    /// The well whose current colour-panel drag session put the front Recent entry there.
    private var wellSession: NSColorWell?

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
    /// The box-behind-text palette: the same colours, with black at 80% (the default box).
    static let backgroundPresetColors = Array(presetColors.dropLast()) + [NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.8)]
    static let backgroundPresetColorNames = Array(presetColorNames.dropLast()) + ["Black (80%)"]
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

        footer.orientation = .vertical
        footer.alignment = .centerX
        footer.spacing = 10
        footer.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 12, right: 16)
        footer.translatesAutoresizingMaskIntoConstraints = false
        for v in [InspectorStyle.hairline(), makeArrangeRow()] {
            footer.addArrangedSubview(v)
            v.widthAnchor.constraint(equalToConstant: InspectorStyle.contentWidth).isActive = true
        }
        footer.isHidden = true
        addSubview(footer)

        for (well, tip) in [(colorWell, "Custom colour — opens the colour picker"),
                            (backgroundWell, "Custom box colour — opens the colour picker"),
                            (outlineWell, "Outline colour — picking one turns the outline on")] {
            well.target = self
            well.action = #selector(wellChanged(_:))
            well.toolTip = tip
            well.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                well.widthAnchor.constraint(equalToConstant: 40),
                well.heightAnchor.constraint(equalToConstant: 24),
            ])
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            sectionStack.topAnchor.constraint(equalTo: doc.topAnchor),
            sectionStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            sectionStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            sectionStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
        // The scroll area is as tall as its sections unless the panel is too short for them.
        // Below `windowSizeStayPut`, or a long Text panel would grow the window instead of scrolling.
        let fitsContent = scroll.heightAnchor.constraint(equalTo: doc.heightAnchor)
        fitsContent.priority = NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.windowSizeStayPut.rawValue - 10)
        fitsContent.isActive = true
        withFooter = [footer.topAnchor.constraint(equalTo: scroll.bottomAnchor),
                      footer.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)]
        withoutFooter = [scroll.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)]
        NSLayoutConstraint.activate(withoutFooter)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Shows `content` with `style`'s values. Cheap when only values changed.
    func update(content: InspectorContent, tool: EditorTool, style: AnnotationStyle) {
        self.tool = tool
        self.style = style
        titleLabel.stringValue = content.title
        let scrolled = content.sections.filter { $0 != .arrange }
        if scrolled != self.content.sections.filter({ $0 != .arrange }) { rebuild(scrolled) }
        let arrange = content.sections.contains(.arrange)
        if footer.isHidden == arrange {
            footer.isHidden = !arrange
            NSLayoutConstraint.deactivate(arrange ? withoutFooter : withFooter)
            NSLayoutConstraint.activate(arrange ? withFooter : withoutFooter)
        }
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
        wellSession = nil

        for (i, section) in sections.enumerated() {
            if i > 0 { addFullWidth(InspectorStyle.hairline(), inset: 16) }
            let box = NSStackView()
            box.orientation = .vertical
            box.alignment = .leading
            box.spacing = 8
            box.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 14, right: 16)
            if let title = section.title, !Self.inlineLabelled.contains(section) {
                box.addArrangedSubview(InspectorStyle.caption(title))
            }
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
        case .styles: return makeStyleRows()
        case .colour: return makeColourRows()
        case .stroke: return makeStrokeRows(presets: Self.strokePresets, range: Self.strokeRange)
        case .highlighterStroke:
            return makeStrokeRows(presets: HighlighterPen.widthPresets,
                                  range: Double(HighlighterPen.widthRange.lowerBound)...Double(HighlighterPen.widthRange.upperBound))
        case .font: return makeFontRows()
        case .background: return makeBackgroundRows()
        case .effects: return makeEffectsRows()
        case .redaction: return makeRedactionRows()
        case .strength: return makeStrengthRows()
        case .spotlightShape: return makeSpotlightShapeRows()
        case .spotlightDim: return makeSpotlightDimRows()
        case .opacity: return makeOpacityRows()
        case .arrange: return []   // the footer below the scroll area (`makeArrangeRow`)
        case .cropHelp, .selectHelp: return [InspectorStyle.note(section.note ?? "")]
        }
    }

    // MARK: Colour — presets, recents, custom well + eyedropper

    /// What a set of colour rows edits; stored in the swatches' and eyedropper's `tag`.
    private enum ColourTarget: Int { case stroke, textBackground }

    private func makeColourRows(_ target: ColourTarget = .stroke) -> [NSView] {
        let (palette, names) = target == .stroke ? (Self.presetColors, Self.presetColorNames)
                                                 : (Self.backgroundPresetColors, Self.backgroundPresetColorNames)
        let presets = zip(palette, names).map { color, name -> SwatchButton in
            let b = SwatchButton(color: color, target: self, action: #selector(swatchClicked(_:)))
            b.toolTip = name
            b.tag = target.rawValue
            return b
        }
        let presetRow = InspectorStyle.row(presets)
        presetRow.distribution = .equalSpacing   // = the 8pt swatch grid across the 232pt column

        // Recent colours sit on the preset grid (columns 3–8) after a two-column caption. Only
        // the text colour shows them: the box colour keeps to one short block (presets + custom).
        let recentButtons = target == .stroke ? (0..<RecentColors.capacity).map { _ -> SwatchButton in
            let b = SwatchButton(color: .clear, target: self, action: #selector(swatchClicked(_:)))
            b.tag = target.rawValue
            return b
        } : []
        let recentRow = InspectorStyle.row([Self.gridCaption("Recent")] + recentButtons,
                                           spacing: InspectorStyle.swatchGap, fill: true)
        if let last = recentButtons.last { recentRow.setCustomSpacing(0, after: last) }

        let pick = NSButton(title: "Pick from Screen", target: self, action: #selector(eyedropper(_:)))
        pick.image = NSImage(systemSymbolName: "eyedropper", accessibilityDescription: "Eyedropper")
        pick.imagePosition = .imageLeading
        pick.bezelStyle = .rounded
        pick.controlSize = .small
        pick.tag = target.rawValue
        pick.toolTip = "Eyedropper — click anywhere on screen to use that colour"
        let well = target == .stroke ? colorWell : backgroundWell
        let customRow = InspectorStyle.row([Self.gridCaption("Custom"), well, pick],
                                           spacing: InspectorStyle.swatchGap, fill: true)
        customRow.setCustomSpacing(6, after: well)
        customRow.setCustomSpacing(0, after: pick)

        refreshers.append { [unowned self] in
            let current = target == .stroke ? style.strokeColor : style.textBackgroundColor
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
            if !RecentColors.same(RGBAColor(well.color), current) { well.color = current.nsColor }
        }
        return target == .stroke ? [presetRow, recentRow, customRow] : [presetRow, customRow]
    }

    /// "RECENT" / "CUSTOM": an in-row caption two swatch columns wide.
    private static func gridCaption(_ text: String) -> NSTextField {
        let l = InspectorStyle.caption(text)
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: InspectorStyle.swatchCaptionWidth).isActive = true
        return l
    }

    private func colourEdit(_ c: RGBAColor, _ target: ColourTarget = .stroke) -> StyleEdit {
        switch target {
        case .stroke:
            return { s in
                s.strokeColor = c
                s.fillColor = RGBAColor(r: c.r, g: c.g, b: c.b, a: 0.25)
                // A text's outline must stay visible against its new letter colour.
                if s.textOutline { s.textOutlineColor = TextChip.outlineColor(s.textOutlineColor, forText: c) }
            }
        case .textBackground:
            return { $0.textBackgroundColor = c }
        }
    }

    @objc private func swatchClicked(_ sender: SwatchButton) {
        let c = RGBAColor(sender.swatchColor)
        wellSession = nil
        // A recent colour moves to the front; presets are always on show, so they aren't recorded.
        if recents.colors.contains(where: { RecentColors.same($0, c) }) { remember(c, replacingFront: false) }
        onStyleEdit?(colourEdit(c, ColourTarget(rawValue: sender.tag) ?? .stroke), nil)
    }

    /// Any of the three wells: every colour it picks is a custom colour, so it goes into Recent
    /// (one entry per colour-panel session), and one session is one undo step.
    @objc private func wellChanged(_ sender: NSColorWell) {
        let c = RGBAColor(sender.color)
        remember(c, replacingFront: wellSession === sender)
        wellSession = sender
        if sender === backgroundWell {
            onStyleEdit?(colourEdit(c, .textBackground), "backgroundWell")
        } else if sender === outlineWell {
            onStyleEdit?({ $0.textOutlineColor = c; $0.textOutline = true }, "outlineWell")
        } else {
            onStyleEdit?(colourEdit(c), "colourWell")
        }
    }

    @objc private func eyedropper(_ sender: NSButton) {
        let target = ColourTarget(rawValue: sender.tag) ?? .stroke
        NSColorSampler().show { [weak self] picked in
            guard let picked else { return }   // nil = the user pressed Esc
            DispatchQueue.main.async {
                guard let self else { return }
                let c = RGBAColor(picked)
                self.wellSession = nil
                self.remember(c, replacingFront: false)
                self.onStyleEdit?(self.colourEdit(c, target), nil)
            }
        }
    }

    private func remember(_ c: RGBAColor, replacingFront: Bool) {
        let before = recents
        recents.add(c, replacingFront: replacingFront)
        if recents != before { onRecentColorsChanged?(recents.colors) }
    }

    // MARK: Stroke — width slider + Thin / Medium / Thick

    private func makeStrokeRows(presets widths: [CGFloat], range: ClosedRange<Double>) -> [NSView] {
        let slider = LabeledSliderRow(label: "Width", range: range,
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
        for (i, w) in widths.enumerated() {
            presets.setToolTip("\(Int(w)) px", forSegment: i)
            presets.setTag(Int(w), forSegment: i)
        }
        refreshers.append { [unowned self] in
            slider.value = Double(style.lineWidth)
            presets.selectedSegment = widths.firstIndex(of: style.lineWidth) ?? -1
        }
        return [slider, presets]
    }

    @objc private func strokePresetChosen(_ sender: NSSegmentedControl) {
        let w = CGFloat(sender.tag(forSegment: max(0, sender.selectedSegment)))
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

        // B I U S — independent toggles.
        let emphasis = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "bold", accessibilityDescription: "Bold")!,
            NSImage(systemSymbolName: "italic", accessibilityDescription: "Italic")!,
            NSImage(systemSymbolName: "underline", accessibilityDescription: "Underline")!,
            NSImage(systemSymbolName: "strikethrough", accessibilityDescription: "Strikethrough")!,
        ], trackingMode: .selectAny, target: self, action: #selector(emphasisChanged(_:)))
        emphasis.segmentStyle = .rounded
        emphasis.controlSize = .small
        for (i, tip) in ["Bold", "Italic", "Underline", "Strikethrough"].enumerated() {
            emphasis.setToolTip(tip, forSegment: i)
            emphasis.setWidth(28, forSegment: i)
        }

        let align = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Align left")!,
            NSImage(systemSymbolName: "text.aligncenter", accessibilityDescription: "Align centre")!,
            NSImage(systemSymbolName: "text.alignright", accessibilityDescription: "Align right")!,
        ], trackingMode: .selectOne, target: self, action: #selector(alignmentChanged(_:)))
        align.segmentStyle = .rounded
        align.controlSize = .small
        for (i, tip) in ["Align left", "Align centre", "Align right"].enumerated() {
            align.setToolTip(tip, forSegment: i)
            align.setWidth(28, forSegment: i)
        }

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
            emphasis.setSelected(style.fontBold, forSegment: 0)
            emphasis.setSelected(style.fontItalic, forSegment: 1)
            emphasis.setSelected(style.textUnderline, forSegment: 2)
            emphasis.setSelected(style.textStrikethrough, forSegment: 3)
            align.selectedSegment = TextAlign.allCases.firstIndex(of: style.textAlignment) ?? 0
        }
        // Two rows: typeface (family · size), then emphasis · alignment.
        family.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let styleRow = InspectorStyle.row([emphasis, align])
        styleRow.distribution = .equalSpacing
        return [InspectorStyle.row([family, size]), styleRow]
    }

    @objc private func fontFamilyChanged(_ sender: NSPopUpButton) {
        guard let family = sender.selectedItem?.representedObject as? String else { return }
        onStyleEdit?({ $0.fontFamily = family }, nil)
    }

    @objc private func fontSizeChanged(_ sender: NSPopUpButton) {
        guard let size = sender.selectedItem?.representedObject as? CGFloat else { return }
        onStyleEdit?({ $0.fontSize = size }, nil)
    }

    @objc private func emphasisChanged(_ sender: NSSegmentedControl) {
        let bold = sender.isSelected(forSegment: 0), italic = sender.isSelected(forSegment: 1)
        let underline = sender.isSelected(forSegment: 2), strike = sender.isSelected(forSegment: 3)
        onStyleEdit?({ $0.fontBold = bold; $0.fontItalic = italic
                       $0.textUnderline = underline; $0.textStrikethrough = strike }, nil)
    }

    @objc private func alignmentChanged(_ sender: NSSegmentedControl) {
        let a = TextAlign.allCases[max(0, sender.selectedSegment)]
        onStyleEdit?({ $0.textAlignment = a }, nil)
    }

    // MARK: Styles (text) — one-click presets, 3 per row

    private func makeStyleRows() -> [NSView] {
        let chips = TextStylePreset.allCases.map {
            TextPresetChip(preset: $0, target: self, action: #selector(presetChosen(_:)))
        }
        let rows = stride(from: 0, to: chips.count, by: 3).map { i -> NSStackView in
            let row = InspectorStyle.row(Array(chips[i..<min(i + 3, chips.count)]))
            row.distribution = .fillEqually
            return row
        }
        refreshers.append { [unowned self] in
            for chip in chips { chip.isActivePreset = chip.preset.isApplied(to: style) }
        }
        return rows
    }

    @objc private func presetChosen(_ sender: TextPresetChip) {
        let preset = sender.preset
        onStyleEdit?({ preset.apply(to: &$0) }, nil)
    }

    // MARK: Background (text) — None / Solid / Auto; Solid shows the colour rows, both boxes padding + corners

    private func makeBackgroundRows() -> [NSView] {
        let mode = NSSegmentedControl(labels: ["None", "Solid", "Auto"], trackingMode: .selectOne,
                                      target: self, action: #selector(backgroundModeChanged(_:)))
        mode.segmentStyle = .rounded
        mode.controlSize = .small
        mode.segmentDistribution = .fillEqually
        mode.setToolTip("No box behind the text", forSegment: 0)
        mode.setToolTip("A box in the colour you pick below", forSegment: 1)
        mode.setToolTip("A dark or light box, whichever stands out against the text colour", forSegment: 2)

        let colours = Self.column(makeColourRows(.textBackground))
        let autoNote = InspectorStyle.note("Dark or light — whichever stands out against the text colour.")
        let range = AnnotationStyle.textBackgroundPaddingRange
        let padding = LabeledSliderRow(label: "Padding",
                                       range: Double(range.lowerBound)...Double(range.upperBound),
                                       tooltip: "Space between the text and the edge of the box") { "\(Int($0.rounded())) px" }
        padding.onChange = { [unowned self] v, finished in
            let p = CGFloat(v.rounded())
            onStyleEdit?({ $0.textBackgroundPadding = p }, "textBackgroundPadding")
            if finished { onStyleEditEnded?() }
        }
        let radii = AnnotationStyle.textBackgroundCornerRadiusRange
        let corners = LabeledSliderRow(label: "Corners",
                                       range: Double(radii.lowerBound)...Double(radii.upperBound),
                                       tooltip: "How rounded the box's corners are") { "\(Int($0.rounded())) px" }
        corners.onChange = { [unowned self] v, finished in
            let r = CGFloat(v.rounded())
            onStyleEdit?({ $0.textBackgroundCornerRadius = r }, "textBackgroundCornerRadius")
            if finished { onStyleEditEnded?() }
        }
        refreshers.append { [unowned self] in
            let m = style.textBackgroundMode
            mode.selectedSegment = TextBackgroundMode.allCases.firstIndex(of: m) ?? 0
            colours.isHidden = m != .solid
            autoNote.isHidden = m != .auto
            padding.isHidden = m == .none
            corners.isHidden = m == .none
            padding.value = Double(style.textBackgroundPadding)
            corners.value = Double(style.textBackgroundCornerRadius)
        }
        return [mode, colours, autoNote, padding, corners]
    }

    @objc private func backgroundModeChanged(_ sender: NSSegmentedControl) {
        let m = TextBackgroundMode.allCases[max(0, sender.selectedSegment)]
        onStyleEdit?({ $0.textBackgroundMode = m }, nil)
    }

    /// Rows stacked as one panel row (so a group of rows can be shown / hidden together).
    private static func column(_ rows: [NSView]) -> NSStackView {
        let c = NSStackView(views: rows)
        c.orientation = .vertical
        c.alignment = .leading
        c.spacing = 8
        for r in rows { r.widthAnchor.constraint(equalTo: c.widthAnchor).isActive = true }
        return c
    }

    // MARK: Effects (text) — Outline + its colour well, Shadow; then the outline width

    private func makeEffectsRows() -> [NSView] {
        let outline = checkbox("Outline", #selector(outlineToggled(_:)),
                               tooltip: "An edge around every letter — keeps text readable on busy screenshots")
        let shadow = checkbox("Shadow", #selector(shadowToggled(_:)),
                              tooltip: "A soft drop shadow under the text (and its box)")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        // The outline's colour well sits right after its checkbox, so it reads as its colour.
        let row = InspectorStyle.row([outline, outlineWell, spacer, shadow])
        row.setCustomSpacing(6, after: outline)

        let range = AnnotationStyle.textOutlineWidthRange
        let width = LabeledSliderRow(label: "Width", range: Double(range.lowerBound)...Double(range.upperBound),
                                     tooltip: "Outline thickness in image pixels") { "\(Int($0.rounded())) px" }
        width.onChange = { [unowned self] v, finished in
            let w = CGFloat(v.rounded())
            onStyleEdit?({ $0.textOutlineWidth = w }, "textOutlineWidth")
            if finished { onStyleEditEnded?() }
        }
        refreshers.append { [unowned self] in
            outline.state = style.textOutline ? .on : .off
            width.isHidden = !style.textOutline
            width.value = Double(style.textOutlineWidth)
            if !RecentColors.same(RGBAColor(outlineWell.color), style.textOutlineColor) {
                outlineWell.color = style.textOutlineColor.nsColor
            }
            shadow.state = style.textShadow ? .on : .off
        }
        return [row, width]
    }

    private func checkbox(_ title: String, _ action: Selector, tooltip: String) -> NSButton {
        let b = InspectorCheckbox(title: title, target: self, action: action)
        b.toolTip = tooltip
        return b
    }

    @objc private func outlineToggled(_ sender: NSButton) {
        let on = sender.state == .on
        onStyleEdit?({ s in
            s.textOutline = on
            // Default white on white text (Label, Callout) would be an unreadable blob.
            if on { s.textOutlineColor = TextChip.outlineColor(s.textOutlineColor, forText: s.strokeColor) }
        }, nil)
    }

    @objc private func shadowToggled(_ sender: NSButton) {
        let on = sender.state == .on
        onStyleEdit?({ $0.textShadow = on }, nil)
    }

    // MARK: Redaction — Blur / Pixelate / Black-out, then Strength

    /// The mode shown: the active redaction tool's, else the selected redaction's.
    private var redactionMode: RedactionMode { tool.redactionMode ?? style.redactionMode }

    private func makeRedactionRows() -> [NSView] {
        let modes = RedactionMode.allCases
        let seg = NSSegmentedControl(labels: modes.map(\.label), trackingMode: .selectOne,
                                     target: self, action: #selector(redactChanged(_:)))
        seg.segmentStyle = .rounded
        seg.controlSize = .small
        seg.segmentDistribution = .fillEqually
        for (i, m) in modes.enumerated() { seg.setToolTip(m.tool.tooltip, forSegment: i) }
        let note = InspectorStyle.note("")
        refreshers.append { [unowned self] in
            seg.selectedSegment = modes.firstIndex(of: redactionMode) ?? 0
            note.stringValue = Self.redactionNote(redactionMode)
        }
        return [seg, note]
    }

    static func redactionNote(_ mode: RedactionMode) -> String {
        switch mode {
        case .blur: return "Softens what's underneath. Raise the strength until it can't be read."
        case .pixelate: return "Turns what's underneath into blocks. Bigger blocks hide more."
        case .blackout: return "Covers it with solid black — the safest choice, nothing can be recovered."
        }
    }

    @objc private func redactChanged(_ sender: NSSegmentedControl) {
        let mode = RedactionMode.allCases[max(0, sender.selectedSegment)]
        onStyleEdit?({ $0.redactionMode = mode }, nil)   // converts the selected redaction(s)
        onRedactTool?(mode.tool)
    }

    private func makeStrengthRows() -> [NSView] {
        let range = AnnotationStyle.blurRadiusRange
        let slider = LabeledSliderRow(label: "Strength", range: Double(range.lowerBound)...Double(range.upperBound),
                                      tooltip: "How strongly it hides what's underneath") { "\(Int($0.rounded())) px" }
        slider.onChange = { [unowned self] v, finished in
            let px = CGFloat(v.rounded()), pixelate = redactionMode == .pixelate
            onStyleEdit?({ if pixelate { $0.pixelSize = px } else { $0.blurRadius = px } }, "redactionStrength")
            if finished { onStyleEditEnded?() }
        }
        refreshers.append { [unowned self] in
            // Blur and Pixelate share this section, so the range follows the mode.
            let pixelate = redactionMode == .pixelate
            let r = pixelate ? AnnotationStyle.pixelSizeRange : AnnotationStyle.blurRadiusRange
            slider.slider.minValue = Double(r.lowerBound)
            slider.slider.maxValue = Double(r.upperBound)
            slider.slider.toolTip = pixelate ? "Size of each block, in image pixels" : "Blur radius, in image pixels"
            slider.value = Double(pixelate ? style.pixelSize : style.blurRadius)
        }
        return [slider]
    }

    // MARK: Spotlight — Shape, Dim outside

    private func makeSpotlightShapeRows() -> [NSView] {
        let shapes = SpotlightShape.allCases
        let seg = NSSegmentedControl(labels: ["Rectangle", "Ellipse"], trackingMode: .selectOne,
                                     target: self, action: #selector(spotlightShapeChanged(_:)))
        seg.segmentStyle = .rounded
        seg.controlSize = .small
        seg.segmentDistribution = .fillEqually
        for (i, symbol) in ["rectangle", "circle"].enumerated() {
            seg.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), forSegment: i)
            seg.setImageScaling(.scaleProportionallyDown, forSegment: i)
        }
        seg.setToolTip("Rectangle", forSegment: 0)
        seg.setToolTip("Ellipse — or hold ⌥ while dragging", forSegment: 1)
        refreshers.append { [unowned self] in seg.selectedSegment = shapes.firstIndex(of: style.spotlightShape) ?? 0 }
        return [seg]
    }

    @objc private func spotlightShapeChanged(_ sender: NSSegmentedControl) {
        let shape = SpotlightShape.allCases[max(0, sender.selectedSegment)]
        onStyleEdit?({ $0.spotlightShape = shape }, nil)
    }

    private func makeSpotlightDimRows() -> [NSView] {
        let r = AnnotationStyle.spotlightDimRange
        let slider = LabeledSliderRow(label: "Dim", range: Double(r.lowerBound * 100)...Double(r.upperBound * 100),
                                      tooltip: "How dark everything outside the spotlights gets") { "\(Int($0.rounded()))%" }
        slider.onChange = { [unowned self] v, finished in
            let d = CGFloat(v.rounded()) / 100
            onStyleEdit?({ $0.spotlightDim = d }, "spotlightDim")
            if finished { onStyleEditEnded?() }
        }
        refreshers.append { [unowned self] in slider.value = Double(style.spotlightDim * 100) }
        return [slider]
    }

    // MARK: Opacity

    private func makeOpacityRows() -> [NSView] {
        let range = AnnotationStyle.opacityRange
        let slider = LabeledSliderRow(label: "Opacity", range: Double(range.lowerBound * 100)...Double(range.upperBound * 100),
                                      tooltip: "How see-through the object is") { "\(Int($0.rounded()))%" }
        slider.onChange = { [unowned self] v, finished in
            let o = CGFloat(v.rounded()) / 100
            onStyleEdit?({ $0.opacity = o }, "opacity")
            if finished { onStyleEditEnded?() }
        }
        refreshers.append { [unowned self] in slider.value = Double(style.opacity * 100) }
        return [slider]
    }

    // MARK: Arrange — Front / Back / Delete (the footer; built once)

    private func makeArrangeRow() -> NSView {
        func button(_ title: String, _ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            b.imagePosition = .imageLeading
            b.toolTip = tip
            return b
        }
        // Opposite arrows: the stacked-layers symbols were near-identical at this size.
        let row = InspectorStyle.row([
            button("Front", "arrow.up.to.line", "Bring to front ( ] )", #selector(front)),
            button("Back", "arrow.down.to.line", "Send to back ( [ )", #selector(back)),
            button("Delete", "trash", "Delete (⌫)", #selector(delete)),
        ], spacing: 6)
        row.distribution = .fillEqually
        return row
    }

    @objc private func front() { onArrange?(.front) }
    @objc private func back() { onArrange?(.back) }
    @objc private func delete() { onArrange?(.delete) }
}
