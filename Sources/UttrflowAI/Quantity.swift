// A number as written, with whatever symbol is attached to it.

import UttrflowCore

/// A number and the sign or symbol it carries, since "-5", "5%" and "5" are different amounts and share a digit run.
struct Quantity: Equatable, Hashable {
    /// The numeric spelling, with thousands separators already taken out so 12,000 and 12000 are one number.
    let digits: String
    /// A unary sign immediately attached to the number or currency, when the surrounding text makes it a sign.
    let sign: String
    /// A currency before the digits or a percent or degree after them; empty for a bare number.
    let symbol: String

    init(digits: String, sign: String = "", symbol: String) {
        self.digits = digits
        self.sign = sign
        self.symbol = symbol
    }

    /// How it reads, for a refusal that has to name what went missing.
    var written: String {
        symbol == "%" || symbol == "\u{00B0}" ? sign + digits + symbol : sign + symbol + digits
    }
}

/// Reading the quantities out of a text, which is a different job from splitting it into words.
enum Quantities {
    /// Symbols that stand before the digits they belong to.
    static let leading: Set<Character> = ["$", "\u{00A3}", "\u{20AC}", "\u{20B9}", "\u{00A5}"]

    /// Symbols that stand after the digits they belong to.
    static let trailing: Set<Character> = ["%", "\u{00B0}"]

    /// Every number the text states, in order, each with the symbol attached to it.
    static func read(in text: String) -> [Quantity] {
        let characters = Array(text)
        let separators = groupingCommas(in: characters)
        var found: [Quantity] = []
        var index = 0
        while index < characters.count {
            guard characters[index].isNumber else {
                index += 1
                continue
            }
            var end = index
            var hasDecimal = false
            while end < characters.count,
                characters[end].isNumber
                    || separators.contains(end)
                    || isDecimalPoint(characters, at: end, hasDecimal: hasDecimal)
            {
                if characters[end] == "." { hasDecimal = true }
                end += 1
            }
            let digits = String(characters[index..<end]).filter { $0.isNumber || $0 == "." }
            let marker = marker(around: characters, from: index, to: end)
            found.append(Quantity(digits: digits, sign: marker.sign, symbol: marker.symbol))
            index = end
        }
        return found
    }

    /// The positions of the commas that group one number's digits, so "12,345" is one number and "10,20,30" is three.
    static func groupingCommas(in characters: [Character]) -> Set<Int> {
        var found: Set<Int> = []
        var index = 0
        while index < characters.count {
            guard characters[index].isNumber else {
                index += 1
                continue
            }
            let start = index
            var commas: [Int] = []
            while index < characters.count {
                if characters[index].isNumber {
                    index += 1
                } else if characters[index] == ",", index + 1 < characters.count,
                    characters[index + 1].isNumber
                {
                    commas.append(index)
                    index += 1
                } else {
                    break
                }
            }
            guard !commas.isEmpty, !followsDecimalPoint(characters, at: start) else { continue }
            let spelling = String(characters[start..<index])
            if DigitGrouping.thousands.matches(spelling) || DigitGrouping.indian.matches(spelling) {
                found.formUnion(commas)
            }
        }
        return found
    }

    /// Whether the digit run at `start` is the fraction of a decimal, which is never grouped.
    private static func followsDecimalPoint(_ characters: [Character], at start: Int) -> Bool {
        start > 1 && characters[start - 1] == "." && characters[start - 2].isNumber
    }

    /// Whether the character at `index` is a decimal point inside one number rather than the end of it.
    private static func isDecimalPoint(
        _ characters: [Character], at index: Int, hasDecimal: Bool
    ) -> Bool {
        guard !hasDecimal, characters[index] == ".", index > 0, index + 1 < characters.count else {
            return false
        }
        return characters[index - 1].isNumber && characters[index + 1].isNumber
    }

    /// The sign and symbol this run of digits carries: before it, or a trailing symbol with at most a space between.
    private static func marker(
        around characters: [Character], from start: Int, to end: Int
    ) -> (sign: String, symbol: String) {
        var sign = ""
        var symbol = ""
        if start > 0, leading.contains(characters[start - 1]) {
            symbol = String(characters[start - 1])
            sign = unarySign(in: characters, at: start - 2)
        } else {
            sign = unarySign(in: characters, at: start - 1)
            if !sign.isEmpty, start > 1, leading.contains(characters[start - 2]) {
                symbol = String(characters[start - 2])
            }
        }

        var after = end
        if after < characters.count, characters[after] == " " { after += 1 }
        if after < characters.count, trailing.contains(characters[after]) {
            symbol = String(characters[after])
        }
        return (sign, symbol)
    }

    private static func unarySign(in characters: [Character], at index: Int) -> String {
        guard index >= 0, characters[index] == "-" || characters[index] == "+" else { return "" }
        return isUnaryBoundary(in: characters, before: index) ? String(characters[index]) : ""
    }

    private static func isUnaryBoundary(in characters: [Character], before sign: Int) -> Bool {
        if sign == 0 { return true }
        if leading.contains(characters[sign - 1]) {
            return isUnaryBoundary(in: characters, before: sign - 1)
        }
        if characters[sign - 1].isWhitespace {
            var previous = sign - 1
            while previous >= 0, characters[previous].isWhitespace { previous -= 1 }
            guard previous >= 0 else { return true }
            return !characters[previous].isNumber
        }
        return "([{,:".contains(characters[sign - 1])
    }
}
