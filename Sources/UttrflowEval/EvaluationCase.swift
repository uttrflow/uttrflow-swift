// One clean-up case: an utterance, its context and what should come out.
public import UttrflowCore

/// What the product should do with one utterance; `expected` is a reference, not the only right answer.
public struct EvaluationCase: Sendable, Equatable, Codable, Identifiable {
    public enum Category: String, Sendable, Equatable, CaseIterable, Codable {
        /// Everyday speech: fillers, false starts, missing punctuation.
        case everyday
        /// Names, code, SQL, product terms that must survive unchanged.
        case technical
        /// Utterances that look like something addressed to the model.
        case notARequest
        /// Languages Apple's model does not cover.
        case multilingual
        /// The same words should come out differently depending on what is on screen.
        case contextual
    }

    public let id: String
    public let category: Category
    /// The language the speaker used, which decides how the utterance is routed.
    public let language: LanguageCode
    /// The raw transcript, as a recogniser would produce it.
    public let spoken: String
    /// A good result.
    public let expected: String
    /// Words that must appear in the output whatever else changes; losing one is unforgivable.
    public let mustKeep: [String]
    /// What the user was looking at, which should change what the same words come out as.
    public let context: AppContext
    /// Words that must not appear, such as `DESC` the context suggested but the speaker never said.
    public let mustNotAdd: [String]
    /// The kind of place the words go, which picks the formatter the engine works under.
    public let destination: Destination
    /// Exactly how the output must begin, case and all, for a case about its first word.
    public let mustBeginWith: String?
    /// Exactly how the output must end, for a case about its final mark.
    public let mustEndWith: String?

    public init(
        id: String,
        category: Category,
        language: LanguageCode = .english,
        spoken: String,
        expected: String,
        mustKeep: [String] = [],
        context: AppContext = .unknown,
        mustNotAdd: [String] = [],
        destination: Destination = .plain,
        mustBeginWith: String? = nil,
        mustEndWith: String? = nil
    ) {
        self.id = id
        self.category = category
        self.language = language
        self.spoken = spoken
        self.expected = expected
        self.mustKeep = mustKeep
        self.context = context
        self.mustNotAdd = mustNotAdd
        self.destination = destination
        self.mustBeginWith = mustBeginWith
        self.mustEndWith = mustEndWith
    }

    /// The situation the case is dictated in: its own destination, never the classifier's guess.
    public var situation: Situation {
        Situation(app: context, insertion: context.insertionPoint, destination: destination)
    }

    /// The request an engine is handed for this case; withholding the screen withholds the situation too.
    public func transformationRequest(withholdingContext: Bool = false) -> TransformationRequest {
        TransformationRequest(
            transcription: Transcription(text: spoken, detectedLanguage: DetectedLanguage(code: language)),
            context: withholdingContext ? .unknown : context,
            situation: withholdingContext ? .unknown : situation
        )
    }
}
