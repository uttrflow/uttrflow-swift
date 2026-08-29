public import struct Foundation.Date
public import struct Foundation.UUID

/// Where a word came from.
///
/// Kept on every entry because it is what makes a bad one diagnosable rather than
/// mysterious. A word the user typed in themselves and a word the app inferred deserve
/// different treatment when something goes wrong, and only this distinguishes them.
public enum WordOrigin: String, Sendable, Equatable, CaseIterable, Codable {
    /// The user corrected a dictation and did not undo it.
    case learned
    /// The user typed it into the dictionary themselves.
    case added
    /// It appeared often enough across successful dictations to be worth keeping.
    case observed
}

/// One word this user says that a general model would not expect.
public struct DictionaryEntry: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    /// The spelling that should end up on screen.
    public let word: String
    /// How it sounds, when that differs from how it is written — "Nikhil" for a name a
    /// recogniser hears as "Nikkel". Absent when the spelling is a fair guide.
    public let pronunciation: String?
    public let origin: WordOrigin
    public let firstSeen: Date
    /// How many dictations this entry has been applied to.
    public var timesUsed: Int
    /// How many of those the user undid.
    ///
    /// The ratio of this to ``timesUsed`` is the only honest signal that an entry is
    /// wrong, and it is what lets a bad word retire itself instead of waiting to be
    /// noticed.
    public var timesReverted: Int

    public init(
        id: UUID = UUID(), word: String, pronunciation: String? = nil, origin: WordOrigin,
        firstSeen: Date, timesUsed: Int = 0, timesReverted: Int = 0
    ) {
        self.id = id
        self.word = word
        self.pronunciation = pronunciation
        self.origin = origin
        self.firstSeen = firstSeen
        self.timesUsed = timesUsed
        self.timesReverted = timesReverted
    }

    /// What the index should key this entry on: how it sounds, not how it is spelt.
    public var soundsLike: String { pronunciation ?? word }

    /// Whether the entry has earned its place.
    ///
    /// An entry the user keeps undoing is teaching the app to be wrong, which is the
    /// specific failure the reset exists for — but waiting for someone to notice and
    /// reset is a poor design when the evidence is already counted. Two undos out of
    /// three uses, with at least three uses so a single bad day cannot retire a good
    /// word.
    public var isTrustworthy: Bool {
        guard timesUsed >= 3 else { return true }
        return Double(timesReverted) / Double(timesUsed) < 0.5
    }
}
