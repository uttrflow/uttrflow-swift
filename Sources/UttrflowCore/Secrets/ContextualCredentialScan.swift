/// Recognises a generated value after a short credential phrase, as `password is <value>` does.
enum ContextualCredentialScan {
    private static let maximumContextBytes = 96
    private static let maximumContextWords = 8
    private static let minimumCredentialAlphanumerics = 5

    private struct CredentialCue {
        let end: Int
        let acceptsCredentialSpecificPunctuation: Bool
    }

    /// Checks each line's phrase cues once, without rescanning a long clip per cue.
    static func matches(_ text: String, tally: ScanTally?) -> Bool {
        ClipBytes.read(text) { _, bytes in
            // Every phrase has a space or tab before its `is` or `for`.
            guard ClipBytes.contains(bytes, " ") || ClipBytes.contains(bytes, "\t") else { return false }
            var read = 0
            defer { tally?.record(read) }
            var lineStart = 0
            while lineStart < bytes.count {
                var lineEnd = lineStart
                while lineEnd < bytes.count, !isLineBreak(bytes[lineEnd]) {
                    read += 1
                    lineEnd += 1
                }
                var offset = lineStart
                while offset < lineEnd {
                    read += 1
                    if let cue = opensKeyword(bytes, at: offset, read: &read),
                        let value = valueRange(after: cue.end, before: lineEnd, in: bytes, read: &read),
                        isCredential(
                            value,
                            acceptsCredentialSpecificPunctuation: cue.acceptsCredentialSpecificPunctuation,
                            in: bytes, read: &read)
                    {
                        return true
                    }
                    offset += 1
                }
                lineStart = lineEnd + 1
            }
            return false
        }
    }

    /// Whether a credential phrase starts at this word boundary, and where the phrase ends.
    private static func opensKeyword(
        _ bytes: UnsafeBufferPointer<UInt8>, at start: Int, read: inout Int
    ) -> CredentialCue? {
        guard isWordStart(bytes, at: start), start == 0 || !isWordByte(bytes[start - 1]) else { return nil }
        switch lowered(bytes[start]) {
        case UInt8(ascii: "p"):
            return credentialCue(
                wordEnd("password", in: bytes, at: start, read: &read), joinedPunctuation: true)
                ?? credentialCue(
                    wordEnd("passcode", in: bytes, at: start, read: &read), joinedPunctuation: true)
                ?? credentialCue(
                    wordEnd("passphrase", in: bytes, at: start, read: &read), joinedPunctuation: true)
                ?? credentialCue(wordEnd("pin", in: bytes, at: start, read: &read), joinedPunctuation: true)
        case UInt8(ascii: "t"):
            return credentialCue(wordEnd("token", in: bytes, at: start, read: &read), joinedPunctuation: true)
        case UInt8(ascii: "s"):
            return credentialCue(
                wordEnd("secret", in: bytes, at: start, read: &read), joinedPunctuation: true)
        case UInt8(ascii: "c"):
            return credentialCue(wordEnd("code", in: bytes, at: start, read: &read), joinedPunctuation: false)
        case UInt8(ascii: "k"):
            return credentialCue(wordEnd("key", in: bytes, at: start, read: &read), joinedPunctuation: true)
        case UInt8(ascii: "a"):
            guard let apiEnd = wordEnd("api", in: bytes, at: start, read: &read) else { return nil }
            var keyStart = apiEnd
            if keyStart < bytes.count,
                bytes[keyStart] == UInt8(ascii: " ") || bytes[keyStart] == UInt8(ascii: "_")
                    || bytes[keyStart] == UInt8(ascii: "-")
            {
                keyStart += 1
            }
            return credentialCue(
                wordEnd("key", in: bytes, at: keyStart, read: &read), joinedPunctuation: true)
        default:
            return nil
        }
    }

    private static func credentialCue(_ end: Int?, joinedPunctuation: Bool) -> CredentialCue? {
        guard let end else { return nil }
        return CredentialCue(end: end, acceptsCredentialSpecificPunctuation: joinedPunctuation)
    }

