import AppKit

/// Tree-sitter captures use UTF-8 byte offsets relative to the exact fenced code string.
public struct PreviewSyntaxSpan: Codable {
    public let start: Int
    public let end: Int
    public let color: String?
    public let bold: Bool?
    public let italic: Bool?
}

/// Code text and language identify a fence; unknown/missing parsers produce no captures.
public struct PreviewCodeHighlight: Codable {
    public let code: String
    public let language: String
    public let spans: [PreviewSyntaxSpan]

    func apply(to output: NSMutableAttributedString, font: NSFont) {
        let bytes = Data(output.string.utf8)
        // ponytail: prefix decoding per capture; precompute UTF-8/UTF-16 offsets if large fences lag.
        for span in spans {
            guard span.start >= 0, span.end > span.start, span.end <= bytes.count,
                  let prefix = String(data: bytes.prefix(span.start), encoding: .utf8),
                  let token = String(data: bytes.subdata(in: span.start..<span.end), encoding: .utf8) else { continue }
            let range = NSRange(location: prefix.utf16.count, length: token.utf16.count)
            if let color = span.color {
                output.addAttribute(.foregroundColor, value: PreviewTheme(colors: ["token": color]).color("token", fallback: .labelColor), range: range)
            }
            var tokenFont = font
            if span.bold == true { tokenFont = NSFontManager.shared.convert(tokenFont, toHaveTrait: .boldFontMask) }
            if span.italic == true { tokenFont = NSFontManager.shared.convert(tokenFont, toHaveTrait: .italicFontMask) }
            if span.bold == true || span.italic == true { output.addAttribute(.font, value: tokenFont, range: range) }
        }
    }
}
