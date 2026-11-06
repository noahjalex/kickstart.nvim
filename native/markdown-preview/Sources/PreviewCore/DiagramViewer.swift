import AppKit

/// Only successfully rendered, guarded Mermaid fences receive this attachment type.
/// The PDF is exported once from the same source/theme, never from the inline image.
public final class DiagramAttachment: NSTextAttachment {
    public let pdfData: Data
    public let pdfDocument: CGPDFDocument
    public let diagramSize: NSSize
    public let canvasColor: NSColor
    public let dark: Bool
    public let source: String

    public init?(image: NSImage, pdfData: Data, canvasColor: NSColor, dark: Bool, source: String) {
        guard pdfData.count <= 8 * 1024 * 1024,
              let provider = CGDataProvider(data: pdfData as CFData),
              let document = CGPDFDocument(provider), document.numberOfPages == 1,
              let page = document.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        guard box.origin == .zero, box.width.isFinite, box.height.isFinite,
              box.width > 0, box.height > 0, box.width <= 4096, box.height <= 4096 else { return nil }
        self.pdfData = pdfData
        self.pdfDocument = document
        self.diagramSize = box.size
        self.canvasColor = canvasColor
        self.dark = dark
        self.source = source
        super.init(data: nil, ofType: nil)
        self.image = image
        bounds = NSRect(origin: .zero, size: image.size)
    }

    public required init?(coder: NSCoder) { return nil }
}

/// Intercepts only clicks inside a marked diagram glyph; all normal text/image behavior stays native.
public final class DiagramArticleTextView: NSTextView {
    public var onOpenDiagram: ((DiagramAttachment) -> Void)?

    public func diagram(at point: NSPoint) -> DiagramAttachment? {
        guard let layout = layoutManager, let container = textContainer, let storage = textStorage,
              storage.length > 0 else { return nil }
        layout.ensureLayout(for: container)
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyph = layout.glyphIndex(for: local, in: container)
        guard glyph < layout.numberOfGlyphs else { return nil }
        let character = layout.characterIndexForGlyph(at: glyph)
        guard let diagram = storage.attribute(.attachment, at: character, effectiveRange: nil) as? DiagramAttachment,
              layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local)
        else { return nil }
        return diagram
    }

    @discardableResult public func openDiagram(at point: NSPoint) -> Bool {
        guard let diagram = diagram(at: point), let open = onOpenDiagram else { return false }
        open(diagram)
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        if !openDiagram(at: convert(event.locationInWindow, from: nil)) { super.mouseDown(with: event) }
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        guard let storage = textStorage, let layout = layoutManager, let container = textContainer else { return }
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value is DiagramAttachment else { return }
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            addCursorRect(rect, cursor: .pointingHand)
        }
    }
}

private final class DiagramZoomScrollView: NSScrollView {
    weak var viewer: DiagramViewerView?

    override func scrollWheel(with event: NSEvent) {
        guard let viewer else { return }
        let delta = event.scrollingDeltaY
        guard delta.isFinite, delta != 0 else { return }
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.01 : 0.1
        viewer.setZoom(magnification * exp(min(1, max(-1, delta * sensitivity))))
    }
}

private final class CenteredDiagramClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var result = super.constrainBoundsRect(proposedBounds)
        if let document = documentView {
            if document.frame.width < result.width { result.origin.x = (document.frame.width - result.width) / 2 }
            if document.frame.height < result.height { result.origin.y = (document.frame.height - result.height) / 2 }
        }
        return result
    }
}

/// PDF drawing stays vector at every magnification; no zoom-sized bitmap allocation or pan rerender.
private final class DiagramCanvas: NSView {
    let diagram: DiagramAttachment
    weak var viewer: DiagramViewerView?
    private var dragLocation: NSPoint?
    override var isFlipped: Bool { true }

