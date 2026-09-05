public import UttrflowCore
public import struct Foundation.UUID

/// What can stop Uttrflow changing, or remembering, what was said.
///
/// One case, because there is one cause and one consequence. Everything behind the
/// seams below reads or writes a store on disk, and the only thing a store can do to a
/// dictation is refuse — after which the dictation must carry on exactly as though the
/// feature were switched off. §19.
///
/// Its own type rather than any one store's, because three different stores are reached
/// through these seams and none of them owns the others' failures. Deliberately *not* a
/// ``UttrflowFailure``: the pipeline swallows this by design, so a sentence written for a
/// user would be a sentence no user could ever be shown.
public enum DictationChangeError: Error, Sendable, Equatable {
    /// A store would not answer, or would not take the change.
    case storeRefused
}

/// One word a recogniser produced, and how sure it was of that word.
///
/// The confidence is not decoration. It is the first of the correction engine's three
/// conditions and the only one that says where help is worth spending: a word the model
/// is certain of does not need the dictionary arguing with it, and a word it
/// half-guessed is exactly where a personal spelling belongs.
public struct ScoredWord: Sendable, Equatable {
    public let text: String
    /// Between zero and one, as the recogniser reports it.
    public let confidence: Double

    public init(text: String, confidence: Double) {
        self.text = text
        self.confidence = confidence
    }
}

extension Transcription {
    /// The transcript as words the recogniser scored, or `nil` when it scored nothing.
    ///
    /// `nil` is not "everything is certain" — it is "nobody measured", and the two must
    /// never be conflated. A single score standing in for every word makes correction's
    /// first condition either vacuous, so a restrained engine rewrites every dictation,
    /// or unsatisfiable, so it can never fire. Declining to judge is the third answer
    /// and the right one, which is why the question is asked here once with its reason
    /// attached rather than answered ad hoc by whoever needs it.
    ///
    /// The words come from WhisperKit's own `WordTiming.probability`, which is why
    /// `wordTimestamps` is asked for — measured at +1.4% of a transcription, against a
    /// spread that genuinely discriminates: "up" at 0.41 beside content words at 0.99.
    /// Apple's recogniser reports nothing of the kind, so a build using it gets `nil`
    /// and no corrections, which is the honest outcome rather than a degraded one.
    ///
    /// One entry per whitespace-separated word of ``text``, in order, because that is
    /// what a correction's word range indexes. Segment words are matched against that
    /// split rather than trusted to align with it: a recogniser is free to break words
    /// differently from the text it also gave us, and a misalignment here would score
    /// the wrong word.
    public var scoredWords: [ScoredWord]? {
        let spoken = text.spokenWords.map(String.init)
        guard !spoken.isEmpty else { return nil }

        var scores: [String: Double] = [:]
        for word in segments.flatMap(\.words) {
            let key = word.text.lowercased()
            guard !key.isEmpty else { continue }
            // Lowest wins where a word repeats: the doubtful reading is the one worth
            // acting on, and taking the confident one would hide it.
            scores[key] = min(scores[key] ?? word.confidence, word.confidence)
        }
        guard !scores.isEmpty else { return nil }

        return spoken.map { word in
            let key = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            // A word the recogniser did not score is left unjudged rather than guessed
            // at, and 1 means "no reason to doubt it", which keeps it out of reach of
            // condition one.
            return ScoredWord(text: word, confidence: scores[key] ?? 1)
        }
    }
}

/// Puts the user's own spelling where the recogniser guessed at one.
///
/// The pipeline depends on this rather than on the correction engine, for the reason
/// ``TranscriptCleaning`` gives about the tidier: the whole speak-to-inserted sequence
/// has to be testable with no dictionary anywhere near it.
///
/// It proposes and does not apply. Handing back a rewritten string would take the
/// decision away from the only layer that knows whether the dictation is still wanted,
/// and would leave nothing to show the user or to undo.
public protocol WordCorrecting: Sendable {
    /// - Parameters:
    ///   - transcription: What the recogniser produced, before any tidying.
    ///   - context: What the user is looking at, read once for this dictation.
    /// - Returns: Every change worth arguing for, with word ranges into the whitespace-
    ///   separated words of `transcription.text`. Empty is the expected answer.
    /// - Throws: ``DictationChangeError`` when the dictionary could not be consulted.
    ///   The dictation carries on regardless.
    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection]
}

