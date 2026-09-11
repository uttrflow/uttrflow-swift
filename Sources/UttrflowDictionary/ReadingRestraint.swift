// What a sound key cannot decide on its own.

/// The restraint every phonetic lookup needs and the encoder cannot supply. See `Docs/cleanup.md`.
public enum ReadingRestraint {
    /// The opening letters a reading must share, because a word that merely rhymes is noise, not a reading.
    public static let openingLettersShared = 2

    /// Lower-cased letters and digits, so "payment sheet" and `PaymentSheet` open the same way.
    public static func closedUp(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Whether a reading opens like the word heard; the encoder drops inner vowels, so the opening is what is left.
    public static func opensAlike(_ reading: String, heard: String) -> Bool {
        let reading = closedUp(reading)
        let heard = closedUp(heard)
        guard reading.count >= openingLettersShared, heard.count >= openingLettersShared else {
            return reading == heard
        }
        return reading.prefix(openingLettersShared) == heard.prefix(openingLettersShared)
    }

    /// Whether a reading is worth offering for what was heard: another spelling, sounding alike and opening alike.
    public static func isWorthOffering(_ reading: String, for heard: String) -> Bool {
        closedUp(reading) != closedUp(heard) && opensAlike(reading, heard: heard)
            && DoubleMetaphone.code(for: reading).sounds(like: DoubleMetaphone.code(for: heard))
    }
}
