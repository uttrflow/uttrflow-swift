// Single-pass readers for the credential shapes a backtracking pattern would read quadratically.

private import Synchronization

/// How many characters the secret scanners read while this was bound to `SecretShapes.tally`.
package final class ScanTally: Sendable {
    private let read = Mutex(0)

    package init() {}

    /// The characters read so far.
    package var count: Int { read.withLock { $0 } }

    func record(_ characters: Int) { read.withLock { $0 += characters } }
}

extension Character {
    /// The byte of the one ASCII scalar this character is, since a pattern's ASCII class matches nothing else.
    var loneASCII: UInt8? {
        let bytes = utf8
        guard bytes.count == 1, let byte = bytes.first, byte < 0x80 else { return nil }
        return byte
    }

    /// Whether this is one of the ASCII digits 0 to 9, which a pattern's `\d` over a secret means.
    var isASCIIDigit: Bool { loneASCII.map { (0x30...0x39).contains($0) } ?? false }

    /// Whether this is written in Latin script or is common punctuation, judged by its first scalar.
    var isLatinScript: Bool {
        guard let value = unicodeScalars.first?.value else { return true }
        return value < 0x0250 || Self.latinBlocks.contains { $0.contains(value) }
    }

    /// The Latin blocks past Latin Extended-B: Additional, Extended-C, -D, -E and -F.
    private static let latinBlocks: [ClosedRange<UInt32>] = [
        0x1E00...0x1EFF, 0x2C60...0x2C7F, 0xA720...0xA7FF, 0xAB30...0xAB6F, 0x10780...0x107BF,
    ]

    /// Whether this is U+212A KELVIN SIGN, which a case-insensitive `k` also matches.
    var isKelvinSign: Bool { utf8.elementsEqual([0xE2, 0x84, 0xAA]) }
}

/// Reads a JWT the way `eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.` matches one, in one pass.
enum JSONWebTokenScan {
    static func matches(_ text: String, read: inout Int) -> Bool {
        // Whether the run before the last full stop held `eyJ` with a character after it.
        var afterHeader = false
        // Whether the current run holds `eyJ` with a character after it.
        var hasHeader = false
        var runLength = 0
        var matchedOfPrefix = 0
        for character in text {
            read += 1
            if let byte = character.loneASCII, isSegmentByte(byte) {
                if matchedOfPrefix == 3 { hasHeader = true }
                matchedOfPrefix = advance(matchedOfPrefix, with: byte)
                runLength += 1
                continue
            }
            if character.loneASCII == UInt8(ascii: ".") {
                if afterHeader, runLength > 0 { return true }
                afterHeader = hasHeader
            } else {
                afterHeader = false
            }
            hasHeader = false
            runLength = 0
            matchedOfPrefix = 0
        }
        return false
    }

    /// How much of `eyJ` ends at this byte, given how much ended at the one before.
    private static func advance(_ matched: Int, with byte: UInt8) -> Int {
        if byte == UInt8(ascii: "e") { return 1 }
        if matched == 1, byte == UInt8(ascii: "y") { return 2 }
        return matched == 2 && byte == UInt8(ascii: "J") ? 3 : 0
    }

    /// The base64url alphabet a segment is drawn from.
    private static func isSegmentByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "-"):
            true
        default: false
        }
    }
}

