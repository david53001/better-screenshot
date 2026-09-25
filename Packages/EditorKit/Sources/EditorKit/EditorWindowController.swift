import AppKit

/// The annotation editor window: a floating frosted-glass tool pill over a centred canvas,
/// a collapsible side panel (`EditorInspectorView`) on the right, a hint line + action bar at
/// the bottom, and undo/redo + the panel toggle in the title bar.
public final class EditorWindowController: NSWindowController {
    private let canvas: EditorCanvasView
    /// The default style for new objects — the sticky default the host persists.
    private var style = AnnotationStyle.default
    public var onCopy: ((CGImage) -> Void)?
    public var onSave: ((CGImage) -> Void)?
    public var onAddToStack: ((CGImage) -> Void)?
    /// Fired whenever the default style changes (any inspector edit), so the host can
    /// persist it as the next session's default.
    public var onStyleChanged: ((AnnotationStyle) -> Void)?
    /// Fired when the Recent colours change (newest first, at most 6), for the host to persist.
    public var onRecentColorsChanged: (([RGBAColor]) -> Void)?

    private var toolButtons: [EditorTool: IconToolButton] = [:]
    private let inspector: EditorInspectorView
    private let scrollView = EditorScrollView()
    private let zoom: CanvasZoomController
    private let dimsLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private let undoButton = NSButton()
    private let redoButton = NSButton()
    private let inspectorButton = NSButton()
    private var canvasBesidePanel: NSLayoutConstraint!
    private var canvasToEdge: NSLayoutConstraint!

    /// Minimum window width with the panel shown (600 canvas column + 8 gap + 264 panel +
    /// 12 margin) and hidden.
    private static let minWidthWithPanel: CGFloat = 884
    private static let minWidthBare: CGFloat = 600
    private static let bottomBarHeight: CGFloat = 84

    private let toolGroups: [[EditorTool]] = [
        [.select],
        [.arrow, .line, .rectangle, .filledRectangle, .ellipse],
        [.text, .counter, .highlighter],
        [.blur, .pixelate, .spotlight],
        [.crop],
    ]

    /// The neutral backdrop around the canvas. The window is always dark (see `init`).
    private let backdrop = NSColor(white: 0.12, alpha: 1)