    init(diagram: DiagramAttachment) {
        self.diagram = diagram
        super.init(frame: NSRect(origin: .zero, size: diagram.diagramSize))
        setAccessibilityElement(true)
        setAccessibilityLabel(diagram.image?.accessibilityDescription ?? "Mermaid diagram")
    }
    required init?(coder: NSCoder) { return nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let page = diagram.pdfDocument.page(at: 1) else { return }
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.drawPDFPage(page)
        context.restoreGState()
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(viewer)
        dragLocation = event.locationInWindow
        NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let previousLocation = dragLocation, let viewer else { return }
        // Convert both window points through the current transform: correct at every zoom and Y orientation.
        let previous = convert(previousLocation, from: nil)
        let current = convert(event.locationInWindow, from: nil)
        viewer.pan(by: NSSize(width: previous.x - current.x, height: previous.y - current.y))
        dragLocation = event.locationInWindow
    }
    private func endDrag() {
        if dragLocation != nil { NSCursor.pop(); dragLocation = nil }
    }
    override func mouseUp(with event: NSEvent) { endDrag() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { endDrag() }
        super.viewWillMove(toWindow: newWindow)
    }
}

/// Native scroll/magnification mechanics, with only fit/centering and shortcut glue added.
public final class DiagramViewerView: NSView {
    public let scrollView: NSScrollView = DiagramZoomScrollView()
    public let diagram: DiagramAttachment
    public private(set) var fitting = true
    private var lastViewport = NSSize.zero
    public override var acceptsFirstResponder: Bool { true }