/// Reads `scheme://user:password@host`, or `scheme://:password@host`, the way the connection-string pattern matches it, in one pass.
enum CredentialledURLScan {
    static func matches(_ text: String, read: inout Int) -> Bool {
        // Whether the run of scheme characters that ends here holds a letter, which a scheme must start with.
        var schemeHasLetter = false
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            read += 1
            let next = text.index(after: index)
            if let byte = character.loneASCII, isSchemeByte(byte) {
                schemeHasLetter = schemeHasLetter || isLetter(byte)
            } else {
                if isByte(character, ":"), schemeHasLetter,
                    let rest = slashes(in: text, from: next, read: &read),
                    carriesPassword(text, from: rest, read: &read)
                {
                    return true
                }
                schemeHasLetter = false
            }
            index = next
        }
        return false
    }

    /// Where the text continues after `//`, when `//` stands at `index`.
    private static func slashes(in text: String, from index: String.Index, read: inout Int) -> String.Index? {
        var cursor = index
        for _ in 0..<2 {
            guard cursor < text.endIndex else { return nil }
            read += 1
            guard isByte(text[cursor], "/") else { return nil }
            cursor = text.index(after: cursor)
        }
        return cursor
    }

    /// Whether `user:password@`, the user possibly empty, and one visible character follow; runs stop at `:`, `/`, `@`.
    private static func carriesPassword(_ text: String, from start: String.Index, read: inout Int) -> Bool {
        guard let colon = run(in: text, from: start, allowingEmpty: true, read: &read),
            isByte(text[colon], ":")
        else {
            return false
        }
        guard let at = run(in: text, from: text.index(after: colon), read: &read), isByte(text[at], "@")
        else { return false }
        let host = text.index(after: at)
        guard host < text.endIndex else { return false }
        read += 1
        return !text[host].isWhitespace
    }

    /// Where a run of userinfo characters from `start` ends, when something follows it and it may be that long.
    private static func run(
        in text: String, from start: String.Index, allowingEmpty: Bool = false, read: inout Int
    ) -> String.Index? {
        var index = start
        while index < text.endIndex {
            read += 1
            let character = text[index]
            if character.isWhitespace || isByte(character, ":") || isByte(character, "/")
                || isByte(character, "@")
            {
                break
            }
            index = text.index(after: index)
        }
        return (allowingEmpty || index > start) && index < text.endIndex ? index : nil
    }

    private static func isByte(_ character: Character, _ ascii: Unicode.Scalar) -> Bool {
        character.loneASCII == UInt8(ascii: ascii)
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
    }

    /// The characters a URL scheme may contain after its first letter.
    private static func isSchemeByte(_ byte: UInt8) -> Bool {
        isLetter(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            || byte == UInt8(ascii: "+") || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "-")
    }
}

/// A place in the text, with how many characters stand before it.
struct TextPosition {
    var index: String.Index
    var offset: Int
}

/// Reads `API_KEY=…`-shaped lines the way the named-secret pattern matches them, reading each character a bounded number of times.
struct NamedSecretScan {
    private let text: String
    private(set) var read = 0
    private var breaks: WordBreaks
    /// The last unquoted value read: where it started, where it stops, its last ASCII digit and its last non-Latin character.
    private var bareRun: (start: TextPosition, stop: TextPosition, lastNumber: Int?, lastNonLatin: Int?)?
    /// The last quoted value read: where its opening quote stands, and where the value ends.
    private var quotedRun: (open: String.Index, end: String.Index?)?
    /// The last line ending asked about: where the value ended, and where the pattern's `$` stands after it.
    private var lineEnd: (from: String.Index, end: String.Index?)?

    init(_ text: String) {
        self.text = text
        breaks = WordBreaks(text)
    }

    /// The spellings `(?:api[_-]?keys?|secrets?|…|pass)\b` accepts, lowercase, as bytes.
    static let keywords: [[UInt8]] = {
        func joined(_ first: String, _ second: String) -> [String] {
            ["", "_", "-"].map { first + $0 + second }
        }
        let plurals = (joined("api", "key") + ["secret", "token", "password", "credential"]).flatMap {
            [$0, $0 + "s"]
        }
        let singulars =
            ["passwd", "pwd", "pass"] + joined("private", "key") + joined("access", "key")
            + joined("auth", "token")
            + joined("client", "secret")
        return (plurals + singulars).map { Array($0.utf8) }
    }()

    /// Whether some line names a secret and gives a value the named-secret rule accepts.
    mutating func matches() -> Bool {
        var position = TextPosition(index: text.startIndex, offset: 0)
        // Where the pattern's next search starts, since its matches never overlap.
        var resume = text.startIndex
        // The lone ASCII byte of the character before `position`, which decides whether a name can start there.
        var previous: UInt8?
        while position.index < text.endIndex {
            read += 1
            let current = text[position.index].loneASCII
            if position.index >= resume, let current, Self.initials.contains(Self.lowered(current)) {
                let ends = keywordEnds(at: position, first: Self.lowered(current))
                if !ends.isEmpty,
                    Self.opensName(after: previous, at: current)
                        || breaks.isBoundary(position.index, from: position.index)
                {
                    for end in ends where breaks.isBoundary(end.index, from: position.index) {
                        guard let assignment = assignment(after: end) else { continue }
                        if assignment.accepted { return true }
                        resume = assignment.end
                        break
                    }
                }
            }
            previous = current
            advance(&position)
        }
        return false
    }

