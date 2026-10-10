/// Whether one word can stand in another's place in a sentence, judged by the word class each takes in that place.
public enum WordSlot {
    /// Words that open an utterance of their own, so a correction never takes one as the word it replaces with.
    public static let utteranceOpeners: Set<String> = Restatement.answerHeads.union(["please"])

    /// Whether the first of `following` takes the word class `replaced` has after `lead`, so it can replace that word.
    public static func fits(
        replacing replaced: String, after lead: [String], with following: [String]
    ) -> Bool {
        guard let replacement = following.first, !utteranceOpeners.contains(replacement) else { return false }
        guard
            let original = LexicalClass.tag(
                ofWordAt: lead.count, in: lead + [replaced] + following.dropFirst()),
            let candidate = LexicalClass.tag(ofWordAt: lead.count, in: lead + following)
        else { return false }
        return original == candidate
    }
}
