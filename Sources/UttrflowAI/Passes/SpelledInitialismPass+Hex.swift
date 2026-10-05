import UttrflowCore

/// Reads characters spoken after a hex cue ("zero x", "hex", "hash", "pound", "commit", "sha") as one lower-case token.
extension SpelledInitialismPass {
    private struct HexCue {
        let width: Int
        let prefix: String
        let keepsCue: Bool
        let lengths: ClosedRange<Int>
        let exact: Set<Int>?
    }

    /// The cue that opens at `position`, or nil when no cue word stands there.
    private static func hexCue(at position: Int, in live: [Int], draft: Draft) -> HexCue? {
        let key = draft.shape(at: live[position]).key
        let hasNext = position + 1 < live.count && !draft.shape(at: live[position]).endsClause
        if key == "zero" || key == "0", hasNext, draft.shape(at: live[position + 1]).key == "x",
            !draft.shape(at: live[position + 1]).endsClause
        {
            return HexCue(width: 2, prefix: "0x", keepsCue: false, lengths: 1...16, exact: nil)
        }
        guard hasNext else { return nil }
        switch key {
        case "hex": return HexCue(width: 1, prefix: "", keepsCue: true, lengths: 2...16, exact: nil)
        case "hash", "pound":
            return HexCue(width: 1, prefix: "#", keepsCue: false, lengths: 3...8, exact: [3, 6, 8])
        case "commit", "sha": return HexCue(width: 1, prefix: "", keepsCue: true, lengths: 7...40, exact: nil)
        default: return nil
        }
    }

    /// The hex characters one word names: a letter a to f, a digit word, or digits already written.
    private static func hexCharacters(_ shape: WordShape) -> String? {
        if shape.isCutOff { return nil }
        if !shape.key.isEmpty, shape.key.allSatisfy({ $0.isASCII && $0.isNumber }) { return shape.key }
        if let digit = hexDigitWords[shape.key] { return digit }
        guard !ambiguousHexNames.contains(shape.key), let letter = letterNames[shape.key],
            "ABCDEF".contains(letter)
        else { return nil }
        return letter.lowercased()
    }

    private static let hexDigitWords: [String: String] = [
        "zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
    ]

    private static let ambiguousHexNames: Set<String> = ["be", "see"]

    /// Joins each cued run of hex characters whose length the cue allows; any other word ends the run.
    static func joinHexTokens(in draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            guard let cue = hexCue(at: position, in: live, draft: draft) else {
                position += 1
                continue
            }
            var value = ""
            var end = position + cue.width
            var capital = false
            while end < live.count, live[end] == live[end - 1] + 1, !draft.words[live[end]].isLayoutMark {
                let shape = draft.shape(at: live[end])
                if shape.key == "capital", !shape.endsClause, !capital {
                    capital = true
                    end += 1
                    continue
                }
                guard var characters = hexCharacters(shape), !(capital && characters.first?.isNumber == true)
                else { break }
                if capital { characters = characters.uppercased() }
                capital = false
                value += characters
                end += 1
                if shape.endsClause { break }
            }
            if capital { end -= 1 }
            let first = position + cue.width
            guard end > first, cue.lengths.contains(value.count), cue.exact?.contains(value.count) ?? true
            else {
                position += 1
                continue
            }
            let closing = draft.shape(at: live[end - 1]).suffix
            let token = cue.prefix + value
            let written = closing.isEmpty ? token : WordShape.marked(token, with: closing)
            let target = cue.keepsCue ? first : position
            draft.replace(at: live[target], with: written, by: id)
            let kept = cue.keepsCue ? [live[position], live[target]] : [live[target]]
            for index in live[position..<end] where !kept.contains(index) { draft.remove(at: index, by: id) }
            live = draft.presentIndices
            position = target == position ? position + 1 : position + 2
        }
        return draft
    }
}
