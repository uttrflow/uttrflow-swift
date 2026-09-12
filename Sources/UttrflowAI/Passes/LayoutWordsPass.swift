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
        var position = 0
        while position < live.count {
            guard
                let found = mark(at: position, in: live, of: draft),
                position + found.length < live.count,
                !MentionGuard.isMentioned(at: position, spanning: found.length, in: live, of: draft)
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
        let keys = live[position...].map { draft.shape(at: $0).key }
        guard let spoken = NumberWords.cardinal(keys[...]), spoken.value > 0 else { return nil }
        return spoken
    }

    private func matches(_ words: [String], at position: Int, in live: [Int], of draft: Draft) -> Bool {
        position + words.count <= live.count
            && zip(words, live[position..<position + words.count]).allSatisfy {
                $0 == draft.shape(at: $1).key
            }
    }
}
