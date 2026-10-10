// The correction engine over a dictionary, as the pipeline's word-correcting seam.
public import UttrflowCore
public import UttrflowDictionary
import UttrflowAI
private import Synchronization

/// The correction engine over the user's dictionary: mapping only, deciding none of it.
public struct DictionaryCorrections: WordCorrecting {
    /// The words offered in an application arranged by sound, read when a dictation fixes it.
    public typealias Indexing = @Sendable (_ application: String?) async -> PhoneticIndex
    /// The heard-to-meant pairings the user kept or undid, read when a dictation fixes it.
    public typealias Pairing = @Sendable () async -> [String: ConfusionPairs.Feature]

    private let index: Indexing
    private let pairs: Pairing
    private let engine = WordCorrectionEngine()
    /// The dictation's running budget once fixed; unfixed, every call is its own dictation.
    private let spent: Spent?
    /// The held dictionary's revision once fixed; unfixed, the dictionary can change under every call.
    public let revision: UInt64?

    /// `pairs` is the ledger's ``ConfusionPairs`` projection; none leaves the gate as the dictionary alone makes it.
    public init(index: @escaping Indexing, pairs: @escaping Pairing = { [:] }) {
        self.init(index: index, pairs: pairs, spent: nil, revision: nil)
    }

    private init(index: @escaping Indexing, pairs: @escaping Pairing, spent: Spent?, revision: UInt64?) {
        self.index = index
        self.pairs = pairs
        self.spent = spent
        self.revision = revision
    }

    /// The dictionary as it stands now in the context's application and one budget for every piece; a word learnt later waits.
    public func fixed(for context: AppContext) async -> any WordCorrecting {
        let held = await index(context.bundleIdentifier)
        let heldPairs = await pairs()
        return DictionaryCorrections(
            index: { _ in held }, pairs: { heldPairs }, spent: Spent(), revision: held.revision)
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
        let dictionary = await index(context.bundleIdentifier)
        // No score, no judgement: Apple's recogniser reports none, so it gets only an entry's case, which weighs nothing.
        guard let scored = transcription.scoredWords else {
            return WeighedCorrections(
                corrections: Self.recasings(of: transcription.text, against: dictionary, seeing: context))
        }
        let utterance = Utterance(
            words: scored.map { SpokenWord(text: $0.text, confidence: $0.confidence) })

        let pairing = await pairs()
        func charge(_ budget: inout CorrectionBudget) -> CorrectionVerdict {
            engine.verdict(
                for: utterance, against: dictionary, seeing: context, spending: &budget,
                hearing: newWords ?? utterance.words.count, considering: isConsidered, pairs: pairing)
        }
        var fresh = CorrectionBudget()
        let verdict = spent?.budget.withLock { charge(&$0) } ?? charge(&fresh)

        return WeighedCorrections(corrections: verdict.proposals.map(Self.dictation), held: verdict.held)
    }

    /// Every run of `text` spelling an entry in another case, written the entry's way: all an unscored transcript gets.
    package static func recasings(
        of text: String, against dictionary: PhoneticIndex, seeing context: AppContext
    ) -> [DictationCorrection] {
        let heard = text.spokenWords.map { SpokenWord(text: String($0), confidence: 1) }
        let recased = WordCorrectionEngine.recasings(
            of: Utterance(words: heard), against: dictionary, seeing: context)
        return recased.map(Self.dictation)
    }

    /// One engine proposal as the pipeline records it.
    private static func dictation(_ proposal: WordCorrection) -> DictationCorrection {
        DictationCorrection(
            heard: proposal.heard, wrote: proposal.replacement, wordRange: proposal.wordRange,
            entryID: proposal.entryID, reason: proposal.reason,
            heardConfidence: proposal.heardConfidence, evidence: proposal.evidence)
    }
}

/// One dictation's budget, shared by its pieces and its seam pass; taken under a lock so no two calls overspend it.
private final class Spent: Sendable {
    let budget = Mutex(CorrectionBudget())
}
