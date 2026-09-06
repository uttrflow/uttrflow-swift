import UttrflowCore

/// Words that mean the word after them is being talked about rather than dictated.
enum MentionGuard {
    static let determiners: Set<String> = [
        "a", "an", "the", "put", "add", "insert", "with", "no", "this", "that", "each", "every",
        "my", "your", "his", "her", "its", "their", "our", "another", "any", "some", "same",
    ]

    /// The ones a modifier may stand between and the mark; a verb takes its object with nothing in between.
    static let phraseOpeners: Set<String> = [
        "a", "an", "the", "with", "no", "this", "that", "each", "every", "my", "your", "his",
        "her", "its", "their", "our", "another", "any", "some", "same",
    ]

    /// How far back the word that opens a noun phrase may stand: "the hundred metre dash".
    static let phraseReach = 3

    /// The spoken names of marks and layout, which close the phrase an opener began rather than heading it.
    static let markNames: Set<String> = Set(
        SpokenPunctuationPass.marks.flatMap(\.words) + LayoutWordsPass.marks.flatMap(\.words))

    /// Whether the mark word at `position` is mentioned; `reach` is how far the phrase's own opener may stand.
    static func isMentioned(
        at position: Int, spanning length: Int, in live: [Int], of draft: Draft, reach: Int = 1
    ) -> Bool {
        guard position > 0 else { return true }
        if opensThePhrase(ending: position, reaching: reach, in: live, of: draft) { return true }
        let next = position + length
        return next < live.count && draft.shape(at: live[next]).key == "of"
    }

    /// Whether a determiner opens the phrase the mark word heads, with only modifiers standing between.
    private static func opensThePhrase(
        ending position: Int, reaching reach: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        // A hyphen joins the two words around it, so it heads no phrase and only the word before it speaks.
        let far = draft.shape(at: live[position]).key == "hyphen" ? 1 : reach
        for back in 1...min(far, position) {
            let key = draft.shape(at: live[position - back]).key
            if back == 1 ? determiners.contains(key) : phraseOpeners.contains(key) { return true }
            if markNames.contains(key) { return false }
        }
        return false
    }
}
