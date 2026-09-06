public import UttrflowCore

/// Turns "new line", "new paragraph" and "bullet point" into layout when they stand between words.
public struct LayoutWordsPass: CleaningPass {
    public static let id: PassID = .layoutWords

    /// What each spoken phrase becomes; a bullet marker carries its own dash and space.
    static let marks: [(words: [String], mark: String)] = [
        (["new", "line"], "\n"), (["new", "paragraph"], "\n\n"), (["blank", "line"], "\n\n"),
        (["bullet", "point"], "\n- "), (["next", "point"], "\n- "),
    ]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            guard
                let found = Self.marks.first(where: { matches($0.words, at: position, in: live, of: draft) }),
                position + found.words.count < live.count,
                !MentionGuard.isMentioned(at: position, spanning: found.words.count, in: live, of: draft)
            else {
                position += 1
                continue
            }
            draft.replace(at: live[position], with: found.mark, by: Self.id)
            for index in live[position + 1..<position + found.words.count] {
                draft.remove(at: index, by: Self.id)
            }
            live.removeSubrange(position + 1..<position + found.words.count)
            position += 1
        }
        return draft
    }

    private func matches(_ words: [String], at position: Int, in live: [Int], of draft: Draft) -> Bool {
        position + words.count <= live.count
            && zip(words, live[position..<position + words.count]).allSatisfy {
                $0 == draft.shape(at: $1).key
            }
    }
}