    /// Whether a keyword may start after `_` or at a lowercase-to-uppercase step, as in `DB_PASSWORD`.
    private static func opensName(after previous: UInt8?, at current: UInt8) -> Bool {
        guard let previous else { return false }
        return previous == UInt8(ascii: "_")
            || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(previous)
                && (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(current)
    }

    /// The letters a keyword can start with.
    private static let initials = Set(keywords.compactMap(\.first))

    private static func lowered(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }

    private func advance(_ position: inout TextPosition) {
        position.index = text.index(after: position.index)
        position.offset += 1
    }

    /// Where each spelling of a keyword that starts at `start`, whose first letter is already read, ends.
    private mutating func keywordEnds(at start: TextPosition, first: UInt8) -> [TextPosition] {
        var ends: [TextPosition] = []
        for keyword in Self.keywords where keyword.first == first {
            var position = start
            advance(&position)
            var matched = true
            for expected in keyword.dropFirst() {
                guard position.index < text.endIndex else {
                    matched = false
                    break
                }
                read += 1
                guard Self.character(text[position.index], matches: expected) else {
                    matched = false
                    break
                }
                advance(&position)
            }
            if matched { ends.append(position) }
        }
        return ends
    }

    /// Whether a character matches a keyword's byte case-insensitively, as a pattern literal does.
    private static func character(_ character: Character, matches expected: UInt8) -> Bool {
        if let byte = character.loneASCII { return lowered(byte) == expected }
        return expected == UInt8(ascii: "k") && character.isKelvinSign
    }

    /// Where `["']?\s*[:=]\s*`, a value and the end of its line match after a keyword, and whether the rule accepts the value.
    private mutating func assignment(after end: TextPosition) -> (end: String.Index, accepted: Bool)? {
        var position = end
        if let byte = byte(at: position.index), byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
            advance(&position)
        }
        skipWhitespace(&position)
        guard let separator = byte(at: position.index),
            separator == UInt8(ascii: ":") || separator == UInt8(ascii: "=")
        else { return nil }
        advance(&position)
        skipWhitespace(&position)
        guard position.index < text.endIndex else { return nil }
        if let quote = text[position.index].loneASCII,
            quote == UInt8(ascii: "\"") || quote == UInt8(ascii: "'")
        {
            guard let close = closingQuote(from: position, quote: quote),
                let lineEnd = endOfLine(from: text.index(after: close))
            else { return nil }
            return (lineEnd, true)
        }
        return bareAssignment(from: position)
    }

    /// The byte at `index` when it is a lone ASCII character, read once.
    private mutating func byte(at index: String.Index) -> UInt8? {
        guard index < text.endIndex else { return nil }
        read += 1
        return text[index].loneASCII
    }

    private mutating func skipWhitespace(_ position: inout TextPosition) {
        while position.index < text.endIndex {
            read += 1
            guard text[position.index].isWhitespace else { return }
            advance(&position)
        }
    }

    /// Where a quoted value that opens at `open` closes, when at least one character stands inside and no line feed does.
    private mutating func closingQuote(from open: TextPosition, quote: UInt8) -> String.Index? {
        if let cached = quotedRun, cached.open == open.index { return cached.end }
        var index = text.index(after: open.index)
        var close: String.Index?
        while index < text.endIndex {
            read += 1
            let character = text[index]
            if character.loneASCII == quote {
                close = index > text.index(after: open.index) ? index : nil
                break
            }
            if character == "\n" { break }
            index = text.index(after: index)
        }
        quotedRun = (open.index, close)
        return close
    }

    /// Where an unquoted value from `start` ends its line, and whether it has a digit, or is long and Latin, to be a secret.
    private mutating func bareAssignment(from start: TextPosition) -> (end: String.Index, accepted: Bool)? {
        let run = bareValue(from: start)
        guard run.stop.offset > start.offset, let lineEnd = endOfLine(from: run.stop.index) else {
            return nil
        }
        let length = run.stop.offset - start.offset
        // The rule reads a value that opens with a quote character as quoted, and quoted values always count.
        let first = String(text[start.index])
        let quoted = length >= 2 && (first.hasPrefix("\"") || first.hasPrefix("'"))
        let hasNumber = run.lastNumber.map { $0 >= start.offset } ?? false
        // A sentence in a script written without spaces is one long run, so length alone counts only in Latin.
        let isLatin = run.lastNonLatin.map { $0 < start.offset } ?? true
        let isLong = length >= 12 && isLatin && !isReference(from: start.index, to: run.stop.index)
        return (lineEnd, quoted || hasNumber || isLong)
    }

