import AppKit
public import struct Foundation.Data

/// The plain text of a rich clip, for a target with no formatting. See Docs/clipboard-plain-form.md.
public enum RichTextPlainForm: Sendable {
    /// The plain text of bounded RTF, or `nil` when AppKit cannot read it.
    public static func plainText(fromRTF data: Data) -> String? {
        guard
            let richText = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil)
        else { return nil }
        return richText.string
    }

    /// The readable plain-text form of `html`; total, so unparseable input yields text rather than an error.
    public static func plainText(fromHTML html: String) -> String {
        conversion(fromHTML: html).text
    }

    static func conversion(
        fromHTML html: String, maximumOutputBytes: Int = ClipboardBudget.standard.largestClip
    ) -> (text: String, wasTruncated: Bool) {
        var tokenizer = HTMLTokenizer(html)

        // Input with nothing recognisably HTML in it keeps its tags, so `Array<String>` survives.
        guard tokenizer.looksLikeMarkup() else {
            var output = Output(maximumBytes: maximumOutputBytes)
            output.append(HTMLEntities.decoding(html))
            return (output.result, output.didReachLimit)
        }

        var tokens: [HTMLToken] = []
        while let token = tokenizer.next() { tokens.append(token) }
        var renderer = PlainTextRenderer(
            itemCounts: PlainTextRenderer.itemCounts(in: tokens), maximumOutputBytes: maximumOutputBytes)
        for token in tokens {
            renderer.consume(token)
            if renderer.didReachLimit { break }
        }
        return renderer.finish()
    }
}

// MARK: - Writing

/// Accumulates output; breaks are requested, not written, so blank lines never pile up.
private struct Output {
    private static let truncationMarker = "…"

    private let maximumBytes: Int?
    private let truncationMarker: String?
    private var text = ""
    private var contentBytes = 0
    private var pendingBreaks = 0
    private var pendingSpace = false
    private var didTruncate = false

    init(maximumBytes: Int) {
        let marker: String?
        switch maximumBytes {
        case ..<1: marker = nil
        case 1...2: marker = String(repeating: ".", count: maximumBytes)
        default: marker = Self.truncationMarker
        }
        truncationMarker = marker
        self.maximumBytes = maximumBytes > 0 ? maximumBytes : nil
    }

    /// Asks for `count` newlines before the next content; the largest request wins.
    mutating func requestBreak(_ count: Int) {
        guard !didTruncate, !text.isEmpty else { return }
        pendingBreaks = max(pendingBreaks, count)
        pendingSpace = false
    }

    /// Asks for a single space, which a break already pending outranks.
    mutating func requestSpace() {
        guard !didTruncate, !text.isEmpty, !text.hasSuffix(" "), pendingBreaks == 0 else { return }
        pendingSpace = true
    }

    mutating func append(_ content: String) {
        guard !didTruncate, !content.isEmpty else { return }
        settlePending()
        guard !didTruncate else { return }
        appendBounded(content)
    }

    /// A list marker, after which nothing may be inserted before the item's first word.
    mutating func appendMarker(_ marker: String) {
        guard !didTruncate else { return }
        settlePending()
        guard !didTruncate else { return }
        appendBounded(marker)
        pendingSpace = false
    }

    var result: String { text }
    var didReachLimit: Bool { didTruncate }

    private mutating func settlePending() {
        if pendingBreaks > 0 {
            // Verbatim content can end in its own newlines; counting them stops a blank line after `<pre>`.
            let existing = trailingNewlines
            if pendingBreaks > existing {
                appendBounded(String(repeating: "\n", count: pendingBreaks - existing))
            }
        } else if pendingSpace {
            appendBounded(" ")
        }
        pendingBreaks = 0
        pendingSpace = false
    }

    private mutating func appendBounded(_ content: String) {
        guard let maximumBytes else {
            text += content
            return
        }
        let remainingBytes = maximumBytes - contentBytes
        let contentBytesToAppend = content.utf8.count
        guard contentBytesToAppend <= remainingBytes else {
            let markerBytes = truncationMarker?.utf8.count ?? 0
            let contentLimit = max(0, maximumBytes - markerBytes)
            let retained = Self.utf8Prefix(text, limitedTo: contentLimit)
            text = retained
            contentBytes = retained.utf8.count
            let prefix = Self.utf8Prefix(content, limitedTo: max(0, contentLimit - contentBytes))
            text += prefix
            contentBytes += prefix.utf8.count
            if let truncationMarker { text += truncationMarker }
            didTruncate = true
            return
        }
        text += content
        contentBytes += contentBytesToAppend
    }

