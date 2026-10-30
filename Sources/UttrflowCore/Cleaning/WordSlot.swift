import Foundation

/// Whether one word can stand in another's place in a sentence, judged by the word class each takes in that place.
public enum WordSlot {
    /// Words that open an utterance of their own, so a correction never takes one as the word it replaces with.
    public static let utteranceOpeners: Set<String> = Restatement.answerHeads.union(["please"])

    /// The English weekday names, as lower-cased word keys.
    static let weekdays: Set<String> = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return Set(calendar.weekdaySymbols.map { $0.lowercased() })
    }()

    /// Whether the first of `following` takes the word class `replaced` has after `lead`, so it can replace that word.
    public static func fits(
        replacing replaced: String, after lead: [String], with following: [String]
    ) -> Bool {
        guard let replacement = following.first, !utteranceOpeners.contains(replacement) else { return false }
        // The tagger reads a lower-case weekday as a noun or an adverb by the words around it, so two weekdays are taken as one class.
        if weekdays.contains(replaced), weekdays.contains(replacement) { return true }
        guard
            let original = LexicalClass.tag(
                ofWordAt: lead.count, in: lead + [replaced] + following.dropFirst()),
            let candidate = LexicalClass.tag(ofWordAt: lead.count, in: lead + following)
        else { return false }
        // A word the tagger has no class for, as most romanised Hindi, gives no evidence against the swap.
        return original == candidate || original == .otherWord
    }
}
