/// The plain text of a rich clip, for a target with no formatting. See Docs/clipboard-plain-form.md.
public enum RichTextPlainForm: Sendable {
    /// The readable plain-text form of `html`; total, so unparseable input yields text rather than an error.
    public static func plainText(fromHTML html: String) -> String {
        var tokenizer = HTMLTokenizer(html)

        // Input with nothing recognisably HTML in it keeps its tags, so `Array<String>` survives.
        guard tokenizer.looksLikeMarkup() else { return HTMLEntities.decoding(html) }

        var renderer = PlainTextRenderer()
        while let token = tokenizer.next() {
            renderer.consume(token)
        }
        return renderer.finish()
    }
}

// MARK: - Tokenising

/// One start or end tag with all of its attributes.
private struct HTMLTag {
    var name: String
    var isClosing: Bool
    var attributes: [String: String]

    func attribute(_ name: String) -> String? { attributes[name] }

    /// The `class` attribute split into tokens, because `unchecked` contains `checked`.
    var classes: [String] {
        (attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

private enum HTMLToken {
    case text(String)
    case tag(HTMLTag)
}

/// A single forward pass over the source; `<` begins a tag only when a tag name could follow.
private struct HTMLTokenizer {
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
        index = position(of: target, from: index, ignoringCase: true) ?? count
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

private enum HTMLElements {
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

private enum HTMLEntities {
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

    /// The named entities copied text carries; `nbsp` and the invisible joiners decode to plain or nothing.
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ensp": " ", "emsp": " ", "thinsp": " ", "shy": "", "zwnj": "", "zwj": "",
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

// MARK: - Writing

/// Accumulates output; breaks are requested, not written, so blank lines never pile up.
private struct Output {
    private var text = ""
    private var pendingBreaks = 0
    private var pendingSpace = false

    /// Asks for `count` newlines before the next content; the largest request wins.
    mutating func requestBreak(_ count: Int) {
        guard !text.isEmpty else { return }
        pendingBreaks = max(pendingBreaks, count)
        pendingSpace = false
    }

    /// Asks for a single space, which a break already pending outranks.
    mutating func requestSpace() {
        guard !text.isEmpty, !text.hasSuffix(" "), pendingBreaks == 0 else { return }
        pendingSpace = true
    }

    mutating func append(_ content: String) {
        guard !content.isEmpty else { return }
        settlePending()
        text += content
    }

    /// A list marker, after which nothing may be inserted before the item's first word.
    mutating func appendMarker(_ marker: String) {
        settlePending()
        text += marker
        pendingSpace = false
    }

    var result: String { text }

    private mutating func settlePending() {
        if pendingBreaks > 0 {
            // Verbatim content can end in its own newlines; counting them stops a blank line after `<pre>`.
            let existing = trailingNewlines
            if pendingBreaks > existing {
                text += String(repeating: "\n", count: pendingBreaks - existing)
            }
        } else if pendingSpace {
            text += " "
        }
        pendingBreaks = 0
        pendingSpace = false
    }

    private var trailingNewlines: Int {
        var found = 0
        var index = text.endIndex
        while index > text.startIndex, found < 2 {
            let before = text.index(before: index)
            guard text[before] == "\n" else { break }
            found += 1
            index = before
        }
        return found
    }
}

// MARK: - Rendering

/// Turns the token stream into the text a plain target receives.
private struct PlainTextRenderer {
    private var out = Output()
    private var lists: [ListFrame] = []
    private var pendingMarker: String?
    /// Depth of `<pre>` and `<code>`, whose whitespace is kept exactly as written.
    private var verbatimDepth = 0
    private var trimNewlineAfterPre = false
    private var link: LinkCapture?

    private struct ListFrame {
        var isOrdered: Bool
        var isChecklist: Bool
        var count = 0
    }

    private struct LinkCapture {
        var href: String
        var text = ""
    }

    mutating func consume(_ token: HTMLToken) {
        switch token {
        case .text(let text): write(text)
        case .tag(let tag): apply(tag)
        }
    }

    mutating func finish() -> String {
        // A document that stops inside an anchor still knows where the anchor pointed.
        closeLink()
        // Trailing whitespace is never content; it is the newline before `</pre>`.
        return out.result.trimmedTrailing()
    }

    // MARK: Text

    private mutating func write(_ raw: String) {
        var text = raw
        if trimNewlineAfterPre {
            trimNewlineAfterPre = false
            // Drops the newline after `<pre>` scalar by scalar, since CR LF is one `Character`.
            if text.unicodeScalars.first == "\r" { text.unicodeScalars.removeFirst() }
            if text.unicodeScalars.first == "\n" { text.unicodeScalars.removeFirst() }
        }

        guard verbatimDepth == 0 else {
            guard !text.isEmpty else { return }
            if link != nil {
                link?.text += text
            } else {
                startContent()
                out.append(text)
            }
            return
        }

        let run = CollapsedRun(text)
        guard !run.body.isEmpty else {
            // Whitespace alone must not bring a list marker out ahead of its own item.
            if pendingMarker == nil, run.hasLeadingSpace || run.hasTrailingSpace {
                if link == nil { out.requestSpace() } else { appendSpaceToLink() }
            }
            return
        }

        if link != nil {
            if run.hasLeadingSpace { appendSpaceToLink() }
            link?.text += run.body
            if run.hasTrailingSpace { appendSpaceToLink() }
            return
        }
        startContent()
        if run.hasLeadingSpace { out.requestSpace() }
        out.append(run.body)
        if run.hasTrailingSpace { out.requestSpace() }
    }

    private mutating func appendSpaceToLink() {
        guard let current = link, !current.text.isEmpty, !current.text.hasSuffix(" ") else { return }
        link?.text += " "
    }

    /// Emits the pending `<li>` marker at its first content, since an `<input>` inside may change it.
    private mutating func startContent() {
        guard let marker = pendingMarker else { return }
        pendingMarker = nil
        out.appendMarker(marker)
    }

    // MARK: Tags

    private mutating func apply(_ tag: HTMLTag) {
        switch tag.name {
        case "a":
            if tag.isClosing {
                closeLink()
            } else {
                closeLink()
                link = LinkCapture(href: tag.attribute("href") ?? "")
            }
        case "ul", "ol", "menu":
            if tag.isClosing {
                if !lists.isEmpty { lists.removeLast() }
                pendingMarker = nil
            } else {
                lists.append(
                    ListFrame(isOrdered: tag.name == "ol", isChecklist: isChecklist(tag)))
            }
            out.requestBreak(1)
        case "li":
            if tag.isClosing {
                // An item with nothing in it gets no line.
                pendingMarker = nil
            } else {
                openItem(tag)
            }
            out.requestBreak(1)
        case "input":
            if !tag.isClosing { applyCheckbox(tag) }
        case "pre":
            stepVerbatim(tag)
            trimNewlineAfterPre = !tag.isClosing
            out.requestBreak(1)
        case "code", "kbd", "samp", "tt":
            stepVerbatim(tag)
        case "td", "th":
            // Cells running into each other would mash two words into one; a space is the least this can do.
            if !tag.isClosing { out.requestSpace() }
        case "hr":
            out.requestBreak(2)
        // Everything else contributes its text and nothing else, the right default for an unknown tag.
        default:
            if isHeading(tag.name) {
                // The one place a blank line is added: separation is plain text's only cue for a heading.
                out.requestBreak(2)
            } else if Self.blockTags.contains(tag.name) {
                out.requestBreak(1)
            }
        }
    }

    /// Enters or leaves a stretch whose whitespace is kept exactly as written.
    private mutating func stepVerbatim(_ tag: HTMLTag) {
        verbatimDepth = tag.isClosing ? max(0, verbatimDepth - 1) : verbatimDepth + 1
    }

    private func isHeading(_ name: String) -> Bool {
        guard name.count == 2, name.hasPrefix("h"), let level = name.last?.wholeNumberValue
        else { return false }
        return (1...6).contains(level)
    }

    private static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "br", "caption", "dd", "details", "div",
        "dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "header", "main",
        "nav", "p", "section", "summary", "table", "tbody", "tfoot", "thead", "tr",
    ]

    // MARK: Lists

    private mutating func openItem(_ tag: HTMLTag) {
        let indent = String(repeating: " ", count: max(0, lists.count - 1) * 2)
        if let checked = checkboxState(of: tag) {
            pendingMarker = indent + Self.box(checked)
        } else if lists.last?.isChecklist == true {
            pendingMarker = indent + Self.box(false)
        } else if lists.last?.isOrdered == true {
            lists[lists.count - 1].count += 1
            // Plain digits, so the tenth item is `10.` and the list stays a list.
            pendingMarker = "\(indent)\(lists[lists.count - 1].count). "
        } else {
            pendingMarker = indent + "\u{2022} "
        }
    }

    private static func box(_ checked: Bool) -> String { checked ? "[x] " : "[ ] " }

    /// Whether a `<ul>` is a checklist; Notes labels the list, editors the items, GitHub neither.
    private func isChecklist(_ tag: HTMLTag) -> Bool {
        let markers: Set<String> = ["checklist", "task-list", "tasklist", "contains-task-list"]
        if tag.classes.contains(where: markers.contains) { return true }
        return tag.attribute("data-type").map { ["tasklist", "task-list"].contains($0.lowercased()) }
            ?? false
    }

    /// Whether an `<li>` states its own tick state, and what it is.
    private func checkboxState(of tag: HTMLTag) -> Bool? {
        if let value = tag.attribute("data-checked") ?? tag.attribute("aria-checked") {
            return value.lowercased() == "true"
        }
        let classes = tag.classes
        if classes.contains("checked") { return true }
        if classes.contains(where: ["unchecked", "task-list-item", "checklist-item"].contains) {
            return false
        }
        return nil
    }

    /// A real `<input type="checkbox">`, which may arrive after its `<li>` and overrules that item's marker.
    private mutating func applyCheckbox(_ tag: HTMLTag) {
        guard tag.attribute("type")?.lowercased() == "checkbox" else { return }
        let checked = tag.attribute("checked") != nil || tag.attribute("aria-checked") == "true"
        guard let marker = pendingMarker else {
            startContent()
            out.append(Self.box(checked).trimmingTrailingSpace())
            out.requestSpace()
            return
        }
        let indent = String(marker.prefix(while: { $0 == " " }))
        pendingMarker = indent + Self.box(checked)
    }

    // MARK: Links

    /// Writes a link as `text (url)`, or the text alone when it is the url or the href goes nowhere.
    private mutating func closeLink() {
        guard let captured = link else { return }
        link = nil
        let text = captured.text.trimmedEdges()
        let href = captured.href.trimmedEdges()

        guard isFollowable(href) else {
            write(text)
            return
        }
        if text.isEmpty {
            write(href)
        } else if sameDestination(text, href) {
            write(text)
        } else {
            write("\(text) (\(href))")
        }
    }

    /// An address that still points somewhere once the document around it is gone.
    private func isFollowable(_ href: String) -> Bool {
        guard let scheme = href.urlScheme() else { return false }
        return !["javascript", "data", "vbscript", "about"].contains(scheme)
    }

    /// Whether printing the url after the text would only repeat it; case, scheme and slash are ignored.
    private func sameDestination(_ text: String, _ href: String) -> Bool {
        func canonical(_ value: String) -> String {
            var result = value.lowercased()
            for prefix in ["https://", "http://", "mailto:", "tel:"] where result.hasPrefix(prefix) {
                result.removeFirst(prefix.count)
            }
            while result.hasSuffix("/") { result.removeLast() }
            return result
        }
        return canonical(text) == canonical(href)
    }
}

// MARK: - Small string work

/// A text run with its inner whitespace collapsed to one space and its edge whitespace remembered.
private struct CollapsedRun {
    let body: String
    let hasLeadingSpace: Bool
    let hasTrailingSpace: Bool

    init(_ text: String) {
        var out = String.UnicodeScalarView()
        var leading = false
        var pending = false
        for scalar in text.unicodeScalars {
            guard !scalar.properties.isWhitespace else {
                pending = true
                continue
            }
            if pending {
                if out.isEmpty { leading = true } else { out.append(" ") }
                pending = false
            }
            out.append(scalar)
        }
        body = String(out)
        hasLeadingSpace = leading
        // A run of only whitespace still separates its neighbours.
        hasTrailingSpace = pending
    }
}

extension String {
    fileprivate func trimmedEdges() -> String {
        String(trimmedTrailing().unicodeScalars.drop(while: \.properties.isWhitespace))
    }

    fileprivate func trimmingTrailingSpace() -> String {
        var copy = self
        while copy.hasSuffix(" ") { copy.removeLast() }
        return copy
    }

    fileprivate func trimmedTrailing() -> String {
        var scalars = unicodeScalars[...]
        while let last = scalars.last, last.properties.isWhitespace { scalars.removeLast() }
        return String(scalars)
    }

    /// The scheme of an absolute url; hand-written because `URL` accepts `page.html` as a url.
    fileprivate func urlScheme() -> String? {
        var scheme = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            if scalar == ":" {
                return scheme.isEmpty ? nil : String(scheme).lowercased()
            }
            guard
                scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)
                    || "+-.".unicodeScalars.contains(scalar)
            else { return nil }
            scheme.append(scalar)
        }
        return nil
    }
}
