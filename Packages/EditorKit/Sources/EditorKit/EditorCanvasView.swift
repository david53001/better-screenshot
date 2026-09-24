import AppKit

public final class EditorCanvasView: NSView {
    public private(set) var document: EditorDocument
    public var tool: EditorTool = .select
    public var style = AnnotationStyle.default { didSet { restyleActiveField(); needsDisplay = true } }
    /// Fired when an existing text annotation opens for editing, with its style, so
    /// the window can switch to the Text tool and show that style in the inspector.
    public var onEditText: ((AnnotationStyle) -> Void)?

    // MARK: - Selection (supports multiple objects)
    private var selectedIDs: Set<UUID> = [] {
        didSet { if selectedIDs != oldValue { openStyleGroup = nil } }
    }
    /// The single selected annotation, or nil when zero or several are selected
    /// (resize handles only make sense for exactly one).
    private var soleSelectedID: UUID? { selectedIDs.count == 1 ? selectedIDs.first : nil }
    private var dragStartImagePoint: CGPoint?
    private var inProgress: (any Annotation)?
    /// Live drag rectangle (image coords) for region tools (blur/pixelate/crop),
    /// which have no committable preview shape — shown as a dashed marquee.
    private var regionMarquee: CGRect?
    /// Live rubber-band rectangle (image coords) for the select tool's marquee.
    private var marqueeRect: CGRect?

    // MARK: - Task 14: Resize handles
    // Handle index: 0=TL 1=TC 2=TR 3=ML 4=MR 5=BL 6=BC 7=BR
    private var activeHandleIndex: Int? = nil
    private var handleOriginalFrame: CGRect = .zero
    private let handleSize: CGFloat = 8

    // MARK: - Undo / redo history (document snapshots)
    // EditorDocument is a value type, so a snapshot is just a copy of the struct.
    private var undoStack: [EditorDocument] = []
    private var redoStack: [EditorDocument] = []
    /// Pre-drag snapshot, pushed on mouseUp only if the drag actually mutated.
    private var pendingDragSnapshot: EditorDocument?
    private var didDragMutate = false

    /// Fired after any change affecting the dimensions readout, selection, or
    /// undo/redo availability, so the window chrome can refresh itself.
    public var onStateChange: (() -> Void)?

    public var hasSelection: Bool { !selectedIDs.isEmpty }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// True while the inline text editor is open (tool shortcuts must not fire then).
    public var isEditingText: Bool { activeField != nil }

    /// The selected objects in document (stacking) order.
    private var selectedAnnotations: [any Annotation] {
        document.annotations.filter { selectedIDs.contains($0.id) }
    }
    /// The selection described by the tool that draws each object (for the inspector).
    public var selectedTools: [EditorTool] { selectedAnnotations.compactMap(EditorTool.maker(of:)) }
    /// The style the inspector shows for the selection (the backmost selected object's).
    public var selectionStyle: AnnotationStyle? { selectedAnnotations.first?.style }

    /// Style edits that share this group (one slider drag, one colour-panel session)
    /// merge into a single undo step. Any other change or a new selection ends the group.
    private var openStyleGroup: AnyHashable?

    private func snapshot() {
        undoStack.append(document)
        if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack.removeAll()
        openStyleGroup = nil
    }

