// Finds where a costly pattern could match in a clip, so it reads windows rather than the whole clip.

import Foundation

/// A clip's UTF-8 bytes read in place, and the character positions they fall in.
package struct ClipBytes {
    package let text: String

    /// Runs `body` over the text's UTF-8, copying it into contiguous storage first only if it is not already.
    package static func read<Result>(
        _ text: String, _ body: (ClipBytes, UnsafeBufferPointer<UInt8>) -> Result
    ) -> Result {
        if let result = text.utf8.withContiguousStorageIfAvailable({ body(ClipBytes(text: text), $0) }) {
            return result
        }
        var copy = text
        copy.makeContiguousUTF8()
        return copy.utf8.withContiguousStorageIfAvailable { body(ClipBytes(text: copy), $0) }
            ?? body(ClipBytes(text: copy), UnsafeBufferPointer(start: nil, count: 0))
    }

    /// Whether `needle` occurs anywhere in the bytes, which every character-level occurrence requires.
    package static func contains(_ bytes: UnsafeBufferPointer<UInt8>, _ needle: StaticString) -> Bool {
        guard let base = bytes.baseAddress, bytes.count >= needle.utf8CodeUnitCount else { return false }
        return memmem(base, bytes.count, needle.utf8Start, needle.utf8CodeUnitCount) != nil
    }

    /// Whether any of `needles` occurs in the text's bytes; a pattern needing one of them as characters needs it here.
    package static func containsAny(_ text: String, _ needles: [StaticString]) -> Bool {
        read(text) { _, bytes in needles.contains { contains(bytes, $0) } }
    }

    /// Whether every byte is ASCII, in which case each byte is its own character except a CR before a LF.
    package static func isASCII(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        !bytes.contains { $0 >= 0x80 }
    }

    /// Counts each character-boundary check, so a test can bound the walk without a clock.
    @TaskLocal package static var boundaryTally: ScanTally?

    /// How many bytes the walks test for a character boundary before settling for a scalar one.
    static let characterSteps = 8

    /// The start of the character holding the byte at `offset`, or of its scalar inside a very long character.
    package func character(atOrBefore offset: Int) -> String.Index {
        var probe = offset
        while probe > 0, offset - probe < Self.characterSteps {
            if let index = characterIndex(at: probe) { return index }
            probe -= 1
        }
        guard probe > 0 else { return text.startIndex }
        var scalar = offset
        while scalar > 0, isContinuation(scalar) { scalar -= 1 }
        return text.utf8.index(text.utf8.startIndex, offsetBy: scalar)
    }

    /// The first character boundary at or after the byte at `offset`, or scalar boundary inside a very long character.
    func boundary(atOrAfter offset: Int) -> String.Index {
        let count = text.utf8.count
        var probe = offset
        while probe < count, probe - offset < Self.characterSteps {
            if let index = characterIndex(at: probe) { return index }
            probe += 1
        }
        guard probe < count else { return text.endIndex }
        var scalar = offset
        while scalar < count, isContinuation(scalar) { scalar += 1 }
        return text.utf8.index(text.utf8.startIndex, offsetBy: scalar)
    }

    /// The character index at a byte offset, when a character starts there.
    private func characterIndex(at offset: Int) -> String.Index? {
        Self.boundaryTally?.record(1)
        return text.utf8.index(text.utf8.startIndex, offsetBy: offset).samePosition(in: text)
    }

    /// Whether the byte at `offset` continues a scalar rather than starting one.
    private func isContinuation(_ offset: Int) -> Bool {
        text.utf8[text.utf8.index(text.utf8.startIndex, offsetBy: offset)] & 0xC0 == 0x80
    }

    func byteOffset(of index: String.Index) -> Int {
        text.utf8.distance(from: text.utf8.startIndex, to: index)
    }
}

/// Runs the vendor-key pattern on bounded windows around literal prefixes.
enum VendorKeyWindows {
    /// Characters read from each prefix, well past the longest shortest match of any row.
    static let width = 128

    /// How much of a window must lie after a prefix for that prefix to count as already read.
    static let longestShortestMatch = VendorKeyPrefixes.longestShortestMatch + 1

