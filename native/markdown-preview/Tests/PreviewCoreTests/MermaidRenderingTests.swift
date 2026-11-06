import AppKit
import XCTest
@testable import PreviewCore

final class MermaidRenderingTests: XCTestCase {
    private var directory: URL!
    private var paths: PreviewPaths!
    private let examples = [
        ("flowchart", "flowchart LR\n  A[Read 日本語] --> B{Valid?}\n  B -->|yes| C[Render]\n  B -->|no| D[Source]\n"),
        ("sequence", "sequenceDiagram\n  participant Alice\n  participant Bob\n  Alice->>Bob: Hello\n  Bob-->>Alice: Hi\n"),
        ("pie", "pie title Pets\n  \"Cats\" : 3\n  \"Dogs\" : 2\n")
    ]

    override func setUpWithError() throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.md")
        try "".write(to: source, atomically: true, encoding: .utf8)
        paths = try PreviewPaths(source: source.path, root: directory.path)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    private func attachments(_ text: NSAttributedString) -> [NSTextAttachment] {
        var result: [NSTextAttachment] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment { result.append(attachment) }
        }
        return result
    }

    func testRealImagesSourceCopyThemeAndResponsiveLayout() throws {
        // Lane-private artifacts, no windows, image viewers, or general pasteboard.
        let artifacts = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/lane-artifacts")
        try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        for dark in [false, true] {
            let theme = PreviewTheme(dark: dark, colors: [
                "foreground": dark ? "#eeeeee" : "#222222", "background": dark ? "#111122" : "#ffffff",
                "link": "#4080ff", "border": "#888888"
            ])
            for (name, source) in examples {
                let rendered = NSMutableAttributedString(attributedString: MarkdownRenderer(paths: paths, theme: theme)
                    .render("```mermaid\n\(source)```\n\nFollowing paragraph."))
                let attachment = try XCTUnwrap(attachments(rendered).first as? DiagramAttachment)
                XCTAssertEqual(attachment.source, source)
                XCTAssertFalse(rendered.string.contains(source), "Successful diagrams must hide duplicate source")
                let paragraph = try XCTUnwrap(rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
                XCTAssertEqual(paragraph.alignment, .center)
                let boundary = try XCTUnwrap(paragraph.textBlocks.last as? RoundedCodeBlock)
                XCTAssertGreaterThan(boundary.radius, 0)
                XCTAssertEqual(boundary.outline, theme.color("border", fallback: .red))
                XCTAssertEqual(attachments(rendered).count, 1)
                let image = try XCTUnwrap(attachment.image)
                XCTAssertGreaterThan(image.size.width, 50)
                XCTAssertGreaterThan(image.size.height, 50)
                XCTAssertFalse(try XCTUnwrap(image.accessibilityDescription).isEmpty)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: artifacts.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
                var colors = Set<String>()
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 5) {
                    for x in stride(from: 0, to: bitmap.pixelsWide, by: 5) {
                        if let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.1 {
                            colors.insert(color.description)
                        }
                    }
                }
                XCTAssertGreaterThan(colors.count, 2, "Diagram must contain actual drawing, not an empty image")
                let storage = NSTextStorage(attributedString: rendered)
                let layout = NSLayoutManager(); storage.addLayoutManager(layout)
                let container = NSTextContainer(size: NSSize(width: 320, height: 10000))
                container.lineFragmentPadding = 0
                layout.addTextContainer(container)
                let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 850, height: 2000), textContainer: container)
                view.isEditable = false; view.isSelectable = true
                for width in [272.0, 850.0, 272.0] {
                    MarkdownRenderer.resizeAttachments(in: storage, availableWidth: width)
                    container.containerSize.width = width
                    layout.invalidateLayout(forCharacterRange: NSRange(location: 0, length: storage.length), actualCharacterRange: nil)
                    layout.ensureLayout(for: container)
                    XCTAssertLessThanOrEqual(attachment.bounds.width, min(width, 640))
                    XCTAssertLessThanOrEqual(attachment.bounds.height, 480)
                    XCTAssertEqual(attachment.bounds.width / attachment.bounds.height,
                                   image.size.width / image.size.height, accuracy: 0.0001)
                    XCTAssertGreaterThan(layout.usedRect(for: container).height, attachment.bounds.height)
                    XCTAssertLessThan(layout.usedRect(for: container).height, 1900)
                    let rect = layout.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: container)
                    XCTAssertLessThanOrEqual(rect.maxX, width + 1)
                    XCTAssertEqual(rect.midX, width / 2, accuracy: 2, "Inline diagram must stay centered")
                    // Draw the real TextKit attachment as well as rasterizing its NSImage.
                    let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: rep)
                }
                let viewer = DiagramViewerView(diagram: attachment)
                let copyItem = try XCTUnwrap(viewer.scrollView.documentView?.menu?.items.first { $0.title == "Copy Source" })
                XCTAssertEqual(copyItem.action, #selector(DiagramViewerView.copyDiagramSource(_:)))
                XCTAssertTrue(copyItem.target === viewer)
                XCTAssertTrue(viewer.copyDiagramSource(to: pasteboard))
                XCTAssertEqual(pasteboard.string(forType: .string), source)
                print("MermaidKit \(name) \(dark ? "dark" : "light"): \(image.size), \(colors.count) sampled colors")
            }
        }
    }

    func testAutonumberAlwaysRetainsCopyableSourceWithoutCallingUpstream() throws {
        let renderer = MarkdownRenderer(paths: paths)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        // Only render through the host guard: the exact first fixture traps upstream 2.9.1.
        let sources = [
            "sequenceDiagram\nautonumber 9223372036854775807\nA->>B: Hello",
            "sequenceDiagram\n  autonumber    9223372036854775807\nA->>B: Hello\n",
            "sequenceDiagram\n\tautonumber \t9223372036854775807\nA->>B: Hello\n",
            "sequenceDiagram\n\u{00a0}autonumber 9223372036854775807\nA->>B: Hello\n",
            "sequenceDiagram\n%% ignored comment\nautonumber 9223372036854775807\nA->>B: Hello\n",
            "---\ntitle: Example\n---\nsequenceDiagram\naccTitle: Example\nautonumber 9223372036854775807\nA->>B: Hello\n",
            "sequenceDiagram\nautonumber 1 9223372036854775807\nA->>B: Hello\n",
            "sequenceDiagram\nautonumber 1 -9223372036854775808\nA->>B: Hello\nB->>A: Hi\n",
            "sequenceDiagram\nAUTONUMBER 9223372036854775807\nA->>B: Hello\n",
            "sequenceDiagram\nAutoNumber 9223372036854775807\nA->>B: Hello\n",
            "sequenceDiagram\nautonumber\nA->>B: Hello\n",
            "sequenceDiagram\nautonumber off\nA->>B: Hello\n",
            "sequenceDiagram\n%% autonumber is only a comment\nA->>B: Hello\n",
            "sequenceDiagram\nA->>B: Mention AutoNumber in a label\n",
            "---\ntitle: AutoNumber example\n---\nsequenceDiagram\nA->>B: Hello\n"
        ]
        for source in sources {
            let text = renderer.render("```mermaid\n\(source)\(source.hasSuffix("\n") ? "" : "\n")```\n")
            XCTAssertTrue(attachments(text).isEmpty, "Autonumber must stay source-only: \(source)")
            let view = NSTextView()
            view.isEditable = false; view.isSelectable = true
            view.textStorage!.setAttributedString(text)
            let range = (view.string as NSString).range(of: source)
            XCTAssertNotEqual(range.location, NSNotFound)
            guard range.location != NSNotFound else { continue }
            view.setSelectedRange(range)
            pasteboard.clearContents()
            XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
            XCTAssertEqual(pasteboard.string(forType: .string), source)
        }
    }

    func testFallbackOrdinaryCodeAndWorkLimits() throws {
        let renderer = MarkdownRenderer(paths: paths)
        for source in ["notADiagram\nA --> B\n", "pie\nthis is invalid\n", "flowchart TD\n" + String(repeating: "%% padding\n", count: 65),
                       "flowchart TD\nA[" + String(repeating: "x", count: 2048) + "]\n"] {
            let text = renderer.render("```mermaid\n\(source)```\n")
            XCTAssertTrue(attachments(text).isEmpty)
            XCTAssertTrue(text.string.contains(source))
        }
        let ordinary = renderer.render("```swift\nlet value = 42\n```\n")
        XCTAssertTrue(attachments(ordinary).isEmpty)
        XCTAssertEqual(ordinary.string, "let value = 42\n")
        XCTAssertTrue((ordinary.attribute(.font, at: 0, effectiveRange: nil) as! NSFont).isFixedPitch)
        let many = (0..<12).map { _ in "```mermaid\nflowchart LR\nA --> B\n```\n" }.joined(separator: "\n")
        let bounded = renderer.render(many)
        XCTAssertEqual(attachments(bounded).count, 8)
        XCTAssertEqual(bounded.string.components(separatedBy: "A --> B").count - 1, 4)
    }
}
