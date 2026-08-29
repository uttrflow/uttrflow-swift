public import UttrflowCore
public import UttrflowDictionary
public import struct Foundation.Date

/// Where the words worth putting in front of the recogniser come from.
///
/// Asked once per dictation rather than handed over as a list, because the answer
/// changes between dictations: the ranking depends on what is on screen at the moment
/// the key goes down, and on everything the user has said since the last one.
///
/// Optional everywhere it is used. An engine given no source behaves exactly as it did
/// before biasing existed, which is what keeps this a quality improvement rather than a
/// new way for a dictation to fail.
public protocol VocabularySource: Sendable {
    /// The words to condition the decoder with, most valuable first.
    func vocabulary() async -> [String]
}

/// The user's own dictionary, ranked for the dictation about to happen.
///
/// A bridge and nothing more, on purpose. ``WorkingSet`` owns which words are worth a
/// prompt slot and knows nothing about recognisers; ``VocabularyPrompt`` owns what fits
/// in the prompt and knows nothing about how a word earned its place. Neither would be
/// improved by learning the other's job.
public struct DictionaryVocabulary: VocabularySource {
    /// Everything the ranking needs, read at the moment a dictation begins.
    ///
    /// One closure rather than three because the three describe a single instant. Split
    /// across three awaits, the entries could be read before a word was learnt and the
    /// screen after the user switched app, and the ranking would be of a moment that
    /// never happened.
    public typealias Reading =
        @Sendable () async -> (
            entries: [DictionaryEntry], context: AppContext, now: Date
        )

    private let read: Reading
    private let limit: Int

    /// - Parameters:
    ///   - limit: How many words to rank. The prompt's own token budget is usually the
    ///     binding constraint, so raising this buys less than it looks like it should.
    ///   - read: How to obtain the dictionary, the screen and the clock.
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
