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
    /// Every way the user says it when that differs from how it is written, at most `maximumPronunciations`.
    public let pronunciations: [String]
    public let origin: WordOrigin
    public let firstSeen: Date
    /// How many landed dictations this entry appeared in, by a rewrite or spelled right by the recogniser.
    public var timesUsed: Int
    /// How many uses the user undid; the ratio to `timesUsed` is what lets a bad word retire itself.
    public var timesReverted: Int

    /// The most either counter may ever hold, so adding, subtracting or comparing them never overflows.
    public static let maximumCount = Int.max / 2

    /// The most pronunciations one entry keeps; each adds index keys, so the bound keeps filing cheap.
    public static let maximumPronunciations = 4

    /// An entry with at most one pronunciation, which is what the editor and most callers hold.
    public init(
        id: UUID = UUID(), word: String, pronunciation: String? = nil, origin: WordOrigin,
        firstSeen: Date, timesUsed: Int = 0, timesReverted: Int = 0
    ) {
        self.init(
            id: id, word: word, pronunciations: pronunciation.map { [$0] } ?? [], origin: origin,
            firstSeen: firstSeen, timesUsed: timesUsed, timesReverted: timesReverted)
    }

    /// An entry said several ways; blanks and repeats are dropped and the list is cut at `maximumPronunciations`.
    public init(
        id: UUID = UUID(), word: String, pronunciations: [String], origin: WordOrigin,
        firstSeen: Date, timesUsed: Int = 0, timesReverted: Int = 0
    ) {
        self.id = id
        self.word = word
        self.pronunciations = Self.bounded(pronunciations)
        self.origin = origin
        self.firstSeen = firstSeen
        self.timesUsed = Self.clamped(timesUsed)
        self.timesReverted = Self.clamped(timesReverted)
    }

    private enum CodingKeys: String, CodingKey {
        case id, word, pronunciation, pronunciations, origin, firstSeen, timesUsed, timesReverted
    }

    /// Decodes a stray counter into domain, and a file from before the list as its one `pronunciation`.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let single = try values.decodeIfPresent(String.self, forKey: .pronunciation)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            word: try values.decode(String.self, forKey: .word),
            pronunciations: try values.decodeIfPresent([String].self, forKey: .pronunciations)
                ?? single.map { [$0] } ?? [],
            origin: try values.decode(WordOrigin.self, forKey: .origin),
            firstSeen: try values.decode(Date.self, forKey: .firstSeen),
            timesUsed: try values.decode(Int.self, forKey: .timesUsed),
            timesReverted: try values.decode(Int.self, forKey: .timesReverted))
    }

    /// Writes the list, and its first entry as `pronunciation` so a build from before the list still reads it.
    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(word, forKey: .word)
        try values.encodeIfPresent(pronunciation, forKey: .pronunciation)
        if pronunciations.count > 1 { try values.encode(pronunciations, forKey: .pronunciations) }
        try values.encode(origin, forKey: .origin)
        try values.encode(firstSeen, forKey: .firstSeen)
        try values.encode(timesUsed, forKey: .timesUsed)
        try values.encode(timesReverted, forKey: .timesReverted)
    }

    /// The first pronunciation, the one the editor shows; absent when the spelling is a fair guide.
    public var pronunciation: String? { pronunciations.first }

    /// The spelling with case and spaces closed up, preserving symbols that change its written identity.
    public var spellingKey: String { Self.spellingKey(for: word) }

    /// The key two spellings share when they write the same word; an all-filtered spelling keys as itself.
    public static func spellingKey(for spelling: String) -> String {
        let closed = spelling.lowercased().filter { $0.isLetter || $0.isNumber || "+#&./-".contains($0) }
        return closed.isEmpty ? spelling.lowercased() : closed
    }

    /// The sound the entry is ranked by: its first pronunciation, or the spelling when it has none.
    public var soundsLike: String { pronunciation ?? word }

    /// Every reading the index files the entry under: the spelling, then each pronunciation, without repeats.
    public var readings: [String] {
        Self.bounded([word] + pronunciations, limit: Self.maximumPronunciations + 1)
    }

    /// The entry spelt in Latin letters, a Devanagari spelling kept as its pronunciation. See `Docs/latin-output.md`.
    public var inLatinScript: DictionaryEntry {
        guard Romaniser.containsDevanagari(word) else { return self }
        return DictionaryEntry(
            id: id, word: Romaniser.romanised(word),
            pronunciations: pronunciations.isEmpty ? [word] : pronunciations,
            origin: origin,
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

    /// Non-blank, distinct, in order and at most `limit`, so every path that builds an entry holds the same bound.
    static func bounded(_ readings: [String], limit: Int = maximumPronunciations) -> [String] {
        var seen: Set<String> = []
        let kept = readings.filter { !$0.allSatisfy(\.isWhitespace) && seen.insert($0).inserted }
        return Array(kept.prefix(limit))
    }

    /// Keeps a persisted or incremented counter inside zero and `maximumCount`, negative values included.
    static func clamped(_ count: Int) -> Int {
        min(max(count, 0), maximumCount)
    }
}
