// One dictionary entry and where it came from.

import UttrflowCore
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
    /// This build ships knowing it, the product's own name among them. See `Docs/app-dictionary-store.md`.
    case shipped
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
    /// How many landed dictations this entry appeared in, by a rewrite or spelled right by the recogniser.
    public var timesUsed: Int
    /// How many uses the user undid; the ratio to `timesUsed` is what lets a bad word retire itself.
    public var timesReverted: Int

    /// The most either counter may ever hold, so adding, subtracting or comparing them never overflows.
    public static let maximumCount = Int.max / 2

    public init(
        id: UUID = UUID(), word: String, pronunciation: String? = nil, origin: WordOrigin,
        firstSeen: Date, timesUsed: Int = 0, timesReverted: Int = 0
    ) {
        self.id = id
        self.word = word
        self.pronunciation = pronunciation
        self.origin = origin
        self.firstSeen = firstSeen
        self.timesUsed = Self.clamped(timesUsed)
        self.timesReverted = Self.clamped(timesReverted)
    }

    /// Decodes a hand-edited or otherwise stray counter into the domain the rest of the type assumes.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            word: try values.decode(String.self, forKey: .word),
            pronunciation: try values.decodeIfPresent(String.self, forKey: .pronunciation),
            origin: try values.decode(WordOrigin.self, forKey: .origin),
            firstSeen: try values.decode(Date.self, forKey: .firstSeen),
            timesUsed: try values.decode(Int.self, forKey: .timesUsed),
            timesReverted: try values.decode(Int.self, forKey: .timesReverted))
    }

    /// The spelling with case and spaces closed up, preserving symbols that change its written identity.
    public var spellingKey: String { Self.spellingKey(for: word) }

    /// The key two spellings share when they write the same word; an all-filtered spelling keys as itself.
    public static func spellingKey(for spelling: String) -> String {
        let closed = spelling.lowercased().filter { $0.isLetter || $0.isNumber || "+#&./-".contains($0) }
        return closed.isEmpty ? spelling.lowercased() : closed
    }

    /// What the index should key this entry on: how it sounds, not how it is spelt.
    public var soundsLike: String { pronunciation ?? word }

    /// The entry spelt in Latin letters, a Devanagari spelling kept as its pronunciation. See `Docs/latin-output.md`.
    public var inLatinScript: DictionaryEntry {
        guard Romaniser.containsDevanagari(word) else { return self }
        return DictionaryEntry(
            id: id, word: Romaniser.romanised(word), pronunciation: pronunciation ?? word, origin: origin,
            firstSeen: firstSeen, timesUsed: timesUsed, timesReverted: timesReverted)
    }

    /// Uses the word survived, undos netted out; safe to compute because both counters stay in domain.
    public var netUses: Int { timesUsed - timesReverted }

    /// Uses without an undo that promote a learned word out of provisional standing. See `Docs/app-dictionary-store.md`.
    public static let promotionUses = 3

    /// A word learned from Uttrflow's own output that the user has not yet kept through `promotionUses` uses.
    public var isProvisional: Bool {
        origin == .learned && timesReverted == 0 && timesUsed < Self.promotionUses
    }

    /// Whether the entry has earned its place: fewer than half its uses undone, once it has three.
    public var isTrustworthy: Bool {
        guard timesUsed >= 3 else { return true }
        return Double(timesReverted) / Double(timesUsed) < 0.5
    }

    /// Keeps a persisted or incremented counter inside zero and `maximumCount`, negative values included.
    static func clamped(_ count: Int) -> Int {
        min(max(count, 0), maximumCount)
    }
}
