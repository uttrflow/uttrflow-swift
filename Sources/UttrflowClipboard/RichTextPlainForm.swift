/// What a rich clip becomes when it is pasted somewhere that has no formatting to
/// receive it.
///
/// A formatted clip carries two representations, and this is the one that goes into a
/// terminal, a code editor, a commit message or a search field. The whole rule is that
/// what arrives there must be text a person could have typed. Never `<strong>` and never
/// `<h1>` — but equally never `**bold**`, because asterisks are not formatting at a shell
/// prompt, they are noise the user then has to delete by hand. Every decision below falls
/// out of that one sentence: the target is plain, so the output is plain, and anything
/// added to stand in for weight would be something the user did not write.
///
/// HTML is the input because HTML is what everything upstream produces. A browser copy
/// puts `public.html` on the pasteboard, `NSAttributedString` round-trips through it, and
/// the editors people keep notes in emit it.
///
/// Parsed here rather than by `NSAttributedString(html:)` for three reasons, each
/// sufficient alone: that initialiser is main-actor bound, it is slow enough to be felt on
/// a panel whose entire promise is opening instantly, and it would pull the AppKit text
/// system into a module that deliberately knows nothing about drawing.
public enum RichTextPlainForm: Sendable {
    /// The readable plain-text form of a rich clip.
    ///
    /// Total: there is no malformed input, only input that yields less. Anything that
    /// cannot be understood as markup is treated as the text it also looks like, which is
    /// the only behaviour that keeps the promise that pasting never loses words.
    ///
    /// - Parameter html: The rich representation of a clip, exactly as it arrived.
    /// - Returns: Text with no markup left in it.
    public static func plainText(fromHTML html: String) -> String {
        var tokenizer = HTMLTokenizer(html)

        // Input with nothing recognisably HTML in it is handed back with only its entities
        // decoded — no tags removed, no whitespace reflowed.
        //
        // This is the guard that stops the function eating code. `Array<String>` and
        // `if (a < b)` are both what a browser would call markup, and a browser would be
        // right; here it would mean a snippet losing a type parameter on the way into an
        // editor, which is the worst thing this file could do. Well-formed input never
        // reaches this branch — real HTML says `&lt;` — so nothing is given up.
        guard tokenizer.looksLikeMarkup() else { return HTMLEntities.decoding(html) }

        var renderer = PlainTextRenderer()
        while let token = tokenizer.next() {
            renderer.consume(token)
        }
        return renderer.finish()
    }
}

// MARK: - Tokenising

/// One start or end tag, with only the attributes anybody downstream asks for kept —
/// which is all of them, because a dictionary of six entries is cheaper than deciding
/// twice what a tag is.
private struct HTMLTag {
    var name: String
    var isClosing: Bool
    var attributes: [String: String]

    func attribute(_ name: String) -> String? { attributes[name] }

    /// The `class` attribute split into the tokens a stylesheet would see.
    ///
    /// Split rather than searched because `unchecked` contains `checked`, and a
    /// substring test would tick every box in an untouched checklist.
    var classes: [String] {
        (attributes["class"] ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
    }
}

private enum HTMLToken {
    case text(String)
    case tag(HTMLTag)
}

/// A single forward pass over the source, producing text runs and tags.
///
/// Hand-written because the alternative is a text system on the paste path, and because
/// the interesting behaviour here is entirely about what happens to input that is *not*
/// well-formed. A browser's parser and this one agree on the rule that matters: `<` only
/// begins a tag when what follows it could begin a tag name, so `a < b` in prose is prose.
private struct HTMLTokenizer {
    private let scalars: [Unicode.Scalar]
    private let count: Int
    private var index = 0
    /// Set after a `<script>`, `<style>` or `<title>` start tag, so their contents are
    /// skipped rather than tokenised. Their text must never reach the pasteboard, and
    /// their contents are not markup — a `<` inside a script is an operator.
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

    /// Whether anything in the input is recognisably HTML.
    ///
    /// Two signals, either one sufficient. A tag naming a real element is the obvious
    /// one. An *end* tag of any name is the other, and it is what saves the documents the
    /// first signal misses: Word's `<o:p></o:p>` and every custom element name nobody can
    /// enumerate. Code does not close tags — `Array<String>` and `template <typename T>`
    /// have no `</…>` anywhere — so the second signal buys that coverage without giving
    /// up the protection the guard exists for.
    ///
    /// Scanned before tokenising, over the same buffer, so the answer costs one pass and
    /// no second copy of a large clip.
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