    private static func utf8Prefix(_ content: String, limitedTo byteLimit: Int) -> String {
        var prefix = String.UnicodeScalarView()
        var byteCount = 0
        for scalar in content.unicodeScalars {
            let scalarBytes = scalar.utf8.count
            guard byteCount + scalarBytes <= byteLimit else { break }
            prefix.append(scalar)
            byteCount += scalarBytes
        }
        return String(prefix)
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
    private static let maximumListIndentDepth = 8

    private var out: Output
    private var lists: [ListFrame] = []
    /// How many items each list holds directly, by the order the lists open in; a `reversed` list counts down from it.
    private let itemCounts: [Int]
    /// How many lists have opened so far, which indexes `itemCounts`.
    private var listsOpened = 0
    private var pendingMarker: String?
    /// Depth of `<pre>` and `<code>`, whose whitespace is kept exactly as written.
    private var verbatimDepth = 0
    private var trimNewlineAfterPre = false
    private var link: LinkCapture?

    private struct ListFrame {
        var isOrdered: Bool
        var isChecklist: Bool
        /// The number the next item takes unless it gives its own `value`.
        var next = 1
        /// One, or minus one for a `reversed` list.
        var step = 1
    }

    init(itemCounts: [Int], maximumOutputBytes: Int) {
        out = Output(maximumBytes: maximumOutputBytes)
        self.itemCounts = itemCounts
    }

    /// How many items each list holds directly, in the order the lists open, nesting as `apply` does.
    static func itemCounts(in tokens: [HTMLToken]) -> [Int] {
        var counts: [Int] = []
        var open: [Int] = []
        for case .tag(let tag) in tokens {
            switch tag.name {
            case "ul", "ol", "menu":
                if tag.isClosing {
                    if !open.isEmpty { open.removeLast() }
                } else {
                    open.append(counts.count)
                    counts.append(0)
                }
            case "li" where !tag.isClosing:
                if let list = open.last { counts[list] += 1 }
            default:
                break
            }
        }
        return counts
    }

    /// An attribute's integer the way HTML reads one: leading space, a sign, then digits, and the rest ignored.
    static func integer(_ text: String?) -> Int? {
        guard let text else { return nil }
        var rest = Substring(text.drop(while: \.isWhitespace))
        let isNegative = rest.first == "-"
        if rest.first == "-" || rest.first == "+" { rest = rest.dropFirst() }
        let digits = rest.prefix(while: \.isASCII).prefix(while: \.isNumber)
        guard !digits.isEmpty, let magnitude = Int(digits) else { return nil }
        return isNegative ? -magnitude : magnitude
    }

    private struct LinkCapture {
        var href: String
        var text = ""
    }

    mutating func consume(_ token: HTMLToken) {
        guard !out.didReachLimit else { return }
        switch token {
        case .text(let text): write(text)
        case .tag(let tag): apply(tag)
        }
    }

    var didReachLimit: Bool { out.didReachLimit }

    mutating func finish() -> (text: String, wasTruncated: Bool) {
        // A document that stops inside an anchor still knows where the anchor pointed.
        closeLink()
        // Trailing whitespace is never content; it is the newline before `</pre>`.
        return (out.result.trimmedTrailing(), out.didReachLimit)
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

    /// Keeps link words apart when their HTML would make separate text lines.
    private mutating func requestBreak(_ count: Int) {
        if link != nil {
            appendSpaceToLink()
        } else {
            out.requestBreak(count)
        }
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
                lists.append(openList(tag))
            }
            requestBreak(1)
        case "li":
            if tag.isClosing {
                // An item with nothing in it gets no line.
                pendingMarker = nil
            } else {
                openItem(tag)
            }
            requestBreak(1)
        case "input":
            if !tag.isClosing { applyCheckbox(tag) }
        case "pre":
            stepVerbatim(tag)
            trimNewlineAfterPre = !tag.isClosing
            requestBreak(1)
        case "code", "kbd", "samp", "tt":
            stepVerbatim(tag)
        case "td", "th":
            // Cells running into each other would mash two words into one; a space is the least this can do.
            if !tag.isClosing { out.requestSpace() }
        case "hr":
            requestBreak(2)
        // Everything else contributes its text and nothing else, the right default for an unknown tag.
        default:
            if isHeading(tag.name) {
                // The one place a blank line is added: separation is plain text's only cue for a heading.
                requestBreak(2)
            } else if Self.blockTags.contains(tag.name) {
                requestBreak(1)
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

    /// A list's frame, numbered from its `start`, or down from its item count when `reversed`.
    private mutating func openList(_ tag: HTMLTag) -> ListFrame {
        let items = listsOpened < itemCounts.count ? itemCounts[listsOpened] : 0
        listsOpened += 1
        var frame = ListFrame(isOrdered: tag.name == "ol", isChecklist: isChecklist(tag))
        guard frame.isOrdered else { return frame }
        let start = Self.integer(tag.attribute("start"))
        if tag.attribute("reversed") != nil {
            frame.next = start ?? items
            frame.step = -1
        } else {
            frame.next = start ?? 1
        }
        return frame
    }

    private mutating func openItem(_ tag: HTMLTag) {
        let depth = min(lists.count, Self.maximumListIndentDepth)
        let indent = String(repeating: " ", count: max(0, depth - 1) * 2)
        if let checked = checkboxState(of: tag) {
            pendingMarker = indent + Self.box(checked)
        } else if lists.last?.isChecklist == true {
            pendingMarker = indent + Self.box(false)
        } else if lists.last?.isOrdered == true {
            let last = lists.count - 1
            if let value = Self.integer(tag.attribute("value")) { lists[last].next = value }
            // Plain digits, so the tenth item is `10.` and the list stays a list.
            pendingMarker = "\(indent)\(lists[last].next). "
            lists[last].next &+= lists[last].step
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

    /// Whether printing the url after the text would only repeat it; scheme, host case and slash are ignored.
    private func sameDestination(_ text: String, _ href: String) -> Bool {
        Self.canonicalDestination(text) == Self.canonicalDestination(href)
    }

    /// A url without its scheme and with only its host lowercased, since a path, query or fragment keeps its case.
    private static func canonicalDestination(_ value: String) -> String {
        var rest = Substring(value)
        for prefix in ["https://", "http://", "mailto:", "tel:"] where rest.lowercased().hasPrefix(prefix) {
            rest = rest.dropFirst(prefix.count)
        }
        let end = rest.firstIndex(where: { "/?#".contains($0) }) ?? rest.endIndex
        let authority = rest[..<end]
        let host = authority.lastIndex(of: "@").map(authority.index(after:)) ?? authority.startIndex
        var result = String(authority[..<host]) + authority[host...].lowercased() + rest[end...]
        while result.hasSuffix("/") { result.removeLast() }
        return result
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
