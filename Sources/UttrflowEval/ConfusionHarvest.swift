// Word pairs the recogniser confused on accented read speech, counted by first-language group, with no text beyond them.
private import UttrflowCore

/// The sound contrast a confused pair most plausibly shows, read from the two spellings.
public enum ConfusionClass: String, Sendable, Equatable, CaseIterable, Codable, Comparable {
    case vw = "v/w"
    case th = "th as t/d/s/f"
    case lr = "l/r"
    case sz = "s/z"
    case shs = "sh/s"
    case hDropping = "h-dropping"
    case finalConsonant = "final consonant"
    case vowel
    case other

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The class of `reference` written as `recognised`.
    public init(reference: String, recognised: String) {
        func swapped(_ a: String, _ b: String) -> Bool {
            reference.replacingOccurrences(of: a, with: b) == recognised
                || reference.replacingOccurrences(of: b, with: a) == recognised
        }
        let vowels = Set("aeiouy")
        if swapped("v", "w") {
            self = .vw
        } else if let th = reference.range(of: "th"),
            let offset = Optional(reference.distance(from: reference.startIndex, to: th.lowerBound)),
            offset < recognised.count,
            swapped("th", String(recognised[recognised.index(recognised.startIndex, offsetBy: offset)]))
        {
            self = .th
        } else if swapped("l", "r") {
            self = .lr
        } else if swapped("sh", "s") {
            self = .shs
        } else if swapped("s", "z") {
            self = .sz
        } else if reference.hasPrefix("h"), String(reference.dropFirst()) == recognised {
            self = .hDropping
        } else if recognised.count < reference.count, reference.hasPrefix(recognised),
            reference.dropFirst(recognised.count).allSatisfy({ !vowels.contains($0) })
        {
            self = .finalConsonant
        } else if reference.filter({ !vowels.contains($0) }) == recognised.filter({ !vowels.contains($0) }) {
            self = .vowel
        } else {
            self = .other
        }
    }
}

/// One decoded utterance: what was read, what was written, and who read it, by group only.
public struct HarvestUtterance: Sendable, Equatable {
    public let reference: [String]
    public let recognised: [String]
    public let group: String
    public let speaker: String

    public init(reference: [String], recognised: [String], group: String, speaker: String) {
        self.reference = reference
        self.recognised = recognised
        self.group = group
        self.speaker = speaker
    }
}

/// Where the table came from, written into the file so a reader can reproduce it.
public struct HarvestProvenance: Sendable, Equatable, Codable {
    public let dataset: String
    public let version: String
    public let licence: String
    public let engine: String
    public let seed: UInt64

    public init(dataset: String, version: String, licence: String, engine: String, seed: UInt64) {
        self.dataset = dataset
        self.version = version
        self.licence = licence
        self.engine = engine
        self.seed = seed
    }
}

/// The committable table: word pairs and class counts per group, nothing else.
public struct ConfusionTable: Sendable, Equatable, Codable {
    public struct Pair: Sendable, Equatable, Codable {
        public let reference: String
        public let recognised: String
        public let group: String
        public let count: Int
    }

    public struct ClassCount: Sendable, Equatable, Codable {
        public let group: String
        public let confusionClass: String
        public let count: Int
    }

    public let provenance: HarvestProvenance
    public let minimumSpeakers: Int
    public let pairs: [Pair]
    public let classes: [ClassCount]

    /// A digest of the table that is the same on every run for the same content.
    public var digest: String {
        var text = "\(provenance)|\(minimumSpeakers)"
        for pair in pairs { text += "|\(pair.reference)>\(pair.recognised)@\(pair.group)=\(pair.count)" }
        for row in classes { text += "|\(row.confusionClass)@\(row.group)=\(row.count)" }
        let value = text.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return String(value, radix: 16)
    }
}

/// Builds the table from the decoded utterances alone, and measures how much of a held-out half it covers.
public enum ConfusionHarvest {
    /// The group a first-language group too small to publish is merged into.
    public static let mergedGroup = "other"

    /// The substitutions of one utterance, as (reference word, recognised word).
    public static func substitutions(_ utterance: HarvestUtterance) -> [(String, String)] {
        WordErrorRate.measure(reference: utterance.reference, hypothesis: utterance.recognised).alignment
            .compactMap {
                if case .substitution(let reference, let hypothesis) = $0 {
                    (reference, hypothesis)
                } else {
                    nil
                }
            }
    }

    /// Whether `speaker` falls in the held-out half for `seed`, decided by a stable hash.
    public static func isHeldOut(speaker: String, seed: UInt64) -> Bool {
        stableHash(speaker, seed: seed) % 2 == 1
    }

    /// A hash of `text` that is the same on every run for the same `seed`, unlike `Hasher`.
    static func stableHash(_ text: String, seed: UInt64) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037 ^ seed) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    /// Each utterance's group, with groups read by fewer than `minimumSpeakers` speakers merged into `other`.
    static func publishedGroups(_ utterances: [HarvestUtterance], minimumSpeakers: Int) -> [String: String] {
        var speakers: [String: Set<String>] = [:]
        for utterance in utterances { speakers[utterance.group, default: []].insert(utterance.speaker) }
        return speakers.mapValues(\.count).reduce(into: [:]) { result, entry in
            result[entry.key] = entry.value >= minimumSpeakers ? entry.key : mergedGroup
        }
    }

    /// The table for `utterances`, sorted so two runs over the same input give the same digest.
    public static func table(
        _ utterances: [HarvestUtterance], provenance: HarvestProvenance, minimumSpeakers: Int
    ) -> ConfusionTable {
        let groups = publishedGroups(utterances, minimumSpeakers: minimumSpeakers)
        var pairs: [[String]: Int] = [:]
        var classes: [[String]: Int] = [:]
        for utterance in utterances {
            let group = groups[utterance.group] ?? mergedGroup
            for (reference, recognised) in substitutions(utterance) {
                pairs[[reference, recognised, group], default: 0] += 1
                let kind = ConfusionClass(reference: reference, recognised: recognised)
                classes[[group, kind.rawValue], default: 0] += 1
            }
        }
        return ConfusionTable(
            provenance: provenance, minimumSpeakers: minimumSpeakers,
            pairs: pairs.sorted { $0.key.lexicographicallyPrecedes($1.key) }.map {
                ConfusionTable.Pair(
                    reference: $0.key[0], recognised: $0.key[1], group: $0.key[2], count: $0.value)
            },
            classes: classes.sorted { $0.key.lexicographicallyPrecedes($1.key) }.map {
                ConfusionTable.ClassCount(group: $0.key[0], confusionClass: $0.key[1], count: $0.value)
            })
    }

    /// The share of substitutions in `heldOut` whose word pair `table` holds, or `nil` with none.
    public static func coverage(of table: ConfusionTable, on heldOut: [HarvestUtterance]) -> Double? {
        let known = Set(table.pairs.map { [$0.reference, $0.recognised] })
        let errors = heldOut.flatMap(substitutions)
        guard !errors.isEmpty else { return nil }
        return Double(errors.count { known.contains([$0.0, $0.1]) }) / Double(errors.count)
    }
}
