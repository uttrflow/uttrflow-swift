// Recognises a payment card number.

/// A card number: a network's prefix, a length it issues, and a Luhn pass. See Docs/clipboard-secrets.md.
enum CardNumberShape {
    /// Whether a card number stands anywhere in the text, on its own rather than inside a longer number.
    static func matches(_ text: String) -> Bool {
        CardNumberRuns.candidates(in: text, tally: SecretShapes.patternTally).contains { run in
            // The run with two characters either side, which is all `standsAlone` looks at.
            let lower = text.index(run.lowerBound, offsetBy: -2, limitedBy: text.startIndex)
            let upper = text.index(run.upperBound, offsetBy: 2, limitedBy: text.endIndex)
            let context = (lower ?? text.startIndex)..<(upper ?? text.endIndex)
            guard let printed = printedForm(of: text[context]) else {
                return hasCardNumber(in: text[run], of: text)
            }
            let before = text.distance(from: context.lowerBound, to: run.lowerBound)
            let after = text.distance(from: run.upperBound, to: context.upperBound)
            let start = printed.index(printed.startIndex, offsetBy: before)
            let end = printed.index(printed.endIndex, offsetBy: -after)
            return hasCardNumber(in: printed[start..<end], of: printed)
        }
    }

    /// Whether the pattern finds a card number in `run` that stands alone in `text`, which holds it.
    static func hasCardNumber(in run: Substring, of text: String) -> Bool {
        run.matches(of: candidate).contains { match in
            standsAlone(match.range, in: text) && isCardNumber(match.output.0.filter(\.isNumber))
        }
    }

    /// Digits unbroken, or in printed groups with one separator throughout; `issuers` rules on length.
    nonisolated(unsafe) static let candidate =
        #/
        [0-9]{4}([\x20\n\-.])[0-9]{4}\1[0-9]{4}\1[0-9]{4}(?:\1[0-9]{3})?   # 4-4-4-4 and 4-4-4-4-3
        | [0-9]{4}([\x20\n\-.])[0-9]{6}\2[0-9]{4,5}                     # 4-6-5 and 4-6-4
        | [0-9]{4}([\x20\n\-.])[0-9]{3}\3[0-9]{3}\3[0-9]{3}              # 4-3-3-3
        | [0-9]{13,19}
        /#

    /// Fullwidth digits zero to nine, which some input methods type.
    static let fullwidthDigits: ClosedRange<UInt32> = 0xFF10...0xFF19

    /// The fullwidth forms of the printable ASCII characters, each 0xFEE0 above its ASCII form.
    static let fullwidthASCII: ClosedRange<UInt32> = 0xFF01...0xFF5E

    /// Whether this scalar separates a card's groups: horizontal Unicode whitespace, or a fullwidth hyphen or full stop.
    static func isSeparator(_ value: UInt32) -> Bool {
        value == 0xFF0D || value == 0xFF0E
            || (!lineBreaks.contains(value) && Unicode.Scalar(value)?.properties.isWhitespace == true)
    }

    /// Newline scalars split columnar text into separate runs rather than joining card groups.
    private static let lineBreaks: Set<UInt32> = [0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029]

    /// The text with fullwidth forms as ASCII, line breaks as `\n` and other spaces as U+0020, character for character; `nil` when nothing changes.
    static func printedForm(of text: Substring) -> String? {
        guard
            text.unicodeScalars.contains(where: { isRewritten($0.value) })
                || text.contains(where: hasDigitWithCombiningMarks)
        else { return nil }
        return String(text.map(printed))
    }

    /// The character as the pattern reads it; a character carrying a combining mark stays as it is.
    private static func printed(_ character: Character) -> Character {
        let scalars = character.unicodeScalars
        guard scalars.count == 1 || character == "\r\n", let value = scalars.first?.value else {
            guard hasDigitWithCombiningMarks(character), let value = scalars.first?.value else {
                return character
            }
            let digit = fullwidthDigits.contains(value) ? value - 0xFEE0 : value
            guard let scalar = Unicode.Scalar(digit) else { return character }
            return Character(scalar)
        }
        if character.isNewline { return "\n" }
        if character.isWhitespace { return " " }
        guard fullwidthASCII.contains(value) else { return character }
        return Character(Unicode.Scalar(UInt8(value - 0xFEE0)))
    }

    /// Whether a decimal digit forms one grapheme with only combining marks.
    private static func hasDigitWithCombiningMarks(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard scalars.count > 1, let first = scalars.first,
            first.value <= 0x7F && (0x30...0x39).contains(first.value)
                || fullwidthDigits.contains(first.value)
        else { return false }
        return scalars.dropFirst().allSatisfy { isCombiningMark($0.value) }
    }

