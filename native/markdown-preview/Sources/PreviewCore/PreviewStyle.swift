import AppKit

/// Font configuration uses installed family/PostScript names; unavailable fonts keep native fallbacks.
public struct PreviewFontStyle: Decodable {
    public var family: String?
    public var size: Double?
    public var weight: String?
    public var italic: Bool?

    func font(fallback: NSFont) -> NSFont {
        let points = CGFloat(size.flatMap { $0.isFinite && (8...96).contains($0) ? $0 : nil } ?? Double(fallback.pointSize))
        var font = family.flatMap { NSFont(name: $0, size: points) }
            ?? NSFont(descriptor: fallback.fontDescriptor, size: points) ?? fallback
        if let weight {
            let weights = ["regular": 5, "medium": 6, "semibold": 8, "bold": 9]
            if let value = weights[weight], let family = font.familyName {
                let traits = NSFontManager.shared.traits(of: font).subtracting(.boldFontMask)
                font = NSFontManager.shared.font(withFamily: family, traits: traits, weight: value, size: points) ?? font
            }
        }
        if italic == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }
}

/// Typography configuration is loaded once at launch; omitted fields retain the article defaults.
public struct PreviewStyle: Decodable {
    public var body: PreviewFontStyle?
    public var heading: PreviewFontStyle?
    public var code: PreviewFontStyle?
    public var table: PreviewFontStyle?
    public var articleWidth: Double?
    public var lineHeight: Double?
    public var paragraphSpacing: Double?
    public var cornerRadius: Double?

    public init() {}

    public static func load(from url: URL) throws -> PreviewStyle {
        try JSONDecoder().decode(PreviewStyle.self, from: Data(contentsOf: url))
    }

    public var readingWidth: CGFloat { bounded(articleWidth, fallback: 680, range: 320...1600) }
    var leading: CGFloat { bounded(lineHeight, fallback: 30, range: 12...120) }
    var paragraphGap: CGFloat { bounded(paragraphSpacing, fallback: 24, range: 0...120) }
    var radius: CGFloat { bounded(cornerRadius, fallback: 10, range: 0...32) }

    private func bounded(_ value: Double?, fallback: Double, range: ClosedRange<Double>) -> CGFloat {
        CGFloat(value.flatMap { $0.isFinite && range.contains($0) ? $0 : nil } ?? fallback)
    }
}

/// Rounded code backgrounds remain native text blocks, preserving selection and wrapping.
final class RoundedCodeBlock: NSTextBlock {
    var radius: CGFloat = 10
    var outline: NSColor = .separatorColor

    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView?, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        let path = NSBezierPath(roundedRect: frameRect.insetBy(dx: 8.5, dy: 8.5), xRadius: radius, yRadius: radius)
        backgroundColor?.setFill(); path.fill()
        outline.setStroke(); path.lineWidth = 1; path.stroke()
    }
}

/// Enclosed native tables round only their four exterior corners, never the individual interior cells.
final class RoundedPreviewTable: NSTextTable {
    var rowCount = 1
    var radius: CGFloat = 10
    var outline: NSColor = .separatorColor

    override func drawBackground(for block: NSTextTableBlock, withFrame frameRect: NSRect, in controlView: NSView, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        // TextKit clips painting to the cell frame; keep the entire outline inside it.
        let rect = frameRect.insetBy(dx: 0.5, dy: 0.5)
        let first = block.startingRow == 0
        let last = block.startingRow == rowCount - 1
        let left = block.startingColumn == 0
        let right = block.startingColumn == numberOfColumns - 1
        let top = controlView.isFlipped ? first : last
        let bottom = controlView.isFlipped ? last : first
        let r = min(radius, rect.width / 2, rect.height / 2)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        for (corner, next, rounded) in [
            (CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.midY), top && right),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY), bottom && right),
            (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY), bottom && left),
            (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), top && left),
        ] {
            if rounded { path.addArc(tangent1End: corner, tangent2End: next, radius: r) }
            else { path.addLine(to: corner) }
        }
        path.closeSubpath()
        context.saveGState()
        context.addPath(path)
        context.setFillColor((block.backgroundColor ?? .clear).cgColor)
        context.setStrokeColor(outline.cgColor)
        context.setLineWidth(1)
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }
}
