import Foundation
import UttrflowCore

/// Writes a spoken spreadsheet formula as the formula: "a one to a ten" as `A1:A10`, function names in capitals, and operators and brackets as their marks.
struct FormulaNotationPass: PieceCleaningPass {
    static let id: PassID = .formulaNotation
    // Writing a reference adds a digit and a name that were spoken as words, so only these two laws hold.
    static let laws: Set<PassLaw> = [.idempotent, .latinOnly]

    /// Whether the cell's text before the caret already begins with `=`.
    var cellHoldsFormula = false

    /// Whether the cell is known to be empty, so a leading "equals" or "formula" opens a formula.
    var cellIsEmpty = false

    /// Whether the caret stands inside a string literal the cell has opened and not closed.
    var caretInString = false

    /// What separates the arguments of a function, which the system locale decides: a comma or a semicolon.
    var argumentSeparator = ","

    /// The comma or semicolon the system locale puts between function arguments, read when the pipeline is built.
    static var systemSeparator: String {
        Locale.current.decimalSeparator == "," ? ";" : ","
    }

    func apply(_ draft: Draft) -> Draft {
        let live = draft.presentIndices
        guard let first = live.first else { return draft }
        let raw = live.map { draft.words[$0].text }
        let spoken = raw.map(Self.trimmed)
        let keys = spoken.map { $0.lowercased() }
        let opens = cellIsEmpty && Self.openers.contains(keys[0])
        guard cellHoldsFormula || opens else { return draft }
        let writer = Writer(spoken: spoken, raw: raw, keys: keys, separator: argumentSeparator)
        // A sentence said in a formula cell, "the town is divided by a river", holds no reference or bracket to write.
        guard writer.holdsFormula(continuingString: caretInString && cellHoldsFormula) else { return draft }
        let written =
            writer
            .run(opening: opens, continuingString: caretInString && cellHoldsFormula)
        var draft = draft
        draft.replace(at: first, with: written, by: Self.id)
        for index in live.dropFirst() { draft.remove(at: index, by: Self.id) }
        return draft
    }

    /// The word that opens a formula in an empty cell.
    private static let openers: Set<String> = ["equals", "formula"]

    /// A word without the stop or comma the recogniser put after it.
    fileprivate static func trimmed(_ text: String) -> String {
        let bare = text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:?!"))
        // A word that is only a mark, such as a written separator, stays as it is.
        return bare.isEmpty ? text : bare
    }
}

/// Reads the words of one piece left to right into the marks of a formula.
private struct Writer {
    let spoken: [String]
    /// The words as the recogniser wrote them, which a quoted string keeps whole.
    let raw: [String]
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

    /// Whether the words name a cell, say a bracket or quote a string, which is what tells a formula from a sentence.
    func holdsFormula(continuingString: Bool) -> Bool {
        continuingString || keys.filter({ $0 == "quote" }).count >= 2
            || keys.indices.contains { at in
                cellReference(at) != nil
                    || (["open", "close"].contains(keys[at]) && at + 1 < keys.count
                        && Self.brackets.contains(keys[at + 1]))
            }
    }

    func run(opening: Bool, continuingString: Bool = false) -> String {
        var parts: [Part] = []
        var at = 0
        if continuingString {
            // The caret is inside a string literal: its words stay as said until the speaker closes the quotation.
            let close = keys.firstIndex(of: "quote")
            let inner = raw[..<(close ?? raw.count)].joined(separator: " ")
            parts.append(Part(text: close == nil ? inner : inner + "\"", isString: close != nil))
            at = (close ?? keys.count - 1) + 1
        } else if opening {
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
            let inner = raw[(at + 1)..<close].joined(separator: " ")
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
        return (Part(text: raw[at], isWord: true), 1)
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
        // A column is one to three letters said one at a time: "a a one" is AA1.
        var letters = ""
        while position < keys.count, letters.count < 3, spoken[position].count == 1,
            spoken[position].first?.isLetter == true
        {
            letters += spoken[position].uppercased()
            position += 1
        }
        guard !letters.isEmpty else { return nil }
        column += letters
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