    /// Whether a value only points at a secret, as `a.b`, `f()` or `a.b();` do, with no part long and hex enough to be one.
    private mutating func isReference(from start: String.Index, to stop: String.Index) -> Bool {
        var part = 0
        var partIsHex = true
        var isPath = false
        var isCall = false
        var isClosed = false
        var index = start
        // A part of 32 hex letters or more would pass the entropy rule on its own, so it is not a name.
        func endsPart() -> Bool { part > 0 && !(part >= 32 && partIsHex) }
        func isName(_ byte: UInt8) -> Bool {
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte | 0x20) || byte == UInt8(ascii: "_")
                || byte == UInt8(ascii: "$")
        }
        while index < stop {
            read += 1
            let character = text[index]
            index = text.index(after: index)
            if isClosed { return false }
            let byte = character.loneASCII
            if byte == UInt8(ascii: ";") || byte == UInt8(ascii: ",") {
                guard isCall || endsPart() else { return false }
                isClosed = true
            } else if isCall {
                return false
            } else if let byte, isName(byte) {
                part += 1
                partIsHex = partIsHex && character.isHexDigit
            } else if byte == UInt8(ascii: ".") {
                guard endsPart() else { return false }
                (part, partIsHex, isPath) = (0, true, true)
            } else if byte == UInt8(ascii: "("), index < stop, text[index].loneASCII == UInt8(ascii: ")"),
                endsPart()
            {
                read += 1
                index = text.index(after: index)
                isCall = true
            } else {
                return false
            }
        }
        return (isCall || isClosed || endsPart()) && (isPath || isCall)
    }

    /// The run of unquoted value characters that `start` stands in, read once however many keywords share it.
    private mutating func bareValue(
        from start: TextPosition
    ) -> (stop: TextPosition, lastNumber: Int?, lastNonLatin: Int?) {
        if let cached = bareRun, cached.start.offset <= start.offset, start.offset < cached.stop.offset {
            return (cached.stop, cached.lastNumber, cached.lastNonLatin)
        }
        var position = start
        var lastNumber: Int?
        var lastNonLatin: Int?
        while position.index < text.endIndex {
            read += 1
            let character = text[position.index]
            if character.isWhitespace || character == "\n" { break }
            if let byte = character.loneASCII, byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                break
            }
            if character.isASCIIDigit { lastNumber = position.offset }
            if !character.isLatinScript { lastNonLatin = position.offset }
            advance(&position)
        }
        bareRun = (start, position, lastNumber, lastNonLatin)
        return (position, lastNumber, lastNonLatin)
    }

    /// Where `\s*[,;]?\s*$` from `start` puts `$`, which backtracks to the last line break it can reach.
    private mutating func endOfLine(from start: String.Index) -> String.Index? {
        if let cached = lineEnd, cached.from == start { return cached.end }
        var index = start
        let lastBreak = lastLineBreak(skipping: &index)
        var end: String.Index?
        if let mark = byte(at: index), mark == UInt8(ascii: ",") || mark == UInt8(ascii: ";") {
            var after = text.index(after: index)
            let breakAfterMark = lastLineBreak(skipping: &after)
            end = after == text.endIndex ? after : breakAfterMark ?? lastBreak
        } else {
            end = index == text.endIndex ? index : lastBreak
        }
        lineEnd = (start, end)
        return end
    }

    /// The last line break in the whitespace from `index`, leaving `index` after the whitespace.
    private mutating func lastLineBreak(skipping index: inout String.Index) -> String.Index? {
        var last: String.Index?
        while index < text.endIndex {
            read += 1
            let character = text[index]
            guard character.isWhitespace else { break }
            if character.isNewline { last = index }
            index = text.index(after: index)
        }
        return last
    }
}

/// Unicode word boundaries, which `\b` means, found forward once and asked about in increasing order.
struct WordBreaks {
    private let text: String
    /// Boundaries at or after the earliest place still asked about, in order.
    private var found: [String.Index]

    init(_ text: String) {
        self.text = text
        found = [text.startIndex]
    }

    /// Whether `index` is a word boundary; nothing before `floor` is asked about again.
    mutating func isBoundary(_ index: String.Index, from floor: String.Index) -> Bool {
        while let last = found.last, last < index {
            if last < floor { found.removeAll(keepingCapacity: true) }
            found.append(text._wordIndex(after: last))
        }
        if let kept = found.firstIndex(where: { $0 >= floor }), kept > 0 {
            found.removeFirst(kept)
        }
        return found.contains(index)
    }
}
