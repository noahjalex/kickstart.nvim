import AppKit
import PDFKit
import XCTest
@testable import PreviewCore

/// No window is ever ordered, no app is launched, and no input is injected into the desktop.
final class DiagramViewerTests: XCTestCase {
    private var directory: URL!
    private var renderer: MarkdownRenderer!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.md")
        try "".write(to: source, atomically: true, encoding: .utf8)
        renderer = MarkdownRenderer(paths: try PreviewPaths(source: source.path, root: directory.path))
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func diagrams(_ text: NSAttributedString) -> [DiagramAttachment] {
        var result: [DiagramAttachment] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let diagram = value as? DiagramAttachment { result.append(diagram) }
        }
        return result
    }
    private func sample() throws -> DiagramAttachment {
        try XCTUnwrap(diagrams(renderer.render("```mermaid\nflowchart TD\nA[Receive a customer order] --> B[Middle]\nB --> C[Finish]\n```\n")).first)
    }

    func testArticleClickRoutingOnlyAcceptsActualDiagramGlyphs() throws {
        let text = NSMutableAttributedString(attributedString: renderer.render("```mermaid\nflowchart LR\nA[Start] --> B[Finish]\n```\n\nOrdinary source"))
        let normal = NSTextAttachment()
        normal.image = NSImage(size: NSSize(width: 50, height: 40))
        normal.bounds = NSRect(x: 0, y: 0, width: 50, height: 40)
        let normalIndex = text.length
        text.append(NSAttributedString(attachment: normal))
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager(); storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 700, height: 3000))
        layout.addTextContainer(container)
        let article = DiagramArticleTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 3000), textContainer: container)
        article.isEditable = false; article.isSelectable = true
        layout.ensureLayout(for: container)
        func point(at character: Int) -> NSPoint {
            let glyph = layout.glyphRange(forCharacterRange: NSRange(location: character, length: 1), actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyph, in: container)
            return NSPoint(x: rect.midX + article.textContainerOrigin.x, y: rect.midY + article.textContainerOrigin.y)
        }
        var opened: DiagramAttachment?
        article.onOpenDiagram = { opened = $0 }
        XCTAssertTrue(article.openDiagram(at: point(at: 0)))
        XCTAssertTrue(opened === diagrams(text).first)
        opened = nil
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: article.convert(point(at: 0), to: nil), modifierFlags: [],
                                                    timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                    clickCount: 1, pressure: 1))
        article.mouseDown(with: click) // Direct offscreen method call, not system event injection.
        XCTAssertTrue(opened === diagrams(text).first)
        for point in [point(at: normalIndex), point(at: (text.string as NSString).range(of: "Ordinary source").location),
                      NSPoint(x: 699, y: 2999), NSPoint(x: -20, y: -20)] {
            XCTAssertNil(article.diagram(at: point))
            XCTAssertFalse(article.openDiagram(at: point))
        }
        // Source-only guards never produce viewer metadata or a second render path.
        XCTAssertTrue(diagrams(renderer.render("```mermaid\nsequenceDiagram\nautonumber 9223372036854775807\nA->>B: Hello\n```\n")).isEmpty)
        XCTAssertTrue(diagrams(renderer.render("```mermaid\nunsupported diagram\n```\n")).isEmpty)
    }

    func testFourLargeManualDiagramsExportRealVectorPagesNotThumbnails() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let source = tests.appendingPathComponent("mermaid-comparison.md")
        let text = MarkdownRenderer(paths: try PreviewPaths(source: source.path, root: tests.path))
            .render(try String(contentsOf: source, encoding: .utf8))
        let attachments = diagrams(text)
        XCTAssertEqual(attachments.count, 4)
        let artifacts = tests.deletingLastPathComponent().appendingPathComponent(".build/lane-artifacts")
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        for (index, attachment) in attachments.enumerated() {
            let pdf = try XCTUnwrap(PDFDocument(data: attachment.pdfData))
            XCTAssertEqual(pdf.pageCount, 1)
            XCTAssertFalse(try XCTUnwrap(pdf.page(at: 0)?.string).isEmpty, "PDF must contain vector text, not just the inline bitmap")
            XCTAssertGreaterThan(attachment.diagramSize.width, attachment.bounds.width)
            XCTAssertGreaterThan(attachment.diagramSize.height, attachment.bounds.height)
            XCTAssertEqual(attachment.diagramSize.width, attachment.image!.size.width, accuracy: 0.01)
            XCTAssertEqual(attachment.diagramSize.height, attachment.image!.size.height, accuracy: 0.01)
            XCTAssertFalse(text.string.contains(attachment.source))
            let pasteboard = NSPasteboard.withUniqueName()
            let viewer = DiagramViewerView(diagram: attachment)
            XCTAssertTrue(viewer.copyDiagramSource(to: pasteboard))
            XCTAssertEqual(pasteboard.string(forType: .string), attachment.source)
            pasteboard.releaseGlobally()
            viewer.setZoom(2)
            viewer.pan(by: NSSize(width: 20, height: 20))
            viewer.fitDiagram(nil)
            XCTAssertTrue(viewer.fitting)
            let canvas = try XCTUnwrap(viewer.scrollView.documentView)
            XCTAssertEqual(canvas.frame.size, attachment.diagramSize)
            let drawnPDF = canvas.dataWithPDF(inside: canvas.bounds)
            let drawn = try XCTUnwrap(PDFDocument(data: drawnPDF))
            XCTAssertFalse(try XCTUnwrap(drawn.page(at: 0)?.string).isEmpty, "Viewer draw must preserve real PDF text at native size")
            try attachment.pdfData.write(to: artifacts.appendingPathComponent("expanded-\(index + 1).pdf"))
            // Rasterize the actual vector-backed view for file-only inspection, never a shown window.
            let bitmap = try XCTUnwrap(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
            canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: artifacts.appendingPathComponent("expanded-\(index + 1).png"))
            print("Expanded manual diagram \(index + 1): vector \(attachment.diagramSize), inline \(attachment.bounds.size), PDF \(attachment.pdfData.count) bytes")
        }
    }

    func testOutsideClickDeactivationAndControllerCleanupWithoutShowingPanel() throws {
        let diagram = try sample()
        let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        defer { parent.close() }
        for reason in ["outside", "deactivate", "resignKey", "close"] {
            let controller = DiagramViewerController(diagram: diagram)
            let panel = try XCTUnwrap(controller.window)
            parent.addChildWindow(panel, ordered: .above)
            var closed = 0
            controller.onClose = { closed += 1 }
            controller.startMonitoringOutsideClicks()
            controller.startMonitoringOutsideClicks() // Installation is idempotent.
            let inside = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            controller.dismissForOutsideClick(inside)
            XCTAssertEqual(closed, 0)
            XCTAssertTrue(controller.monitoringOutsideClicks)
            switch reason {
            case "outside":
                let outside = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                    timestamp: 0, windowNumber: parent.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                controller.dismissForOutsideClick(outside)
            case "deactivate": NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
            case "resignKey": controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: panel))
            default: controller.close()
            }
            XCTAssertEqual(closed, 1, reason)
            XCTAssertFalse(controller.monitoringOutsideClicks)
            XCTAssertNil(panel.parent)
            XCTAssertNil(controller.onClose)
            XCTAssertFalse(panel.isVisible)
            XCTAssertFalse(parent.isVisible)
        }
        weak var released: DiagramViewerController?
        autoreleasepool {
            let controller = DiagramViewerController(diagram: diagram)
            released = controller
            controller.startMonitoringOutsideClicks()
        }
        XCTAssertNil(released, "Event monitors must not retain the controller")
    }

    func testFitZoomPanResizeAndKeyboardWithoutShowingWindow() throws {
        let diagram = try sample()
        let controller = DiagramViewerController(diagram: diagram)
        let window = try XCTUnwrap(controller.window)
        defer { controller.close() }
        XCTAssertFalse(window.isVisible)
        let panel = try XCTUnwrap(window as? NSPanel)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.collectionBehavior.contains(.transient))
        XCTAssertTrue(panel.styleMask.contains(.utilityWindow))
        XCTAssertTrue(panel.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(panel.titleVisibility, .hidden)
        XCTAssertTrue(panel.titlebarAppearsTransparent)
        XCTAssertEqual(panel.backgroundColor, diagram.canvasColor)
        XCTAssertEqual(controller.viewer.frame.height, panel.frame.height, accuracy: 1,
                       "Canvas must extend beneath the transparent title bar")
        XCTAssertFalse(panel.styleMask.contains(.miniaturizable))
        let viewer = controller.viewer
        let scroll = viewer.scrollView
        XCTAssertEqual(viewer.subviews, [scroll], "No helper bar or controls should occupy the panel")
        XCTAssertEqual(scroll.frame, viewer.bounds)
        XCTAssertTrue(window.firstResponder === viewer)
        XCTAssertTrue(scroll.allowsMagnification)
        XCTAssertTrue(scroll.hasHorizontalScroller && scroll.hasVerticalScroller)
        XCTAssertTrue(viewer.fitting)
        XCTAssertLessThanOrEqual(scroll.magnification, 1)
        XCTAssertEqual(scroll.contentView.bounds.midX, diagram.diagramSize.width / 2, accuracy: 1)
        XCTAssertEqual(scroll.contentView.bounds.midY, diagram.diagramSize.height / 2, accuracy: 1)
        viewer.setZoom(2)
        func wheel(_ delta: Int32) throws {
            let cg = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                          wheel1: delta, wheel2: 0, wheel3: 0))
            scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: cg)))
        }
        let wheelCenter = NSPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY)
        try wheel(1)
        XCTAssertGreaterThan(scroll.magnification, 2, "Wheel must zoom, not scroll")
        XCTAssertEqual(scroll.contentView.bounds.midX, wheelCenter.x, accuracy: 1)
        XCTAssertEqual(scroll.contentView.bounds.midY, wheelCenter.y, accuracy: 1)
        try wheel(-1)
        XCTAssertEqual(scroll.magnification, 2, accuracy: 0.001)
        XCTAssertFalse(viewer.fitting)
        viewer.setZoom(100)
        XCTAssertEqual(scroll.magnification, 8)
        viewer.pan(by: NSSize(width: 1e6, height: 1e6))
        let clip = scroll.contentView
        XCTAssertEqual(clip.bounds.maxX, diagram.diagramSize.width, accuracy: 1)
        XCTAssertEqual(clip.bounds.maxY, diagram.diagramSize.height, accuracy: 1)
        viewer.pan(by: NSSize(width: -1e6, height: -1e6))
        XCTAssertEqual(clip.bounds.minX, 0, accuracy: 1)
        XCTAssertEqual(clip.bounds.minY, 0, accuracy: 1)
        viewer.pan(by: NSSize(width: 30, height: 30))
        let canvas = try XCTUnwrap(scroll.documentView)
        let beforeDrag = clip.bounds.origin
        let downPoint = NSPoint(x: 150, y: 150)
        let dragPoint = NSPoint(x: 110, y: 110)
        let previous = canvas.convert(downPoint, from: nil)
        let current = canvas.convert(dragPoint, from: nil)
        func mouse(_ type: NSEvent.EventType, at point: NSPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        // Direct method calls on an unshown canvas; no system event posting.
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: downPoint))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: dragPoint))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: dragPoint))
        XCTAssertEqual(clip.bounds.origin.x, beforeDrag.x + previous.x - current.x, accuracy: 0.1)
        XCTAssertEqual(clip.bounds.origin.y, beforeDrag.y + previous.y - current.y, accuracy: 0.1)
        let center = NSPoint(x: clip.bounds.midX, y: clip.bounds.midY)
        viewer.setZoom(7)
        XCTAssertEqual(clip.bounds.midX, center.x, accuracy: 1)
        XCTAssertEqual(clip.bounds.midY, center.y, accuracy: 1)
        viewer.setZoom(-1)
        XCTAssertEqual(scroll.magnification, scroll.minMagnification)
        viewer.setZoom(.nan)
        XCTAssertEqual(scroll.magnification, scroll.minMagnification)

        func key(_ characters: String, flags: NSEvent.ModifierFlags = .command, code: UInt16 = 0) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                          windowNumber: window.windowNumber, context: nil, characters: characters,
                                          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }
        XCTAssertTrue(viewer.performKeyEquivalent(with: try key("=")))
        let zoom = scroll.magnification
        XCTAssertTrue(viewer.performKeyEquivalent(with: try key("+", flags: [.command, .shift])))
        XCTAssertGreaterThan(scroll.magnification, zoom)
        XCTAssertTrue(viewer.performKeyEquivalent(with: try key("-")))
        XCTAssertEqual(scroll.magnification, zoom, accuracy: 0.0001)
        XCTAssertTrue(viewer.performKeyEquivalent(with: try key("0")))
        XCTAssertTrue(viewer.fitting)
        // Fit follows resize; explicit zoom does not unexpectedly refit.
        viewer.setFrameSize(NSSize(width: 180, height: 140)); viewer.layout()
        XCTAssertLessThan(scroll.magnification, 1)
        XCTAssertLessThanOrEqual(diagram.diagramSize.width * scroll.magnification, clip.frame.width + 1)
        viewer.setZoom(2)
        viewer.setFrameSize(NSSize(width: 700, height: 400)); viewer.layout()
        XCTAssertEqual(scroll.frame, viewer.bounds)
        XCTAssertEqual(scroll.magnification, 2)
        viewer.fitDiagram(nil)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        XCTAssertFalse(viewer.fitting, "Native pinch completion must leave fit mode")
        XCTAssertFalse(viewer.performKeyEquivalent(with: try key("c")), "Copy must remain in the normal responder chain")
        XCTAssertTrue(viewer.responds(to: #selector(DiagramViewerView.zoomDiagramIn(_:))))
        XCTAssertTrue(viewer.responds(to: #selector(DiagramViewerView.fitDiagram(_:))))
        var closeNotifications = 0
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: nil) { _ in
            closeNotifications += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        controller.startMonitoringOutsideClicks()
        XCTAssertTrue(controller.monitoringOutsideClicks)
        viewer.keyDown(with: try key("\u{1b}", flags: [], code: 53))
        XCTAssertFalse(controller.monitoringOutsideClicks)
        XCTAssertEqual(closeNotifications, 1, "Escape must really close the unshown window")
        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(viewer.performKeyEquivalent(with: try key("w")))
    }
}
