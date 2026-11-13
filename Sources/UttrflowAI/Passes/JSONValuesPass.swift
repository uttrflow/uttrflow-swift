import Foundation
import UttrflowCore

extension PassID {
    /// A JSON fragment's keys and string values quoted, its numbers and literals left bare.
    static let jsonValues: PassID = "jsonValues"
}

/// Writes a JSON fragment's keys and string values quoted and its numbers, `true`, `false` and `null` bare, in a JSON file's code.
struct JSONValuesPass: PieceCleaningPass {
    static let id: PassID = .jsonValues
    static let laws: Set<PassLaw> = Set(PassLaw.allCases)

    func apply(_ draft: Draft) -> Draft {
        let live = draft.presentIndices
        let text = live.map { draft.words[$0].text }.joined(separator: " ")
        guard let fragment = Self.jsonFragment(text), fragment != text, let first = live.first else {
            return draft
        }
        var draft = draft
        draft.replace(at: first, with: fragment, by: Self.id)
        for index in live.dropFirst() { draft.remove(at: index, by: Self.id) }
        return draft
    }

    /// JSON's structural marks; every run of words between two of them is one key or one value.
    private static let jsonMarks: Set<Character> = ["{", "}", "[", "]", ":", ","]

    /// The JSON fragment the written words spell, keys and string values quoted and the rest left bare, or nil with no pair or array to read.
    static func jsonFragment(_ text: String) -> String? {
        var pieces: [(mark: Character?, words: String)] = []
        var run = ""
        for character in text {
            if jsonMarks.contains(character) {
                pieces.append((nil, run))
                pieces.append((character, ""))
                run = ""
            } else {
                run.append(character)
            }
        }
        pieces.append((nil, run))
        guard pieces.contains(where: { $0.mark == ":" || $0.mark == "[" }) else { return nil }
        var written = ""
        for (index, piece) in pieces.enumerated() {
            if let mark = piece.mark {
                written.append(mark)
                if mark == ":" || mark == "," { written.append(" ") }
                continue
            }
            let words = piece.words.trimmingCharacters(in: .whitespaces)
            guard !words.isEmpty else { continue }
            let isKey = pieces.indices.contains(index + 1) && pieces[index + 1].mark == ":"
            // A run already written as a string is kept, so a second reading changes nothing.
            if words.count > 1, words.hasPrefix("\""), words.hasSuffix("\"") {
                written += words
            } else {
                written += isKey ? Quoting.write(words, style: .json) : jsonValue(words)
            }
        }
        return written.trimmingCharacters(in: .whitespaces)
    }

    /// A value as JSON writes it: a number, `true`, `false` or `null` bare, anything else a quoted string.
    private static func jsonValue(_ words: String) -> String {
        if ["true", "false", "null"].contains(words) || isJSONNumber(words) { return words }
        let parts = words.split(separator: " ").map(String.init)
        // Digits said one by one are one number: "one two three" is 123.
        if parts.count > 1, parts.allSatisfy({ $0.count == 1 && $0.allSatisfy(\.isNumber) }) {
            return parts.joined()
        }
        if let read = NumberWords.cardinal(parts[...]), read.count == parts.count {
            return String(read.value)
        }
        return Quoting.write(words, style: .json)
    }

    /// Whether the text is a JSON number literal: an optional minus, digits, and an optional fraction.
    private static func isJSONNumber(_ text: String) -> Bool {
        text.range(of: #"^-?(0|[1-9][0-9]*)(\.[0-9]+)?$"#, options: .regularExpression) != nil
    }
}
