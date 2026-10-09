// The guarantee that dictation writes only Latin letters.
import Foundation

/// What one scalar is to the Latin-only rule; the single classifier every Latin-script check is built on.
public enum ScriptClass: Sendable, Equatable {
    /// A scalar in a block Latin text uses: ASCII, accented and styled Latin, fullwidth Latin and its digits.
    case latin
    /// A letter or combining mark of another script.
    case foreignLetter
    /// A digit or other number of another script.
    case foreignNumber
    /// Punctuation, symbols, emoji and spaces, which belong to no script.
    case neutral

    /// The class of `scalar`, read from its Unicode properties and the one Latin table.
    public static func of(_ scalar: Unicode.Scalar) -> ScriptClass {
        if LatinScript.isInLatinRange(scalar) { return .latin }
        let properties = scalar.properties
        if properties.isAlphabetic { return .foreignLetter }
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return .foreignLetter
        case .decimalNumber, .letterNumber, .otherNumber: return .foreignNumber
        default: return .neutral
        }
    }
}

/// What script enforcement wrote and how many words each conversion produced; the counts carry no text.
public struct ScriptEnforcement: Sendable, Equatable {
    /// The text in Latin letters only.
    public let text: String
    /// Words that held Devanagari and were romanised.
    public let wordsRomanised: Int
    /// Words that held another non-Latin script and were transliterated.
    public let wordsTransliterated: Int
}

/// What dictation may write: Latin letters, digits, punctuation and symbols, never another script. See `Docs/latin-output.md`.
public enum LatinScript {
    /// Whether every letter in `text` is a Latin one; digits of any script, punctuation, symbols and emoji are not letters.
    public static func isLatin(_ text: some StringProtocol) -> Bool {
        !text.unicodeScalars.contains(where: isForeign)
    }

    /// Whether no letter, mark or digit in `text` belongs to another script; the check a suggestion must pass before it is written.
    public static func writesOnlyLatin(_ text: some StringProtocol) -> Bool {
        text.unicodeScalars.allSatisfy { [.latin, .neutral].contains(ScriptClass.of($0)) }
    }

    /// The text in Latin letters only: Devanagari romanised, any other script transliterated, a romanised sentence start capitalised.
    public static func enforced(_ text: String) -> String {
        enforcement(of: text).text
    }

    /// `enforced` with the count of words each conversion wrote, so a written word that was not heard has a named origin.
    public static func enforcement(of text: String) -> ScriptEnforcement {
        var romanised = 0
        var transliterated = 0
        for word in text.split(whereSeparator: \.isWhitespace) {
            if Romaniser.containsDevanagari(String(word)) { romanised += 1 }
            if word.unicodeScalars.contains(where: { isForeign($0) && !Romaniser.isDevanagari($0) }) {
                transliterated += 1
            }
        }
        return ScriptEnforcement(
            text: latinText(text), wordsRomanised: romanised, wordsTransliterated: transliterated)
    }

    /// The Latin-only form of `text`; `enforcement(of:)` is its one caller.
    private static func latinText(_ text: String) -> String {
        guard Romaniser.containsDevanagari(text) || !isLatin(text) || containsForeignDigit(text) else {
            return text
        }
        let romanised = Romaniser.romanised(text, capitalisingSentences: true)
        var output = String.UnicodeScalarView()
        var foreign = String.UnicodeScalarView()
        func flush() {
            guard !foreign.isEmpty else { return }
            output.append(contentsOf: transliterated(String(foreign)).unicodeScalars)
            foreign.removeAll()
        }
        for scalar in romanised.unicodeScalars {
            if isForeign(scalar) {
                foreign.append(scalar)
            } else if let digit = westernDigit(scalar) {
                flush()
                output.append(digit)
            } else {
                flush()
                output.append(scalar)
            }
        }
        flush()
        return String(output)
    }

    /// Whether most letters in `text` are of a script other than Latin and Devanagari, which no English or Hindi speech produces.
    public static func isMostlyUntranscribedScript(_ text: some StringProtocol) -> Bool {
        var transcribed = 0
        var other = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            if isInLatinRange(scalar) || Romaniser.isDevanagari(scalar) {
                transcribed += 1
            } else {
                other += 1
            }
        }
        return other > transcribed
    }

    /// A run of another script through ICU, with anything ICU cannot write in Latin letters dropped.
    static func transliterated(_ run: String) -> String {
        let latin = run.applyingTransform(.toLatin, reverse: false) ?? ""
        let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return String(String.UnicodeScalarView(plain.unicodeScalars.filter { !isForeign($0) }))
    }

    /// Whether a scalar is a letter or a combining mark of a script other than Latin.
    static func isForeign(_ scalar: Unicode.Scalar) -> Bool {
        ScriptClass.of(scalar) == .foreignLetter
    }

    /// Whether a scalar sits in a block Latin text uses; the one table every Latin-script check consults.
    public static func isInLatinRange(_ scalar: Unicode.Scalar) -> Bool {
        latinRanges.contains { $0.contains(scalar.value) }
    }

    /// Whether any decimal digit is written in a script other than Latin.
    static func containsForeignDigit(_ text: String) -> Bool {
        text.unicodeScalars.contains { westernDigit($0) != nil }
    }

    /// A decimal digit of another script as its Western digit, or `nil` for anything else.
    static func westernDigit(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        guard !scalar.isASCII, scalar.properties.numericType == .decimal,
            let value = scalar.properties.numericValue, let digit = Unicode.Scalar(0x30 + UInt32(value))
        else { return nil }
        return digit
    }

    /// Latin letters and the combining marks, variation selectors and letter-like symbols Latin text uses.
    static let latinRanges: [ClosedRange<UInt32>] = [
        0x0000...0x02FF,  // Basic Latin through the spacing modifier letters.
        0x0300...0x036F,  // Combining diacritical marks.
        0x1AB0...0x1AFF,  // Combining diacritical marks, extended.
        0x1D00...0x1EFF,  // Phonetic extensions and Latin extended additional.
        0x2070...0x218F,  // Superscripts, combining marks for symbols, letter-like symbols, number forms.
        0x2460...0x24FF,  // Enclosed alphanumerics.
        0x2C60...0x2C7F,  // Latin extended C.
        0xA720...0xA7FF,  // Latin extended D.
        0xAB30...0xAB6F,  // Latin extended E.
        0xFB00...0xFB06,  // Latin ligatures.
        0xFE00...0xFE0F,  // Variation selectors, which emoji carry.
        0xFE20...0xFE2F,  // Combining half marks.
        0xFF10...0xFF19,  // Fullwidth digits.
        0xFF21...0xFF5A,  // Fullwidth Latin letters.
        0x1D400...0x1D6A5,  // Mathematical Latin letters; the rest of the block before the digits is Greek.
        0x1D7CE...0x1D7FF,  // Mathematical digits.
        0x1F100...0x1F1FF,  // Enclosed alphanumerics supplement, flags included.
        0xE0000...0xE01EF,  // Tags and variation selectors supplement.
    ]
}