    /// The token after `is`, or after `:` or `=` only past a `for …` context, which named assignments leave out.
    private static func valueRange(
        after start: Int, before lineEnd: Int, in bytes: UnsafeBufferPointer<UInt8>, read: inout Int
    ) -> Range<Int>? {
        var cursor = skipSpaces(from: start, before: lineEnd, in: bytes, read: &read)
        if let isEnd = wordEnd("is", in: bytes, at: cursor, before: lineEnd, read: &read) {
            let valueStart = skipSpaces(from: isEnd, before: lineEnd, in: bytes, read: &read)
            guard valueStart < lineEnd else { return nil }
            return tokenRange(from: valueStart, before: lineEnd, in: bytes, read: &read)
        }
        guard let forEnd = wordEnd("for", in: bytes, at: cursor, before: lineEnd, read: &read) else {
            return nil
        }
        cursor = skipSpaces(from: forEnd, before: lineEnd, in: bytes, read: &read)
        let contextStart = cursor
        var words = 0
        while cursor < lineEnd, cursor - contextStart <= maximumContextBytes, words < maximumContextWords {
            if let valueStart = separatorValueStart(at: cursor, before: lineEnd, in: bytes, read: &read) {
                return tokenRange(from: valueStart, before: lineEnd, in: bytes, read: &read)
            }
            if bytes[cursor] == UInt8(ascii: ",") || bytes[cursor] == UInt8(ascii: ";") { return nil }
            while cursor < lineEnd, !isHorizontalSpace(bytes[cursor]),
                bytes[cursor] != UInt8(ascii: ":"), bytes[cursor] != UInt8(ascii: "=")
            {
                read += 1
                cursor += 1
            }
            if cursor < lineEnd,
                bytes[cursor] == UInt8(ascii: ":") || bytes[cursor] == UInt8(ascii: "=")
            {
                return tokenRange(
                    from: skipSpaces(from: cursor + 1, before: lineEnd, in: bytes, read: &read),
                    before: lineEnd, in: bytes, read: &read)
            }
            words += 1
            cursor = skipSpaces(from: cursor, before: lineEnd, in: bytes, read: &read)
        }
        return nil
    }

    /// The start of a value following a same-line `is`, colon or equals sign.
    private static func separatorValueStart(
        at offset: Int, before end: Int, in bytes: UnsafeBufferPointer<UInt8>, read: inout Int
    ) -> Int? {
        if let isEnd = wordEnd("is", in: bytes, at: offset, before: end, read: &read) {
            let start = skipSpaces(from: isEnd, before: end, in: bytes, read: &read)
            return start < end ? start : nil
        }
        guard offset < end else { return nil }
        read += 1
        guard bytes[offset] == UInt8(ascii: ":") || bytes[offset] == UInt8(ascii: "=") else { return nil }
        let start = skipSpaces(from: offset + 1, before: end, in: bytes, read: &read)
        return start < end ? start : nil
    }

    /// One whitespace-delimited value with sentence punctuation removed at its edges.
    private static func tokenRange(
        from start: Int, before end: Int, in bytes: UnsafeBufferPointer<UInt8>, read: inout Int
    ) -> Range<Int>? {
        if start < end, bytes[start] == UInt8(ascii: "<") {
            var placeholderEnd = start + 1
            while placeholderEnd < end, bytes[placeholderEnd] != UInt8(ascii: ">") {
                read += 1
                placeholderEnd += 1
            }
            if placeholderEnd < end {
                read += 1
                return start..<(placeholderEnd + 1)
            }
        }
        var stop = start
        while stop < end, !isHorizontalSpace(bytes[stop]) {
            read += 1
            stop += 1
        }
        var lower = start
        var upper = stop
        while lower < upper, isOpeningPunctuation(bytes[lower]) { lower += 1 }
        while upper > lower, isClosingPunctuation(bytes[upper - 1]) { upper -= 1 }
        return lower < upper ? lower..<upper : nil
    }

