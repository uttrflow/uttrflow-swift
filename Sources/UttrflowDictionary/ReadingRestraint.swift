// What a sound key cannot decide on its own.

internal import Foundation
public import UttrflowCore

/// What a phonetic lookup must ask beyond the sound key: how far apart the two pronunciations are. See `Docs/cleanup.md`.
public enum ReadingRestraint {
    /// Lower-cased letters and digits, so "payment sheet" and `PaymentSheet` open the same way.
    public static func closedUp(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Whether a reading sounds within one phoneme of the word heard, by weighted phoneme distance over the lexicon.
    public static func soundsNear(_ reading: String, heard: String) -> Bool {
        PhonemeLexicon.shared.soundsNear(reading, heard)
    }


    /// Whether both words are ones a general recogniser already expects, which makes a shared sound key a collision rather than evidence.
    public static func bothOrdinary(_ reading: String, heard: String) -> Bool {
        GeneralVocabulary.isOrdinary(closedUp(reading)) && GeneralVocabulary.isOrdinary(closedUp(heard))

    }

    /// Whether one ordinary word is offered for another it is not said exactly like: a near sound, not a reading.
    public static func isOrdinaryCollision(_ reading: String, heard: String) -> Bool {
        bothOrdinary(reading, heard: heard) && !PhonemeLexicon.shared.soundsSame(reading, heard)
    }


    /// Whether a reading is worth offering: another spelling, sharing a sound key, within one phoneme, and not one ordinary word for another.

    public static func isWorthOffering(_ reading: String, for heard: String) -> Bool {
        isWorthOffering(ReadingKey(reading), for: ReadingKey(heard))
    }

    /// The same question of two words whose spelling and sound are already worked out, for a caller asking many.
    public static func isWorthOffering(_ reading: ReadingKey, for heard: ReadingKey) -> Bool {

        guard reading.closed != heard.closed, reading.sound.sounds(like: heard.sound) else { return false }
        return !isOrdinaryCollision(reading.word, heard: heard.word)
            && soundsNear(reading.word, heard: heard.word)

    }
}

/// A word with the two things the reading check asks of it already worked out, so many asks cost one each.
public struct ReadingKey: Sendable, Equatable {
    public let word: String
    /// The spelling with case and marks closed up, which both halves of the check compare on.
    public let closed: String
    /// How it sounds, taken once rather than once per comparison.
    public let sound: WordSound

    public init(_ word: String) {
        self.word = word
        self.closed = ReadingRestraint.closedUp(word)
        self.sound = WordSound(of: word)
    }
}
