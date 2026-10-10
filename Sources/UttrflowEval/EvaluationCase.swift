// One clean-up case: an utterance, its context and what should come out.
import struct Foundation.Date
public import UttrflowCore
import UttrflowDictionary
import UttrflowPipeline

/// What the product should do with one utterance; `expected` is a reference, not the only right answer.
public struct EvaluationCase: Sendable, Equatable, Identifiable {
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
        /// Second-language grammar that is written down as spoken, never repaired.
        case secondLanguage
        /// An entry into a one-line field of no known purpose, which is a value and takes no stop alone.
        case oneLineField
        /// A dictation of three hundred words or more, where sentence ends are what a tidier drops first.
        case longInput
        /// A dictation that is only an address or a path, which is a literal and takes no capital or stop.
        case bareLiteral
        /// A query or command for a launcher panel, which keeps the heard case and takes no stop.
        case commandInput
        /// A whole developer dictation that mixes flags, paths, numbers, lists and casing, held to one exact written form.
        case developerGenre
        /// A dictation holding words from the user's dictionary, which come out in the entry's spelling.
        case dictionary
        /// A dictation into a page in a browser: web mail, web chat or a search field.
        case webDestination
        /// A recogniser's wrong sound-alike, repaired to the word the sentence needs, beside one already right.
        case homophone
        /// A short Hindi or Hinglish reply, an English loanword in Hindi, or romanised Hindi dictated as it is.
        case hinglishReply

        /// Whether every reference here is only what `Docs/agents/product.md` lets the tidier make of a transcript.
        var isTranscriptOnly: Bool {
            switch self {
            case .everyday, .notARequest, .secondLanguage, .oneLineField, .longInput, .bareLiteral,
                .commandInput, .developerGenre, .dictionary, .webDestination:
                true
            // These join spoken words into an identifier, romanise, take a spelling from the screen or repair a word.
            case .technical, .multilingual, .contextual, .grammar, .homophone, .hinglishReply: false
            }
        }
    }

    /// Where a case's text came from; every value in every case is invented, whichever it is.
    public enum Origin: String, Sendable, Equatable, CaseIterable, Codable {
        /// Written from scratch to state a behaviour.
        case authored
        /// Rebuilt from a reported failure, keeping its shape with every value invented.
        case reportRewrite
        /// Generated from a template or a rule rather than written one by one.
        case synthetic
    }

    public let id: String
    public let category: Category
    /// Where the case came from, which is what a reviewer reads before asking whether it holds a real person's text.
    public let origin: Origin
    /// The issue the case was added for, when it was added for one.
    public let addedFor: Int?
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
    /// The fewest sentences the output must close, for a long case one run-on sentence must fail.
    public let minimumSentences: Int?
    /// The one written form a structured output must take, character for character, where any other spelling is wrong.
    public let expectedExact: String?
    /// The spoken runs the recogniser was unsure of, which is what makes a case about a doubtful reading fire.
    public let doubtful: [String]
    /// The formatting case classes this case exercises, which is what the coverage matrix counts.
    public let classes: [FormattingClass]
    /// The code-mixing cell the case fills, when it is one of the grid's cases.
    public let codeMix: CodeMixCell?
    /// The kind of number the case is about, which the number grammar report counts.
    public let semiotic: SemioticClass?
    /// The kind of whole text a person writes that the case is, when it is one of the genre cases.
    public let genre: Genre?
    /// The kind of person whose writing the case stands for, when it is one of the segment slices.
    public let segment: Segment?
    /// The positions of the spoken words a sentence-length pause follows, which times every word when non-empty.
    public let pausedAfter: [Int]
    /// The user's dictionary words, handed to the engine as the request's vocabulary, as the pipeline hands them.
    public let dictionary: [String]

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
        minimumSentences: Int? = nil,
        expectedExact: String? = nil,
        doubtful: [String] = [],
        classes: [FormattingClass] = [],
        codeMix: CodeMixCell? = nil,
        semiotic: SemioticClass? = nil,
        genre: Genre? = nil,
        segment: Segment? = nil,
        pausedAfter: [Int] = [],
        dictionary: [String] = [],
        origin: Origin = .authored,
        addedFor: Int? = nil
    ) {
        self.id = id
        self.category = category
        self.origin = origin
        self.addedFor = addedFor
        self.language = language
        self.spoken = spoken
        self.expected = expected
        self.mustKeep = mustKeep
        self.context = context
        self.mustNotAdd = mustNotAdd
        self.destination = destination
        self.mustBeginWith = mustBeginWith
        self.mustEndWith = mustEndWith
        self.minimumSentences = minimumSentences
        self.expectedExact = expectedExact
        self.doubtful = doubtful
        self.classes = classes
        self.codeMix = codeMix
        self.semiotic = semiotic
        self.genre = genre
        self.segment = segment
        self.pausedAfter = pausedAfter
        self.dictionary = dictionary
    }

    /// Below the correction engine's threshold, which is the line a doubtful word has to fall under.
    public static let doubtfulConfidence = 0.3

    /// What the recogniser produced, scored word by word only where the case names a doubtful run.
    public var transcription: Transcription {
        Transcription(
            text: spoken, detectedLanguage: DetectedLanguage(code: language), segments: segments)
    }

    /// The transcription as the pipeline hands it to an engine: a dictionary word written in its entry's case first.
    var corrected: Transcription {
        guard !dictionary.isEmpty else { return transcription }
        let entries = dictionary.map {
            DictionaryEntry(word: $0, origin: .added, firstSeen: Date(timeIntervalSince1970: 0))
        }
        let recased = DictionaryCorrections.recasings(
            of: spoken, against: PhoneticIndex(entries: entries), seeing: context)
        let text = DictationCorrection.applying(recased, to: spoken).text
        return Transcription(
            text: text, detectedLanguage: DetectedLanguage(code: language), segments: segments)
    }

    /// How long each spoken word lasts, and the silence after it, where a case times its words.
    static let wordLength: Duration = .milliseconds(300)
    static let wordGap: Duration = .milliseconds(100)
    /// The silence a case's pause stands for, a little past the piece boundary's own.
    static let pauseLength: Duration = .seconds(1)

    /// One segment carrying a score for every spoken word, or none at all when nothing was doubtful or paused.
    private var segments: [TranscriptionSegment] {
        guard !doubtful.isEmpty || !pausedAfter.isEmpty else { return [] }
        let spokenWords = WordTokens.words(spoken, .display)
        // A run is doubted where it stands, so naming one word does not doubt every other occurrence of it.
        var unsure: Set<Int> = []
        for run in doubtful {
            let wanted = WordTokens.words(run, .display).map(Self.bare)
            guard let start = Self.place(of: wanted, in: spokenWords, past: unsure) else { continue }
            unsure.formUnion(start..<(start + wanted.count))
        }
        var clock = Duration.zero
        let timed = !pausedAfter.isEmpty
        let words = spokenWords.enumerated().map { index, text in
            let start = clock
            clock += Self.wordLength
            let end = clock
            clock += pausedAfter.contains(index) ? Self.pauseLength : Self.wordGap
            return TranscribedWord(
                text: text, confidence: unsure.contains(index) ? Self.doubtfulConfidence : 1,
                start: timed ? start : nil, end: timed ? end : nil)
        }
        return [TranscriptionSegment(text: spoken, start: .zero, end: timed ? clock : .zero, words: words)]
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
            transcription: corrected,
            context: withholdingContext ? .unknown : context,
            situation: withholdingContext ? .unknown : situation,
            vocabulary: dictionary
        )
    }
}
