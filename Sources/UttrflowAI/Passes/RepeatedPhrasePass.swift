public import UttrflowCore

/// Removes a run of two to four words said twice in a row, keeping the second: "so I was I was thinking".
public struct RepeatedPhrasePass: CleaningPass {
    public static let id: PassID = "repeatedPhrase"

    static let lengths = 2...4

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            guard let length = repeatLength(at: position, in: live, of: draft) else {
                position += 1
                continue
            }
            for index in live[position..<position + length] { draft.remove(at: index, by: Self.id) }
            live.removeSubrange(position..<position + length)
        }
        return draft
    }

    /// The longest run at `position` repeated verbatim right after itself, with no punctuation inside.
    private func repeatLength(at position: Int, in live: [Int], of draft: Draft) -> Int? {
        for length in Self.lengths.reversed() where position + 2 * length <= live.count {
            let first = live[position..<position + length]
            let second = live[position + length..<position + 2 * length]
            let sameWords = zip(first, second).allSatisfy {
                draft.shape(at: $0).key == draft.shape(at: $1).key
            }
            let unbroken = !(first + second.dropLast()).contains { draft.shape(at: $0).endsClause }
            if sameWords, unbroken { return length }
        }
        return nil
    }
}
