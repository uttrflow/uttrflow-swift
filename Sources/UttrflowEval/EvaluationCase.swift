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
        /// Grammar slips a formatter may repair, and the dialect that must stay.
        case grammar
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
    /// The spoken runs the recogniser was unsure of, which is what makes a case about a doubtful reading fire.
    public let doubtful: [String]

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
        mustEndWith: String? = nil,
        doubtful: [String] = []
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
        self.doubtful = doubtful
    }

    /// Below the correction engine's threshold, which is the line a doubtful word has to fall under.
    public static let doubtfulConfidence = 0.3

    /// What the recogniser produced, scored word by word only where the case names a doubtful run.
    public var transcription: Transcription {
        Transcription(
            text: spoken, detectedLanguage: DetectedLanguage(code: language), segments: segments)
    }

    /// One segment carrying a score for every spoken word, or none at all when nothing was doubtful.
    private var segments: [TranscriptionSegment] {
        guard !doubtful.isEmpty else { return [] }
        let spokenWords = spoken.split(whereSeparator: \.isWhitespace).map(String.init)
        // A run is doubted where it stands, so naming one word does not doubt every other occurrence of it.
        var unsure: Set<Int> = []
        for run in doubtful {
            let wanted = run.split(whereSeparator: \.isWhitespace).map { Self.bare(String($0)) }
            guard let start = Self.place(of: wanted, in: spokenWords, past: unsure) else { continue }
            unsure.formUnion(start..<(start + wanted.count))
        }
        let words = spokenWords.enumerated().map { index, text in
            TranscribedWord(
                text: text, confidence: unsure.contains(index) ? Self.doubtfulConfidence : 1)
        }
        return [TranscriptionSegment(text: spoken, start: .zero, end: .zero, words: words)]
    }

    /// A word with its edge punctuation dropped and lowercased, so "cash," is the "cash" a case names.
    static func bare(_ word: String) -> String {
        let head = word.drop(while: { !$0.isLetter && !$0.isNumber })
        return String(head.reversed().drop(while: { !$0.isLetter && !$0.isNumber }).reversed())
            .lowercased()
    }

    /// Where a run of words first stands past what is already doubted, so naming a word twice doubts it twice.
    private static func place(of run: [String], in words: [String], past taken: Set<Int>) -> Int? {
        guard !run.isEmpty, run.count <= words.count else { return nil }
        return (0...(words.count - run.count)).first { start in
            let range = start..<(start + run.count)
            return !range.contains(where: taken.contains)
                && zip(run, words[range]).allSatisfy { $0 == bare($1) }
        }
    }

    /// The situation the case is dictated in: its own destination, never the classifier's guess.
    public var situation: Situation {
        Situation(app: context, insertion: context.insertionPoint, destination: destination)
    }

    /// The request an engine is handed for this case; withholding the screen withholds the situation too.
    public func transformationRequest(withholdingContext: Bool = false) -> TransformationRequest {
        TransformationRequest(
            transcription: transcription,
            context: withholdingContext ? .unknown : context,
            situation: withholdingContext ? .unknown : situation
        )
    }
}
