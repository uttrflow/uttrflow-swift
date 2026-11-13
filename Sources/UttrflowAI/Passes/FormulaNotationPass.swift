import Foundation
import UttrflowCore

/// Writes a spoken spreadsheet formula as the formula: "a one to a ten" as `A1:A10`, function names in capitals, and operators and brackets as their marks.
struct FormulaNotationPass: PieceCleaningPass {
    static let id: PassID = .formulaNotation
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    /// Whether the cell's text before the caret already begins with `=`.
    var cellHoldsFormula = false

    /// Whether the cell is known to be empty, so a leading "equals" or "formula" opens a formula.
    var cellIsEmpty = false

    /// What separates the arguments of a function, which the system locale decides: a comma or a semicolon.
    var argumentSeparator = ","

    /// The comma or semicolon the system locale puts between function arguments, read when the pipeline is built.
    static var systemSeparator: String {
        Locale.current.decimalSeparator == "," ? ";" : ","
    }

    func apply(_ draft: Draft) -> Draft {
        let live = draft.presentIndices
        guard let first = live.first else { return draft }
        let spoken = live.map { Self.trimmed(draft.words[$0].text) }
        let keys = spoken.map { $0.lowercased() }
        let opens = cellIsEmpty && Self.openers.contains(keys[0])
        guard cellHoldsFormula || opens else { return draft }
        let written = Writer(spoken: spoken, keys: keys, separator: argumentSeparator).run(opening: opens)
        var draft = draft
        draft.replace(at: first, with: written, by: Self.id)
        for index in live.dropFirst() { draft.remove(at: index, by: Self.id) }
        return draft
    }

    /// The word that opens a formula in an empty cell.
    private static let openers: Set<String> = ["equals", "formula"]

    /// A word without the stop or comma the recogniser put after it.
    fileprivate static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:?!"))
    }
}

/// Reads the words of one piece left to right into the marks of a formula.
private struct Writer {
    let spoken: [String]
    let keys: [String]
    let separator: String

    /// One written part: a mark or a name joins its neighbours, a word the speaker said stays apart from the next.
    private struct Part {
        var text: String
        var isWord = false
        var isString = false
    }

    private static let brackets: Set<String> = ["paren", "parenthesis", "bracket"]
    private static let rangeWords: Set<String> = ["to", "through", "colon"]

    func run(opening: Bool) -> String {
        var parts: [Part] = []
        var at = 0
        if opening {
            parts.append(Part(text: "="))
            at = 1
        }
        while at < keys.count {
            if let (cell, length) = cellReference(at) {
                parts.append(Part(text: cell))
                at += length
                // A range is two references joined by "to" or "through".
                if at < keys.count, Self.rangeWords.contains(keys[at]),
                    let (end, endLength) = cellReference(at + 1)
                {
                    parts.append(Part(text: ":" + end))
                    at += 1 + endLength
                }
                continue
            }
            let (found, length) = next(at, after: parts.last)
            // A sheet's name said in quotes takes single quotes, as a reference to it needs.
            if found.text == "!", let sheet = parts.last, sheet.isString {
                parts[parts.count - 1].text = "'" + sheet.text.dropFirst().dropLast() + "'"
            }
            parts.append(found)
            at += length
        }
        return parts.enumerated().reduce(into: "") { text, entry in
            let (position, part) = entry
            if position > 0, part.isWord, parts[position - 1].isWord { text += " " }
            text += part.text
        }
    }

    /// The part standing at `at` and how many words it takes.
    private func next(_ at: Int, after _: Part?) -> (Part, Int) {
        let key = keys[at]
        if key == "quote", let close = keys[(at + 1)...].firstIndex(of: "quote") {
            let inner = spoken[(at + 1)..<close].joined(separator: " ")
            return (Part(text: "\"" + inner + "\"", isString: true), close - at + 1)
        }
        if key == "comma" || key == "semicolon" { return (Part(text: separator), 1) }
        if at + 1 < keys.count, Self.brackets.contains(keys[at + 1]) {
            if key == "open" { return (Part(text: "("), 2) }
            if key == "close" { return (Part(text: ")"), 2) }
        }
        for candidate in FormulaWords.operators where matches(candidate.words, at: at) {
            return (Part(text: candidate.mark), candidate.words.count)
        }
        if FormulaWords.functions.contains(key), at + 2 < keys.count, keys[at + 1] == "open",
            Self.brackets.contains(keys[at + 2])
        {
            return (Part(text: key.uppercased()), 1)
        }
        if key == "true" || key == "false" { return (Part(text: key.uppercased()), 1) }
        if let number = NumberWords.digits(key) { return (Part(text: number), 1) }
        if let (value, length) = NumberWords.cardinal(keys[at...]) {
            return (Part(text: String(value)), length)
        }
        return (Part(text: spoken[at], isWord: true), 1)
    }

    private func matches(_ words: [String], at: Int) -> Bool {
        at + words.count <= keys.count && Array(keys[at..<(at + words.count)]) == words
    }

    /// A cell reference spoken from `at`: an optional "dollar", a letter, an optional "dollar", then the row number.
    private func cellReference(_ at: Int) -> (String, Int)? {
        var position = at
        var column = ""
        var row = ""
        if position < keys.count, keys[position] == "dollar" {
            column = "$"
            position += 1
        }
        guard position < keys.count, spoken[position].count == 1, let letter = spoken[position].first,
            letter.isLetter
        else { return nil }
        column += spoken[position].uppercased()
        position += 1
        if position < keys.count, keys[position] == "dollar" {
            row = "$"
            position += 1
        }
        guard position < keys.count else { return nil }
        let number: (value: Int, count: Int)?
        if let digits = NumberWords.digits(keys[position]), let value = Int(digits) {
            number = (value, 1)
        } else {
            number = NumberWords.cardinal(keys[position...])
        }
        guard let number, (1...1_048_576).contains(number.value) else { return nil }
        return (column + row + String(number.value), position + number.count - at)
    }
}
