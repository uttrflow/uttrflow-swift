// The words worth conditioning the recogniser with.

public import UttrflowCore
public import struct Foundation.Date

/// The words worth putting in front of the recogniser before it decodes anything; spellings only.
public enum WorkingSet {
    /// How many words fit a conditioning prompt beside everything else that conditions the decoder.
    public static let defaultLimit = 96

    /// The age at which a word's value halves: thirty days.
    static let recencyHalfLifeInDays = 30.0

    /// What the frontmost app agreeing with an entry is worth: one, the most frequency alone can give.
    static let affinityWeight = 1.0

    /// The highest-value words within `limit`, best first, scored on frequency, recency and screen affinity.
    public static func words(
        from entries: [DictionaryEntry],
        limit: Int = WorkingSet.defaultLimit,
        now: Date,
        favouring context: AppContext = .unknown
    ) -> [String] {
        guard limit > 0 else { return [] }
        let wanted = soundsOnScreen(in: context)
        let ranked =
            entries
            .filter(\.isTrustworthy)
            .map { (entry: $0, value: value(of: $0, now: now, wanted: wanted)) }
            .sorted { first, second in
                if first.value != second.value { return first.value > second.value }
                // Ties broken the same way buckets are, so the two lists never disagree.
                return PhoneticIndex.isMoreUseful(first.entry, second.entry)
            }
        return ranked.prefix(limit).map(\.entry.word)
    }

    /// The most words read off the screen, so a selected document is a bounded read.
    static let maximumWordsOnScreen = 64

    /// The sounds of everything the frontmost app is showing, split on anything that is not a letter.
    static func soundsOnScreen(in context: AppContext) -> Set<String> {
        let onScreen = [context.applicationName, context.documentName, context.selectedText]
            .compactMap { $0 }
            .joined(separator: " ")
        let visible = Utterance(
            words: LearnableWords.words(in: onScreen, atMost: maximumWordsOnScreen)
                .map { SpokenWord(text: $0, confidence: 1) })
        return visible.sounds(upTo: PhoneticIndex.maximumWordsPerEntry)
    }

    /// What one prompt slot spent on this entry is worth.
    static func value(of entry: DictionaryEntry, now: Date, wanted: Set<String>) -> Double {
        let kept = Double(max(0, entry.timesUsed - entry.timesReverted))
        let frequency = kept / (1 + kept)
        // Clamped at zero, so a future-stamped entry scores as brand new, not impossibly valuable.
        let ageInDays = max(0, now.timeIntervalSince(entry.firstSeen)) / 86_400
        let recency = recencyHalfLifeInDays / (recencyHalfLifeInDays + ageInDays)
        let onScreen = DoubleMetaphone.code(for: entry.soundsLike).sounds(likeAnyOf: wanted)
        return frequency + recency + (onScreen ? affinityWeight : 0)
    }
}
