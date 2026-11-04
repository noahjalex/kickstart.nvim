import AppKit
import XCTest
@testable import PreviewCore

final class MarkdownRendererTests: XCTestCase {
    private var directory: URL!
    private var source: URL!

    override func setUpWithError() throws {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        source = directory.appendingPathComponent("source.md")
        try "saved text".write(to: source, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testRepresentativeNativeRendering() throws {
        let markdown = """
        # Main heading

        A paragraph with *italic*, **bold**, ***both***, `inline()`, and [a link](next.md).
        A soft break.

        - first
          - nested
        - [x] finished

        3. third
        4. fourth

        > Quoted words

        ```swift
        let code = "<not markup>"
        ```

        | Name | Detail |
        | --- | --- |
        | Alice | **Long cell** with a link [next](next.md) |
        | Bob | unicode 日本語 |

        <custom>Unknown content</custom>

        ```mermaid
        graph TD; A-->B
        ```

        $unhandled math$
        """
        let paths = try PreviewPaths(source: source.path, root: directory.path)
        let rendered = MarkdownRenderer(paths: paths).render(markdown)
        for text in ["Main heading", "italic", "bold", "• first", "• nested", "☑ finished", "3. third", "4. fourth",
                     "Quoted words", "let code = \"<not markup>\"", "Alice", "Long cell", "日本語",
                     "<custom>Unknown content</custom>", "graph TD; A-->B", "$unhandled math$"] {
            XCTAssertTrue(rendered.string.contains(text), "Missing: \(text) in \(rendered.string)")
        }
        func attribute(_ key: NSAttributedString.Key, at text: String) -> Any? {
            rendered.attribute(key, at: (rendered.string as NSString).range(of: text).location, effectiveRange: nil)
        }
        XCTAssertGreaterThan((attribute(.font, at: "Main heading") as! NSFont).pointSize, 16)
        XCTAssertTrue(NSFontManager.shared.traits(of: attribute(.font, at: "bold") as! NSFont).contains(.boldFontMask))
        XCTAssertTrue(NSFontManager.shared.traits(of: attribute(.font, at: "italic") as! NSFont).contains(.italicFontMask))
        let both = NSFontManager.shared.traits(of: attribute(.font, at: "both") as! NSFont)
        XCTAssertTrue(both.contains(.boldFontMask) && both.contains(.italicFontMask))
        XCTAssertEqual(attribute(.link, at: "a link") as? String, "next.md")
        XCTAssertEqual((attribute(.paragraphStyle, at: "Alice") as! NSParagraphStyle).textBlocks.count, 1)
        XCTAssertEqual((attribute(.paragraphStyle, at: "Quoted words") as! NSParagraphStyle).textBlocks.count, 1)
        XCTAssertTrue((attribute(.font, at: "let code") as! NSFont).isFixedPitch)
        rendered.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            XCTAssertEqual((value as! NSColor).alphaComponent, 1, "Text must stay opaque")
        }
        // Force actual native text layout, not just an attributed-string shape assertion.
        let storage = NSTextStorage(attributedString: rendered)
        let layout = NSLayoutManager(); storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: 700, height: 10000))
        layout.addTextContainer(container); layout.ensureLayout(for: container)
        XCTAssertGreaterThan(layout.usedRect(for: container).height, 300)
        XCTAssertEqual(layout.numberOfGlyphs, rendered.length)
    }

    func testCodeBlockUsesAvailableWidth() throws {
        let paths = try PreviewPaths(source: source.path, root: directory.path)
        let code = "paymentDetails: string[]"
        let rendered = MarkdownRenderer(paths: paths).render("```typescript\n\(code)\n```\n\nFollowing paragraph.")
        let storage = NSTextStorage(attributedString: rendered)
        let layout = NSLayoutManager(); storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
        layout.addTextContainer(container)
        // Relayout at narrow and wide sizes, as when resizing the preview window.
        for width in [700.0, 320.0, 850.0] {
            container.containerSize.width = width
            layout.ensureLayout(for: container)
            var line = NSRange()
            let rect = layout.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: &line)
            XCTAssertGreaterThanOrEqual(line.length, code.utf16.count, "Code collapsed at width \(width): \(rect)")
            XCTAssertLessThan(layout.usedRect(for: container).height, 200, "Short code must not turn into a tall column")
        }
    }

    func testNeovimThemeAndTypography() throws {
        let theme = PreviewTheme(dark: true, colors: [
            "foreground": "#c0caf5", "background": "#1a1b26", "heading1": "#7aa2f7",
            "link": "#7dcfff", "code": "#9ece6a", "codeBackground": "#16161e",
            "quote": "#565f89", "border": "#414868",
        ])
        let paths = try PreviewPaths(source: source.path, root: directory.path)
        let rendered = MarkdownRenderer(paths: paths, theme: theme).render("""
        # Heading

        Body with `inline` and [link](next.md).

        > Quote

        ```swift
        let value = 1
        ```

        | Name | Value |
        | :--- | ---: |
        | Cell | Data |
        """)
        func attribute(_ key: NSAttributedString.Key, at text: String) -> Any? {
            rendered.attribute(key, at: (rendered.string as NSString).range(of: text).location, effectiveRange: nil)
        }
        for (text, role) in [("Heading", "heading1"), ("Body", "foreground"), ("inline", "code"),
                             ("link", "link"), ("let value", "foreground")] {
            XCTAssertEqual(attribute(.foregroundColor, at: text) as? NSColor, theme.color(role, fallback: .red))
        }
        XCTAssertEqual((attribute(.font, at: "Body") as! NSFont).pointSize, 18)
        XCTAssertEqual((attribute(.paragraphStyle, at: "Body") as! NSParagraphStyle).minimumLineHeight, 30)
        XCTAssertEqual((attribute(.paragraphStyle, at: "Body") as! NSParagraphStyle).paragraphSpacing, 24)
        XCTAssertEqual((attribute(.font, at: "Heading") as! NSFont).pointSize, 40)
        XCTAssertEqual((attribute(.paragraphStyle, at: "Heading") as! NSParagraphStyle).paragraphSpacingBefore, 0)
        XCTAssertTrue(NSFontManager.shared.traits(of: attribute(.font, at: "Quote") as! NSFont).contains(.italicFontMask))
        XCTAssertEqual((attribute(.font, at: "Name") as! NSFont).pointSize, 15)
        XCTAssertEqual((attribute(.paragraphStyle, at: "Value") as! NSParagraphStyle).alignment, .right)
        XCTAssertEqual((attribute(.paragraphStyle, at: "Name") as! NSParagraphStyle).alignment, .left)
        XCTAssertNotEqual((attribute(.font, at: "Body") as! NSFont).familyName, NSFont.systemFont(ofSize: 18).familyName)
        XCTAssertTrue((attribute(.font, at: "inline") as! NSFont).isFixedPitch)
        XCTAssertEqual(attribute(.backgroundColor, at: "inline") as? NSColor, theme.color("codeBackground", fallback: .red))
        let codeBlock = (attribute(.paragraphStyle, at: "let value") as! NSParagraphStyle).textBlocks.first!
        XCTAssertEqual(codeBlock.backgroundColor, theme.color("codeBackground", fallback: .red))
        let tableBlock = (attribute(.paragraphStyle, at: "Name") as! NSParagraphStyle).textBlocks.first!
        XCTAssertEqual(tableBlock.backgroundColor, theme.color("codeBackground", fallback: .red))
        let snapshot = PreviewSnapshot(source: source.path, root: directory.path, text: "test", theme: theme)
        let decoded = try JSONDecoder().decode(PreviewSnapshot.self, from: JSONEncoder().encode(snapshot))
        XCTAssertEqual(decoded.theme?.colors, theme.colors)
        XCTAssertEqual(decoded.theme?.dark, true)
        for invalid in ["oops", "#gggggg", "#12345678"] {
            XCTAssertEqual(PreviewTheme(colors: ["code": invalid]).color("code", fallback: .red), .red)
        }
    }

    func testLocalResourceBoundaryAndImages() throws {
        let sibling = directory.deletingLastPathComponent().appendingPathComponent(directory.lastPathComponent + "-outside.md")
        try "secret".write(to: sibling, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sibling) }
        let escape = directory.appendingPathComponent("escape.md")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: sibling)
        let next = directory.appendingPathComponent("next file 日本語.md")
        try "next".write(to: next, atomically: true, encoding: .utf8)
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 20, height: 20).fill(); image.unlockFocus()
        let imageURL = directory.appendingPathComponent("sample.tiff")
        try image.tiffRepresentation!.write(to: imageURL)
        let paths = try PreviewPaths(source: source.path, root: directory.path)
        XCTAssertEqual(try paths.localResource("next%20file%20%E6%97%A5%E6%9C%AC%E8%AA%9E.md#heading"), next)
        XCTAssertEqual(try paths.localResource(next.path), next)
        XCTAssertEqual(try paths.localResource("#heading"), source)
        for denied in ["escape.md", "../\(sibling.lastPathComponent)", sibling.absoluteString,
                       "https://example.com/image.png", "http://example.com", "//example.com/file", "javascript:alert(1)",
                       "missing.md", "file://remotehost/etc/passwd", "%2e%2e/\(sibling.lastPathComponent)"] {
            XCTAssertThrowsError(try paths.localResource(denied), denied)
        }
        XCTAssertThrowsError(try PreviewPaths(source: escape.path, root: directory.path))
        let rendered = MarkdownRenderer(paths: paths).render("![red](sample.tiff) ![secret](escape.md) ![remote](https://example.com/a.png)")
        XCTAssertNotNil(rendered.attribute(.attachment, at: 0, effectiveRange: nil))
        let standalone = MarkdownRenderer(paths: paths).render("![red](sample.tiff)")
        XCTAssertEqual((standalone.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle).alignment, .center)
        XCTAssertTrue(rendered.string.contains("[Image: secret — escape.md]"))
        XCTAssertTrue(rendered.string.contains("[Image: remote — https://example.com/a.png]"))
    }
}