    public init(diagram: DiagramAttachment, frame: NSRect = NSRect(x: 0, y: 0, width: 900, height: 650)) {
        self.diagram = diagram
        super.init(frame: frame)
        appearance = NSAppearance(named: diagram.dark ? .darkAqua : .aqua)
        let clip = CenteredDiagramClipView()
        clip.backgroundColor = diagram.canvasColor
        (scrollView as? DiagramZoomScrollView)?.viewer = self
        scrollView.contentView = clip
        scrollView.backgroundColor = diagram.canvasColor
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.025
        scrollView.maxMagnification = 8
        let canvas = DiagramCanvas(diagram: diagram)
        canvas.viewer = self
        scrollView.documentView = canvas
        addSubview(scrollView)
        let sourceMenu = NSMenu()
        let copyItem = sourceMenu.addItem(withTitle: "Copy Source", action: #selector(copyDiagramSource(_:)), keyEquivalent: "")
        copyItem.target = self
        canvas.menu = sourceMenu
        NotificationCenter.default.addObserver(self, selector: #selector(magnificationChanged(_:)),
                                               name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
        layout()
    }
    required init?(coder: NSCoder) { return nil }
    deinit { NotificationCenter.default.removeObserver(self) }

    public override func layout() {
        super.layout()
        scrollView.frame = bounds
        scrollView.tile()
        if lastViewport != scrollView.contentView.frame.size {
            lastViewport = scrollView.contentView.frame.size
            if fitting { fitDiagram(nil) }
            else { pan(by: .zero) }
        }
    }

    @objc private func magnificationChanged(_ notification: Notification) {
        fitting = false
    }

    public func setZoom(_ value: CGFloat) {
        guard value.isFinite else { return }
        fitting = false
        let center = NSPoint(x: scrollView.contentView.bounds.midX, y: scrollView.contentView.bounds.midY)
        scrollView.setMagnification(min(scrollView.maxMagnification, max(scrollView.minMagnification, value)), centeredAt: center)
        pan(by: .zero)
    }
    @objc public func zoomDiagramIn(_ sender: Any?) { setZoom(scrollView.magnification * 1.25) }
    @objc public func zoomDiagramOut(_ sender: Any?) { setZoom(scrollView.magnification / 1.25) }
    @objc public func fitDiagram(_ sender: Any?) {
        let viewport = scrollView.contentView.frame.size
        let fit = min(1, viewport.width / diagram.diagramSize.width, viewport.height / diagram.diagramSize.height)
        setZoom(fit)
        fitting = true
        let clip = scrollView.contentView
        let centered = NSPoint(x: (diagram.diagramSize.width - clip.bounds.width) / 2,
                               y: (diagram.diagramSize.height - clip.bounds.height) / 2)
        clip.scroll(to: clip.constrainBoundsRect(NSRect(origin: centered, size: clip.bounds.size)).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    /// Writes exact Mermaid source; callers can supply a private pasteboard for offscreen checks.
    @discardableResult public func copyDiagramSource(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(diagram.source, forType: .string)
    }
    @objc public func copyDiagramSource(_ sender: Any?) { copyDiagramSource(to: .general) }

    /// Dragging and tests share the same native clip constraints.
    public func pan(by delta: NSSize) {
        let clip = scrollView.contentView
        var proposed = clip.bounds
        proposed.origin.x += delta.width
        proposed.origin.y += delta.height
        clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
        scrollView.reflectScrolledClipView(clip)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if flags.contains(.command), !flags.contains(.control), !flags.contains(.option) {
            switch event.charactersIgnoringModifiers {
            case "+", "=": zoomDiagramIn(nil)
            case "-": zoomDiagramOut(nil)
            case "0": fitDiagram(nil)
            case "w": window?.performClose(nil)
            default: return super.performKeyEquivalent(with: event)
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { cancelOperation(nil) }
        else { super.keyDown(with: event) }
    }
    public override func cancelOperation(_ sender: Any?) { window?.performClose(nil) }
}

/// Floating transient panel; initialization stays offscreen and monitoring starts only on presentation.
public final class DiagramViewerController: NSWindowController, NSWindowDelegate {
    public let viewer: DiagramViewerView
    public var onClose: (() -> Void)?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    var monitoringOutsideClicks: Bool { localClickMonitor != nil }

    public init(diagram: DiagramAttachment) {
        viewer = DiagramViewerView(diagram: diagram)
        let panel = NSPanel(contentRect: viewer.bounds, styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = "Mermaid diagram"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.backgroundColor = diagram.canvasColor
        panel.appearance = viewer.appearance
        panel.minSize = NSSize(width: 640, height: 300)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.contentView = viewer
        viewer.autoresizingMask = [.width, .height]
        super.init(window: panel)
        panel.delegate = self
        panel.makeFirstResponder(viewer)
    }
    public required init?(coder: NSCoder) { return nil }
    deinit { stopMonitoringOutsideClicks() }

    public func present(relativeTo parent: NSWindow) {
        guard let window else { return }
        parent.addChildWindow(window, ordered: .above)
        let visible = parent.screen?.visibleFrame ?? parent.frame
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width)
        frame.size.height = min(frame.height, visible.height)
        frame.origin = NSPoint(x: min(max(parent.frame.midX - frame.width / 2, visible.minX), visible.maxX - frame.width),
                               y: min(max(parent.frame.midY - frame.height / 2, visible.minY), visible.maxY - frame.height))
        window.setFrame(frame, display: false)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(viewer)
    }

    public override func showWindow(_ sender: Any?) {
        startMonitoringOutsideClicks()
        super.showWindow(sender)
    }

    // Kept separate from presentation so lifecycle tests never need to order a window.
    func startMonitoringOutsideClicks() {
        guard !monitoringOutsideClicks else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            self?.dismissForOutsideClick(event)
            return event // Outside clicks still reach their original destination.
        }
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in self?.close() }
        NotificationCenter.default.addObserver(self, selector: #selector(applicationDeactivated(_:)),
                                               name: NSApplication.didResignActiveNotification, object: NSApp)
    }

    func dismissForOutsideClick(_ event: NSEvent) {
        if event.window !== window { close() }
    }

    private func stopMonitoringOutsideClicks() {
        if let monitor = localClickMonitor { NSEvent.removeMonitor(monitor); localClickMonitor = nil }
        if let monitor = globalClickMonitor { NSEvent.removeMonitor(monitor); globalClickMonitor = nil }
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: NSApp)
    }

    @objc private func applicationDeactivated(_ notification: Notification) { close() }
    public func windowDidResignKey(_ notification: Notification) { close() }
    public func windowWillClose(_ notification: Notification) {
        stopMonitoringOutsideClicks()
        if let window { window.parent?.removeChildWindow(window) }
        let callback = onClose
        onClose = nil
        callback?()
    }
    public override func close() {
        stopMonitoringOutsideClicks()
        super.close()
    }
}
