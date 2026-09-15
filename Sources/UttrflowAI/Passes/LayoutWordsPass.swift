public import UttrflowCore

/// Turns "new line", "new paragraph", "bullet point" and "number one" into layout, between words only.
public struct LayoutWordsPass: CleaningPass {
    public static let id: PassID = .layoutWords

    /// What each spoken phrase becomes; a bullet marker carries its own dash and space.
    static let marks: [(words: [String], mark: String)] = [
        (["new", "line"], "\n"), (["new", "paragraph"], "\n\n"), (["blank", "line"], "\n\n"),
        (["bullet", "point"], "\n- "), (["next", "point"], "\n- "),
    ]

    /// The word that opens a numbered item. It is not in `marks` because the number after it picks the mark.
    static let numbering = "number"

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        let numbered = Set(live.indices.compactMap { itemValue(at: $0, in: live, of: draft) })
        var position = 0
        while position < live.count {
            guard
                let found = opening(mark(at: position, in: live, of: draft), at: position),
                position + found.length < live.count,
                isUsed(spanning: found.length, at: position, in: live, of: draft),
                isCorroborated(at: position, in: live, of: draft, among: numbered)
            else {
                position += 1
                continue
            }
            draft.replace(at: live[position], with: found.mark, by: Self.id)
            for index in live[position + 1..<position + found.length] {
                draft.remove(at: index, by: Self.id)
            }
            live.removeSubrange(position + 1..<position + found.length)
            position += 1
        }
        return draft
    }

    /// The mark with nothing to break from at the head of the text, where a break is no layout and only an item's number is.
    private func opening(
        _ found: (length: Int, mark: String)?, at position: Int
    ) -> (length: Int, mark: String)? {
        guard let found, position == 0 else { return found }
        let mark = String(found.mark.drop(while: \.isNewline))
        return mark.isEmpty ? nil : (found.length, mark)
    }

    /// Whether the phrase is dictated layout rather than named; one opening its sentence has no lookback to ask, so it needs a mark. See `Docs/cleanup.md`.
    private func isUsed(spanning length: Int, at position: Int, in live: [Int], of draft: Draft) -> Bool {
        // Asked of the sentence, not the text, so a sentence before it cannot turn "number one is broken" into an item.
        guard position == 0 || draft.shape(at: live[position - 1]).endsSentence else {
            return !MentionGuard.isMentioned(at: position, spanning: length, in: live, of: draft)
        }
        let last = draft.shape(at: live[position + length - 1])
        return last.endsClause && !last.endsSentence
    }

    /// Whether a numbered item inside its sentence has a neighbouring item said beside it, since a lone one is a designator.
    private func isCorroborated(
        at position: Int, in live: [Int], of draft: Draft, among numbered: Set<Int>
    ) -> Bool {
        guard position > 0, !draft.shape(at: live[position - 1]).endsSentence,
            let value = itemValue(at: position, in: live, of: draft)
        else { return true }
        return (value > 1 && numbered.contains(value - 1))
            || (value < Int.max && numbered.contains(value + 1))
    }

    /// The number of the item "number" opens at `position`, or nil where no item opens.
    private func itemValue(at position: Int, in live: [Int], of draft: Draft) -> Int? {
        guard draft.shape(at: live[position]).key == Self.numbering, position + 1 < live.count else {
            return nil
        }
        return itemNumber(at: position + 1, in: live, of: draft)?.value
    }

    /// The layout the words at `position` become: one of the fixed phrases, or a numbered item.
    private func mark(at position: Int, in live: [Int], of draft: Draft) -> (length: Int, mark: String)? {
        if let found = Self.marks.first(where: { matches($0.words, at: position, in: live, of: draft) }) {
            return (found.words.count, found.mark)
        }
        guard draft.shape(at: live[position]).key == Self.numbering, position + 1 < live.count,
            let item = itemNumber(at: position + 1, in: live, of: draft)
        else { return nil }
        return (item.count + 1, "\n\(item.value). ")
    }

    /// The item number, spoken or already a numeral, and how many words it took. See `Docs/cleanup.md`.
    private func itemNumber(at position: Int, in live: [Int], of draft: Draft) -> (value: Int, count: Int)? {
        let key = draft.shape(at: live[position]).key
        if let digits = NumberWords.digits(key) {
            guard let value = Int(digits), value > 0 else { return nil }
            return (value, 1)
        }
        let keys = live[draft.sentenceRun(from: position, in: live)].map { draft.shape(at: $0).key }
        guard let spoken = NumberWords.cardinal(keys[...]), spoken.value > 0 else { return nil }
        return spoken
    }

    private func matches(_ words: [String], at position: Int, in live: [Int], of draft: Draft) -> Bool {
        position + words.count <= live.count
            && draft.sentenceRun(from: position, in: live).count >= words.count
            && zip(words, live[position..<position + words.count]).allSatisfy {
                $0 == draft.shape(at: $1).key
            }
    }
}
