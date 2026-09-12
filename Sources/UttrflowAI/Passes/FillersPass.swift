public import UttrflowCore

/// Removes the sounds people make while thinking, and nothing that is ever a word on its own.
public struct FillersPass: CleaningPass {
    public static let id: PassID = .fillers

    /// Whole words that carry no meaning; "like", "well", "so", "basically" and "mm" (millimetres) are out.
    static let fillerWords: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "mmm", "aah", "ahh", "mhm",
    ]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        let live = draft.presentIndices
        var previous: Int?
        for (position, index) in live.enumerated() {
            let word = draft.words[index].text
            // A filler sound is never preceded by a determiner; a noun spelled like one — "the ER" — always is.
            guard Self.fillerWords.contains(draft.shape(at: index).key),
                position == 0
                    || !MentionGuard.isMentioned(at: position, spanning: 1, in: live, of: draft)
            else {
                previous = index
                continue
            }
            // A filler with a comma on both sides was bracketed by them, so the opening one goes too.
            if word.hasSuffix(","), let before = previous, draft.words[before].text.hasSuffix(",") {
                draft.replace(
                    at: before, with: String(draft.words[before].text.dropLast()), by: Self.id)
            }
            draft.remove(at: index, by: Self.id, carryingMarks: true)
        }
        return draft
    }
}
