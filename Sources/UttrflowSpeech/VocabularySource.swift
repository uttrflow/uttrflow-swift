public import UttrflowCore
public import UttrflowDictionary
public import struct Foundation.Date

/// Where the words worth putting in front of the recogniser come from, asked once per dictation.
public protocol VocabularySource: Sendable {
    /// The words to condition the decoder with, most valuable first.
    func vocabulary() async -> [String]
}

/// The user's dictionary ranked for the dictation about to happen; a bridge between two owners.
public struct DictionaryVocabulary: VocabularySource {
    /// Everything the ranking needs, read in one closure so all three describe a single instant.
    public typealias Reading =
        @Sendable () async -> (
            entries: [DictionaryEntry], context: AppContext, now: Date
        )

    private let read: Reading
    private let limit: Int

    /// Ranks up to `limit` words per dictation; the prompt's token budget usually binds first.
    public init(limit: Int = WorkingSet.defaultLimit, reading read: @escaping Reading) {
        self.limit = limit
        self.read = read
    }

    public func vocabulary() async -> [String] {
        let reading = await read()
        return WorkingSet.words(
            from: reading.entries, limit: limit, now: reading.now, favouring: reading.context)
    }
}
