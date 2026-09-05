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

    public init(
        id: String,
        category: Category,
        language: LanguageCode = .english,
        spoken: String,
        expected: String,
        mustKeep: [String] = [],
        context: AppContext = .unknown,
        mustNotAdd: [String] = []
    ) {
        self.id = id
        self.category = category
        self.language = language
        self.spoken = spoken
        self.expected = expected
        self.mustKeep = mustKeep
        self.context = context
        self.mustNotAdd = mustNotAdd
    }
}
