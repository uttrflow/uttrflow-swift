/// How a SQL statement quotes a value and a name, read from the text before the caret and never from a database.
package enum SQLQuoting {
    /// The mark a statement already puts round a name: each is one engine's form.
    package enum IdentifierStyle: Sendable, Equatable {
        case double, backtick, bracket
    }

    /// The comparison words after which a quotation is a value.
    private static let valueIntroducers: Set<String> = [
        "=", "<>", "!=", "<", ">", "<=", ">=", "like", "ilike",
    ]

    /// Whether the spoken words end on a phrase the formula table writes as a comparison mark, so a quotation said next is a value.
    package static func endsComparison(_ spoken: [String]) -> Bool {
        FormulaWords.operators.contains { found in
            valueIntroducers.contains(found.mark)
                && spoken.suffix(found.words.count).elementsEqual(found.words)
        }
    }

    /// Whether a quotation spoken right after `key` is a value; any other word leaves it undecided.
    package static func isValuePosition(after key: String?) -> Bool {
        guard let key else { return false }
        return valueIntroducers.contains(key.lowercased())
    }

    /// The last word of the text, which a spoken piece continues from.
    package static func lastWord(of precedingText: String?) -> String? {
        precedingText?.split(whereSeparator: \.isWhitespace).last.map(String.init)
    }

    /// A value in single quotes, with each apostrophe inside it doubled.
    package static func value(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
    }

    /// The opening and closing mark of a name in `style`.
    package static func marks(for style: IdentifierStyle) -> (opening: String, closing: String) {
        switch style {
        case .double: ("\"", "\"")
        case .backtick: ("`", "`")
        case .bracket: ("[", "]")
        }
    }

    /// The one quoting style the text before the caret uses for names, or `nil` when it shows none or more than one.
    package static func identifierStyle(in precedingText: String?) -> IdentifierStyle? {
        guard let precedingText else { return nil }
        let characters = Array(precedingText)
        var seen: Set<IdentifierStyle> = []
        var index = 0
        while index < characters.count {
            switch characters[index] {
            case "'":
                index = closing("'", after: index, in: characters) ?? characters.count
            case "`":
                guard let end = closing("`", after: index, in: characters) else { return nil }
                if isName(characters[(index + 1)..<end]) { seen.insert(.backtick) }
                index = end
            case "\"":
                guard let end = closing("\"", after: index, in: characters) else { return nil }
                if isName(characters[(index + 1)..<end]) { seen.insert(.double) }
                index = end
            case "[":
                if let end = closing("]", after: index, in: characters), isName(characters[(index + 1)..<end])
                {
                    seen.insert(.bracket)
                    index = end
                }
            default:
                break
            }
            index += 1
        }
        return seen.count == 1 ? seen.first : nil
    }

    /// Where the mark that closes the one at `start` stands; `nil` when the text ends first.
    private static func closing(_ mark: Character, after start: Int, in characters: [Character]) -> Int? {
        var index = start + 1
        while index < characters.count {
            if characters[index] == mark {
                // A doubled mark is part of the text, not its end.
                if mark == "'", index + 1 < characters.count, characters[index + 1] == mark {
                    index += 2
                    continue
                }
                return index
            }
            index += 1
        }
        return nil
    }

    /// Whether the characters are a name: letters, digits, underscores and inner spaces, so an array's `[1, 2]` is not one.
    private static func isName(_ text: ArraySlice<Character>) -> Bool {
        guard let first = text.first, first.isLetter || first == "_" else { return false }
        return text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == " " }
    }
}