    public init(document: EditorDocument) {
        self.document = document
        super.init(frame: NSRect(origin: .zero, size: document.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    /// Zoom resizes the canvas; keep the live text editor on its text at the new scale.
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let field = activeField else { return }
        let p = NSPoint(x: textImageOrigin.x / scale, y: textImageOrigin.y / scale)
        field.setFrameOrigin(p)
        activeRoom = max(bounds.maxX - p.x, 40)
        restyleActiveField()
    }

    // MARK: - Coordinate mapping (view ↔ image)
    private var scale: CGFloat { document.size.width / max(bounds.width, 1) }
    private func imagePoint(_ viewPoint: NSPoint) -> CGPoint {
        CGPoint(x: viewPoint.x * scale, y: viewPoint.y * scale)
    }

    // MARK: - Base image cache
    /// NSImage wrapper for the base, rebuilt only when the base actually
    /// changes (crop/undo/redo swap in a different CGImage).
    private var cachedBase: (cg: CGImage, ns: NSImage)?
    private var baseNSImage: NSImage {
        if let c = cachedBase, c.cg === document.baseImage { return c.ns }
        let ns = NSImage(cgImage: document.baseImage, size: document.size)
        cachedBase = (document.baseImage, ns)
        return ns
    }

    // MARK: - Resize handle geometry (view coords)
    private func handleRects(for viewRect: NSRect) -> [NSRect] {
        let s = handleSize
        let hs = s / 2
        let minX = viewRect.minX, midX = viewRect.midX, maxX = viewRect.maxX
        let minY = viewRect.minY, midY = viewRect.midY, maxY = viewRect.maxY
        return [
            NSRect(x: minX - hs, y: minY - hs, width: s, height: s), // 0 TL
            NSRect(x: midX - hs, y: minY - hs, width: s, height: s), // 1 TC
            NSRect(x: maxX - hs, y: minY - hs, width: s, height: s), // 2 TR
            NSRect(x: minX - hs, y: midY - hs, width: s, height: s), // 3 ML
            NSRect(x: maxX - hs, y: midY - hs, width: s, height: s), // 4 MR
            NSRect(x: minX - hs, y: maxY - hs, width: s, height: s), // 5 BL
            NSRect(x: midX - hs, y: maxY - hs, width: s, height: s), // 6 BC
            NSRect(x: maxX - hs, y: maxY - hs, width: s, height: s), // 7 BR
        ]
    }

    /// Handle indices the sole selection offers: text only resizes its box width (ML/MR).
    private var activeHandleIndices: [Int] {
        guard let id = soleSelectedID, let i = document.index(of: id) else { return [] }
        return document.annotations[i] is TextAnnotation ? [3, 4] : Array(0..<8)
    }

    /// Returns the index (0-7) of the handle hit at viewPoint, or nil.
    private func hitHandle(at viewPoint: NSPoint, viewRect: NSRect) -> Int? {
        let rects = handleRects(for: viewRect)
        for i in activeHandleIndices where rects[i].insetBy(dx: -2, dy: -2).contains(viewPoint) {
            return i
        }
        return nil
    }

    /// Compute a resized frame by dragging handle `idx` from `original` by `delta` (image coords).
    private func resizedFrame(original: CGRect, handleIdx: Int, delta: CGVector) -> CGRect {
        var minX = original.minX, minY = original.minY
        var maxX = original.maxX, maxY = original.maxY
        // TL=0, TC=1, TR=2, ML=3, MR=4, BL=5, BC=6, BR=7
        let movesLeft  = [0, 3, 5].contains(handleIdx)
        let movesRight = [2, 4, 7].contains(handleIdx)
        let movesTop   = [0, 1, 2].contains(handleIdx)
        let movesBot   = [5, 6, 7].contains(handleIdx)
        if movesLeft  { minX += delta.dx }
        if movesRight { maxX += delta.dx }
        if movesTop   { minY += delta.dy }
        if movesBot   { maxY += delta.dy }
        // Keep at least 4px
        if maxX - minX < 4 { if movesLeft { minX = maxX - 4 } else { maxX = minX + 4 } }
        if maxY - minY < 4 { if movesTop  { minY = maxY - 4 } else { maxY = minY + 4 } }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// True when the selected annotation is a rect-based type that exposes a mutable frame.
    private func selectedViewRect() -> NSRect? {
        guard let id = soleSelectedID, let i = document.index(of: id) else { return nil }
        let a = document.annotations[i]
        guard a is RectangleAnnotation || a is FilledRectangleAnnotation
           || a is EllipseAnnotation   || a is RedactionAnnotation
           || a is TextAnnotation else { return nil }
        let bb = a.boundingBox()
        return NSRect(x: bb.minX / scale, y: bb.minY / scale,
                      width: bb.width / scale, height: bb.height / scale)
    }

    /// Combined (union) bounding box of all currently selected annotations, in image coords.
    private func selectionBoundingBox() -> CGRect? {
        var result: CGRect?
        for id in selectedIDs {
            guard let i = document.index(of: id) else { continue }
            let bb = document.annotations[i].boundingBox()
            result = result?.union(bb) ?? bb
        }
        return result
    }

    /// Replace the frame on a rect-based annotation by building a copy with the new frame.
    private func replaceFrame(_ newImageFrame: CGRect) {
        guard let id = soleSelectedID, let i = document.index(of: id) else { return }
        let a = document.annotations[i]
        let updated: (any Annotation)?
        switch a {
        case let r as RectangleAnnotation:
            var c = r; c.frame = newImageFrame; updated = c
        case let f as FilledRectangleAnnotation:
            var c = f; c.frame = newImageFrame; updated = c
        case let e as EllipseAnnotation:
            var c = e; c.frame = newImageFrame; updated = c
        case let r as RedactionAnnotation:
            var c = r; c.frame = newImageFrame; updated = c   // its patch re-renders for the new frame
        case let t as TextAnnotation:
            // Side handles set the box width (text reflows); height follows the text.
            var c = t
            c.wrapWidth = max(newImageFrame.width, t.style.fontSize)
            c.origin.x = newImageFrame.width >= t.style.fontSize
                ? newImageFrame.minX : newImageFrame.maxX - t.style.fontSize
            updated = c
        default:
            updated = nil
        }
        if let u = updated { document.replace(id: id, with: u) }
    }

    // MARK: - Rendering
    public override func draw(_ dirtyRect: NSRect) {
        // Draw base + annotations directly at view scale instead of flattening
        // the full-resolution document into a new CGImage on every redraw
        // (which allocated a base-image-sized context per drag tick).
        // DocumentRenderer still does the full-res flatten for export.
        // Zoomed in far (≥ 3 screen pixels per image pixel): show crisp pixels, not a smear.
        let context = NSGraphicsContext.current
        let interpolation = context?.imageInterpolation ?? .default
        if (window?.backingScaleFactor ?? 2) / scale >= 3 { context?.imageInterpolation = .none }
        baseNSImage.draw(in: bounds)
        context?.imageInterpolation = interpolation
        // Annotations (and the live in-progress preview) draw themselves in
        // image-pixel coordinates; scale the context so image px → view points.
        // The view is flipped, matching the renderer's top-left convention.
        NSGraphicsContext.saveGraphicsState()
        let toView = NSAffineTransform()
        toView.scale(by: 1 / scale)
        toView.concat()
        for a in document.annotations where a.id != editingID { a.drawComposited() }
        inProgress?.drawComposited()
        NSGraphicsContext.restoreGraphicsState()

        // Live marquee for region tools (blur/pixelate/crop) that have no shape preview.
        if let m = regionMarquee {
            let vr = NSRect(x: m.minX / scale, y: m.minY / scale,
                            width: m.width / scale, height: m.height / scale)
            NSColor.systemBlue.setStroke()
            let p = NSBezierPath(rect: vr)
            p.lineWidth = 1; p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()
        }

        // Live rubber-band marquee for the select tool.
        if let m = marqueeRect {
            let vr = NSRect(x: m.minX / scale, y: m.minY / scale,
                            width: m.width / scale, height: m.height / scale)
            NSColor.systemBlue.withAlphaComponent(0.12).setFill()
            NSBezierPath(rect: vr).fill()
            NSColor.systemBlue.setStroke()
            let p = NSBezierPath(rect: vr)
            p.lineWidth = 1; p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()
        }

        // Selection outline(s) — one dashed box per selected annotation.
        for id in selectedIDs {
            guard let i = document.index(of: id) else { continue }
            let bb = document.annotations[i].boundingBox()
            let viewRect = NSRect(x: bb.minX / scale, y: bb.minY / scale,
                                  width: bb.width / scale, height: bb.height / scale)
            NSColor.systemBlue.setStroke()
            let p = NSBezierPath(rect: viewRect.insetBy(dx: -2, dy: -2))
            p.lineWidth = 1; p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()
        }

        // Resize handles only for a single rect-based selection.
        if let vr = selectedViewRect() {
            NSColor.white.setFill()
            NSColor.systemBlue.setStroke()
            let rects = handleRects(for: vr)
            for r in activeHandleIndices.map({ rects[$0] }) {
                let path = NSBezierPath(rect: r)
                path.fill(); path.lineWidth = 1; path.stroke()
            }
        }
    }

    // MARK: - Mouse
    public override func mouseDown(with event: NSEvent) {
        let viewPt = convert(event.locationInWindow, from: nil)
        let p = imagePoint(viewPt)
        dragStartImagePoint = p
        activeHandleIndex = nil
        regionMarquee = nil
        marqueeRect = nil

        textPressPending = false
        switch tool {
        case .select:
            if event.clickCount == 2, let hit = document.topmostHit(at: p),
               document.annotations[document.index(of: hit)!] is TextAnnotation {
                dragStartImagePoint = nil
                editExistingText(id: hit)
                return
            }
            // Resize handle (single selection) first, then an object hit, then
            // an empty-space drag starts a rubber-band marquee.
            if let vr = selectedViewRect(), let hi = hitHandle(at: viewPt, viewRect: vr) {
                activeHandleIndex = hi
                handleOriginalFrame = document.annotations[document.index(of: soleSelectedID!)!].boundingBox()
                pendingDragSnapshot = document; didDragMutate = false
            } else if let hit = document.topmostHit(at: p) {
                // Clicking an object outside the current selection selects just
                // it; clicking one already selected keeps the group (drag = move).
                if !selectedIDs.contains(hit) { selectedIDs = [hit] }
                pendingDragSnapshot = document; didDragMutate = false
            } else {
                selectedIDs = []
                marqueeRect = CGRect(origin: p, size: .zero)
            }
            onStateChange?(); needsDisplay = true
        case .text:
            // Resize handles of a selected text box still work under the Text tool.
            if let vr = selectedViewRect(), let hi = hitHandle(at: viewPt, viewRect: vr) {
                activeHandleIndex = hi
                handleOriginalFrame = document.annotations[document.index(of: soleSelectedID!)!].boundingBox()
                pendingDragSnapshot = document; didDragMutate = false
            } else if let hit = document.topmostHit(at: p),
                      document.annotations[document.index(of: hit)!] is TextAnnotation {
                dragStartImagePoint = nil
                editExistingText(id: hit)
            } else if event.timestamp == focusCommitTimestamp {
                // This click only ended the previous text's editing — don't start another.
                dragStartImagePoint = nil
            } else {
                textPressPending = true   // click = free label, drag = text box (mouseUp)
            }
        case .counter:
            // Selected like any just-drawn object, so the panel restyles it straight away.
            insert(CounterAnnotation.centered(on: p, number: document.nextCounterNumber(), style: style))
        default:
            inProgress = nil // shape creation happens on drag
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartImagePoint else { return }
        let p = EditorBoundsClamp.point(imagePoint(convert(event.locationInWindow, from: nil)), into: document.size)
        switch tool {
        case .select:
            if let hi = activeHandleIndex {
                // Resize via handle.
                let delta = CGVector(dx: p.x - start.x, dy: p.y - start.y)
                let newFrame = resizedFrame(original: handleOriginalFrame, handleIdx: hi, delta: delta)
                replaceFrame(newFrame); didDragMutate = true
            } else if marqueeRect != nil {
                marqueeRect = rect(start, p)
            } else if !selectedIDs.isEmpty {
                // Move the whole selection together, clamped so the group's
                // combined bounding box stays on-canvas (relative positions
                // within the selection are preserved).
                let delta = CGVector(dx: p.x - start.x, dy: p.y - start.y)
                if let box = selectionBoundingBox() {
                    let proposed = box.offsetBy(dx: delta.dx, dy: delta.dy)
                    let clamped = EditorBoundsClamp.box(proposed, into: document.size)
                    let effectiveDelta = CGVector(dx: clamped.minX - box.minX, dy: clamped.minY - box.minY)
                    for id in selectedIDs { document.move(id: id, by: effectiveDelta) }
                }
                dragStartImagePoint = p; didDragMutate = true
            }
        case .arrow:
            inProgress = ArrowAnnotation(start: start, end: p, style: style)
        case .line:
            inProgress = LineAnnotation(start: start, end: p, style: style)
        case .rectangle:
            inProgress = RectangleAnnotation(frame: rect(start, p), filled: false, style: style)
        case .filledRectangle:
            inProgress = FilledRectangleAnnotation(frame: rect(start, p), style: style)
        case .ellipse:
            inProgress = EllipseAnnotation(frame: rect(start, p), style: style)
        case .blur, .pixelate, .blackout, .crop:
            regionMarquee = rect(start, p)
        case .text:
            if let hi = activeHandleIndex {
                let delta = CGVector(dx: p.x - start.x, dy: p.y - start.y)
                replaceFrame(resizedFrame(original: handleOriginalFrame, handleIdx: hi, delta: delta))
                didDragMutate = true
            } else if textPressPending {
                regionMarquee = rect(start, p)
            }
        default: break
        }
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        let p = imagePoint(convert(event.locationInWindow, from: nil))
        let start = dragStartImagePoint ?? p
        let r = rect(start, p)
        if activeHandleIndex != nil {
            // Resize complete — update the stored original frame for next drag.
            if let id = soleSelectedID, let i = document.index(of: id) {
                handleOriginalFrame = document.annotations[i].boundingBox()
            }
            activeHandleIndex = nil
        } else {
            switch tool {
            case .select:
                // Resolve a marquee drag into the set of enclosed objects.
                if let m = marqueeRect {
                    selectedIDs = Set(document.ids(intersecting: m))
                    marqueeRect = nil
                }
            case .blur, .pixelate, .blackout:
                let box = r.intersection(CGRect(origin: .zero, size: document.size))
                if box.width >= 2, box.height >= 2, let mode = tool.redactionMode {
                    var s = style; s.redactionMode = mode
                    insert(RedactionAnnotation(frame: box, source: document.baseImage, style: s))
                }
            case .crop:
                if r.width >= 4, r.height >= 4 { applyCrop(to: r) }
            case .text:
                guard textPressPending else { break }
                textPressPending = false
                let box = rect(start, EditorBoundsClamp.point(p, into: document.size))
                // A real drag (≥ 12 view points wide) makes a fixed-width text box.
                if box.width / scale >= 12 {
                    beginTextEditing(atImagePoint: box.origin, fixedWidth: box.width)
                } else {
                    beginTextEditing(atImagePoint: start)
                }
            default:
                if let a = inProgress { inProgress = nil; insert(a) }  // insert() snapshots
            }
        }
        // Commit a single undo step for a completed move/resize drag.
        if didDragMutate, let snap = pendingDragSnapshot {
            undoStack.append(snap)
            if undoStack.count > 50 { undoStack.removeFirst() }
            redoStack.removeAll()
            openStyleGroup = nil
        }
        pendingDragSnapshot = nil; didDragMutate = false
        dragStartImagePoint = nil; regionMarquee = nil; marqueeRect = nil
        onStateChange?(); needsDisplay = true
    }

    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Keyboard (undo/redo, delete, z-order)
    public override var acceptsFirstResponder: Bool { true }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleUndoRedo(event) { return true }
        return super.performKeyEquivalent(with: event)
    }

    public override func keyDown(with event: NSEvent) {
        if handleUndoRedo(event) { return }
        guard !selectedIDs.isEmpty else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 51, 117: deleteSelected()                                  // Delete / Fwd-Delete
        default:
            if event.charactersIgnoringModifiers == "]" { bringSelectedToFront() }
            else if event.charactersIgnoringModifiers == "[" { sendSelectedToBack() }
            else { super.keyDown(with: event) }
        }
    }

    /// ⌘/⌃Z = undo, ⌘/⌃⇧Z or ⌘/⌃Y = redo. Returns true when consumed.
    private func handleUndoRedo(_ event: NSEvent) -> Bool {
        if activeField != nil { return false }   // let the text editor own ⌘Z while typing
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) || mods.contains(.control) else { return false }
        switch event.keyCode {
        case 6:  mods.contains(.shift) ? redo() : undo(); return true    // Z / ⇧Z
        case 16: redo(); return true                                     // Y
        default: return false
        }
    }

    // MARK: - Mutation entry points for the window controller / inline editor
    public func insert(_ annotation: any Annotation) {
        snapshot(); document.add(annotation); selectedIDs = [annotation.id]
        onStateChange?(); needsDisplay = true
    }
    public func applyCrop(to imageRect: CGRect) {
        guard let cropped = document.cropped(to: imageRect) else { return }
        snapshot()
        document = cropped
        frame = NSRect(origin: .zero, size: document.size)
        selectedIDs = []; onStateChange?(); needsDisplay = true
    }
    public func currentDocument() -> EditorDocument { document }

    // MARK: - Undo / redo + object actions (driven by the window chrome)
    public func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(document); document = prev
        openStyleGroup = nil
        selectedIDs = []; onStateChange?(); needsDisplay = true
    }
    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document); document = next
        openStyleGroup = nil
        selectedIDs = []; onStateChange?(); needsDisplay = true
    }
    public func clearSelection() {
        guard !selectedIDs.isEmpty else { return }
        selectedIDs = []; onStateChange?(); needsDisplay = true
    }
    public func deleteSelected() {
        guard !selectedIDs.isEmpty else { return }
        snapshot()
        for id in selectedIDs { document.remove(id: id) }
        selectedIDs = []
        onStateChange?(); needsDisplay = true
    }
    public func bringSelectedToFront() {
        guard !selectedIDs.isEmpty else { return }
        snapshot()
        // Walk in document order so the selected objects keep their relative stacking.
        for id in document.annotations.map(\.id) where selectedIDs.contains(id) {
            document.bringToFront(id: id)
        }
        onStateChange?(); needsDisplay = true
    }
    public func sendSelectedToBack() {
        guard !selectedIDs.isEmpty else { return }
        snapshot()
        for id in document.annotations.map(\.id).reversed() where selectedIDs.contains(id) {
            document.sendToBack(id: id)
        }
        onStateChange?(); needsDisplay = true
    }

    // MARK: - Inline text editing (Task 11)
    // An NSTextView laid out exactly like the committed TextAnnotation. A free label
    // (click) grows rightward to the canvas edge, then wraps and grows down; a text
    // box (drag, or an existing box) keeps its width and grows down. Return commits,
    // ⇧/⌥Return inserts a newline, Esc or clicking away also commits.
    private var activeField: NSTextView?
    private var textImageOrigin: CGPoint = .zero
    /// Free label: room (view points) from the origin to the canvas's right edge.
    private var activeRoom: CGFloat = 0
    /// Text box width in image px; nil while editing a free label.
    private var activeBoxWidth: CGFloat?
    /// The existing annotation being edited (hidden from the canvas meanwhile).
    private var editingID: UUID?
    private var textPressPending = false
    /// Timestamp of the mouse-down that ended editing, so that same click doesn't open a new text.
    private var focusCommitTimestamp: TimeInterval?

    private var editorAttributes: [NSAttributedString.Key: Any] {
        TextAnnotation.attributes(for: style, fontSize: style.fontSize / scale)
    }

    private func beginTextEditing(atImagePoint p: CGPoint, fixedWidth: CGFloat? = nil, text: String = "") {
        let viewPoint = NSPoint(x: p.x / scale, y: p.y / scale)
        activeRoom = max(bounds.maxX - viewPoint.x, 40)
        activeBoxWidth = fixedWidth
        let field = NSTextView(frame: NSRect(x: viewPoint.x, y: viewPoint.y, width: 20, height: 20))
        field.isRichText = false
        field.drawsBackground = false
        field.allowsUndo = true
        field.textContainerInset = .zero
        field.textContainer?.lineFragmentPadding = 0
        field.textContainer?.widthTracksTextView = false
        field.string = text
        field.delegate = self
        addSubview(field)
        activeField = field
        textImageOrigin = p
        restyleActiveField()
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    private func editExistingText(id: UUID) {
        guard let i = document.index(of: id), let ta = document.annotations[i] as? TextAnnotation else { return }
        selectedIDs = []
        onEditText?(ta.style)
        style = ta.style
        editingID = id
        beginTextEditing(atImagePoint: ta.origin, fixedWidth: ta.wrapWidth, text: ta.text)
        onStateChange?()
    }

    /// Natural single-line-per-paragraph width of the editor's text, in view points.
    private func activeNaturalWidth() -> CGFloat {
        guard let field = activeField else { return 0 }
        let s = NSAttributedString(string: field.string.isEmpty ? " " : field.string, attributes: editorAttributes)
        return ceil(s.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                                   options: [.usesLineFragmentOrigin, .usesFontLeading]).width)
    }

    /// Re-applies the current style to the live editor (inspector changes while typing) and re-fits it.
    private func restyleActiveField() {
        guard let field = activeField else { return }
        let attrs = editorAttributes
        field.typingAttributes = attrs
        field.textStorage?.setAttributes(attrs, range: NSRange(location: 0, length: (field.string as NSString).length))
        field.insertionPointColor = style.strokeColor.nsColor
        field.alphaValue = style.opacity   // match the committed text's opacity while typing
        resizeActiveField()
    }

    private func resizeActiveField() {
        guard let field = activeField, let lm = field.layoutManager, let tc = field.textContainer else { return }
        // Container width == frame width, so centre/right alignment lands where it will render.
        let width = activeBoxWidth.map { $0 / scale } ?? min(activeNaturalWidth() + 2, activeRoom)
        tc.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let font = editorAttributes[.font] as? NSFont ?? .systemFont(ofSize: 12)
        field.setFrameSize(NSSize(width: width, height: max(ceil(used.height), ceil(lm.defaultLineHeight(for: font)))))
    }

    /// Commits any in-progress text — call before exporting so typed text isn't lost.
    public func commitPendingText() { commitText(refocusCanvas: true) }

    private func commitText(refocusCanvas: Bool) {
        guard let field = activeField else { return }
        let text = field.string
        let wrapWidth: CGFloat? = activeBoxWidth
            ?? (activeNaturalWidth() > activeRoom ? activeRoom * scale : nil)
        activeField = nil
        field.delegate = nil
        field.removeFromSuperview()
        if refocusCanvas { window?.makeFirstResponder(self) }
        let editedID = editingID
        editingID = nil
        if let id = editedID, let i = document.index(of: id), var ta = document.annotations[i] as? TextAnnotation {
            if text.isEmpty {
                snapshot(); document.remove(id: id); selectedIDs = []
            } else if ta.text != text || ta.style != style || ta.wrapWidth != wrapWidth {
                snapshot()
                ta.text = text; ta.style = style; ta.wrapWidth = wrapWidth
                document.replace(id: id, with: ta)
                selectedIDs = [id]
            } else {
                selectedIDs = [id]
            }
            onStateChange?(); needsDisplay = true
            return
        }
        guard !text.isEmpty else { onStateChange?(); needsDisplay = true; return }
        insert(TextAnnotation(text: text, origin: textImageOrigin, style: style, wrapWidth: wrapWidth))
    }

    /// Applies an inspector edit (e.g. "width = 7") to every selected object as one undo
    /// step; edits passing the same `group` (a slider drag) merge into that step. The
    /// window applies the same edit to `style`, the default for new objects; the live text
    /// editor restyles from `style`, so this does nothing while text is being typed.
    public func applyStyleEdit(_ edit: (inout AnnotationStyle) -> Void, group: AnyHashable? = nil) {
        guard activeField == nil else { return }
        var changed: [any Annotation] = []
        for var a in selectedAnnotations {
            var s = a.style
            edit(&s)
            guard s != a.style else { continue }
            a.style = s
            changed.append(a)
        }
        guard !changed.isEmpty else { return }
        if group == nil || group != openStyleGroup { snapshot() }
        openStyleGroup = group
        for a in changed { document.replace(id: a.id, with: a) }
        onStateChange?(); needsDisplay = true
    }

    /// Ends a merged style edit (e.g. the slider was released), so the next edit is its own step.
    public func endStyleEditGroup() { openStyleGroup = nil }
}

extension EditorCanvasView: NSTextViewDelegate {
    public func textDidChange(_ notification: Notification) { resizeActiveField() }

    public func textDidEndEditing(_ notification: Notification) {
        // Focus moved elsewhere (e.g. a click on the canvas): don't fight the new responder.
        if let e = NSApp.currentEvent, e.type == .leftMouseDown { focusCommitTimestamp = e.timestamp }
        commitText(refocusCanvas: false)
    }

    public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let mods = NSApp.currentEvent?.modifierFlags ?? []
            if mods.contains(.shift) || mods.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                commitText(refocusCanvas: true)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            commitText(refocusCanvas: true)
            return true
        default:
            return false
        }
    }
}
