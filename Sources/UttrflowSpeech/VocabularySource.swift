// Where the words put in front of the recogniser come from.
public import UttrflowCore
public import UttrflowDictionary
public import struct Foundation.Date

/// Where the words worth putting in front of the recogniser come from, asked once per dictation.
public protocol VocabularySource: Sendable {
    /// The words to condition the decoder with, most valuable first, ranked for what the speaker is looking at.
    func vocabulary(favouring context: AppContext) async -> [String]
}

/// The user's dictionary ranked for the dictation about to happen; a bridge between two owners.
public struct DictionaryVocabulary: VocabularySource {
    /// What the ranking needs beyond the screen, which its caller has already read for this dictation.
    public typealias Reading =
        @Sendable () async -> (entries: [DictionaryEntry], index: PhoneticIndex, now: Date)

    private let read: Reading
    private let evidence: (@Sendable () async -> [EvidenceRow])?
    private let limit: Int

    /// Ranks up to `limit` words; `evidence`, the ledger inside History's window, is given only while the persona layer is on.
    public init(
        limit: Int = WorkingSet.defaultLimit, evidence: (@Sendable () async -> [EvidenceRow])? = nil,
        reading read: @escaping Reading
    ) {
        self.limit = limit
        self.evidence = evidence
        self.read = read
    }

    public func vocabulary(favouring context: AppContext) async -> [String] {
        let reading = await read()
        let rows = await evidence?() ?? []
        return WorkingSet.words(
            from: reading.entries, coded: reading.index, limit: limit, now: reading.now, favouring: context,
            evidence: rows)
    }
}
