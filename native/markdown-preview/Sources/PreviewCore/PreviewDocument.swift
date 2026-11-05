import AppKit
import Markdown

/// Resolved Neovim highlight colors captured at launch; absent colors use native defaults.
public struct PreviewTheme: Codable {
    public let dark: Bool
    public let colors: [String: String]

    public init(dark: Bool = false, colors: [String: String] = [:]) {
        self.dark = dark
        self.colors = colors
    }

    public func color(_ name: String, fallback: NSColor) -> NSColor {
        guard let hex = colors[name], hex.count == 7, hex.first == "#",
              let rgb = UInt32(hex.dropFirst(), radix: 16) else { return fallback.withAlphaComponent(1) }
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255,
                       blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }
}

/// A buffer snapshot; root and launch theme stay fixed during link navigation and subsequent edits.
public struct PreviewSnapshot: Codable {
    public let source: String
    public let root: String
    public let text: String
    public let opacity: Double
    public let activate: Bool
    public let theme: PreviewTheme?
    public let highlights: [PreviewCodeHighlight]?

    public init(source: String, root: String, text: String, opacity: Double = 0.96, activate: Bool = true, theme: PreviewTheme? = nil, highlights: [PreviewCodeHighlight]? = nil) {
        self.source = source
        self.root = root
        self.text = text
        self.opacity = opacity
        self.activate = activate
        self.theme = theme
        self.highlights = highlights
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
    public let theme: PreviewTheme
    public let style: PreviewStyle
    public let highlights: [PreviewCodeHighlight]

    public init(paths: PreviewPaths, theme: PreviewTheme = PreviewTheme(), style: PreviewStyle = PreviewStyle(), highlights: [PreviewCodeHighlight] = []) {
        self.paths = paths
        self.theme = theme
        self.style = style
        self.highlights = highlights
    }

    private var bodyFont: NSFont {
        let font = NSFont.systemFont(ofSize: 18)
        let serif = font.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 18) } ?? font
        return style.body?.font(fallback: serif) ?? serif
    }

    public func render(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = style.paragraphGap
        paragraph.minimumLineHeight = max(style.leading, bodyFont.pointSize * 1.3)
        return renderNode(Document(parsing: text), attributes: [
            .font: bodyFont, .foregroundColor: theme.color("foreground", fallback: .labelColor),
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
            let level = min(5, max(0, heading.level - 1))
            let size = [40.0, 30, 24, 20, 18, 18][level]
            let fallback = NSFont.systemFont(ofSize: 40, weight: .semibold)
            let headingFont = style.heading?.font(fallback: fallback) ?? fallback
            // A configured heading size is the H1 size; preserve the hierarchy below it.
            attrs[.font] = NSFont(descriptor: headingFont.fontDescriptor, size: headingFont.pointSize * size / 40) ?? headingFont
            attrs[.kern] = -0.4
            attrs[.foregroundColor] = theme.color("heading\(heading.level)", fallback: .labelColor)
            let style = paragraphStyle()
            style.minimumLineHeight = (attrs[.font] as! NSFont).pointSize * 1.25
            style.paragraphSpacingBefore = heading.indexInParent == 0 ? 0 : [32.0, 32, 24, 20, 16, 16][level]
            style.paragraphSpacing = [24.0, 16, 12, 8, 8, 8][level]
            attrs[.paragraphStyle] = style
            children(); append("\n")
        case is Strong: fontTrait(.boldFontMask); children()
        case is Emphasis: fontTrait(.italicFontMask); children()
        case is Strikethrough: attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue; children()
        case let code as InlineCode:
            attrs[.font] = style.code?.font(fallback: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)) ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
            attrs[.foregroundColor] = theme.color("code", fallback: .systemPink)
            attrs[.backgroundColor] = theme.color("codeBackground", fallback: .controlBackgroundColor)
            append(code.code)
        case let code as CodeBlock:
            let codeFont = style.code?.font(fallback: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)) ?? NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
            attrs[.font] = codeFont
            attrs[.foregroundColor] = theme.color("foreground", fallback: .labelColor)
            let block = RoundedCodeBlock()
            block.radius = style.radius
            block.outline = theme.color("border", fallback: .separatorColor)
            // TextKit otherwise gives a standalone block zero content width, wrapping every character.
            block.setContentWidth(100, type: .percentageValueType)
            block.backgroundColor = theme.color("codeBackground", fallback: .controlBackgroundColor)
            block.setWidth(16, type: .absoluteValueType, for: .padding)
            block.setWidth(8, type: .absoluteValueType, for: .margin)
            let style = paragraphStyle()
            style.minimumLineHeight = max(24, codeFont.pointSize * 1.5); style.lineSpacing = 0; style.paragraphSpacing = 0
            style.textBlocks += [block]
            attrs[.paragraphStyle] = style
            append(code.code)
            let language = code.language?.components(separatedBy: .whitespaces).first ?? ""
            if let highlight = highlights.first(where: { $0.language == language && $0.code == code.code }) {
                highlight.apply(to: output, font: codeFont)
            }
            if !code.code.hasSuffix("\n") { append("\n") }
        case let link as Markdown.Link:
            attrs[.link] = link.destination
            attrs[.foregroundColor] = theme.color("link", fallback: .linkColor)
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
                let imageText = NSMutableAttributedString(attributedString: NSAttributedString(attachment: attachment))
                imageText.addAttributes(attrs, range: NSRange(location: 0, length: imageText.length))
                output.append(imageText)
            } else {
                append("[Image: \(alt) — \(image.source ?? "missing source")]")
            }
        case is BlockQuote:
            let foreground = theme.color("foreground", fallback: .labelColor)
            attrs[.foregroundColor] = theme.color("quote", fallback: .secondaryLabelColor).blended(withFraction: 0.6, of: foreground) ?? foreground
            fontTrait(.italicFontMask)
            let block = NSTextBlock()
            block.setContentWidth(100, type: .percentageValueType)
            block.setWidth(3, type: .absoluteValueType, for: .border, edge: .minX)
            block.setBorderColor(theme.color("border", fallback: .separatorColor))
            block.setWidth(18, type: .absoluteValueType, for: .padding, edge: .minX)
            let style = paragraphStyle(); style.textBlocks += [block]
            attrs[.paragraphStyle] = style
            children()
        case is OrderedList, is UnorderedList:
            let start = (node as? OrderedList)?.startIndex ?? 1
            for (index, item) in node.children.enumerated() {
                let style = paragraphStyle(); style.firstLineHeadIndent = style.headIndent; style.headIndent += 28
                style.paragraphSpacing = index == node.childCount - 1 ? 24 : 6
                var itemAttrs = attrs; itemAttrs[.paragraphStyle] = style
                let checkbox = (item as? ListItem)?.checkbox
                let marker = checkbox.map { $0 == .checked ? "☑ " : "☐ " }
                    ?? (node is OrderedList ? "\(start + UInt(index)). " : "• ")
                output.append(NSAttributedString(string: marker, attributes: itemAttrs))
                output.append(renderNode(item, attributes: itemAttrs))
            }
        case let table as Table:
            let nativeTable = RoundedPreviewTable()
            nativeTable.radius = style.radius
            nativeTable.outline = theme.color("border", fallback: .separatorColor)
            nativeTable.numberOfColumns = max(1, table.head.childCount)
            nativeTable.collapsesBorders = true
            nativeTable.setContentWidth(100, type: .percentageValueType)
            let rows = [Array(table.head.cells)] + table.body.rows.map { Array($0.cells) }
            nativeTable.rowCount = rows.count
            for (rowIndex, row) in rows.enumerated() {
                for (column, cell) in row.enumerated() {
                    let block = NSTextTableBlock(table: nativeTable, startingRow: rowIndex, rowSpan: 1, startingColumn: column, columnSpan: 1)
                    block.setWidth(12, type: .absoluteValueType, for: .padding)
                    let canvas = theme.color("background", fallback: .textBackgroundColor)
                    let shade = theme.color("codeBackground", fallback: .controlBackgroundColor)
                    block.backgroundColor = rowIndex == 0 ? shade : (rowIndex % 2 == 0 ? canvas.blended(withFraction: 0.45, of: shade) : canvas)
                    let style = paragraphStyle(); style.textBlocks = [block]
                    style.minimumLineHeight = 24; style.paragraphSpacing = 0
                    let alignment = column < table.columnAlignments.count ? table.columnAlignments[column] : nil
                    switch alignment {
                    case .center: style.alignment = .center
                    case .right: style.alignment = .right
                    default: style.alignment = .left
                    }
                    var cellAttrs = attrs; cellAttrs[.paragraphStyle] = style
                    let fallback = NSFont.systemFont(ofSize: 15, weight: rowIndex == 0 ? .semibold : .regular)
                    var tableFont = self.style.table?.font(fallback: fallback) ?? fallback
                    if rowIndex == 0 { tableFont = NSFontManager.shared.convert(tableFont, toHaveTrait: .boldFontMask) }
                    cellAttrs[.font] = tableFont
                    output.append(renderNode(cell, attributes: cellAttrs))
                    output.append(NSAttributedString(string: "\n", attributes: cellAttrs))
                }
            }
            append("\n")
        case is Paragraph:
            if node.childCount == 1, node.child(at: 0) is Markdown.Image {
                let style = paragraphStyle(); style.alignment = .center
                attrs[.paragraphStyle] = style
            }
            children(); append("\n")
        case is Document, is ListItem, is Table.Cell: children()
        case is ThematicBreak:
            let block = NSTextBlock()
            block.setContentWidth(100, type: .percentageValueType)
            block.setWidth(0.5, type: .absoluteValueType, for: .border, edge: .minY)
            block.setBorderColor(theme.color("border", fallback: .separatorColor))
            let style = paragraphStyle(); style.textBlocks = [block]
            style.minimumLineHeight = 1; style.paragraphSpacingBefore = 24; style.paragraphSpacing = 24
            attrs[.font] = NSFont.systemFont(ofSize: 1)
            attrs[.paragraphStyle] = style
            append("\u{200b}\n")
        case let html as HTMLBlock: append(html.rawHTML + "\n")
        case let html as InlineHTML: append(html.rawHTML)
        default:
            // Unknown constructs stay visible instead of silently dropping their contents.
            append(node.format())
        }
        return output
    }
}
