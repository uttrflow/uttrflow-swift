public import UttrflowCore

/// Removes the sounds people make while thinking, and nothing that is ever a word on its own.
public struct FillersPass: CleaningPass {
    public static let id: PassID = .fillers
    public static let removes: RemovalGrant = .sound

    /// Whole words that carry no meaning; "like", "well", "so", "basically" and "mm" (millimetres) are out.
    static let fillerWords: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "er", "erm", "ah", "hmm", "mmm", "aah", "ahh", "mhm",
    ]

    /// Words a sentence sets off with a comma of its own, which a removed filler beside them leaves in place.
    static let discourseWords: Set<String> = [
        "yes", "no", "yeah", "okay", "ok", "well", "thanks", "so", "now", "actually",
    ]

    public init() {}

    /// Whether the comma before a bracketed filler belongs to the sentence rather than to the pause.
    private func sentenceOwnsComma(
        before: Int, fillerAt position: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        if Self.discourseWords.contains(draft.shape(at: before).key) { return true }
        if position + 1 < live.count, Self.discourseWords.contains(draft.shape(at: live[position + 1]).key) {
            return true
        }
        guard let at = live.firstIndex(of: before) else { return false }
        if at == 0 { return true }
        let last = draft.words[live[at - 1]].text.last
        return last == "." || last == "?" || last == "!"
    }

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
            // A filler bracketed by commas takes the opening one too, unless the sentence needs it.
            if word.hasSuffix(","), let before = previous, draft.words[before].text.hasSuffix(","),
                !sentenceOwnsComma(before: before, fillerAt: position, in: live, of: draft)
            {
                draft.replace(
                    at: before, with: String(draft.words[before].text.dropLast()), by: Self.id)
            }
            draft.remove(at: index, by: Self.id, carryingMarks: true)
        }
        return draft
    }
}
