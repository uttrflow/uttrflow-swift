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
            let key = word.text.lowercased()
            guard !key.isEmpty else { continue }
            // Lowest wins where a word repeats: the doubtful reading is the one worth acting on.
            scores[key] = min(scores[key] ?? word.confidence, word.confidence)
        }
        guard !scores.isEmpty else { return nil }

        return spoken.map { word in
            let key = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            // An unscored word gets 1, "no reason to doubt it", which keeps it out of reach of condition one.
            return ScoredWord(text: word, confidence: scores[key] ?? 1)
        }
    }
}

/// Proposes the user's own spelling where the recogniser guessed; it never applies, so the pipeline decides.
public protocol WordCorrecting: Sendable {
    /// Every change worth arguing for, with ranges into the whitespace-split words; a throw is survived.
    func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async throws(DictationChangeError) -> [DictationCorrection]
}

/// Puts the user's stored text where they spoke its trigger.
public protocol SnippetExpanding: Sendable {
    /// The tidied text with snippets expanded and a record of each that fired; a throw is swallowed upstream.
    func expand(_ text: String) async throws(DictationChangeError) -> ExpandedTranscript
}

/// Told what a landed dictation used, one method per store so the pipeline decides what failure survives.
public protocol DictationLearning: Sendable {
    /// Notes that one dictionary entry was applied to a dictation that landed.
    func recordUse(ofEntry id: UUID) async throws(DictationChangeError)

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

    public func recordUse(ofEntry id: UUID) {}

    public func recordUse(ofSnippets ids: [UUID]) {}

    public func learn(heard: String, wrote: String, seeing context: AppContext) {}
}
