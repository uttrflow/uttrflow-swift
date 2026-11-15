// Which requests the rules finish exactly as a model would, so no model is asked.
import UttrflowCore

/// A dictation short, plain and certain enough that the rules write what a model would. See `Docs/cleanup.md`.
public struct RulesAlone: Sendable, Equatable {
    /// The most words a request may hold and still go to the rules alone; zero sends every request down the route.
    public let mostWords: Int

    public init(mostWords: Int) {
        self.mostWords = mostWords
    }

    /// Every request goes down the whole route.
    public static let never = RulesAlone(mostWords: 0)

    /// What ships: replies of up to three words, and requests the rules reduce to that many prose words.
    public static let shortReplies = RulesAlone(mostWords: 3)

    /// Whether the rules alone finish `request`: few words, or few left after the rules, all ASCII, none doubted.
    func covers(_ request: TransformationRequest, steps: CleaningSteps = .default) -> Bool {
        let text = request.transcription.text
        let count = WordTokens.tokens(text, .display).count
        // Only ASCII, so Devanagari still reaches the model that romanises it.
        guard count > 0, mostWords > 0, text.unicodeScalars.allSatisfy(\.isASCII) else { return false }
        // A doubted word is the model's to choose a reading for, which the rules cannot do.
        let draft = Draft(transcription: request.transcription)
        if EvidencePolicy.unscored(draft, in: .rulesAlone) == nil, !UncertainSpan.spans(in: draft).isEmpty {
            return false
        }
        return count <= mostWords || proseWordsLeft(after: request, steps: steps) <= mostWords
    }

    /// The words the rules left as the speaker said them, since a digit run or a spelled code replaces its words.
    private func proseWordsLeft(after request: TransformationRequest, steps: CleaningSteps) -> Int {
        let pipeline = RuleBasedTransformer.pipeline(for: request, steps: steps)
        let finished = pipeline.run(Draft(transcription: request.transcription))
        return finished.words.filter { word in
            guard word.isPresent, !word.isLayoutMark else { return false }
            return Self.letters(word.text) == Self.letters(word.heard) && !Self.letters(word.text).isEmpty
        }.count
    }

    /// A word's letters in lower case, so a capital or a stop a pass wrote does not make it a consumed word.
    private static func letters(_ word: String) -> String {
        String(word.lowercased().filter(\.isLetter))
    }
}