    static func matches(_ text: String, pattern: Regex<Substring>, tally: ScanTally?) -> Bool {
        ClipBytes.read(text) { clip, bytes in
            // Offsets before which every prefix, or every prefix but `SG.`, was already read whole.
            var coveredAll = 0
            var coveredShort = 0
            var offset = 0
            while offset < bytes.count {
                defer { offset += 1 }
                guard offset >= coveredAll, let prefix = prefix(bytes, at: offset) else { continue }
                let isSendGrid = prefix == .sendGrid
                guard isSendGrid || offset >= coveredShort else { continue }
                // The window carries one preceding character for the regex boundary check.
                let contextOffset = offset == 0 ? 0 : offset - 1
                let start = clip.character(atOrBefore: contextOffset)
                let end: String.Index
                if isSendGrid {
                    // Its first segment has no longest length, so the window runs to the end of the token.
                    var stop = offset
                    while stop < bytes.count, isKeyByte(bytes[stop]) { stop += 1 }
                    end = clip.boundary(atOrAfter: stop)
                    coveredAll = stop
                } else {
                    end =
                        clip.text.index(start, offsetBy: width, limitedBy: clip.text.endIndex)
                        ?? clip.text.endIndex
                    let safe =
                        clip.text.index(end, offsetBy: -longestShortestMatch, limitedBy: start) ?? start
                    coveredShort = end == clip.text.endIndex ? bytes.count : clip.byteOffset(of: safe) + 1
                }
                tally?.record(clip.text.distance(from: start, to: end))
                let window = clip.text[start..<end]
                if window.matches(of: pattern).contains(where: {
                    !CredentialPlaceholder.matches(String($0.output))
                }) {
                    return true
                }
            }
            return false
        }
    }

    /// Which kind of prefix opens here: one whose shortest match is bounded, or SendGrid's, which is not.
    private enum Prefix { case bounded, sendGrid }

    /// The bytes every vendor key is written in: letters, digits, `_`, `-` and `.`.
    private static func isKeyByte(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
            UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"), UInt8(ascii: "-"), UInt8(ascii: "."):
            true
        default: false
        }
    }

    private static func prefix(_ bytes: UnsafeBufferPointer<UInt8>, at offset: Int) -> Prefix? {
        if bytes[offset] == UInt8(ascii: "S") {
            return offset + 2 < bytes.count && bytes[offset + 1] == UInt8(ascii: "G")
                && bytes[offset + 2] == UInt8(ascii: ".") ? .sendGrid : nil
        }
        return VendorKeyPrefixes.opens(bytes, at: offset) ? .bounded : nil
    }

}

/// Runs the card-number pattern only over runs of digits, horizontal spaces, hyphens and full stops long enough to hold a card.
enum CardNumberRuns {
    /// The fewest digits any of the pattern's groupings holds.
    static let fewestDigits = 13

    /// The character ranges of each run of digits and separators holding at least thirteen digits.
    static func candidates(in text: String, tally: ScanTally?) -> [Range<String.Index>] {
        ClipBytes.read(text) { clip, bytes in
            var found: [Range<String.Index>] = []
            var runStart = 0
            var digits = 0
            var offset = 0
            while offset <= bytes.count {
                if offset < bytes.count, let (width, isDigit) = runCharacter(bytes, at: offset) {
                    if isDigit { digits += 1 }
                    offset += width
                    continue
                }
                if digits >= fewestDigits {
                    let range = clip.character(atOrBefore: runStart)..<clip.boundary(atOrAfter: offset)
                    tally?.record(clip.text.distance(from: range.lowerBound, to: range.upperBound))
                    found.append(range)
                }
                runStart = offset + 1
                digits = 0
                offset += 1
            }
            return found
        }
    }

    /// The width in bytes of the digit or separator scalar starting at `offset`, and whether it is a digit.
    private static func runCharacter(
        _ bytes: UnsafeBufferPointer<UInt8>, at offset: Int
    ) -> (width: Int, isDigit: Bool)? {
        let lead = bytes[offset]
        switch lead {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return (1, true)
        case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "-"), UInt8(ascii: "."): return (1, false)
        case 0xC2...0xEF:
            let width = lead < 0xE0 ? 2 : 3
            guard offset + width <= bytes.count else { return nil }
            var value = UInt32(lead & (width == 2 ? 0x1F : 0x0F))
            for index in 1..<width { value = value << 6 | UInt32(bytes[offset + index] & 0x3F) }
            if CardNumberShape.fullwidthDigits.contains(value) { return (width, true) }
            return CardNumberShape.isSeparator(value) ? (width, false) : nil
        default: return nil
        }
    }
}

/// Whether a clip has an assignment separator and a named-secret keyword stem.
enum NamedSecretStems {
    /// The first three letters of every keyword, packed so the scan needs no substring allocation.
    private static let prefixes: Set<UInt32> = Set(
        NamedSecretScan.keywords.compactMap { keyword in
            guard keyword.count >= 3 else { return nil }
            return (UInt32(lowered(keyword[0])) << 16) | (UInt32(lowered(keyword[1])) << 8)
                | UInt32(lowered(keyword[2]))
        })

    static func present(in text: String) -> Bool {
        ClipBytes.read(text) { _, bytes in
            guard ClipBytes.contains(bytes, ":") || ClipBytes.contains(bytes, "=") else { return false }
            guard bytes.count >= 3 else { return false }
            return (0...(bytes.count - 3)).contains { offset in
                let prefix =
                    (UInt32(lowered(bytes[offset])) << 16)
                    | (UInt32(lowered(bytes[offset + 1])) << 8) | UInt32(lowered(bytes[offset + 2]))
                return prefixes.contains(prefix)
            }
        }
    }

    private static func lowered(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }
}
