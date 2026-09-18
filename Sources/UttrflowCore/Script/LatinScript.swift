// The guarantee that dictation writes only Latin letters.
import Foundation

/// What dictation may write: Latin letters, digits, punctuation and symbols, never another script. See `Docs/latin-output.md`.
public enum LatinScript {
    /// Whether every letter in `text` is a Latin one; punctuation, digits, symbols and emoji are not letters.
    public static func isLatin(_ text: String) -> Bool {
        !text.unicodeScalars.contains(where: isForeign)
    }

    /// The text in Latin letters only: Devanagari romanised, any other script transliterated, a romanised sentence start capitalised.
    public static func enforced(_ text: String) -> String {
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

    /// A run of another script through ICU, with anything ICU cannot write in Latin letters dropped.
    static func transliterated(_ run: String) -> String {
        let latin = run.applyingTransform(.toLatin, reverse: false) ?? ""
        let plain = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return String(String.UnicodeScalarView(plain.unicodeScalars.filter { !isForeign($0) }))
    }

    /// Whether a scalar is a letter or a combining mark of a script other than Latin.
    static func isForeign(_ scalar: Unicode.Scalar) -> Bool {
        let properties = scalar.properties
        let isMark = [.nonspacingMark, .spacingMark, .enclosingMark].contains(properties.generalCategory)
        guard properties.isAlphabetic || isMark else { return false }
        return !latinRanges.contains { $0.contains(scalar.value) }
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
        0xFF21...0xFF5A,  // Fullwidth Latin letters.
        0x1D400...0x1D7FF,  // Mathematical alphanumerics.
        0x1F100...0x1F1FF,  // Enclosed alphanumerics supplement, flags included.
        0xE0000...0xE01EF,  // Tags and variation selectors supplement.
    ]
}

extension Transcription {
    /// The same transcription with its Devanagari romanised, its timed words romanised one by one.
    public var romanised: Transcription {
        guard Romaniser.containsDevanagari(text) else { return self }
        return Transcription(
            text: Romaniser.romanised(text), detectedLanguage: detectedLanguage,
            segments: segments.map { segment in
                TranscriptionSegment(
                    text: Romaniser.romanised(segment.text), start: segment.start, end: segment.end,
                    words: segment.words.map {
                        TranscribedWord(text: Romaniser.romanised($0.text), confidence: $0.confidence)
                    })
            },
            audioDuration: audioDuration)
    }
}
