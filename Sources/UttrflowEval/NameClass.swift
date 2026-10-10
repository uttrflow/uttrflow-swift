// The proper-name class: names tagged by origin and frequency band, and how a recogniser spelled each.
internal import Foundation

/// One name the recogniser must spell, with the origin and frequency band it is reported under.
public struct NameClassItem: Sendable, Equatable, Codable, Identifiable {
    /// Where a name's spelling comes from, which decides whether its sounds map to English letters.
    public enum Origin: String, Sendable, Equatable, CaseIterable, Codable {
        case english
        case southAsian
        case eastAsian
        case african
        case slavic
        case irishScottish
        case arabic
    }

    /// How often the name is written in English text, judged by the author; see Docs/eval-methodology.md.
    public enum Band: String, Sendable, Equatable, CaseIterable, Codable {
        case common
        case uncommon
        case rare
    }

    /// What the name names, which decides the carrier it is read in.
    public enum Kind: String, Sendable, Equatable, CaseIterable, Codable {
        case given
        case surname
        case place
        /// A given name that is also an ordinary word, so only its capital says it is a person.
        case wordAlike

        /// The fixed words read either side of the name, so what was heard is the run between them.
        public var carrier: (before: String, after: String) {
            switch self {
            case .given, .wordAlike: ("I had a long call with", "this morning")
            case .surname: ("the form was signed by Doctor", "this morning")
            case .place: ("we are flying to", "next week")
            }
        }
    }

    public let id: String
    public let name: String
    public let origin: Origin
    public let band: Band
    public let kind: Kind

    public init(id: String, name: String, origin: Origin, band: Band, kind: Kind) {
        self.id = id
        self.name = name
        self.origin = origin
        self.band = band
        self.kind = kind
    }

    /// The sentence a voice reads.
    public var sentence: String { "\(kind.carrier.before) \(name) \(kind.carrier.after)" }
}

/// The bundled name class, read from `Resources/Corpus/Names/names.json`.
public enum NameClassCorpus {
    /// Why the bundled file could not be read.
    public struct Failure: Error, Equatable {
        public let reason: String
    }

    /// Every name in the bundled file, in file order.
    public static func items() throws -> [NameClassItem] {
        guard
            let path = Bundle.module.path(forResource: "names", ofType: "json", inDirectory: "Corpus/Names"),
            let data = FileManager.default.contents(atPath: path)
        else { throw Failure(reason: "no file") }
        return try decode(data)
    }

    /// The names in one file's bytes, refused whole on a duplicate id or name.
    static func decode(_ data: Data) throws -> [NameClassItem] {
        let items: [NameClassItem]
        do {
            items = try JSONDecoder().decode([NameClassItem].self, from: data)
        } catch {
            throw Failure(reason: "unreadable: \(error)")
        }
        var ids: Set<String> = []
        var names: Set<String> = []
        for item in items {
            guard ids.insert(item.id).inserted else { throw Failure(reason: "duplicate id \(item.id)") }
            guard names.insert(item.name).inserted else {
                throw Failure(reason: "duplicate name \(item.name)")
            }
        }
        return items
    }
}

/// The words between a carrier's own, counted by one normaliser so both ends are cut the same way.
public enum CarrierRun {
    /// The run left once the carrier's word counts come off each end, or `nil` when nothing is left.
    public static func words(
        in transcript: String, before: String, after: String, normaliser: TextNormaliser = .standard
    ) -> [String]? {
        let words = normaliser.words(transcript)
        let leading = normaliser.words(before).count
        let trailing = normaliser.words(after).count
        guard words.count > leading + trailing else { return nil }
        return Array(words[leading..<(words.count - trailing)])
    }
}

/// One clip of one name, transcribed with the name in the vocabulary prompt or without it.
public struct NameClassRow: Sendable, Equatable {
    public let item: NameClassItem
    public let voice: String
    public let inDictionary: Bool
    /// The transcript's words between the carrier's, case kept; `nil` when nothing was left.
    public let heard: [String]?
    public let transcript: String

    /// Case kept and apostrophes dropped, so a capital counts and "O'Sullivan" stays one word.
    public static let spelling = TextNormaliser(rules: [.apostropheFolding, .punctuationAsSeparators])
    /// The same with case folded, so a name heard right but written lower case still counts as spelled.
    public static let letters = TextNormaliser(
        rules: [.caseFolding, .apostropheFolding, .punctuationAsSeparators])

    public init(item: NameClassItem, voice: String, inDictionary: Bool, transcript: String) {
        self.item = item
        self.voice = voice
        self.inDictionary = inDictionary
        self.transcript = transcript
        heard = CarrierRun.words(
            in: transcript, before: item.kind.carrier.before, after: item.kind.carrier.after,
            normaliser: Self.spelling)
    }

    /// Whether the run is the name exactly, capitals included.
    public var isExact: Bool { heard == Self.spelling.words(item.name) }