    /// Whether this scalar is a combining mark, which joins the character before it.
    static func isCombiningMark(_ value: UInt32) -> Bool {
        switch Unicode.Scalar(value)?.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: true
        default: false
        }
    }

    /// Whether a scalar needs rewriting before the card pattern sees the printed characters.
    private static func isRewritten(_ value: UInt32) -> Bool {
        guard value != 0x20, value != 0x0A else { return false }
        return fullwidthASCII.contains(value) || Unicode.Scalar(value)?.properties.isWhitespace == true
    }

    /// What joins a number to more of itself in a date, a decimal, a time or an id; a space does not.
    private static let joiners: Set<Character> = ["-", ".", "/", ":", "_"]

    /// Whether the match is bounded by something other than more digits, directly or across one joiner.
    static func standsAlone(_ range: Range<String.Index>, in text: String) -> Bool {
        let before = text[..<range.lowerBound].suffix(2)
        let after = text[range.upperBound...].prefix(2)
        if let last = before.last {
            if last.isNumber || last == "+" { return false }
            if joiners.contains(last), before.count == 2, before.first?.isNumber == true { return false }
        }
        if let first = after.first {
            if first.isNumber { return false }
            if joiners.contains(first), after.count == 2, after.last?.isNumber == true { return false }
        }
        return true
    }

    /// Whether these digits are a length some network issues under its prefix, and pass Luhn.
    static func isCardNumber(_ digits: String) -> Bool {
        issued(digits) && luhn(digits)
    }

    /// Whether some network issues numbers of this length under this prefix.
    private static func issued(_ digits: String) -> Bool {
        issuers.contains { issuer in
            issuer.lengths.contains(digits.count)
                && Int(digits.prefix(issuer.width)).map(issuer.prefixes.contains) == true
        }
    }

    /// The networks in wide use; anything else is a number rather than a card.
    private static let issuers: [Issuer] = [
        Issuer(width: 1, prefixes: 4...4, lengths: [13, 16, 19]),  // Visa
        Issuer(width: 2, prefixes: 51...55, lengths: [16]),  // Mastercard
        Issuer(width: 4, prefixes: 2221...2720, lengths: [16]),  // Mastercard, 2-series
        Issuer(width: 2, prefixes: 34...34, lengths: [15]),  // American Express
        Issuer(width: 2, prefixes: 37...37, lengths: [15]),  // American Express
        Issuer(width: 2, prefixes: 36...36, lengths: [14, 16]),  // Diners Club
        Issuer(width: 3, prefixes: 300...305, lengths: [14, 16]),  // Diners Club
        Issuer(width: 4, prefixes: 3528...3589, lengths: Set(16...19)),  // JCB
        Issuer(width: 4, prefixes: 6011...6011, lengths: Set(16...19)),  // Discover
        Issuer(width: 3, prefixes: 644...649, lengths: Set(16...19)),  // Discover
        Issuer(width: 2, prefixes: 65...65, lengths: Set(16...19)),  // Discover, RuPay
        Issuer(width: 2, prefixes: 62...62, lengths: Set(16...19)),  // UnionPay
        Issuer(width: 2, prefixes: 60...60, lengths: [16]),  // RuPay
        Issuer(width: 2, prefixes: 81...82, lengths: [16]),  // RuPay
        Issuer(width: 3, prefixes: 508...508, lengths: [16]),  // RuPay
        Issuer(width: 4, prefixes: 2200...2204, lengths: Set(16...19)),  // Mir
        Issuer(width: 4, prefixes: 5018...5018, lengths: Set(13...19)),  // Maestro
        Issuer(width: 4, prefixes: 5020...5020, lengths: Set(13...19)),  // Maestro
        Issuer(width: 4, prefixes: 5038...5038, lengths: Set(13...19)),  // Maestro
        Issuer(width: 4, prefixes: 5893...5893, lengths: Set(13...19)),  // Maestro
        Issuer(width: 4, prefixes: 6304...6304, lengths: Set(13...19)),  // Maestro
        Issuer(width: 4, prefixes: 6759...6763, lengths: Set(13...19)),  // Maestro
    ]

    /// The Luhn checksum every card network uses, which a mistyped digit fails.
    private static func luhn(_ digits: String) -> Bool {
        let sum = digits.reversed().enumerated().reduce(0) { total, next in
            guard let digit = next.element.wholeNumberValue else { return total }
            let weighed = next.offset.isMultiple(of: 2) ? digit : digit * 2
            return total + (weighed > 9 ? weighed - 9 : weighed)
        }
        return sum.isMultiple(of: 10)
    }
}

/// A network's prefixes, read over its leading `width` digits, and the lengths it issues under them.
private struct Issuer {
    let width: Int
    let prefixes: ClosedRange<Int>
    let lengths: Set<Int>
}
