import Foundation

/// How one language writes a quoted value: its delimiters and how a character inside is escaped.
public struct QuoteStyle: Sendable, Equatable {
    /// How a delimiter inside the value stays literal while the text is scanned.
    public enum Literal: Sendable, Equatable {
        case backslash
        case doubledClose
        case none
    }

    public let open: String
    public let close: String
    public let literal: Literal
    public let escapes: [Unicode.Scalar: String]

    public init(open: String, close: String, literal: Literal, escapes: [Unicode.Scalar: String]) {
        self.open = open
        self.close = close
        self.literal = literal
        self.escapes = escapes
    }

    /// SQL string literal: `'o''brien'`.
    public static let sql = QuoteStyle(open: "'", close: "'", literal: .doubledClose, escapes: ["'": "''"])

    /// POSIX shell single quotes, where a quote closes, is escaped, and reopens: `'it'\''s'`.
    public static let shellSingle = QuoteStyle(open: "'", close: "'", literal: .none, escapes: ["'": "'\\''"])

    /// POSIX shell double quotes, where `$`, backquote, `"` and `\` are escaped.
    public static let shellDouble = QuoteStyle(
        open: "\"", close: "\"", literal: .backslash,
        escapes: ["\"": "\\\"", "\\": "\\\\", "$": "\\$", "`": "\\`"])

    /// JSON string, every control character escaped as RFC 8259 requires.
    public static let json = QuoteStyle(
        open: "\"", close: "\"", literal: .backslash,
        escapes: controlEscapes(unicode: { String(format: "\\u%04x", $0) }).merging(
            ["\"": "\\\"", "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t"], uniquingKeysWith: { $1 }))

    /// Swift string literal.
    public static let swift = QuoteStyle(
        open: "\"", close: "\"", literal: .backslash,
        escapes: controlEscapes(unicode: { String(format: "\\u{%x}", $0) }).merging(
            ["\"": "\\\"", "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t", "\0": "\\0"],
            uniquingKeysWith: { $1 }))

    /// Python double-quoted string literal.
    public static let python = QuoteStyle(
        open: "\"", close: "\"", literal: .backslash,
        escapes: controlEscapes(unicode: { String(format: "\\x%02x", $0) }).merging(
            ["\"": "\\\"", "\\": "\\\\", "\n": "\\n", "\r": "\\r", "\t": "\\t"], uniquingKeysWith: { $1 }))

    /// Source-code string delimiters a scanner skips over, longest opener first.
    public static let sourceStrings: [QuoteStyle] = ["\"\"\"", "\"", "'", "`"].map {
        QuoteStyle(open: $0, close: $0, literal: .backslash, escapes: [:])
    }

    /// An escape for every C0 control character, written by `unicode` from its scalar value.
    private static func controlEscapes(unicode: (UInt32) -> String) -> [Unicode.Scalar: String] {
        Dictionary(
            uniqueKeysWithValues: (0..<0x20).compactMap { value in
                Unicode.Scalar(UInt32(value)).map { ($0, unicode(UInt32(value))) }
            })
    }
}

/// The one home for writing a value quoted and for finding quoted regions in text.
public enum Quoting {
    /// Word positions touched by a source string, including an unclosed or escaped quotation.
    package static func heldWords(_ words: [String]) -> Set<Int> {
        let text = words.joined(separator: " ")
        var regions = sourceRegions(in: text).makeIterator()
        var current = regions.next()
        var held = Set<Int>()
        for (position, span) in wordRanges(words, in: text).enumerated() {
            while let region = current, region.upperBound <= span.lowerBound { current = regions.next() }
            if let region = current, region.overlaps(span) { held.insert(position) }
        }
        return held
    }

    private static func sourceRegions(in text: String) -> [Range<String.Index>] {
        var regions: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            switch opening(in: text, at: index, styles: QuoteStyle.sourceStrings) {
            case .closed(let end):
                regions.append(index..<end)
                index = end
            case .unclosed:
                regions.append(index..<text.endIndex)
                return regions
            case .none: index = text.index(after: index)
            }
        }
        return regions
    }

    /// Ranges of already-tokenised words; layout marks may contain their own whitespace.
    private static func wordRanges(_ words: [String], in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        for (position, word) in words.enumerated() {
            let end = text.index(start, offsetBy: word.count)
            ranges.append(start..<end)
            start = position + 1 < words.count ? text.index(after: end) : end
        }
        return ranges
    }

    /// What opens at an index: no quote, a quote closed at `end`, or a quote left open to the end of the text.
    public enum Opening: Equatable {
        case none
        case closed(end: String.Index)
        case unclosed
    }

    /// The value written between the style's delimiters with every special character escaped.
    public static func write(_ value: String, style: QuoteStyle) -> String {
        var body = ""
        for scalar in value.unicodeScalars {
            body += style.escapes[scalar] ?? String(scalar)
        }
        return style.open + body + style.close
    }

    /// The value a `write` produced, or `nil` when the text is not one quoted value in this style.
    public static func read(_ quoted: String, style: QuoteStyle) -> String? {
        guard quoted.count >= style.open.count + style.close.count, quoted.hasPrefix(style.open),
            quoted.hasSuffix(style.close)
        else { return nil }
        let body = Array(quoted.dropFirst(style.open.count).dropLast(style.close.count).unicodeScalars)
        let close = Array(style.close.unicodeScalars)
        let writtenForms = style.escapes.map { ($0.key, Array($0.value.unicodeScalars)) }
            .sorted { $0.1.count > $1.1.count }
        var value = String.UnicodeScalarView()
        var index = 0
        while index < body.count {
            let rest = body[index...]
            if let (scalar, written) = writtenForms.first(where: { rest.starts(with: $0.1) }) {
                value.append(scalar)
                index += written.count
            } else if rest.starts(with: close) {
                return nil
            } else {
                value.append(body[index])
                index += 1
            }
        }
        return String(value)
    }

    /// Every balanced quoted region in the text, delimiters included; an unbalanced opener yields no region.
    public static func scan(_ text: String, style: QuoteStyle) -> [Range<String.Index>] {
        var regions: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            switch opening(in: text, at: index, styles: [style]) {
            case .closed(let end):
                regions.append(index..<end)
                index = end
            case .unclosed:
                return regions
            case .none:
                index = text.index(after: index)
            }
        }
        return regions
    }

    /// Whether the first style whose opener sits at `index` opens a quote there, and where it closes.
    public static func opening(in text: String, at index: String.Index, styles: [QuoteStyle]) -> Opening {
        guard let style = styles.first(where: { text[index...].hasPrefix($0.open) }) else { return .none }
        var cursor = text.index(index, offsetBy: style.open.count)
        while cursor < text.endIndex {
            if style.literal == .backslash, text[cursor] == "\\" {
                cursor = text.index(cursor, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
            } else if text[cursor...].hasPrefix(style.close) {
                let end = text.index(cursor, offsetBy: style.close.count)
                guard style.literal == .doubledClose, text[end...].hasPrefix(style.close) else {
                    return .closed(end: end)
                }
                cursor = text.index(end, offsetBy: style.close.count)
            } else {
                cursor = text.index(after: cursor)
            }
        }
        return .unclosed
    }
}