    /// Whether the `<` at `i` opens markup, or is just a less-than sign somebody copied.
    ///
    /// This one predicate is what keeps `if (a < b && c > d)` intact: the space after the
    /// `<` disqualifies it, so the whole expression is read as the text it is. A `>` is
    /// never special outside a tag, so the other half needs no rule at all.
    private func isMarkupStart(_ i: Int) -> Bool {
        guard scalars[i] == "<", i + 1 < count else { return false }
        let next = scalars[i + 1]
        if isNameStart(next) || next == "!" || next == "?" { return true }
        return next == "/" && i + 2 < count && isNameStart(scalars[i + 2])
    }

    // MARK: Markup

    /// Reads whatever the `<` at `index` opens, always leaving `index` further along.
    ///
    /// Returns nothing for the three things that are markup but not tags — comments,
    /// doctypes, processing instructions — and for a tag that never closes, which is the
    /// end of the input by definition and so takes no text down with it.
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

    /// One `name`, `name=value` or `name="value"` pair, advancing `i` past it.
    ///
    /// Quoted values are read to their quote rather than to the next `>`, which is the
    /// reason attributes are parsed at all: `<a title="a > b">` closes where the quote
    /// says it closes, not where a naive scan for `>` would put it.
    private func readAttribute(from i: inout Int) -> (String, String)? {
        var name = String.UnicodeScalarView()
        while i < count, !isSpace(scalars[i]), !"=>/".unicodeScalars.contains(scalars[i]) {
            name.append(scalars[i])
            i += 1
        }
        guard !name.isEmpty else {
            // A stray `=` or quote where a name should be. Step over it so the loop
            // cannot stall on input nobody meant to write.
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

    /// Runs to the end tag of a raw-text element, or to the end of the input if the
    /// document never closes it — in which case there was nothing after it to lose.
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
    /// Every element HTML defines, including the ones long since obsolete.
    ///
    /// Used once, to answer "is this document HTML at all?", and deliberately generous:
    /// each name left out is a document that would be handed back with its tags showing,
    /// which is the failure this whole file is written to prevent. Names *not* on the list
    /// are still stripped when they appear inside a document that is HTML — Word's
    /// `<o:p>` and every custom element go the same way as `<span>`.
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
    /// Decodes every entity in one left-to-right pass, and never looks at what it wrote.
    ///
    /// The single pass is the whole correctness argument for the case that catches
    /// everybody: `&amp;amp;` is the escaped form of the literal text `&amp;`, so it must
    /// decode to `&amp;` and stop. A decoder that re-scanned its own output would hand
    /// back `&`, silently unescaping text the author had deliberately escaped.
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

    /// The reference beginning at `start`, or nothing if what follows the `&` is not one.
    ///
    /// An unrecognised name is left exactly as written rather than dropped: `&foo;` in a
    /// note is somebody's text, and `AT&T` is a company.
    private static func decodeReference(
        _ scalars: [Unicode.Scalar], at start: Int
    ) -> (replacement: String, end: Int)? {
        // Longest real entity name is a handful of characters; the bound stops a stray
        // ampersand in prose from scanning the rest of a large clip looking for a `;`.
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
        // A C0 control that is not a tab or a newline has no plain-text form and does
        // real damage in a terminal, so it decodes to nothing at all.
        if value < 0x20, value != 0x09, value != 0x0A { return "" }
        return String(scalar)
    }

    /// The named entities that turn up in copied text, plus the five every document has.
    ///
    /// `nbsp` decodes to an ordinary space on purpose. A non-breaking space looks exactly
    /// like a space, is not one, and breaks shell commands and compilers in ways that take
    /// a person minutes to see — which is precisely the kind of surprise this whole file
    /// exists to prevent. The zero-width joiners and the soft hyphen go the same way, to
    /// nothing, for the same reason.
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

/// Accumulates the output and owns every rule about whitespace between blocks.
///
/// Line breaks are *requested* rather than written, and nothing is emitted until real
/// content arrives to sit after them. That inversion is what makes "no piling up blank
/// lines" structural rather than a clean-up pass: `<div><p></p></div><br>` requests four
/// breaks and produces none, and a document that ends in six closing tags ends in no
/// trailing newlines at all.
private struct Output {
    private var text = ""
    private var pendingBreaks = 0
    private var pendingSpace = false

    /// Asks for `count` newlines before whatever comes next. Requests do not add up —
    /// the largest wins — so no amount of nesting can widen a gap.
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

    /// A list marker: like any other content, except that nothing may be inserted between
    /// it and the item's first word.
    mutating func appendMarker(_ marker: String) {
        settlePending()
        text += marker
        pendingSpace = false
    }

    var result: String { text }

    private mutating func settlePending() {
        if pendingBreaks > 0 {
            // Verbatim content can already have ended in newlines of its own. Counting
            // them is what stops a `<pre>` block being followed by a blank line nobody
            // asked for.
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
    /// Depth of `<pre>` and `<code>`, whose contents are the one thing here that is not
    /// reflowed. Code is whitespace, and a snippet that arrives with its indentation
    /// collapsed is a snippet that has to be retyped.
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
        // Trailing whitespace is never anybody's content: it is the newline a source
        // document put before `</pre>`, and pasting it moves the caret for no reason.
        return out.result.trimmedTrailing()
    }

    // MARK: Text

    private mutating func write(_ raw: String) {
        var text = raw
        if trimNewlineAfterPre {
            trimNewlineAfterPre = false
            // The newline directly after `<pre>` is a formatting convention of the source
            // document, not a line of the snippet. HTML has always ignored it.
            //
            // Removed a scalar at a time rather than a `Character`: CR LF is one grapheme
            // in Swift, so `removeFirst()` on the string would take the first letter of
            // the snippet with it.
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
            // Whitespace alone must not bring a list marker out ahead of its own item:
            // the newline between `<li>` and the checkbox inside it is not content.
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

    /// Emits the list marker the pending `<li>` earned, at the moment its first real
    /// content shows up. Deferred rather than written at the `<li>` because whether the
    /// item is a bullet or a checkbox can be settled by an `<input>` *inside* it.
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
                // An item with nothing in it gets no line. A lone bullet in a paste is
                // rubbish somebody has to delete.
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
            // Tables are out of scope, but cells running into each other would mash two
            // words into one. A space is the least this can do and still be honest.
            if !tag.isClosing { out.requestSpace() }
        case "hr":
            out.requestBreak(2)
        // Headings, the remaining blocks, and then everything else — `strong`, `em`, `b`,
        // `i`, `span`, `font`, `mark`, and every tag nobody has heard of — which
        // contributes its text and nothing else. Inline is the right default for an
        // unknown tag: it keeps the words and drops the markup, which is the promise.
        default:
            if isHeading(tag.name) {
                // The one place a blank line is added rather than merely kept. Weight is
                // gone and no marker replaces it, so separation is the only cue plain text
                // has for "this names what follows" — and unlike a `#`, it is not a
                // character the user has to delete.
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

    /// Whether a `<ul>` is a checklist rather than a bullet list.
    ///
    /// Apple Notes labels the list itself; several editors label only the items; GitHub
    /// labels neither and puts a real `<input>` inside. All three are read, because the
    /// clip comes from whichever one the user happened to be in.
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

    /// A real `<input type="checkbox">`, which may arrive after its own `<li>` opened and
    /// so is allowed to overrule the marker that item was going to get.
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

    /// Decides what an anchor looks like once there is nothing to click.
    ///
    /// The url is kept, in brackets after the text, because a plain target cannot hide it
    /// behind a word: dropping it loses the only part of the link that carries any
    /// information, and a note pasted into a commit message with its references silently
    /// removed is worse than one that reads a little longer.
    ///
    /// Two cases refuse that shape. When the text already *is* the url — the ordinary
    /// result of pasting a link into a notes app, which then linkifies it — repeating it
    /// gives `https://x (https://x)`, which is the exact absurdity that makes people stop
    /// trusting a paste. And when the href is not somewhere anyone can go from here — a
    /// `#section` anchor, a relative path, a `javascript:` handler — the text stands alone,
    /// because that address means nothing without the page it was written on.
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

    /// Whether printing the url after the text would only repeat it.
    ///
    /// Compared loosely — case, scheme and a trailing slash are ignored — because the
    /// question is not whether two urls address the same resource but whether a reader
    /// would see the same string twice. Being too eager costs a url the reader can still
    /// read in the text; being too strict produces `https://x (https://x)`.
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

/// A text run with its inner whitespace collapsed, and its edges remembered separately.
///
/// HTML's own rule: any run of whitespace is one space, and whether there was whitespace
/// at the edge decides whether `<b>one</b> <b>two</b>` is two words or one.
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
        // A run that is nothing but whitespace still separates its neighbours: the single
        // space between `</b>` and `<em>` is the only thing keeping two words apart.
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

    /// The scheme of an absolute url, or nothing for a relative one.
    ///
    /// Written by hand rather than with `URL`, which parses relative references happily
    /// and would call `page.html` a url.
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