/// Puts the user's stored text where they spoke its trigger.
public protocol SnippetExpanding: Sendable {
    /// - Parameter text: The tidied transcript, as it would otherwise be inserted.
    /// - Returns: The text to insert, and a record of every snippet that fired.
    /// - Throws: ``DictationChangeError`` when the snippets could not be read. The
    ///   dictation carries on regardless.
    func expand(_ text: String) async throws(DictationChangeError) -> ExpandedTranscript
}

/// Told what a dictation used, once its words are safely on the user's screen.
///
/// Separate from the two seams above because it happens at a different time, and must:
/// a word earns its place by *surviving* a dictation, so nothing may be counted until
/// the words have landed.
///
/// Two methods rather than one, shaped after the two stores behind them — the
/// dictionary counts one entry at a time and the snippets are counted in a batch. A
/// single tidy method would have to fan out somewhere, and the fanning out is a
/// decision about how much of a failure is survivable, which belongs in the pipeline
/// where it can be tested rather than in the wiring where it cannot.
public protocol DictationLearning: Sendable {
    /// Notes that one dictionary entry was applied to a dictation that landed.
    ///
    /// - Throws: ``DictationChangeError`` when the store would not take the note.
    func recordUse(ofEntry id: UUID) async throws(DictationChangeError)

    /// Notes that these snippets fired in a dictation that landed. A snippet that fired
    /// twice appears twice, because that is what the user did.
    ///
    /// - Throws: ``DictationChangeError`` when the store would not take the note.
    func recordUse(ofSnippets ids: [UUID]) async throws(DictationChangeError)
}

/// Offered everything a finished dictation could teach, so that the words a general
/// model has never heard of can be learnt without the user being asked.
///
/// Its own protocol rather than a third method on ``DictationLearning``, because the two
/// are different jobs done from different evidence. That one counts what a dictation
/// *used*, and is handed identifiers of things the dictionary already holds; this one
/// asks what a dictation *showed*, and is handed the raw material — what was said, what
/// was written, and what was on screen. A pipeline can honestly want either without the
/// other, and rolling them together would mean a caller that only wanted counting had to
/// think about what it was allowing to be read.
///
/// Deliberately given no default implementation on the protocol itself. A seam that
/// silently does nothing when a conformer forgets it is how a feature comes to compile
/// and never fire, which is the failure this whole path exists to correct; the way to
/// opt out is to pass ``NoTextChanges``, in writing, at the call site.
public protocol VocabularyLearning: Sendable {
    /// - Parameters:
    ///   - heard: Exactly what the recogniser produced, before the dictionary, the
    ///     tidier or the snippets rewrote any of it. What the user *said*, as closely as
    ///     this pipeline can report it.
    ///   - wrote: What actually landed on their screen.
    ///   - context: What was in front of them while they spoke, read once for this
    ///     dictation.
    /// - Throws: ``DictationChangeError`` when the dictionary would not take the lesson.
    ///   The dictation is already over; nothing is at risk but the lesson.
    func learn(
        heard: String, wrote: String, seeing context: AppContext
    ) async throws(DictationChangeError)
}

/// The seams above, wired to nothing.
///
/// The default for all four, so a pipeline built without a dictionary, without snippets
/// and with nowhere to learn behaves exactly as it did before any of them existed. That is what keeps each of them a quality improvement rather than a new way
/// for a dictation to fail, and it is what the evaluation harness gets for free.
///
/// One type for four protocols rather than four no-ops, because "leave the words alone,
/// and remember nothing" is one behaviour and writing it out four times would be four
/// chances to write it differently.
public struct NoTextChanges:
    WordCorrecting, SnippetExpanding, DictationLearning, VocabularyLearning
{
    public init() {}

    public func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) -> [DictationCorrection] {
        []
    }

    public func expand(_ text: String) -> ExpandedTranscript { .unchanged(text) }

    public func recordUse(ofEntry id: UUID) {}

    public func recordUse(ofSnippets ids: [UUID]) {}

    public func learn(heard: String, wrote: String, seeing context: AppContext) {}
}
