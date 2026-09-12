// The words this build ships knowing, and the record of having seeded them.

public import struct Foundation.Date

/// The words Uttrflow ships knowing, because a general model gets them wrong and every user says them.
public enum ShippedWords {
    /// Bumped when the list changes, so a build that adds a word seeds the new one and not the old ones again.
    public static let version = 1

    /// The spellings, with a pronunciation only where the spelling is not a fair guide to the sound.
    public static let spellings: [(word: String, pronunciation: String?)] = [
        ("Uttrflow", nil)
    ]

    /// The entries as they are written down, dated by whoever is seeding them.
    public static func entries(at moment: Date) -> [DictionaryEntry] {
        spellings.map {
            DictionaryEntry(
                word: $0.word, pronunciation: $0.pronunciation, origin: .shipped, firstSeen: moment)
        }
    }
}
