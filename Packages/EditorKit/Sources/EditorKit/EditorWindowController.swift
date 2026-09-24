import AppKit

/// The annotation editor window. Redesigned chrome: a floating frosted-glass
/// tool pill, an inspector that adapts to the active tool, a quiet bottom
/// action bar, and undo/redo in the title bar — over a centred neutral canvas.
public final class EditorWindowController: NSWindowController {
    private let canvas: EditorCanvasView
    private var style = AnnotationStyle.default
    public var onCopy: ((CGImage) -> Void)?
    public var onSave: ((CGImage) -> Void)?
    public var onAddToStack: ((CGImage) -> Void)?
    /// Fired whenever the active color/stroke-weight/font-size changes, so the
    /// host can persist the style as the next session's default.
    public var onStyleChanged: ((AnnotationStyle) -> Void)?

    // Chrome references kept for live updates.
    private var toolButtons: [EditorTool: IconToolButton] = [:]
    private let inspectorEffect = NSVisualEffectView()
    private let inspectorStack = NSStackView()
    /// Second inspector row — only the Text tool uses it (font controls).
    private let inspectorRow2 = NSStackView()
    private let dimsLabel = NSTextField(labelWithString: "")
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private var swatchButtons: [SwatchButton] = []
    private let customColorWell = NSColorWell()
    private var selectionDependentButtons: [NSButton] = []
    private var scrollView = NSScrollView()
    private let maxDisplayW: CGFloat = 1200

