/// Whether text is written in the Latin alphabet, which is the only script a suggestion may write. See `Docs/predict.md`.
public enum LatinScript {
    /// Whether no letter, mark or digit in the text belongs to a script other than Latin; symbols, emoji and spaces never count.
    public static func writes(_ text: some StringProtocol) -> Bool {
        !text.unicodeScalars.contains(where: isForeign)
    }

    /// Whether the scalar is a letter, mark or digit of another script.
    static func isForeign(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.value >= 0x80 else { return false }
        let properties = scalar.properties
        let writing: Bool
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber:
            writing = true
        default:
            writing = properties.isAlphabetic
        }
        return writing && !latinBlocks.contains { $0.contains(scalar.value) }
    }

    /// The blocks whose letters, marks and digits are Latin or attach to any script: accents, variation selectors, fullwidth and styled Latin.
    static let latinBlocks: [ClosedRange<UInt32>] = [
        0x0080...0x024F,  // Latin-1 Supplement, Latin Extended-A and -B
        0x0250...0x02FF,  // IPA Extensions, Spacing Modifier Letters
        0x0300...0x036F,  // Combining Diacritical Marks
        0x1AB0...0x1AFF,  // Combining Diacritical Marks Extended
        0x1D00...0x1DFF,  // Phonetic Extensions, Combining Diacritical Marks Supplement
        0x1E00...0x1EFF,  // Latin Extended Additional
        0x2070...0x209F,  // Superscripts and Subscripts
        0x20D0...0x20FF,  // Combining Marks for Symbols, which keycap emoji use
        0x2100...0x218F,  // Letterlike Symbols, Number Forms
        0x2460...0x24FF,  // Enclosed Alphanumerics
        0x2C60...0x2C7F,  // Latin Extended-C
        0xA720...0xA7FF,  // Latin Extended-D
        0xAB30...0xAB6F,  // Latin Extended-E
        0xFB00...0xFB06,  // Latin ligatures
        0xFE00...0xFE0F,  // Variation Selectors, which emoji use
        0xFE20...0xFE2F,  // Combining Half Marks
        0xFF10...0xFF19,  // Fullwidth digits
        0xFF21...0xFF3A,  // Fullwidth Latin capitals
        0xFF41...0xFF5A,  // Fullwidth Latin small letters
        0x1D400...0x1D6A5,  // Mathematical Latin letters
        0x1D7CE...0x1D7FF,  // Mathematical digits
        0x1F100...0x1F1FF,  // Enclosed Alphanumeric Supplement, which flags use
        0xE0000...0xE01EF,  // Tags and Variation Selectors Supplement, which emoji use
    ]
}
