// The correction engine over a dictionary, as the pipeline's word-correcting seam.
public import UttrflowCore
public import UttrflowDictionary
import UttrflowAI
private import Synchronization

/// The correction engine over the user's dictionary: mapping only, deciding none of it.
public struct DictionaryCorrections: WordCorrecting {
    /// The dictionary arranged by sound, read when a dictation fixes it.
    public typealias Indexing = @Sendable () async -> PhoneticIndex

    private let index: Indexing
    private let engine = WordCorrectionEngine()
    /// The dictation's running budget once fixed; unfixed, every call is its own dictation.
    private let spent: Spent?

    public init(index: @escaping Indexing) {
        self.init(index: index, spent: nil)
    }

    private init(index: @escaping Indexing, spent: Spent?) {
        self.index = index
        self.spent = spent
    }

    /// The dictionary as it stands now and one budget for every piece; a word learnt later waits for the next dictation.
    public func fixed() async -> any WordCorrecting {
        let held = await index()
        return DictionaryCorrections(index: { held }, spent: Spent())
    }

    public func weighAcrossSeams(
        _ joined: Transcription, at seams: PieceSeams, seeing context: AppContext
    ) async -> WeighedCorrections {
        // Fixed, the pieces hear every joined word, so the seam pass spends what is left and hears none.
        let weighed = await weigh(
            joined, hearing: spent == nil ? nil : 0, considering: seams.admits, seeing: context)
        return WeighedCorrections(corrections: weighed.corrections.filter { seams.admits($0.wordRange) })
    }

    public func corrections(
        for transcription: Transcription, seeing context: AppContext
    ) async -> [DictationCorrection] {
        await weigh(transcription, seeing: context).corrections
    }

    public func weigh(
        _ transcription: Transcription, seeing context: AppContext
    ) async -> WeighedCorrections {
        await weigh(transcription, hearing: nil, considering: { _ in true }, seeing: context)
    }

    /// One engine call against the running budget; `hearing` nil counts every word of the transcription.
    private func weigh(
        _ transcription: Transcription, hearing newWords: Int?,
        considering isConsidered: (Range<Int>) -> Bool, seeing context: AppContext
    ) async -> WeighedCorrections {
        // No score, no judgement: Apple's recogniser reports none, so it gets no corrections.
        guard let scored = transcription.scoredWords else { return WeighedCorrections(corrections: []) }
        let utterance = Utterance(
            words: scored.map { SpokenWord(text: $0.text, confidence: $0.confidence) })

        let dictionary = await index()
        func charge(_ budget: inout CorrectionBudget) -> CorrectionVerdict {
            engine.verdict(
                for: utterance, against: dictionary, seeing: context, spending: &budget,
                hearing: newWords ?? utterance.words.count, considering: isConsidered)
        }
        var fresh = CorrectionBudget()
        let verdict = spent?.budget.withLock { charge(&$0) } ?? charge(&fresh)

        return WeighedCorrections(
            corrections: verdict.proposals.map {
                DictationCorrection(
                    heard: $0.heard, wrote: $0.replacement, wordRange: $0.wordRange,
                    entryID: $0.entryID, reason: $0.reason,
                    heardConfidence: $0.heardConfidence)
            },
            held: verdict.held)
    }
}

/// One dictation's budget, shared by its pieces and its seam pass; taken under a lock so no two calls overspend it.
private final class Spent: Sendable {
    let budget = Mutex(CorrectionBudget())
}
