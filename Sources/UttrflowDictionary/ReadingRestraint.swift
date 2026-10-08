// What a sound key cannot decide on its own.

internal import Foundation

/// What a phonetic lookup must ask beyond the sound key, which the encoder cannot answer. See `Docs/cleanup.md`.
public enum ReadingRestraint {
    /// The opening letters a reading must share, because a word that merely rhymes is noise, not a reading.
    public static let openingLettersShared = 2

    /// Lower-cased letters and digits, so "payment sheet" and `PaymentSheet` open the same way.
    public static func closedUp(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Whether a reading opens like the word heard, or is listed in `Homophones` as the same sound spelt another way.
    public static func opensAlike(_ reading: String, heard: String) -> Bool {
        if Homophones.share(reading, heard) { return true }
        let reading = closedUp(reading).folding(options: .diacriticInsensitive, locale: nil)
        let heard = closedUp(heard).folding(options: .diacriticInsensitive, locale: nil)
        guard reading.count >= openingLettersShared, heard.count >= openingLettersShared else {
            return reading == heard
        }
        return reading.prefix(openingLettersShared) == heard.prefix(openingLettersShared)
    }

    /// Whether both words are ones a general recogniser already expects, which makes a shared sound key a collision rather than evidence.
    public static func bothOrdinary(_ reading: String, heard: String) -> Bool {
        GeneralVocabulary.isOrdinary(closedUp(reading)) && GeneralVocabulary.isOrdinary(closedUp(heard))
    }

    /// Whether a sound key alone is offering one ordinary word for another, which is a collision rather than a reading.
    public static func isOrdinaryCollision(_ reading: String, heard: String) -> Bool {
        bothOrdinary(reading, heard: heard) && !Homophones.share(reading, heard)
    }

    /// Whether a reading is worth offering: another spelling, sounding alike, opening alike, and no ordinary collision.
    public static func isWorthOffering(_ reading: String, for heard: String) -> Bool {
        isWorthOffering(ReadingKey(reading), for: ReadingKey(heard))
    }

    /// The same question of two words whose spelling and sound are already worked out, for a caller asking many.
    public static func isWorthOffering(_ reading: ReadingKey, for heard: ReadingKey) -> Bool {
        guard reading.closed != heard.closed, opensAlike(reading.closed, heard: heard.closed) else {
            return false
        }
        return !isOrdinaryCollision(reading.closed, heard: heard.closed)
            && reading.code.sounds(like: heard.code)
    }
}

/// A word with the two things the reading check asks of it already worked out, so many asks cost one each.
public struct ReadingKey: Sendable, Equatable {
    public let word: String
    /// The spelling with case and marks closed up, which both halves of the check compare on.
    public let closed: String
    /// How it sounds, taken once rather than once per comparison.
    public let code: PhoneticCode

    public init(_ word: String) {
        self.word = word
        self.closed = ReadingRestraint.closedUp(word)
        self.code = DoubleMetaphone.code(for: word)
    }
}