    /// Whether the run is the name once case is folded.
    public var isSpelled: Bool {
        heard.map { Self.letters.words($0.joined(separator: " ")) } == Self.letters.words(item.name)
    }

    /// The run as one string, or a marker when the carrier swallowed it.
    public var heardText: String { heard.map { $0.joined(separator: " ") } ?? "<too short>" }

    /// One tab-separated line, for the rows file a later run is compared with.
    public var line: String {
        [
            voice, inDictionary ? "dictionary" : "plain", item.origin.rawValue, item.band.rawValue,
            item.kind.rawValue, item.name, heardText, transcript,
        ].joined(separator: "\t")
    }
}

/// Exact and spelled shares by origin and band, with and without the dictionary, and the confusions.
public struct NameClassReport: Sendable, Equatable {
    public let rows: [NameClassRow]

    public init(rows: [NameClassRow]) {
        self.rows = rows
    }

    /// The share of `rows` that pass, as a percentage; `nil` for no rows.
    static func share(_ rows: [NameClassRow], _ passes: (NameClassRow) -> Bool) -> Double? {
        rows.isEmpty ? nil : Double(rows.filter(passes).count) / Double(rows.count) * 100
    }

    private static func text(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0) } ?? "n/a"
    }

    /// One table row: clips, then exact and spelled shares without and with the dictionary.
    private func cells(_ group: [NameClassRow]) -> String {
        let plain = group.filter { !$0.inDictionary }
        let biased = group.filter(\.inDictionary)
        let values = [
            Self.share(plain, \.isExact), Self.share(biased, \.isExact),
            Self.share(plain, \.isSpelled), Self.share(biased, \.isSpelled),
        ].map(Self.text)
        return "\(plain.count) | \(biased.count) | " + values.joined(separator: " | ")
    }

    /// The columns ``cells(_:)`` fills, after the grouping columns, and the line under them.
    private static let header = (
        "| Plain clips | Dictionary clips | Exact, plain | Exact, dictionary "
            + "| Spelled, plain | Spelled, dictionary |",
        "|---|---|---|---|---|---|"
    )

    /// One row per origin and band that has clips, then one per band over every origin.
    public var originBandTable: String {
        var lines = ["| Origin | Band " + Self.header.0, "|---|---" + Self.header.1]
        for origin in NameClassItem.Origin.allCases {
            for band in NameClassItem.Band.allCases {
                let group = rows.filter { $0.item.origin == origin && $0.item.band == band }
                guard !group.isEmpty else { continue }
                lines.append("| \(origin.rawValue) | \(band.rawValue) | \(cells(group)) |")
            }
        }
        for band in NameClassItem.Band.allCases {
            let group = rows.filter { $0.item.band == band }
            guard !group.isEmpty else { continue }
            lines.append("| all | \(band.rawValue) | \(cells(group)) |")
        }
        return lines.joined(separator: "\n")
    }

    /// One row per kind that has clips, so a word-alike name's lost capital shows apart.
    public var kindTable: String {
        var lines = ["| Kind " + Self.header.0, "|---" + Self.header.1]
        for kind in NameClassItem.Kind.allCases {
            let group = rows.filter { $0.item.kind == kind }
            guard !group.isEmpty else { continue }
            lines.append("| \(kind.rawValue) | \(cells(group)) |")
        }
        return lines.joined(separator: "\n")
    }

    /// The band whose plain clips are least often exact, ties to the rarer; `nil` for no plain clips.
    public var weakestBand: NameClassItem.Band? {
        let scored = NameClassItem.Band.allCases.reversed().compactMap { band in
            Self.share(rows.filter { $0.item.band == band && !$0.inDictionary }, \.isExact).map { (band, $0) }
        }
        return scored.min { $0.1 < $1.1 }?.0
    }

    /// Every miss as heard against meant, by band then origin, with how many clips heard it so.
    public var confusions: String {
        var lines = ["| Band | Origin | Meant | Heard | Plain | Dictionary |", "|---|---|---|---|---|---|"]
        for band in NameClassItem.Band.allCases {
            for origin in NameClassItem.Origin.allCases {
                let misses = rows.filter { $0.item.band == band && $0.item.origin == origin && !$0.isExact }
                var order: [String] = []
                var counts: [String: (plain: Int, dictionary: Int)] = [:]
                for miss in misses {
                    let key = "\(miss.item.name) | \(miss.heardText)"
                    if counts[key] == nil { order.append(key) }
                    var count = counts[key] ?? (0, 0)
                    if miss.inDictionary { count.dictionary += 1 } else { count.plain += 1 }
                    counts[key] = count
                }
                for key in order {
                    let count = counts[key] ?? (0, 0)
                    lines.append(
                        "| \(band.rawValue) | \(origin.rawValue) | \(key) "
                            + "| \(count.plain) | \(count.dictionary) |")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
