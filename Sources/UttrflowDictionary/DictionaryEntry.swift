// One dictionary entry and where it came from.

public import struct Foundation.Date
public import struct Foundation.UUID

/// Where a word came from, kept on every entry so a bad one is diagnosable.
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
    /// How it sounds when that differs from how it is written; absent when the spelling is a fair guide.
    public let pronunciation: String?
    public let origin: WordOrigin
    public let firstSeen: Date
    /// How many dictations this entry has been applied to.
    public var timesUsed: Int
    /// How many uses the user undid; the ratio to `timesUsed` is what lets a bad word retire itself.
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

    /// Whether the entry has earned its place: fewer than half its uses undone, once it has three.
    public var isTrustworthy: Bool {
        guard timesUsed >= 3 else { return true }
        return Double(timesReverted) / Double(timesUsed) < 0.5
    }
}