    /// Whether this value carries a concrete credential signal rather than a prose word or placeholder.
    private static func isCredential(
        _ range: Range<Int>, acceptsCredentialSpecificPunctuation: Bool,
        in bytes: UnsafeBufferPointer<UInt8>, read: inout Int
    ) -> Bool {
        let value = String(decoding: bytes[range], as: UTF8.self)
        let isAngleRedaction = isAngleRedaction(value)
        guard
            !CredentialPlaceholder.matches(value)
                || (acceptsCredentialSpecificPunctuation && isAngleRedaction)
        else { return false }
        var hasDigit = false
        var hasCredentialPunctuation = false
        var hasJoinedWordPunctuation = false
        var letterOrDigitCount = 0
        for byte in bytes[range] {
            read += 1
            if isAlphaNumeric(byte) { letterOrDigitCount += 1 }
            hasDigit = hasDigit || isDigit(byte)
            hasCredentialPunctuation = hasCredentialPunctuation || isCredentialPunctuation(byte)
            hasJoinedWordPunctuation = hasJoinedWordPunctuation || isCredentialSpecificPunctuation(byte)
        }
        // Cue-specific punctuation avoids mistaking source identifiers for credentials.
        return letterOrDigitCount > 0
            && (hasDigit || SecretShapes.looksGenerated(value)
                || (acceptsCredentialSpecificPunctuation && isAngleRedaction)
                || ((hasCredentialPunctuation
                    || (acceptsCredentialSpecificPunctuation && hasJoinedWordPunctuation))
                    && letterOrDigitCount >= minimumCredentialAlphanumerics))
    }

    private static func isAngleRedaction(_ value: String) -> Bool {
        value == "<value>"
            || (value.first == "<" && value.hasSuffix(" chars>")
                && Int(value.dropFirst().dropLast(" chars>".count)) != nil)
    }

    /// Where an ASCII word ends if it matches here, without matching a prefix of a larger word.
    private static func wordEnd(
        _ word: StaticString, in bytes: UnsafeBufferPointer<UInt8>, at start: Int,
        before limit: Int = Int.max, read: inout Int
    ) -> Int? {
        guard start >= 0, start < bytes.count else { return nil }
        let count = word.utf8CodeUnitCount
        let end = start + count
        guard end <= min(bytes.count, limit) else { return nil }
        for index in 0..<count {
            read += 1
            let expected = lowered(word.utf8Start[index])
            guard lowered(bytes[start + index]) == expected else { return nil }
        }
        guard end == limit || end == bytes.count || !isWordByte(bytes[end]) else { return nil }
        return end
    }

    private static func skipSpaces(
        from start: Int, before end: Int, in bytes: UnsafeBufferPointer<UInt8>, read: inout Int
    ) -> Int {
        var cursor = start
        while cursor < end, isHorizontalSpace(bytes[cursor]) {
            read += 1
            cursor += 1
        }
        return cursor
    }

    private static func isWordStart(_ bytes: UnsafeBufferPointer<UInt8>, at offset: Int) -> Bool {
        guard offset < bytes.count else { return false }
        let byte = lowered(bytes[offset])
        return (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
    }

    private static func isWordByte(_ byte: UInt8) -> Bool {
        let value = lowered(byte)
        return (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(value)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(value) || byte == UInt8(ascii: "_")
    }

    private static func isAlphaNumeric(_ byte: UInt8) -> Bool {
        let value = lowered(byte)
        return (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(value)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(value)
    }

    private static func lowered(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    private static func isCredentialPunctuation(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "!"), UInt8(ascii: "@"), UInt8(ascii: "#"), UInt8(ascii: "$"),
            UInt8(ascii: "%"), UInt8(ascii: "^"), UInt8(ascii: "&"), UInt8(ascii: "*"),
            UInt8(ascii: "~"):
            true
        default:
            false
        }
    }

    private static func isCredentialSpecificPunctuation(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "_") || byte == UInt8(ascii: "-")
            || byte == UInt8(ascii: "<") || byte == UInt8(ascii: ">")
    }

    private static func isHorizontalSpace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t")
    }

    private static func isLineBreak(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
    }

    private static func isOpeningPunctuation(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: "("), UInt8(ascii: "["), UInt8(ascii: "{"):
            true
        default:
            false
        }
    }

    private static func isClosingPunctuation(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: ")"), UInt8(ascii: "]"),
            UInt8(ascii: "}"), UInt8(ascii: "."), UInt8(ascii: ","), UInt8(ascii: "!"),
            UInt8(ascii: "?"), UInt8(ascii: ";"):
            true
        default:
            false
        }
    }
}
