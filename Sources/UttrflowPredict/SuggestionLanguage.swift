// The check that a suggestion goes on in the language of the line it continues.
import NaturalLanguage
import UttrflowCore

/// Whether a candidate continues the typed line in that line's language, judged by the identifier macOS ships. See `Docs/predict.md`.
enum SuggestionLanguage {
    /// Fewest words either side needs before its language is judged; a shorter run is too little to tell.
    static let fewestJudgedWords = 3
    /// How sure the identifier must be of the typed line's language before a continuation is held to it.
    static let typedConfidence = 0.8
    /// How sure the identifier must be that the continuation is another language before it is refused.
    static let continuationConfidence = 0.9

    /// False only in prose, when both sides are long enough to judge and the identifier is sure they are different languages; a command line has no language, and romanised Hindi, which the identifier cannot name, always continues.
    static func continues(_ line: some StringProtocol, in context: PredictionContext) -> Bool {
        guard context.isProse else { return true }
        let typed = context.typed
        let typedKey = TextMatching.caseFoldedKey(String(typed))
        let lineText = String(line)
        let continuation =
            TextMatching.caseFoldedKey(lineText).hasPrefix(typedKey)
            ? String(lineText.dropFirst(typed.count)) : lineText
        let words = WordShape.words(continuation)
        guard words.count >= fewestJudgedWords,
            WordShape.words(typed).count >= fewestJudgedWords,
            !words.contains(where: { !HindiWords.classes(of: $0).isEmpty }),
            let written = language(of: typed, atLeast: typedConfidence),
            let offered = language(of: continuation, atLeast: continuationConfidence)
        else { return true }
        return written == offered
    }

    /// The identifier's most likely language for `text`, or nil when it is less sure than `floor`.
    private static func language(of text: String, atLeast floor: Double) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let best = recognizer.languageHypotheses(withMaximum: 1).max(by: { $0.value < $1.value }),
            best.value >= floor
        else { return nil }
        return best.key
    }
}
