import UttrflowCore

extension LayoutWordsPass {
    /// The words that name a part of a text, which a letter or a roman numeral then numbers. "plan" and "option" are left out: they name things, not parts.
    private static let labelWords: Set<String> = [
        "item", "paragraph", "limb", "clause", "subclause", "subparagraph",
    ]

    /// Words that put a label word inside a noun phrase, so "the item a customer buys" and "new paragraph" are not labels.
    private static let nounPhraseOpeners: Set<String> = [
        "new", "the", "this", "that", "these", "those", "a", "an", "each", "every", "any", "same", "one",
        "per",
        "of", "your", "my", "our", "their", "its", "his", "her",
    ]

    private static let joiners: Set<String> = ["and", "or", "then", "also"]

    private static let letters = "abcdefghijklmnopqrstuvwxyz".map(String.init)
    private static let romans = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x"]

    /// One label said at a position: the words that name it and the letter or numeral after them.
    private struct Label {
        let position: Int
        let length: Int
        let phrase: String
        let token: String
    }

    /// Writes "item a ... item b ..." as "(a)" and "(b)" lines, only for two or more labels said in order from the first.
    func layOutLetteredItems(_ draft: inout Draft) {
        guard layout.contains(.lists) else { return }
        let live = draft.presentIndices
        var series: [[Label]] = []
        var run: [Label] = []
        var sequence: [String] = []
        var spoken = 0
        for position in live.indices where position >= spoken {
            guard let label = label(at: position, in: live, of: draft) else { continue }
            spoken = position + label.length
            if let last = run.last, last.phrase == label.phrase,
                let at = sequence.firstIndex(of: last.token), at + 1 < sequence.count,
                sequence[at + 1] == label.token,
                hasItemBetween(last.position + last.length, label.position, in: live, of: draft)
            {
                run.append(label)
                continue
            }
            if run.count > 1 { series.append(run) }
            run = []
            // A series opens on its first letter or its first numeral, and the opener says which it counts in.
            if label.token == "a" {
                (run, sequence) = ([label], Self.letters)
            } else if label.token == "i" {
                (run, sequence) = ([label], Self.romans)
            }
        }
        if run.count > 1 { series.append(run) }
        for items in series {
            for item in items {
                if item.position > 0 { removeClauseMarkBeforeList(at: item.position, in: live, from: &draft) }
                // The label word becomes the break, or goes at the head of the text; the letter is the enumerator "(a)".
                let opener = live[item.position]
                let letter = live[item.position + item.length - 1]
                if item.position == 0 {
                    draft.remove(at: opener, by: Self.id)
                } else {
                    draft.replace(at: opener, with: "\n", by: Self.id)
                    draft.words[opener].breakEvidence = .spokenCommand
                }
                for index in live[item.position + 1..<item.position + item.length - 1] {
                    draft.remove(at: index, by: Self.id)
                }
                draft.replace(at: letter, with: "(\(item.token))", by: Self.id)
            }
        }
    }

    /// Whether these words say a label and the first letter or numeral after it, so a label said later would continue that series.
    public static func mayOpenSeries(_ words: [String]) -> Bool {
        let keys = words.map { WordShape($0).key }
        for index in keys.indices.dropLast() {
            let named = keys[index] == "sub" ? 2 : 1
            let isLabel =
                named == 2
                ? ["clause", "paragraph"].contains(keys[index + 1]) : labelWords.contains(keys[index])
            if isLabel, index + named < keys.count, ["a", "i"].contains(keys[index + named]) { return true }
        }
        return false
    }

    /// Whether the words from `start` up to `end` hold an item, not only a joining word: "item a and item b" has none.
    private func hasItemBetween(_ start: Int, _ end: Int, in live: [Int], of draft: Draft) -> Bool {
        guard end > start else { return false }
        return end - start > 1 || !Self.joiners.contains(draft.shape(at: live[start]).key)
    }

    /// The label said at `position`, nil where the words are a noun phrase, a clause or a mention.
    private func label(at position: Int, in live: [Int], of draft: Draft) -> Label? {
        let word = draft.shape(at: live[position])
        guard !draft.words[live[position]].isLayoutMark, word.prefix.isEmpty, word.suffix.isEmpty else {
            return nil
        }
        var named = 1
        var phrase = word.key
        if word.key == "sub", position + 1 < live.count {
            let second = draft.shape(at: live[position + 1])
            guard ["clause", "paragraph"].contains(second.key), second.prefix.isEmpty, second.suffix.isEmpty
            else { return nil }
            named = 2
            phrase = "sub" + second.key
        } else if !Self.labelWords.contains(word.key) {
            return nil
        }
        let numeral = position + named
        guard numeral + 1 < live.count, !draft.words[live[numeral]].isLayoutMark,
            !draft.isHindi(at: live[numeral])
        else { return nil }
        let token = draft.shape(at: live[numeral])
        guard token.prefix.isEmpty, ["", ",", ":"].contains(token.suffix),
            Self.letters.contains(token.key) || Self.romans.contains(token.key)
        else { return nil }
        // A label opening a noun phrase is part of a sentence.
        if position > 0, Self.nounPhraseOpeners.contains(draft.shape(at: live[position - 1]).key) {
            return nil
        }
        // A numeral said before a verb is the subject of a clause, as with a number after "number".
        let after = draft.shape(at: live[numeral + 1])
        guard !draft.words[live[numeral + 1]].isLayoutMark, !Self.predicateOpeners.contains(after.key) else {
            return nil
        }
        return Label(position: position, length: named + 1, phrase: phrase, token: token.key)
    }
}
