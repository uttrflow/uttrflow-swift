public import UttrflowCore

/// Removes the doubled function word a false start leaves behind: "the the deployment".
public struct StammersPass: CleaningPass {
    public static let id: PassID = .stammers
    public static let removes: RemovalGrant = .repetition

    /// Function words English doubles on purpose: a past perfect, a doubled relative, a conjunction, a comforting.
    static let legitimateDoubles: Set<String> = ["had", "that", "so", "there"]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        var previous: String?
        for (i, index) in live.enumerated() {
            let word = draft.words[index].text.lowercased()
            if word == previous, !FunctionWords.isContent(word),
                !Self.legitimateDoubles.contains(word)
            {
                // A doubled function word is a stammer.
                draft.remove(at: index, by: Self.id, carryingMarks: true)
                continue
            }
            // A doubled number is a digit of one value when another number sits beside the pair, otherwise a stammer.
            if word == previous, NumberWords.isNumber(word),
                !Self.surroundedByNumber(at: i, in: live, draft: draft)
            {
                draft.remove(at: index, by: Self.id, carryingMarks: true)
                continue
            }
            previous = word
        }
        return draft
    }

    /// Whether a number word sits immediately before or after the doubled pair at `i`.
    private static func surroundedByNumber(at i: Int, in live: [Int], draft: Draft) -> Bool {
        if i >= 2, NumberWords.isNumber(draft.words[live[i - 2]].text.lowercased()) { return true }
        if i + 1 < live.count,
            NumberWords.isNumber(draft.words[live[i + 1]].text.lowercased())
        {
            return true
        }
        return false
    }
}
