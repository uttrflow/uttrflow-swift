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
    /// How many of those uses the person left unedited; the only use count that raises rank. See `Docs/app-dictionary-store.md`.
    var timesAccepted: Int
    /// How many uses the user undid; the ratio to `timesUsed` is what lets a bad word retire itself.
    public var timesReverted: Int
    /// The bundle identifiers it is offered in, as the person chose them; empty is everywhere. See ``ApplicationScope``.
    public let applications: [String]

    /// The most either counter may ever hold, so adding, subtracting or comparing them never overflows.
    public static let maximumCount = Int.max / 2

    /// The most pronunciations one entry keeps; each adds index keys, so the bound keeps filing cheap.
    public static let maximumPronunciations = 4

    /// An entry with at most one pronunciation, which is what the editor and most callers hold.
    public init(
        id: UUID = UUID(), word: String, pronunciation: String? = nil, origin: WordOrigin,
        firstSeen: Date, timesUsed: Int = 0, timesAccepted: Int? = nil, timesReverted: Int = 0,
        applications: [String] = []
    ) {
        self.init(
            id: id, word: word, pronunciations: pronunciation.map { [$0] } ?? [], origin: origin,
            firstSeen: firstSeen, timesUsed: timesUsed, timesAccepted: timesAccepted,
            timesReverted: timesReverted, applications: applications)
    }

    /// An entry said several ways; blanks and repeats are dropped and the list is cut at `maximumPronunciations`.
    public init(
        id: UUID = UUID(), word: String, pronunciations: [String], origin: WordOrigin,
        firstSeen: Date, timesUsed: Int = 0, timesAccepted: Int? = nil, timesReverted: Int = 0,
        applications: [String] = []
    ) {
        self.id = id
        self.word = word
        self.pronunciations = Self.bounded(pronunciations)
        self.origin = origin
        self.firstSeen = firstSeen
        self.timesUsed = Self.clamped(timesUsed)
        // Unspoken, an entry's accepted uses are its uses, so a file from before the counter keeps its rank.
        self.timesAccepted = min(Self.clamped(timesAccepted ?? timesUsed), self.timesUsed)
        self.timesReverted = Self.clamped(timesReverted)
        self.applications = ApplicationScope.normalised(applications)
    }

    private enum CodingKeys: String, CodingKey {
        case id, word, pronunciation, pronunciations, origin, firstSeen, timesUsed, timesAccepted,
            timesReverted, applications
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
            timesAccepted: try values.decodeIfPresent(Int.self, forKey: .timesAccepted),
            timesReverted: try values.decode(Int.self, forKey: .timesReverted),
            applications: try values.decodeIfPresent([String].self, forKey: .applications) ?? [])
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
        // Written only when it differs from `timesUsed`, which is what a file without it reads as.
        if timesAccepted != timesUsed { try values.encode(timesAccepted, forKey: .timesAccepted) }
        try values.encode(timesReverted, forKey: .timesReverted)
        if !applications.isEmpty { try values.encode(applications, forKey: .applications) }
    }

    /// Whether this word is offered where `bundleIdentifier` is in front.
    public func applies(in bundleIdentifier: String?) -> Bool {
        ApplicationScope.admits(applications, in: bundleIdentifier)
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

    /// How the editor's one field separates pronunciations, and how it shows a list.
    public static let pronunciationSeparator = ","

    /// The pronunciations a field holds, split at each comma, trimmed and bounded as an entry holds them.
    public static func pronunciations(inField field: String) -> [String] {
        bounded(
            field.split(separator: Character(pronunciationSeparator))
                .map {
                    String($0.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
                })
    }

    /// The list as the editor's one field shows it, so editing an entry keeps every pronunciation.
    public var pronunciationField: String { Self.pronunciationField(for: pronunciations) }

    /// A list as the editor's field shows it, after the bound an entry holds, so a field never offers more than is kept.
    public static func pronunciationField(for pronunciations: [String]) -> String {
        bounded(pronunciations).joined(separator: pronunciationSeparator + " ")
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
            firstSeen: firstSeen, timesUsed: timesUsed, timesAccepted: timesAccepted,
            timesReverted: timesReverted, applications: applications)
    }

    /// Accepted uses, undos netted out; the one count rank reads, safe because both counters stay in domain.
    public var netUses: Int { timesAccepted - timesReverted }

    /// Uses without an undo that promote a learned word out of provisional standing. See `Docs/app-dictionary-store.md`.
    public static let promotionUses = 3

    /// A word learned from Uttrflow's own output that the user has not yet kept through `promotionUses` uses.
    public var isProvisional: Bool {
        origin == .learned && timesReverted == 0 && timesUsed < Self.promotionUses
    }

    /// Whether the entry has earned its place under its origin's rule. See `Docs/app-dictionary-store.md`.
    public var isTrustworthy: Bool {
        Self.isTrustworthy(origin: origin, used: timesUsed, reverted: timesReverted)
    }

    /// When undo evidence retires a word: enough uses, then a revert rate provably above what is allowed.
    struct RetirementRule: Equatable {
        /// Uses below which no amount of undoing retires the word.
        let minimumUses: Int
        /// The revert rate the word may have; retirement needs the lower confidence bound above it.
        let allowedRevertRate: Double
    }

    /// The one-sided 95% normal quantile the lower confidence bound uses.
    static let retirementConfidenceZ = 1.645

    /// Learned and observed words follow the gate's tolerance; typed and shipped words need far more evidence.
    static func retirementRule(for origin: WordOrigin) -> RetirementRule {
        switch origin {
        case .learned, .observed: RetirementRule(minimumUses: 3, allowedRevertRate: 0.25)
        case .added, .shipped: RetirementRule(minimumUses: 10, allowedRevertRate: 0.5)
        }
    }

    /// The Wilson lower bound on the revert rate after `reverted` undos in `used` uses.
    static func revertRateLowerBound(used: Int, reverted: Int) -> Double {
        guard used > 0 else { return 0 }
        let n = Double(used)
        let p = min(Double(reverted), n) / n
        let z2 = retirementConfidenceZ * retirementConfidenceZ
        let centre = p + z2 / (2 * n)
        let spread = retirementConfidenceZ * (p * (1 - p) / n + z2 / (4 * n * n)).squareRoot()
        return (centre - spread) / (1 + z2 / n)
    }

    /// Whether counters of an origin keep the word in force, so a caller without an entry asks the same rule.
    static func isTrustworthy(origin: WordOrigin, used: Int, reverted: Int) -> Bool {
        let rule = retirementRule(for: origin)
        guard used >= rule.minimumUses else { return true }
        return revertRateLowerBound(used: used, reverted: reverted) <= rule.allowedRevertRate
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
