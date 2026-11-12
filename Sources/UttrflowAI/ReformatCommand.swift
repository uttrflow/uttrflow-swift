// Plans "capitalise that", "all caps that", "make that a list" and "make that one paragraph" on the last insertion. See `Docs/commands.md`.
public import UttrflowCore

/// A change of case or layout that a `reformat` row of the spoken-command registry asks of the last insertion.
public enum Reformat: String, Sendable, Equatable, CaseIterable {
    /// Each sentence, and the text, opens with a capital.
    case sentence
    /// Every letter is a capital.
    case upper
    /// Each sentence or line is an item of a bulleted list.
    case list
    /// Every line and paragraph break goes, so the text is one paragraph.
    case paragraph
}

/// What a reformat makes of the last insertion: its new text, or why nothing is written.
public enum ReformatOutcome: Sendable, Equatable {
    /// The text written in place of the insertion, holding the same words in the same order.
    case reformatted(String)
    /// Nothing is written; the reason is the whole notice.
    case refused(String)
}

/// Reads and plans the `reformat` rows of the spoken-command registry, through the passes that lay out and case dictation.
public enum ReformatCommand {
    /// The reformat a whole utterance names, ignoring the recogniser's case and closing mark; nil for anything else.
    public static func reformat(heard: String) -> Reformat? {
        let keys = WordTokens.words(heard, .display).map { WordShape($0).key }
        let row = SpokenCommands.reformats.first { $0.words == keys }
        return row.flatMap { Reformat(rawValue: $0.text) }
    }

    /// `text` reformatted for `destination`, refused when it would change a word, change nothing, or lay out a list where none is.
    public static func plan(
        _ reformat: Reformat, of text: String, in destination: Destination
    ) -> ReformatOutcome {
        let draft = Draft(keepingLineBreaks: text)
        let formatted: Draft
        switch reformat {
        case .sentence:
            formatted = FirstWordPass(policy: .alwaysCapital, capitaliseCalendarWords: false).apply(draft)
        case .upper:
            formatted = SpokenCasingPass.shouting(draft)
        case .list:
            guard DestinationFormatter.registry[destination]?.layout.contains(.lists) == true else {
                return .refused("Lists are not laid out here, so the last dictation was left as it was.")
            }
            guard let listed = LayoutWordsPass.listingSentences(draft) else {
                return .refused("The last dictation is one sentence, so there is nothing to list.")
            }
            formatted = listed
        case .paragraph:
            var joined = draft
            LayoutWordsPass.joinOnOneLine(&joined, by: LayoutWordsPass.id)
            formatted = joined
        }
        let written = formatted.text
        guard keepsWords(of: text, in: written) else {
            return .refused("That would change a word, so the last dictation was left as it was.")
        }
        guard written != text else { return .refused("The last dictation already reads that way.") }
        return .reformatted(written)
    }

    /// Whether `written` holds the words of `original` in order, none added, dropped or changed, case and marks aside.
    static func keepsWords(of original: String, in written: String) -> Bool {
        WordErrorRate.measure(reference: words(original), hypothesis: words(written)).errors == 0
    }

    /// The notice once a reformat ran; it names no words.
    public static func done(_ reformat: Reformat) -> String {
        switch reformat {
        case .sentence: "Capitalised the last dictation."
        case .upper: "Put the last dictation in capitals."
        case .list: "Made the last dictation a list."
        case .paragraph: "Made the last dictation one paragraph."
        }
    }

    /// The words of `text` as compared: lower-cased cores, with marks, breaks and item marks left out.
    private static func words(_ text: String) -> [String] {
        Draft(keepingLineBreaks: text).words.filter { !$0.isLayoutMark }.map { WordShape($0.text).key }
            .filter { !$0.isEmpty }
    }
}
