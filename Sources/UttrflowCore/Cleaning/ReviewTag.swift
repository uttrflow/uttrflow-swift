/// A code-review label said first ("nit", "question"), which a colon sets off from the clause it heads. See `Docs/cleanup.md`.
public enum ReviewTag {
    /// Whether the first word of a dictation is a review label heading the clause after it.
    public static func leads(_ shapes: [WordShape]) -> Bool {
        let words = shapes.filter { !$0.key.isEmpty }
        guard words.count >= 3, words[0].prefix.isEmpty, words[0].suffix.isEmpty else { return false }
        let tag = words[0].key
        let next = words[1].key
        if adjectiveTags.contains(tag) { return opensClause(next) }
        guard nounTags.contains(tag), !attachesToNoun.contains(next) else { return false }
        // "question is whether…" makes the label the subject; "question is this needed" asks.
        guard QuestionShape.verbsBeforeSubject.contains(next) else { return true }
        let after = words[2].key
        return after != "that"
            && (QuestionShape.subjects.contains(after) || QuestionShape.determiners.contains(after))
    }

    /// Labels that are nouns, set off unless the next word makes the label part of the sentence.
    static let nounTags: Set<String> = ["nit", "suggestion", "question"]

    /// Labels that are adjectives, set off only before a clause, since before a noun they describe it.
    static let adjectiveTags: Set<String> = ["minor", "optional"]

    /// Words that continue a noun as a phrase or a subject: "question for you", "suggestion and a fix".
    private static let attachesToNoun: Set<String> = [
        "for", "about", "of", "on", "from", "to", "with", "by", "in", "and", "or", "here", "there",
        "be", "been", "being",
    ]

    /// Whether a word can open a clause but never follow an adjective inside a noun phrase.
    private static func opensClause(_ word: String) -> Bool {
        QuestionShape.subjects.contains(word) || QuestionShape.hindiSubjects.contains(word)
            || hindiObliquePronouns.contains(word) || QuestionShape.determiners.contains(word)
            || QuestionShape.questionWords.contains(word) || QuestionShape.verbsBeforeSubject.contains(word)
            || QuestionShape.contractedNewSubjects.contains(word)
    }

    /// Romanised Hindi pronouns that open a clause as its experiencer: "mujhe lagta hai".
    private static let hindiObliquePronouns: Set<String> = [
        "mujhe", "humein", "hume", "tumhe", "tumhein", "aapko", "usko", "use", "unko", "unhe",
    ]
}
