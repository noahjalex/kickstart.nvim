import AppKit
import XCTest
@testable import PreviewCore

/// Check the exact manual comparison documents without launching a window or touching the clipboard.
final class MermaidComparisonTests: XCTestCase {
    func testManualComparisonDocumentsRenderDiagrams() throws {
        _ = NSApplication.shared
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        for (filename, expected) in [("representative.md", 1), ("mermaid-comparison.md", 4)] {
            let source = tests.appendingPathComponent(filename)
            let renderer = MarkdownRenderer(paths: try PreviewPaths(source: source.path, root: tests.path))
            let rendered = renderer.render(try String(contentsOf: source, encoding: .utf8))
            var diagrams = 0
            rendered.enumerateAttribute(.attachment, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
                if let attachment = value as? NSTextAttachment {
                    diagrams += 1
                    XCTAssertNotNil(attachment.image)
                    XCTAssertGreaterThan(attachment.bounds.width, 0)
                    XCTAssertGreaterThan(attachment.bounds.height, 0)
                }
            }
            XCTAssertEqual(diagrams, expected, "Manual fixture unexpectedly fell back to source: \(filename)")
        }
    }
}
