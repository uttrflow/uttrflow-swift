// The seams through which a dictionary, snippets and learning reach the pipeline.
public import UttrflowCore
public import struct Foundation.UUID

/// The one thing a store can do to a dictation: refuse, after which the dictation carries on (§19).
public enum DictationChangeError: Error, Sendable, Equatable {
    /// A store would not answer, or would not take the change.
    case storeRefused
}

/// One word a recogniser produced and how sure it is, which says where a correction is worth spending.
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
    /// The transcript as scored words, or `nil` when nobody measured. See Docs/pipeline-changes.md.
    public var scoredWords: [ScoredWord]? {
        let spoken = text.spokenWords.map(String.init)
        guard !spoken.isEmpty else { return nil }

        var scores: [String: Double] = [:]
        for word in segments.flatMap(\.words) {
            // Both sides reduce a word the same way, or a word wearing a comma never finds its score.
            let key = SpokenToken(word.text).scoreKey
            guard !key.isEmpty else { continue }
            // Lowest wins where a word repeats: the doubtful reading is the one worth acting on.
            scores[key] = min(scores[key] ?? word.confidence, word.confidence)
        }
        guard !scores.isEmpty else { return nil }

        return spoken.map { word in
            // An unscored word gets 1, "no reason to doubt it", which keeps it out of reach of condition one.
            ScoredWord(text: word, confidence: scores[SpokenToken(word).scoreKey] ?? 1)
        }
    }
}

/// Proposes the user's own spelling where the recogniser guessed; it never applies, so the pipeline decides.
public protocol WordCorrecting: Sendable {
    /// Every change worth arguing for, with ranges into the whitespace-split words; a throw is survived.
    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection]

    /// The changes, and the word ranges it weighed a reading for and kept as heard; ranges as `corrections`.
    func weigh(
        _ transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> WeighedCorrections

    /// The joined pieces weighed for changes that cross a seam and overlap none already made; ranges as `weigh`.
    func weighAcrossSeams(
        _ joined: Transcription, at seams: PieceSeams, seeing context: AppContext
    ) async throws(DictationChangeError) -> WeighedCorrections

    /// This corrector held to what it knows now, so every piece of one dictation is corrected alike.
    func fixed() async -> any WordCorrecting

    /// The revision of what a fixed corrector holds, carried in the cleaning record; nil when it holds nothing that changes.
    var revision: UInt64? { get }
}

extension WordCorrecting {
    public var revision: UInt64? { nil }
}

/// Where joined pieces meet, and the word ranges their own passes already changed.
public struct PieceSeams: Sendable, Equatable {
    /// Word indexes in the joined transcript at which one piece ends and the next begins.
    public let boundaries: [Int]
    /// Word ranges the pieces' own passes changed, which a seam change may not touch.
    public let changed: [Range<Int>]

    public init(boundaries: [Int], changed: [Range<Int>]) {
        self.boundaries = boundaries
        self.changed = changed
    }

    /// Whether a change over `range` spans a seam and leaves every earlier change alone.
    public func admits(_ range: Range<Int>) -> Bool {
        boundaries.contains { range.lowerBound < $0 && range.upperBound > $0 }
            && !changed.contains { $0.overlaps(range) }
    }
}

/// A corrector's changes and the runs it declined to change, which a later layer must leave as heard.
public struct WeighedCorrections: Sendable, Equatable {
    public let corrections: [DictationCorrection]
    public let held: [Range<Int>]

    public init(corrections: [DictationCorrection], held: [Range<Int>] = []) {
        self.corrections = corrections
        self.held = held
    }
}

extension WordCorrecting {
    /// A corrector that names no declined run holds none.
    public func weigh(
        _ transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> WeighedCorrections {
        WeighedCorrections(corrections: try await corrections(for: transcription, seeing: context))
    }

    /// A corrector with no running budget weighs the joined text whole and keeps the seam changes.
    public func weighAcrossSeams(
        _ joined: Transcription, at seams: PieceSeams, seeing context: AppContext
    ) async throws(DictationChangeError) -> WeighedCorrections {
        let weighed = try await weigh(joined, seeing: context)
        return WeighedCorrections(corrections: weighed.corrections.filter { seams.admits($0.wordRange) })
    }

    /// A corrector that reads nothing that can change is already fixed.
    public func fixed() async -> any WordCorrecting { self }
}

/// Puts the user's stored text where they spoke its trigger.
public protocol SnippetExpanding: Sendable {
    /// The tidied text with snippets expanded and a record of each that fired; a throw is swallowed upstream.
    func expand(_ text: String) async throws(DictationChangeError) -> ExpandedTranscript
}

/// Told what a landed dictation used, one method per store so the pipeline decides what failure survives.
public protocol DictationLearning: Sendable {
    /// Notes the entries a landed dictation used: those `ids` applied, each listed once, and any spelled in `text`.
    func recordUse(ofEntries ids: [UUID], writtenIn text: String) async throws(DictationChangeError)

    /// Notes that these snippets fired in a dictation that landed; one that fired twice appears twice.
    func recordUse(ofSnippets ids: [UUID]) async throws(DictationChangeError)
}

/// Offered what a finished dictation showed, to learn new words unasked. See Docs/pipeline-changes.md.
public protocol VocabularyLearning: Sendable {
    /// Learns from what was `heard`, what was `wrote`, and the `context`; the dictation is already over.
    func learn(
        heard: String, wrote: String, seeing context: AppContext
    ) async throws(DictationChangeError)
}

/// The seams above wired to nothing: leave the words alone and remember nothing, written once.
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

    public func recordUse(ofEntries ids: [UUID], writtenIn text: String) {}

    public func recordUse(ofSnippets ids: [UUID]) {}

    public func learn(heard: String, wrote: String, seeing context: AppContext) {}
}