    /// `recentColors`: the persisted Recent colours (newest first); changes come back
    /// through `onRecentColorsChanged`.
    public init(image: CGImage, defaultStyle: AnnotationStyle = .default, recentColors: [RGBAColor] = []) {
        canvas = EditorCanvasView(document: EditorDocument(baseImage: image))
        inspector = EditorInspectorView(recentColors: recentColors)
        zoom = CanvasZoomController(canvas: canvas, scrollView: scrollView)

        // Room for the image at its real on-screen size (points, not pixels — 100%), up to
        // 1200pt wide, plus the panel, within the screen; Fit then scales the image into
        // whatever room the window has, never past 100%.
        let mainScreen = NSScreen.main ?? NSScreen.screens.first
        let real = ZoomMath.pointSize(pixels: CGSize(width: image.width, height: image.height),
                                      backingScale: mainScreen?.backingScaleFactor ?? 2)
        let displayW = min(real.width, 1200)
        let displayH = displayW * real.height / max(real.width, 1)
        let screen = mainScreen?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let contentW = min(max(displayW + 48, Self.minWidthBare) + EditorInspectorView.width + 20,
                           screen.width - 40)
        let contentH = min(max(displayH + 112 /*top band + insets*/ + Self.bottomBarHeight, 520),
                           screen.height - 60)
        let window = EditorWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentW, height: contentH),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Annotate"
        window.titlebarAppearsTransparent = true
        // Always dark, like the video editor: the dark HUD panels are vibrant and blend with
        // the window behind them, so in Light mode they washed out to mid-grey.
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: Self.minWidthWithPanel, height: 440)
        super.init(window: window)

        style = defaultStyle
        canvas.style = defaultStyle
        window.backgroundColor = backdrop
        buildUI()
        // Delete / [ / ] are handled in the canvas's keyDown — make it the
        // first responder up front instead of requiring a click first.
        window.initialFirstResponder = canvas
        window.keyEquivalentHandler = { [weak self] in self?.handleKeyEquivalent($0) ?? false }
        window.escapeHandler = { [weak self] in self?.escape() }
        canvas.onStateChange = { [weak self] in self?.refreshChrome() }
        canvas.onEditText = { [weak self] textStyle in
            // Show the edited text's own style; not persisted until the user changes it.
            guard let self else { return }
            self.style = textStyle.keepingToolDefaults(of: self.style)
            self.canvas.style = textStyle
            self.selectTool(.text)
        }
        wireInspector()
        window.contentView?.layoutSubtreeIfNeeded()
        zoom.fit()
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
        scrollView.contentInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = buildToolbar()
        let bottomBar = buildBottomBar()
        buildTitlebarButtons()

        content.addSubview(scrollView)
        content.addSubview(bottomBar)
        content.addSubview(toolbar)
        content.addSubview(inspector)

        canvasBesidePanel = scrollView.trailingAnchor.constraint(equalTo: inspector.leadingAnchor, constant: -8)
        canvasToEdge = scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor)
        NSLayoutConstraint.activate([
            // The tool pill sits in a reserved band above the canvas column, never over the image.
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            toolbar.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
            canvasBesidePanel,

            inspector.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            inspector.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            inspector.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -12),

            bottomBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: Self.bottomBarHeight),
        ])
    }

    private func buildToolbar() -> NSVisualEffectView {
        let pill = NSVisualEffectView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.appearance = NSAppearance(named: .vibrantDark)
        pill.material = .hudWindow
        pill.blendingMode = .withinWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 15
        pill.layer?.masksToBounds = true
        pill.layer?.borderWidth = 1
        pill.layer?.borderColor = NSColor(white: 1, alpha: 0.10).cgColor

        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 3
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        for (gi, group) in toolGroups.enumerated() {
            if gi > 0 { row.addArrangedSubview(makeSeparator(height: 22, alpha: 0.13)) }
            for tool in group {
                let b = IconToolButton(tool: tool, symbol: tool.symbolName, tip: tool.tooltip,
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

    private func makeSeparator(height: CGFloat, alpha: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor(white: 1, alpha: alpha).cgColor
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 1),
            v.heightAnchor.constraint(equalToConstant: height),
        ])
        return v
    }

    /// Hint line (what the active tool / selection does) above the dims · zoom · actions row.
    private func buildBottomBar() -> NSView {
        let bar = NSVisualEffectView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.material = .headerView
        bar.blendingMode = .withinWindow
        bar.state = .active

        let hairline = NSView()
        hairline.translatesAutoresizingMaskIntoConstraints = false
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor.separatorColor.cgColor
        bar.addSubview(hairline)

        let hintIcon = NSImageView(image: NSImage(systemSymbolName: "info.circle",
                                                  accessibilityDescription: "Hint")!)
        hintIcon.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        hintIcon.contentTintColor = .tertiaryLabelColor
        hintLabel.font = .systemFont(ofSize: 12)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.lineBreakMode = .byTruncatingTail
        hintLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let hintRow = NSStackView(views: [hintIcon, hintLabel])
        hintRow.orientation = .horizontal
        hintRow.spacing = 6
        hintRow.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(hintRow)

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

        // Zoom sits just left of the actions so Copy stays the rightmost, primary button.
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let actions = NSStackView(views: [zoom.popup, divider, doneBtn, stackBtn, saveBtn, copyBtn])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        actions.setCustomSpacing(12, after: zoom.popup)
        actions.setCustomSpacing(10, after: divider)
        actions.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(actions)

        NSLayoutConstraint.activate([
            hairline.topAnchor.constraint(equalTo: bar.topAnchor),
            hairline.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            hintRow.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
            hintRow.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16),
            hintRow.trailingAnchor.constraint(lessThanOrEqualTo: bar.trailingAnchor, constant: -16),

            dimsLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 18),
            dimsLabel.centerYAnchor.constraint(equalTo: actions.centerYAnchor),

            actions.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16),
            actions.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -12),
        ])
        return bar
    }

    private func buildTitlebarButtons() {
        configureTitlebarButton(undoButton, symbol: "arrow.uturn.backward",
                                tip: "Undo (⌘Z)", action: #selector(undoAction))
        configureTitlebarButton(redoButton, symbol: "arrow.uturn.forward",
                                tip: "Redo (⇧⌘Z)", action: #selector(redoAction))
        configureTitlebarButton(inspectorButton, symbol: "sidebar.right",
                                tip: "Hide Inspector (⌥⌘I)", action: #selector(toggleInspector))
        inspectorButton.setButtonType(.pushOnPushOff)
        inspectorButton.state = .on
        let stack = NSStackView(views: [undoButton, redoButton, inspectorButton])
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.setCustomSpacing(10, after: redoButton)
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 10)
        // A trailing accessory takes its width from the view's frame, which is zero until set —
        // without this the buttons sit past the window's right edge, clipped away.
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .trailing
        accessory.view = stack
        window?.addTitlebarAccessoryViewController(accessory)
    }

    private func configureTitlebarButton(_ b: NSButton, symbol: String, tip: String, action: Selector) {
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

    // MARK: - Side panel

    private func wireInspector() {
        inspector.onStyleEdit = { [weak self] edit, group in self?.applyStyleEdit(edit, group: group) }
        inspector.onStyleEditEnded = { [weak self] in self?.canvas.endStyleEditGroup() }
        inspector.onRecentColorsChanged = { [weak self] in self?.onRecentColorsChanged?($0) }
        inspector.onRedactTool = { [weak self] tool in
            // Under a redaction tool the switch changes the tool (keeping the just-drawn, just-
            // converted object selected); under Select it only converted the selection.
            guard let self, self.canvas.tool.redactionMode != nil else { return }
            self.selectTool(tool, keepSelection: true)
        }
        inspector.onArrange = { [weak self] action in
            guard let canvas = self?.canvas else { return }
            switch action {
            case .front: canvas.bringSelectedToFront()
            case .back: canvas.sendSelectedToBack()
            case .delete: canvas.deleteSelected()
            }
        }
    }

    /// An inspector edit changes the default style (new objects, the live text editor, the
    /// persisted sticky default) and every selected object (one undo step).
    private func applyStyleEdit(_ edit: StyleEdit, group: AnyHashable?) {
        if editsHighlighterPen {
            var pen = style.withHighlighterPen
            edit(&pen)
            style.rememberHighlighterPen(from: pen)
        } else {
            edit(&style)
        }
        canvas.style = defaultStyle(for: canvas.tool)
        canvas.applyStyleEdit(edit, group: group)
        onStyleChanged?(style)
        refreshChrome()
    }

    /// The highlighter keeps its own sticky colour / width / opacity (`HighlighterPen`): panel
    /// edits go to it while the Highlighter is active or only highlighter strokes are selected.
    private var editsHighlighterPen: Bool {
        let selection = canvas.selectedTools
        return canvas.tool == .highlighter
            || (canvas.tool == .select && !selection.isEmpty && selection.allSatisfy { $0 == .highlighter })
    }

    /// The style new objects of `tool` get (and the panel shows while nothing is selected).
    private func defaultStyle(for tool: EditorTool) -> AnnotationStyle {
        tool == .highlighter ? style.withHighlighterPen : style
    }

    @objc private func toggleInspector() { setInspectorShown(inspector.isHidden) }

    private func setInspectorShown(_ shown: Bool) {
        guard let window else { return }
        inspector.isHidden = !shown
        // Deactivate before activating so the two trailing constraints never coexist.
        (shown ? canvasToEdge : canvasBesidePanel).isActive = false
        (shown ? canvasBesidePanel : canvasToEdge).isActive = true
        window.minSize.width = shown ? Self.minWidthWithPanel : Self.minWidthBare
        if shown, window.frame.width < Self.minWidthWithPanel {
            var f = window.frame
            f.size.width = Self.minWidthWithPanel
            window.setFrame(f, display: true)
        }
        inspectorButton.state = shown ? .on : .off
        inspectorButton.toolTip = shown ? "Hide Inspector (⌥⌘I)" : "Show Inspector (⌥⌘I)"
        window.contentView?.layoutSubtreeIfNeeded()
        zoom.refresh()
    }

    // MARK: - Tools + keyboard

    private func selectTool(_ tool: EditorTool, keepSelection: Bool = false) {
        if tool != canvas.tool { canvas.commitPendingText() }
        // A drawing tool starts fresh; Select keeps the selection (e.g. the object just drawn).
        if tool != .select, !keepSelection { canvas.clearSelection() }
        canvas.tool = tool
        canvas.style = defaultStyle(for: tool)
        for (t, b) in toolButtons { b.isSelectedTool = (t == tool) }
        refreshChrome()
    }

    @objc private func toolButtonClicked(_ sender: IconToolButton) { selectTool(sender.tool) }

    /// Single-key tool shortcuts (V A L R F O T N H B P X S C). Keys reach the window controller
    /// through the responder chain only when nothing else used them — the inline text
    /// editor consumes typing, so shortcuts are off while text is being edited.
    public override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard mods.isEmpty, !canvas.isEditingText,
              let chars = event.charactersIgnoringModifiers,
              let tool = EditorTool.forShortcut(chars) else { return super.keyDown(with: event) }
        selectTool(tool)
    }

    /// Esc (via `EditorWindow.cancelOperation`): back to Select; pressed again under Select,
    /// it clears the selection.
    private func escape() {
        if canvas.tool == .select { canvas.clearSelection() } else { selectTool(.select) }
    }

    /// ⌘+ / ⌘= zoom in · ⌘− zoom out · ⌘0 fit · ⌘1 100% · ⌥⌘I side panel.
    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if mods == [.command, .option], key == "i" { toggleInspector(); return true }
        guard mods.subtracting(.shift) == .command else { return false }
        switch key {
        case "=", "+": zoom.zoom(in: true)
        case "-": zoom.zoom(in: false)
        case "0": zoom.fit()
        case "1": zoom.actualSize()
        default: return false
        }
        return true
    }

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
        let selection = canvas.selectedTools
        inspector.update(content: InspectorModel.content(tool: canvas.tool, selection: selection),
                         tool: canvas.tool, style: canvas.selectionStyle ?? defaultStyle(for: canvas.tool))
        hintLabel.stringValue = InspectorModel.hint(tool: canvas.tool, selection: selection,
                                                    editingText: canvas.isEditingText)
        zoom.refresh()   // crop / undo may have changed the image size
    }
}

/// Routes the zoom and panel key equivalents to the controller — the app is a menu-bar
/// agent with no main menu to carry them — and Esc, which NSWindow turns into its own
/// `cancelOperation(_:)` instead of passing it on to the window controller.
private final class EditorWindow: NSWindow {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?
    var escapeHandler: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if let escapeHandler { escapeHandler() } else { super.cancelOperation(sender) }
    }
}
