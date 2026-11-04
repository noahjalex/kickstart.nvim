import AppKit
import Markdown

/// A buffer snapshot; root stays fixed during link navigation and subsequent edits.
public struct PreviewSnapshot: Codable {
    public let source: String
    public let root: String
    public let text: String
    public let opacity: Double
    public let activate: Bool

    public init(source: String, root: String, text: String, opacity: Double = 0.96, activate: Bool = true) {
        self.source = source
        self.root = root
        self.text = text
        self.opacity = opacity
        self.activate = activate
    }
}

/// Resolves local resources after symlinks, with a component-wise inferred-root boundary.
public struct PreviewPaths {
    public let source: URL
    public let root: URL

    public init(source: String, root: String) throws {
        guard source.hasPrefix("/"), root.hasPrefix("/") else {
            throw PreviewError.rejected("source and root must be absolute paths")
        }
        self.root = URL(fileURLWithPath: root).resolvingSymlinksInPath().standardizedFileURL
        self.source = URL(fileURLWithPath: source).resolvingSymlinksInPath().standardizedFileURL
        try requireInsideRoot(self.source)
    }

    public func requireInsideRoot(_ url: URL) throws {
        let base = root.pathComponents
        guard Array(url.pathComponents.prefix(base.count)) == base,
              FileManager.default.isReadableFile(atPath: url.path) else {
            throw PreviewError.rejected("missing, unreadable, or outside inferred root: \(url.path)")
        }
    }

    public func localResource(_ destination: String) throws -> URL {
        guard !destination.hasPrefix("//"),
              let url = URL(string: destination, relativeTo: source)?.absoluteURL,
              url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else {
            throw PreviewError.rejected("only local resources and external HTTPS links are allowed")
        }
        let target = URL(fileURLWithPath: url.path).resolvingSymlinksInPath().standardizedFileURL
        try requireInsideRoot(target)
        return target
    }
}

public enum PreviewError: LocalizedError {
    case rejected(String)
    public var errorDescription: String? {
        switch self { case .rejected(let reason): return "Markdown preview: \(reason)" }
    }
}

/// Renders swift-markdown into native attributed text; unknown nodes fall back to readable Markdown.
public struct MarkdownRenderer {
    public let paths: PreviewPaths
    public init(paths: PreviewPaths) { self.paths = paths }

    public func render(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 8
        paragraph.lineSpacing = 3
        return renderNode(Document(parsing: text), attributes: [
            .font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.labelColor.withAlphaComponent(1),
            .paragraphStyle: paragraph,
        ])
    }

    private func renderNode(_ node: Markup, attributes: [NSAttributedString.Key: Any]) -> NSMutableAttributedString {
        var attrs = attributes
        let output = NSMutableAttributedString(string: "")
        func append(_ string: String) { output.append(NSAttributedString(string: string, attributes: attrs)) }
        func children() {
            for child in node.children { output.append(renderNode(child, attributes: attrs)) }
        }
        func paragraphStyle() -> NSMutableParagraphStyle {
            (attrs[.paragraphStyle] as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
        }
        func fontTrait(_ trait: NSFontTraitMask) {
            attrs[.font] = NSFontManager.shared.convert(attrs[.font] as! NSFont, toHaveTrait: trait)
        }
        switch node {
        case let text as Markdown.Text: append(text.string)
        case is SoftBreak: append(" ")
        case is LineBreak: append("\n")
        case let heading as Heading:
            attrs[.font] = NSFont.boldSystemFont(ofSize: [30.0, 25, 21, 19, 17, 16][min(5, max(0, heading.level - 1))])
            children(); append("\n")
        case is Strong: fontTrait(.boldFontMask); children()
        case is Emphasis: fontTrait(.italicFontMask); children()
        case is Strikethrough: attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue; children()
        case let code as InlineCode:
            attrs[.font] = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            append(code.code)
        case let code as CodeBlock:
            attrs[.font] = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            let style = paragraphStyle(); style.headIndent += 12; style.firstLineHeadIndent = style.headIndent
            attrs[.paragraphStyle] = style
            append(code.code); if !code.code.hasSuffix("\n") { append("\n") }
        case let link as Markdown.Link:
            attrs[.link] = link.destination
            children()
        case let image as Markdown.Image:
            let alt = image.plainText
            if let destination = image.source, let url = try? paths.localResource(destination),
               let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20 * 1024 * 1024,
               let nativeImage = NSImage(contentsOf: url), nativeImage.size.width > 0, nativeImage.size.height > 0 {
                let scale = min(1, 640 / nativeImage.size.width, 480 / nativeImage.size.height)
                let attachment = NSTextAttachment()
                attachment.image = nativeImage
                attachment.bounds = NSRect(x: 0, y: 0, width: nativeImage.size.width * scale, height: nativeImage.size.height * scale)
                output.append(NSAttributedString(attachment: attachment))
            } else {
                append("[Image: \(alt) — \(image.source ?? "missing source")]")
            }
        case is BlockQuote:
            let style = paragraphStyle(); style.headIndent += 20; style.firstLineHeadIndent = style.headIndent
            attrs[.paragraphStyle] = style
            append("▎ "); children()
        case is OrderedList, is UnorderedList:
            let start = (node as? OrderedList)?.startIndex ?? 1
            for (index, item) in node.children.enumerated() {
                let style = paragraphStyle(); style.firstLineHeadIndent = style.headIndent; style.headIndent += 24
                var itemAttrs = attrs; itemAttrs[.paragraphStyle] = style
                let checkbox = (item as? ListItem)?.checkbox
                let marker = checkbox.map { $0 == .checked ? "☑ " : "☐ " }
                    ?? (node is OrderedList ? "\(start + UInt(index)). " : "• ")
                output.append(NSAttributedString(string: marker, attributes: itemAttrs))
                output.append(renderNode(item, attributes: itemAttrs))
            }
        case let table as Table:
            let nativeTable = NSTextTable()
            nativeTable.numberOfColumns = max(1, table.head.childCount)
            nativeTable.collapsesBorders = true
            let rows = [Array(table.head.cells)] + table.body.rows.map { Array($0.cells) }
            for (rowIndex, row) in rows.enumerated() {
                for (column, cell) in row.enumerated() {
                    let block = NSTextTableBlock(table: nativeTable, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                    block.setWidth(6, type: .absoluteValueType, for: .padding)
                    block.setWidth(0.5, type: .absoluteValueType, for: .border)
                    block.setBorderColor(.separatorColor)
                    let style = paragraphStyle(); style.textBlocks = [block]
                    var cellAttrs = attrs; cellAttrs[.paragraphStyle] = style
                    if rowIndex == 0 { cellAttrs[.font] = NSFont.boldSystemFont(ofSize: 16) }
                    output.append(renderNode(cell, attributes: cellAttrs))
                    output.append(NSAttributedString(string: "\n", attributes: cellAttrs))
                }
            }
            append("\n")
        case is Paragraph: children(); append("\n")
        case is Document, is ListItem, is Table.Cell: children()
        case is ThematicBreak: append("────────────\n")
        case let html as HTMLBlock: append(html.rawHTML + "\n")
        case let html as InlineHTML: append(html.rawHTML)
        default:
            // Unknown constructs stay visible instead of silently dropping their contents.
            append(node.format())
        }
        return output
    }
}
