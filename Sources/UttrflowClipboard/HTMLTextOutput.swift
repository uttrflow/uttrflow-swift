/// Accumulates output; breaks are requested, not written, so blank lines never pile up.
struct HTMLTextOutput {
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
