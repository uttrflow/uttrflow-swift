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

    /// What ships: replies of up to three words, where the model was measured to change nothing.
    public static let shortReplies = RulesAlone(mostWords: 3)

    /// Whether the rules alone finish `request`: a few words, all ASCII, none of them doubted by the recogniser.
    func covers(_ request: TransformationRequest) -> Bool {
        let text = request.transcription.text
        let count = WordTokens.tokens(text, .display).count
        // Only ASCII, so Devanagari still reaches the model that romanises it.
        guard count > 0, count <= mostWords, text.unicodeScalars.allSatisfy(\.isASCII) else {
            return false
        }
        // A doubted word is the model's to choose a reading for, which the rules cannot do.
        let draft = Draft(transcription: request.transcription)
        guard EvidencePolicy.unscored(draft, in: .rulesAlone) == nil else { return true }
        return UncertainSpan.spans(in: draft).isEmpty
    }
}