    // Inspector preset palette.
    private let presetColors: [NSColor] = [
        NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1), // red
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.04, alpha: 1), // orange
        NSColor(srgbRed: 1.00, green: 0.84, blue: 0.04, alpha: 1), // yellow
        NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1), // green
        NSColor(srgbRed: 0.04, green: 0.52, blue: 1.00, alpha: 1), // blue
        NSColor(srgbRed: 0.75, green: 0.35, blue: 0.95, alpha: 1), // purple
        NSColor.white,
        NSColor.black,
    ]

    // Tool → (SF Symbol, tooltip). Order also defines toolbar grouping below.
    private static let toolInfo: [EditorTool: (symbol: String, tip: String)] = [
        .select: ("cursorarrow", "Select"),
        .arrow: ("arrow.up.right", "Arrow"),
        .line: ("line.diagonal", "Line"),
        .rectangle: ("rectangle", "Rectangle"),
        .filledRectangle: ("rectangle.fill", "Filled Rectangle"),
        .ellipse: ("circle", "Ellipse"),
        .text: ("textformat", "Text — click to type, drag for a text box, double-click text to edit"),
        .counter: ("1.circle.fill", "Counter"),
        .blur: ("drop.fill", "Blur"),
        .pixelate: ("square.grid.3x3.fill", "Pixelate"),
        .crop: ("crop", "Crop"),
    ]
    private let toolGroups: [[EditorTool]] = [
        [.select],
        [.arrow, .line, .rectangle, .filledRectangle, .ellipse],
        [.text, .counter],
        [.blur, .pixelate],
        [.crop],
    ]

    private lazy var backdrop = NSColor(name: nil) { ap in
        ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.90, alpha: 1)
    }

    public init(image: CGImage, defaultStyle: AnnotationStyle = .default) {
        let doc = EditorDocument(baseImage: image)
        self.canvas = EditorCanvasView(document: doc)

        let displayW = min(CGFloat(image.width), 1200)
        let displayH = displayW * CGFloat(image.height) / CGFloat(image.width)
        canvas.frame = NSRect(x: 0, y: 0, width: displayW, height: displayH)

        let contentW = max(displayW, 600)
        let contentH = min(displayH, 620) + 150 /*reserved top chrome band*/ + 56 /*action bar*/
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Annotate"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 600, height: 440)
        super.init(window: window)

        self.style = defaultStyle
        canvas.style = defaultStyle
        window.backgroundColor = backdrop
        buildUI()
        // Delete / [ / ] are handled in the canvas's keyDown — make it the
        // first responder up front instead of requiring a click first.
        window.initialFirstResponder = canvas
        canvas.onStateChange = { [weak self] in self?.refreshChrome() }
        canvas.onEditText = { [weak self] textStyle in
            // Show the edited text's own style; not persisted until the user changes it.
            guard let self else { return }
            self.style = textStyle
            self.canvas.style = textStyle
            self.selectTool(.text)
        }
        selectTool(.arrow)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Build

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Scroll view + centred canvas over the neutral backdrop.
        let clip = CenteringClipView()
        clip.drawsBackground = true
        clip.backgroundColor = backdrop
        scrollView.contentView = clip
        scrollView.documentView = canvas
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backdrop
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        // Toolbar + inspector now live in a reserved band above the scroll view
        // (the scrollView top is pinned below the inspector), so the canvas can
        // never slide under the chrome. Only a small breathing inset is needed.
        scrollView.contentInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = buildToolbar()
        buildInspector()
        let actionBar = buildActionBar()
        buildTitlebarHistory()

        content.addSubview(scrollView)
        content.addSubview(actionBar)
        content.addSubview(toolbar)
        content.addSubview(inspectorEffect)

        NSLayoutConstraint.activate([
            // Canvas starts below the inspector pill — reserved chrome band, no overlap.
            scrollView.topAnchor.constraint(equalTo: inspectorEffect.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: actionBar.topAnchor),

            actionBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            actionBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            actionBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            actionBar.heightAnchor.constraint(equalToConstant: 56),

            toolbar.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),

            inspectorEffect.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            inspectorEffect.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            inspectorEffect.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, constant: -16),
        ])
    }

    private func darkPill(cornerRadius: CGFloat) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.appearance = NSAppearance(named: .vibrantDark)
        v.material = .hudWindow
        v.blendingMode = .withinWindow
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.masksToBounds = true
        v.layer?.borderWidth = 1
        v.layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor
        return v
    }

    private func buildToolbar() -> NSVisualEffectView {
        let pill = darkPill(cornerRadius: 15)
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 3
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false

        for (gi, group) in toolGroups.enumerated() {
            if gi > 0 { row.addArrangedSubview(makeSeparator()) }
            for tool in group {
                let info = Self.toolInfo[tool]!
                let b = IconToolButton(tool: tool, symbol: info.symbol, tip: info.tip,
                                       target: self, action: #selector(toolButtonClicked(_:)))
                toolButtons[tool] = b
                row.addArrangedSubview(b)
            }
        }

        pill.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: pill.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -6),
            row.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
        ])
        return pill
    }

    private func makeSeparator() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.13).cgColor
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 1),
            v.heightAnchor.constraint(equalToConstant: 22),
        ])
        return v
    }

    private func buildInspector() {
        let pill = inspectorEffect
        pill.appearance = NSAppearance(named: .vibrantDark)
        pill.material = .hudWindow
        pill.blendingMode = .withinWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.layer?.cornerRadius = 12
        pill.layer?.masksToBounds = true
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = NSColor(white: 1, alpha: 0.09).cgColor

        for row in [inspectorStack, inspectorRow2] {
            row.orientation = .horizontal
            row.spacing = 12
            row.alignment = .centerY
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 28).isActive = true
        }
        // Rows stack vertically; a hidden (empty) second row takes no space, so
        // single-row tools keep the original 44pt pill.
        let rows = NSStackView(views: [inspectorStack, inspectorRow2])
        rows.orientation = .vertical
        rows.alignment = .centerX
        rows.spacing = 8
        rows.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: pill.topAnchor, constant: 8),
            rows.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -8),
            rows.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 14),
            rows.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -14),
        ])
    }

    private func buildActionBar() -> NSView {
        let bar = NSVisualEffectView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.state = .active

        // Top hairline.
        let hairline = NSView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor.separatorColor.cgColor
        bar.addSubview(hairline)

        dimsLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        dimsLabel.textColor = .secondaryLabelColor
        dimsLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(dimsLabel)

        let doneBtn = NSButton(title: "Done", target: self, action: #selector(doneAction))
        doneBtn.isBordered = false
        doneBtn.attributedTitle = NSAttributedString(string: "Done",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor,
                         .font: NSFont.systemFont(ofSize: 13)])
        doneBtn.keyEquivalent = "w"; doneBtn.keyEquivalentModifierMask = [.command]

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveAction))
        saveBtn.bezelStyle = .rounded
        saveBtn.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
        saveBtn.imagePosition = .imageLeading
        saveBtn.keyEquivalent = "s"; saveBtn.keyEquivalentModifierMask = [.command]

        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyAction))
        copyBtn.bezelStyle = .rounded
        copyBtn.bezelColor = .controlAccentColor
        copyBtn.contentTintColor = .white
        copyBtn.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        copyBtn.imagePosition = .imageLeading
        copyBtn.attributedTitle = NSAttributedString(string: "Copy",
            attributes: [.foregroundColor: NSColor.white,
                         .font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        copyBtn.keyEquivalent = "c"; copyBtn.keyEquivalentModifierMask = [.command, .shift]

        let stackBtn = NSButton(title: "Stack", target: self, action: #selector(addToStackAction))
        stackBtn.bezelStyle = .rounded
        stackBtn.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: "Stack")
        stackBtn.imagePosition = .imageLeading
        stackBtn.toolTip = "Keep in the bottom-right stack"

        let actions = NSStackView(views: [doneBtn, stackBtn, saveBtn, copyBtn])
        actions.orientation = .horizontal
        actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(actions)

        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: bar.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            dimsLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 18),
            dimsLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            actions.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            actions.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
        return bar
    }

    private func buildTitlebarHistory() {
        configureHistoryButton(undoButton, symbol: "arrow.uturn.backward",
                               tip: "Undo", action: #selector(undoAction))
        configureHistoryButton(redoButton, symbol: "arrow.uturn.forward",
                               tip: "Redo", action: #selector(redoAction))
        let stack = NSStackView(views: [undoButton, redoButton])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 10)

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = stack
        window?.addTitlebarAccessoryViewController(accessory)
    }

    private func configureHistoryButton(_ b: NSButton, symbol: String, tip: String, action: Selector) {
        b.translatesAutoresizingMaskIntoConstraints = false
        b.isBordered = false
        b.bezelStyle = .shadowlessSquare
        b.imagePosition = .imageOnly
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.target = self
        b.action = action
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 26),
            b.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    // MARK: - Inspector (adaptive)

    private func rebuildInspector(for tool: EditorTool) {
        inspectorStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        inspectorRow2.arrangedSubviews.forEach { $0.removeFromSuperview() }
        defer { inspectorRow2.isHidden = inspectorRow2.arrangedSubviews.isEmpty }
        swatchButtons.removeAll()
        selectionDependentButtons.removeAll()

        switch tool {
        case .select:
            inspectorStack.addArrangedSubview(makeLabel("Object"))
            inspectorStack.addArrangedSubview(makeObjectActions())
        case .arrow, .line, .rectangle, .ellipse:
            inspectorStack.addArrangedSubview(makeLabel(Self.toolInfo[tool]!.tip))
            inspectorStack.addArrangedSubview(makeColorRow())
            inspectorStack.addArrangedSubview(makeDivider())
            inspectorStack.addArrangedSubview(makeWeightSegment())
        case .filledRectangle:
            inspectorStack.addArrangedSubview(makeLabel("Filled"))
            inspectorStack.addArrangedSubview(makeColorRow())
        case .text:
            inspectorStack.addArrangedSubview(makeLabel("Text"))
            inspectorStack.addArrangedSubview(makeColorRow())
            inspectorStack.addArrangedSubview(makeDivider())
            inspectorStack.addArrangedSubview(makeTextBackgroundToggle())
            inspectorRow2.addArrangedSubview(makeFontPopup())
            inspectorRow2.addArrangedSubview(makeFontSizePopup())
            inspectorRow2.addArrangedSubview(makeDivider())
            inspectorRow2.addArrangedSubview(makeBoldItalicSegment())
            inspectorRow2.addArrangedSubview(makeAlignmentSegment())
        case .counter:
            inspectorStack.addArrangedSubview(makeLabel("Counter"))
            inspectorStack.addArrangedSubview(makeColorRow())
        case .blur, .pixelate:
            inspectorStack.addArrangedSubview(makeLabel("Redact"))
            inspectorStack.addArrangedSubview(makeRedactSegment(current: tool))
        case .crop:
            inspectorStack.addArrangedSubview(makeLabel("Crop"))
            inspectorStack.addArrangedSubview(makeHint("Drag the area to keep"))
        }
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text.uppercased())
        l.font = .systemFont(ofSize: 10, weight: .semibold)
        l.textColor = NSColor(white: 1, alpha: 0.45)
        return l
    }

    private func makeHint(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 12)
        l.textColor = NSColor(white: 1, alpha: 0.62)
        return l
    }

    private func makeDivider() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: 0.13).cgColor
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 1),
            v.heightAnchor.constraint(equalToConstant: 20),
        ])
        return v
    }

    private func makeColorRow() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        for color in presetColors {
            let sw = SwatchButton(color: color, target: self, action: #selector(swatchClicked(_:)))
            sw.isSelectedSwatch = colorsMatch(color, style.strokeColor.nsColor)
            swatchButtons.append(sw)
            row.addArrangedSubview(sw)
        }
        customColorWell.target = self
        customColorWell.action = #selector(customColorChanged(_:))
        customColorWell.color = style.strokeColor.nsColor
        customColorWell.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            customColorWell.widthAnchor.constraint(equalToConstant: 28),
            customColorWell.heightAnchor.constraint(equalToConstant: 22),
        ])
        row.addArrangedSubview(customColorWell)
        return row
    }

    private func makeWeightSegment() -> NSSegmentedControl {
        let seg = NSSegmentedControl(labels: ["S", "M", "L"], trackingMode: .selectOne,
                                     target: self, action: #selector(weightChanged(_:)))
        seg.segmentStyle = .rounded
        let widths: [CGFloat] = [2, 4, 7]
        seg.selectedSegment = widths.firstIndex(of: style.lineWidth) ?? 1
        return seg
    }

    private static let fontSizes: [CGFloat] = [12, 14, 18, 24, 30, 36, 48, 64, 96]

    private func makeFontPopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.controlSize = .small
        pop.target = self
        pop.action = #selector(fontFamilyChanged(_:))
        let menu = pop.menu!
        for preset in TextFont.presets {
            let item = NSMenuItem(title: preset.label, action: nil, keyEquivalent: "")
            item.representedObject = preset.family
            item.attributedTitle = NSAttributedString(string: preset.label, attributes: [
                .font: TextFont.font(family: preset.family, size: 13, bold: false, italic: false)])
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for family in TextFont.installedFamilies {
            let item = NSMenuItem(title: family, action: nil, keyEquivalent: "")
            item.representedObject = family
            menu.addItem(item)
        }
        if let item = menu.items.first(where: { ($0.representedObject as? String) == style.fontFamily }) {
            pop.select(item)
        } else {
            // A persisted family that's no longer installed renders as System — say so.
            pop.selectItem(at: 0)
        }
        pop.toolTip = "Font"
        pop.widthAnchor.constraint(lessThanOrEqualToConstant: 150).isActive = true
        return pop
    }

    private func makeFontSizePopup() -> NSPopUpButton {
        let pop = NSPopUpButton(frame: .zero, pullsDown: false)
        pop.controlSize = .small
        pop.target = self
        pop.action = #selector(fontSizeChanged(_:))
        var sizes = Self.fontSizes
        if !sizes.contains(style.fontSize) { sizes.append(style.fontSize); sizes.sort() }
        for size in sizes {
            pop.addItem(withTitle: "\(Int(size)) pt")
            pop.lastItem?.representedObject = size
        }
        pop.selectItem(at: sizes.firstIndex(of: style.fontSize) ?? 0)
        pop.toolTip = "Font size"
        return pop
    }

    private func makeBoldItalicSegment() -> NSSegmentedControl {
        let seg = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "bold", accessibilityDescription: "Bold")!,
            NSImage(systemSymbolName: "italic", accessibilityDescription: "Italic")!,
        ], trackingMode: .selectAny, target: self, action: #selector(boldItalicChanged(_:)))
        seg.segmentStyle = .rounded
        seg.setSelected(style.fontBold, forSegment: 0)
        seg.setSelected(style.fontItalic, forSegment: 1)
        seg.setToolTip("Bold", forSegment: 0)
        seg.setToolTip("Italic", forSegment: 1)
        return seg
    }

    private func makeAlignmentSegment() -> NSSegmentedControl {
        let seg = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Align left")!,
            NSImage(systemSymbolName: "text.aligncenter", accessibilityDescription: "Align centre")!,
            NSImage(systemSymbolName: "text.alignright", accessibilityDescription: "Align right")!,
        ], trackingMode: .selectOne, target: self, action: #selector(alignmentChanged(_:)))
        seg.segmentStyle = .rounded
        seg.selectedSegment = TextAlign.allCases.firstIndex(of: style.textAlignment) ?? 0
        return seg
    }

    private func makeTextBackgroundToggle() -> NSButton {
        let b = NSButton(checkboxWithTitle: "Background", target: self, action: #selector(textBackgroundChanged(_:)))
        b.state = style.textBackground ? .on : .off
        b.attributedTitle = NSAttributedString(string: "Background",
            attributes: [.foregroundColor: NSColor(white: 1, alpha: 0.85),
                         .font: NSFont.systemFont(ofSize: 12)])
        return b
    }

    private func makeRedactSegment(current: EditorTool) -> NSSegmentedControl {
        let seg = NSSegmentedControl(labels: ["Blur", "Pixelate"], trackingMode: .selectOne,
                                     target: self, action: #selector(redactChanged(_:)))
        seg.segmentStyle = .rounded
        seg.selectedSegment = current == .pixelate ? 1 : 0
        return seg
    }

    private func makeObjectActions() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 6
        func button(_ title: String, _ symbol: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: " " + title, target: self, action: action)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            b.imagePosition = .imageLeading
            b.contentTintColor = NSColor(white: 1, alpha: 0.85)
            selectionDependentButtons.append(b)
            return b
        }
        row.addArrangedSubview(button("Front", "square.3.layers.3d.top.filled", #selector(bringFront)))
        row.addArrangedSubview(button("Back", "square.3.layers.3d.bottom.filled", #selector(sendBack)))
        row.addArrangedSubview(button("Delete", "trash", #selector(deleteObject)))
        return row
    }

    // MARK: - Tool selection

    private func selectTool(_ tool: EditorTool) {
        canvas.tool = tool
        for (t, b) in toolButtons { b.isSelectedTool = (t == tool) }
        rebuildInspector(for: tool)
        refreshChrome()
    }

    @objc private func toolButtonClicked(_ sender: IconToolButton) { selectTool(sender.tool) }

    // MARK: - Inspector actions

    @objc private func swatchClicked(_ sender: SwatchButton) {
        applyStrokeColor(sender.swatchColor)
        for sw in swatchButtons { sw.isSelectedSwatch = (sw === sender) }
        customColorWell.color = sender.swatchColor
    }

    @objc private func customColorChanged(_ sender: NSColorWell) {
        applyStrokeColor(sender.color)
        for sw in swatchButtons { sw.isSelectedSwatch = colorsMatch(sw.swatchColor, sender.color) }
    }

    private func applyStrokeColor(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        style.strokeColor = RGBAColor(c)
        style.fillColor = RGBAColor(c.withAlphaComponent(0.25))
        styleDidChange()
    }

    /// Pushes `style` to the canvas (new objects + the live text editor + selected
    /// text under the Text tool) and reports it for persistence as the sticky default.
    private func styleDidChange() {
        canvas.style = style
        canvas.applyStyleToSelectedText()
        onStyleChanged?(style)
    }

    @objc private func weightChanged(_ sender: NSSegmentedControl) {
        let widths: [CGFloat] = [2, 4, 7]
        style.lineWidth = widths[max(0, sender.selectedSegment)]
        styleDidChange()
    }

    @objc private func fontSizeChanged(_ sender: NSPopUpButton) {
        guard let size = sender.selectedItem?.representedObject as? CGFloat else { return }
        style.fontSize = size
        styleDidChange()
    }

    @objc private func fontFamilyChanged(_ sender: NSPopUpButton) {
        guard let family = sender.selectedItem?.representedObject as? String else { return }
        style.fontFamily = family
        styleDidChange()
    }

    @objc private func boldItalicChanged(_ sender: NSSegmentedControl) {
        style.fontBold = sender.isSelected(forSegment: 0)
        style.fontItalic = sender.isSelected(forSegment: 1)
        styleDidChange()
    }

    @objc private func alignmentChanged(_ sender: NSSegmentedControl) {
        style.textAlignment = TextAlign.allCases[max(0, sender.selectedSegment)]
        styleDidChange()
    }

    @objc private func textBackgroundChanged(_ sender: NSButton) {
        style.textBackground = (sender.state == .on)
        styleDidChange()
    }

    @objc private func redactChanged(_ sender: NSSegmentedControl) {
        selectTool(sender.selectedSegment == 1 ? .pixelate : .blur)
    }

    @objc private func bringFront() { canvas.bringSelectedToFront() }
    @objc private func sendBack() { canvas.sendSelectedToBack() }
    @objc private func deleteObject() { canvas.deleteSelected() }

    // MARK: - History + export

    @objc private func undoAction() { canvas.undo() }
    @objc private func redoAction() { canvas.redo() }

    @objc private func copyAction() {
        canvas.commitPendingText()
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onCopy?(img)
    }
    @objc private func saveAction() {
        canvas.commitPendingText()
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onSave?(img)
    }
    @objc private func addToStackAction() {
        canvas.commitPendingText()
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onAddToStack?(img)
        window?.close()
    }
    @objc private func doneAction() { window?.close() }

    // MARK: - Chrome refresh

    private func refreshChrome() {
        let size = canvas.currentDocument().size
        dimsLabel.stringValue = "\(Int(size.width)) × \(Int(size.height)) px"
        undoButton.isEnabled = canvas.canUndo
        redoButton.isEnabled = canvas.canRedo
        let hasSel = canvas.hasSelection
        selectionDependentButtons.forEach { $0.isEnabled = hasSel }
        fitCanvas()
    }

    /// Keep the canvas displayed at a consistent fit-to-width scale (re-applied
    /// after crop/undo changes the document's pixel size).
    private func fitCanvas() {
        let s = canvas.currentDocument().size
        guard s.width > 0 else { return }
        let w = min(s.width, maxDisplayW)
        let h = w * s.height / s.width
        if canvas.frame.size != NSSize(width: w, height: h) {
            canvas.frame = NSRect(x: 0, y: 0, width: w, height: h)
        }
    }

    // MARK: - Helpers

    private func colorsMatch(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return false }
        let t: CGFloat = 0.02
        return abs(x.redComponent - y.redComponent) < t
            && abs(x.greenComponent - y.greenComponent) < t
            && abs(x.blueComponent - y.blueComponent) < t
            && abs(x.alphaComponent - y.alphaComponent) < t
    }
}
