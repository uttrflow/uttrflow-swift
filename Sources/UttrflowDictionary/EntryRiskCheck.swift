// Whether a word added to the dictionary would be proposed in place of ordinary words, found before it can do harm.

/// What replaying the shipped sentences through the dictionary lookup says about one entry.
public struct EntryRisk: Sendable, Equatable {
    /// Sentences in which the entry would be proposed for an ordinary word.
    public let sentencesHit: Int
    /// Sentences replayed.
    public let sentencesChecked: Int

    /// Whether the entry would replace ordinary words often enough to warn the person who is adding it.
    public var isRisky: Bool {
        sentencesChecked > 0 && Double(sentencesHit) / Double(sentencesChecked) >= EntryRiskCheck.flagShare
    }
}

/// Replays invented, ordinary sentences, as text only, through the lookup the correction engine uses.
public enum EntryRiskCheck {
    /// The share of the shipped sentences an entry may be proposed in before it is flagged: two of forty.
    public static let flagShare = 0.05

    /// Checks `entry` alone against `sentences`, counting each sentence where it would stand in for an ordinary word.
    public static func risk(
        of entry: DictionaryEntry, sentences: [String] = EntryRiskSentences.all
    ) -> EntryRisk {
        let index = PhoneticIndex(entries: [entry])
        let hit = sentences.filter { sentence in
            sentence.split(separator: " ").map { String($0).lowercased() }.contains { word in
                GeneralVocabulary.isOrdinary(word) && !index.candidates(soundingLike: word).isEmpty
            }
        }
        return EntryRisk(sentencesHit: hit.count, sentencesChecked: sentences.count)
    }
}
