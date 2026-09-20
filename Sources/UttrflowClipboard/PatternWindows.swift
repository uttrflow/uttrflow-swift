// Finds where a costly pattern could match in a clip, so it reads windows rather than the whole clip.

import Foundation

/// A clip's UTF-8 bytes read in place, and the character positions they fall in.
struct ClipBytes {
    let text: String

    /// Runs `body` over the text's UTF-8, copying it into contiguous storage first only if it is not already.
    static func read<Result>(
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
    static func contains(_ bytes: UnsafeBufferPointer<UInt8>, _ needle: StaticString) -> Bool {
        guard let base = bytes.baseAddress, bytes.count >= needle.utf8CodeUnitCount else { return false }
        return memmem(base, bytes.count, needle.utf8Start, needle.utf8CodeUnitCount) != nil
    }

    /// Whether any of `needles` occurs in the text's bytes; a pattern needing one of them as characters needs it here.
    static func containsAny(_ text: String, _ needles: [StaticString]) -> Bool {
        read(text) { _, bytes in needles.contains { contains(bytes, $0) } }
    }

    /// Whether every byte is ASCII, in which case each byte is its own character except a CR before a LF.
    static func isASCII(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        !bytes.contains { $0 >= 0x80 }
    }

    /// Counts each character-boundary check, so a test can bound the walk without a clock.
    @TaskLocal package static var boundaryTally: ScanTally?

    /// How many bytes the walks test for a character boundary before settling for a scalar one.
    static let characterSteps = 8

    /// The start of the character holding the byte at `offset`, or of its scalar inside a very long character.
    func character(atOrBefore offset: Int) -> String.Index {
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

/// Runs the vendor-key pattern only on windows that open at one of its literal prefixes.
enum VendorKeyWindows {
    /// Characters read from each prefix; the longest shortest match, `dop_v1_` and forty hex digits, is 47.
    static let width = 128

    /// How much of a window must lie after a prefix for that prefix to count as already read.
    static let longestShortestMatch = 48

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
                let start = clip.character(atOrBefore: offset)
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
                if clip.text[start..<end].firstMatch(of: pattern) != nil { return true }
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
        return opensPrefix(bytes, at: offset) ? .bounded : nil
    }

    /// Whether one of the pattern's literal prefixes starts at this byte.
    private static func opensPrefix(_ bytes: UnsafeBufferPointer<UInt8>, at offset: Int) -> Bool {
        func has(_ literal: StaticString) -> Bool {
            let length = literal.utf8CodeUnitCount
            guard offset + length <= bytes.count else { return false }
            let start = literal.utf8Start
            for index in 1..<length where bytes[offset + index] != start[index] { return false }
            return true
        }
        switch bytes[offset] {
        case UInt8(ascii: "s"): return has("sk-") || has("sk_live_") || has("sk_test_") || has("shpat_")
        case UInt8(ascii: "p"): return has("pk_live_") || has("pk_test_")
        case UInt8(ascii: "r"): return has("rk_live_") || has("rk_test_")
        case UInt8(ascii: "g"):
            return has("ghp_") || has("gho_") || has("ghu_") || has("ghs_") || has("ghr_")
                || has("github_pat_")
                || has("glpat-")
        case UInt8(ascii: "x"):
            return has("xoxb-") || has("xoxa-") || has("xoxp-") || has("xoxr-") || has("xoxs-")
                || has("xoxe-")
        case UInt8(ascii: "A"): return has("AKIA") || has("ASIA") || has("AIza")
        case UInt8(ascii: "n"): return has("npm_")
        case UInt8(ascii: "d"): return has("dop_v1_")
        default: return false
        }
    }
}

/// Runs the card-number pattern only over runs of digits, spaces and hyphens long enough to hold a card.
enum CardNumberRuns {
    /// The fewest digits any of the pattern's groupings holds.
    static let fewestDigits = 13

    /// The character ranges of each run of digits, spaces and hyphens holding at least thirteen digits.
    static func candidates(in text: String, tally: ScanTally?) -> [Range<String.Index>] {
        ClipBytes.read(text) { clip, bytes in
            var found: [Range<String.Index>] = []
            var runStart = 0
            var digits = 0
            for offset in 0...bytes.count {
                let byte = offset < bytes.count ? bytes[offset] : 0
                switch byte {
                case UInt8(ascii: "0")...UInt8(ascii: "9"): digits += 1
                case UInt8(ascii: " "), UInt8(ascii: "-"): break
                default:
                    if digits >= fewestDigits {
                        let range = clip.character(atOrBefore: runStart)..<clip.boundary(atOrAfter: offset)
                        tally?.record(clip.text.distance(from: range.lowerBound, to: range.upperBound))
                        found.append(range)
                    }
                    runStart = offset + 1
                    digits = 0
                }
            }
            return found
        }
    }
}

/// Whether a clip holds a separator and the stem of some secret's name, which the named-secret rule cannot match without.
enum NamedSecretStems {
    static func present(in text: String) -> Bool {
        ClipBytes.read(text) { _, bytes in
            guard ClipBytes.contains(bytes, ":") || ClipBytes.contains(bytes, "=") else { return false }
            for offset in bytes.indices where opensStem(bytes, at: offset) { return true }
            return false
        }
    }

    /// Whether a stem starts here, case-insensitively, with `token`'s `k` also read as U+212A KELVIN SIGN.
    private static func opensStem(_ bytes: UnsafeBufferPointer<UInt8>, at offset: Int) -> Bool {
        func has(_ stem: StaticString) -> Bool {
            let length = stem.utf8CodeUnitCount
            guard offset + length <= bytes.count else { return false }
            for index in 0..<length where lowered(bytes[offset + index]) != stem.utf8Start[index] {
                return false
            }
            return true
        }
        switch lowered(bytes[offset]) {
        case UInt8(ascii: "a"): return has("api") || has("access") || has("auth")
        case UInt8(ascii: "s"): return has("secret")
        case UInt8(ascii: "p"): return has("pass") || has("pwd") || has("private")
        case UInt8(ascii: "c"): return has("credential") || has("client")
        case UInt8(ascii: "t"): return has("token") || (has("to") && hasKelvinEn(bytes, at: offset + 2))
        default: return false
        }
    }

    /// Whether U+212A KELVIN SIGN and then `en` stand at this offset.
    private static func hasKelvinEn(_ bytes: UnsafeBufferPointer<UInt8>, at offset: Int) -> Bool {
        guard offset + 5 <= bytes.count else { return false }
        return bytes[offset] == 0xE2 && bytes[offset + 1] == 0x84 && bytes[offset + 2] == 0xAA
            && lowered(bytes[offset + 3]) == UInt8(ascii: "e")
            && lowered(bytes[offset + 4]) == UInt8(ascii: "n")
    }

    private static func lowered(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }
}
