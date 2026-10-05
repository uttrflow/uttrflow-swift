// MARK: - Tokenising

/// One start or end tag with all of its attributes.
struct HTMLTag {
    var name: String
    var isClosing: Bool
    var attributes: [String: String]

    func attribute(_ name: String) -> String? { attributes[name] }

    /// The `class` attribute split into tokens, because `unchecked` contains `checked`.
    var classes: [String] {
        (attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

enum HTMLToken {
    case text(String)
    case tag(HTMLTag)
}

/// A single forward pass over the source; `<` begins a tag only when a tag name could follow.
struct HTMLTokenizer {
    private let scalars: [Unicode.Scalar]
    private let count: Int
    private var index = 0
    /// Set after a `<script>`, `<style>` or `<title>` start tag, so their contents are skipped whole.
    private var rawTextElement: String?

    init(_ html: String) {
        scalars = Array(html.unicodeScalars)
        count = scalars.count
    }

    mutating func next() -> HTMLToken? {
        while index < count {
            if let element = rawTextElement {
                rawTextElement = nil
                skipToEndTag(of: element)
                continue
            }
            guard isMarkupStart(index) else { return .text(readText()) }
            guard let tag = readTag() else { continue }
            if !tag.isClosing, Self.rawTextElements.contains(tag.name) {
                rawTextElement = tag.name
            }
            return .tag(tag)
        }
        return nil
    }

    private static let rawTextElements: Set<String> = ["script", "style", "title"]

    /// Whether anything in the input is HTML: a known element, or any end tag, which code never has.
    mutating func looksLikeMarkup() -> Bool {
        defer { index = 0 }
        var i = 0
        while i < count {
            defer { i += 1 }
            guard isMarkupStart(i), let shape = tagShape(at: i) else { continue }
            if shape.isClosing || HTMLElements.names.contains(shape.name) { return true }
        }
        return false
    }

    private func tagShape(at start: Int) -> (name: String, isClosing: Bool)? {
        var i = start + 1
        let shape = readTagName(from: &i)
        return shape.name.isEmpty ? nil : shape
    }

    /// The optional `/` and the name after a `<`, lowercased, advancing `i` past both.
    private func readTagName(from i: inout Int) -> (name: String, isClosing: Bool) {
        let isClosing = scalars[i] == "/"
        if isClosing { i += 1 }
        var name = String.UnicodeScalarView()
        while i < count, isNameScalar(scalars[i]) {
            name.append(scalars[i])
            i += 1
        }
        return (String(name).lowercased(), isClosing)
    }

    // MARK: Text

    private mutating func readText() -> String {
        var raw = String.UnicodeScalarView()
        while index < count, !isMarkupStart(index) {
            raw.append(scalars[index])
            index += 1
        }
        return HTMLEntities.decoding(String(raw))
    }

    /// Whether the `<` at `i` opens markup; a space after it means `a < b` is prose.
    private func isMarkupStart(_ i: Int) -> Bool {
        guard scalars[i] == "<", i + 1 < count else { return false }
        let next = scalars[i + 1]
        if isNameStart(next) || next == "!" || next == "?" { return true }
        return next == "/" && i + 2 < count && isNameStart(scalars[i + 2])
    }

    // MARK: Markup

    /// Reads whatever the `<` at `index` opens; comments, doctypes and unclosed tags yield nothing.
    private mutating func readTag() -> HTMLTag? {
        let next = scalars[index + 1]
        if next == "!" {
            if matches("<!--", at: index) {
                skip(past: "-->")
            } else {
                skip(past: ">")
            }
            return nil
        }
        if next == "?" {
            skip(past: ">")
            return nil
        }

        var i = index + 1
        let (name, isClosing) = readTagName(from: &i)

        var attributes: [String: String] = [:]
        var closed = false
        while i < count {
            while i < count, isSpace(scalars[i]) { i += 1 }
            guard i < count else { break }
            if scalars[i] == ">" {
                i += 1
                closed = true
                break
            }
            // A solidus is either the one in `<br/>` or junk; either way it names nothing.
            if scalars[i] == "/" {
                i += 1
                continue
            }
            let attribute = readAttribute(from: &i)
            if let attribute { attributes[attribute.0] = attribute.1 }
        }

        guard closed else {
            index = count
            return nil
        }
        index = i
        return HTMLTag(name: name, isClosing: isClosing, attributes: attributes)
    }

    /// One attribute pair, reading a quoted value to its quote so `title="a > b"` closes at the quote.
    private func readAttribute(from i: inout Int) -> (String, String)? {
        var name = String.UnicodeScalarView()
        while i < count, !isSpace(scalars[i]), !"=>/".unicodeScalars.contains(scalars[i]) {
            name.append(scalars[i])
            i += 1
        }
        guard !name.isEmpty else {
            // A stray `=` or quote where a name should be; step over it so the loop cannot stall.
            i += 1
            return nil
        }

        while i < count, isSpace(scalars[i]) { i += 1 }
        var value = String.UnicodeScalarView()
        if i < count, scalars[i] == "=" {
            i += 1
            while i < count, isSpace(scalars[i]) { i += 1 }
            if i < count, scalars[i] == "\"" || scalars[i] == "'" {
                let quote = scalars[i]
                i += 1
                while i < count, scalars[i] != quote {
                    value.append(scalars[i])
                    i += 1
                }
                if i < count { i += 1 }
            } else {
                while i < count, !isSpace(scalars[i]), scalars[i] != ">" {
                    value.append(scalars[i])
                    i += 1
                }
            }
        }
        return (String(name).lowercased(), HTMLEntities.decoding(String(value)))
    }

    // MARK: Skipping

    private mutating func skip(past terminator: String) {
        let target = Array(terminator.unicodeScalars)
        index = position(of: target, from: index + 1).map { $0 + target.count } ?? count
    }

    /// Runs to the end tag of a raw-text element, or to the end of the input if it never closes.
    private mutating func skipToEndTag(of name: String) {
        let target = Array("</\(name)".unicodeScalars)
        var searchFrom = index
        while let candidate = position(of: target, from: searchFrom, ignoringCase: true) {
            let afterName = candidate + target.count
            if afterName == count || isSpace(scalars[afterName]) || scalars[afterName] == "/"
                || scalars[afterName] == ">"
            {
                index = candidate
                return
            }
            searchFrom = candidate + 1
        }
        index = count
    }

    /// Where `target` next begins at or after `start`, or `nil` when it never does.
    private func position(of target: [Unicode.Scalar], from start: Int, ignoringCase: Bool = false) -> Int? {
        var i = start
        while i + target.count <= count {
            if matches(target, at: i, ignoringCase: ignoringCase) { return i }
            i += 1
        }
        return nil
    }

    private func matches(_ literal: String, at i: Int) -> Bool {
        matches(Array(literal.unicodeScalars), at: i)
    }

    private func matches(_ target: [Unicode.Scalar], at i: Int, ignoringCase: Bool = false) -> Bool {
        guard i + target.count <= count else { return false }
        for offset in 0..<target.count {
            let found = scalars[i + offset]
            let wanted = target[offset]
            if found == wanted { continue }
            guard ignoringCase, sameLetter(found, wanted) else { return false }
        }
        return true
    }

    private func sameLetter(_ a: Unicode.Scalar, _ b: Unicode.Scalar) -> Bool {
        a.properties.isAlphabetic && String(a).lowercased() == String(b).lowercased()
    }

    private func isSpace(_ scalar: Unicode.Scalar) -> Bool { scalar.properties.isWhitespace }

    private func isNameStart(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }

    private func isNameScalar(_ scalar: Unicode.Scalar) -> Bool {
        isNameStart(scalar) || ("0"..."9").contains(scalar) || scalar == "-" || scalar == ":"
    }
}

// MARK: - Elements

enum HTMLElements {
    /// Every element HTML defines, obsolete ones included; generous, because a miss leaves tags showing.
    static let names: Set<String> = [
        "a", "abbr", "acronym", "address", "applet", "area", "article", "aside", "audio",
        "b", "base", "basefont", "bdi", "bdo", "big", "blockquote", "body", "br", "button",
        "canvas", "caption", "center", "cite", "code", "col", "colgroup", "data", "datalist",
        "dd", "del", "details", "dfn", "dialog", "dir", "div", "dl", "dt", "em", "embed",
        "fieldset", "figcaption", "figure", "font", "footer", "form", "frame", "frameset",
        "h1", "h2", "h3", "h4", "h5", "h6", "head", "header", "hgroup", "hr", "html", "i",
        "iframe", "img", "input", "ins", "kbd", "label", "legend", "li", "link", "main",
        "map", "mark", "marquee", "menu", "meta", "meter", "nav", "nobr", "noframes",
        "noscript", "object", "ol", "optgroup", "option", "output", "p", "param", "picture",
        "pre", "progress", "q", "rp", "rt", "ruby", "s", "samp", "script", "search",
        "section", "select", "slot", "small", "source", "span", "strike", "strong", "style",
        "sub", "summary", "sup", "table", "tbody", "td", "template", "textarea", "tfoot",
        "th", "thead", "time", "title", "tr", "track", "tt", "u", "ul", "var", "video", "wbr",
    ]
}

// MARK: - Entities

enum HTMLEntities {
    /// Decodes every entity in one pass and never re-reads its output, so `&amp;amp;` yields `&amp;`.
    static func decoding(_ raw: String) -> String {
        guard raw.utf8.contains(UInt8(ascii: "&")) else { return raw }

        var out = String.UnicodeScalarView()
        let scalars = Array(raw.unicodeScalars)
        var i = 0
        while i < scalars.count {
            guard scalars[i] == "&", let decoded = decodeReference(scalars, at: i) else {
                out.append(scalars[i])
                i += 1
                continue
            }
            out.append(contentsOf: decoded.replacement.unicodeScalars)
            i = decoded.end
        }
        return String(out)
    }

    /// The reference beginning at `start`, or nothing; an unknown name stays as written, so `AT&T` survives.
    private static func decodeReference(
        _ scalars: [Unicode.Scalar], at start: Int
    ) -> (replacement: String, end: Int)? {
        // The bound stops a stray ampersand scanning the rest of a large clip for a `;`.
        let limit = min(scalars.count, start + 12)
        var i = start + 1
        var body = String.UnicodeScalarView()
        while i < limit, scalars[i] != ";" {
            body.append(scalars[i])
            i += 1
        }
        guard i < limit, scalars[i] == ";", !body.isEmpty else { return nil }
        guard let replacement = expand(String(body)) else { return nil }
        return (replacement, i + 1)
    }

    private static func expand(_ body: String) -> String? {
        guard body.hasPrefix("#") else { return named[body.lowercased()] }
        let digits = body.dropFirst()
        let value: UInt32?
        if digits.first == "x" || digits.first == "X" {
            value = UInt32(digits.dropFirst(), radix: 16)
        } else {
            value = UInt32(digits, radix: 10)
        }
        guard let value, let scalar = Unicode.Scalar(value) else { return nil }
        // A C0 control other than tab or newline decodes to nothing; it does real damage in a terminal.
        if value < 0x20, value != 0x09, value != 0x0A { return "" }
        return String(scalar)
    }

    /// The named entities copied text carries; `nbsp` decodes to a plain space and the joiners to themselves.
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ensp": " ", "emsp": " ", "thinsp": " ", "shy": "", "zwnj": "\u{200C}", "zwj": "\u{200D}",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}", "bull": "\u{2022}",
        "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}", "rdquo": "\u{201D}",
        "laquo": "\u{00AB}", "raquo": "\u{00BB}", "middot": "\u{00B7}", "sect": "\u{00A7}",
        "para": "\u{00B6}", "dagger": "\u{2020}", "copy": "\u{00A9}", "reg": "\u{00AE}",
        "trade": "\u{2122}", "deg": "\u{00B0}", "times": "\u{00D7}", "divide": "\u{00F7}",
        "plusmn": "\u{00B1}", "euro": "\u{20AC}", "pound": "\u{00A3}", "yen": "\u{00A5}",
        "cent": "\u{00A2}", "frac12": "\u{00BD}", "frac14": "\u{00BC}", "rarr": "\u{2192}",
        "larr": "\u{2190}", "harr": "\u{2194}", "check": "\u{2713}",
    ]
}
