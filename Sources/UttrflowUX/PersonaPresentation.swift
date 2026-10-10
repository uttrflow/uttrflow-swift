// What the evidence ledger records about this user, as items Settings lists and removes one at a time.

public import UttrflowCore
import UttrflowDictionary
public import struct Foundation.UUID

/// One removable fact the ledger holds, named by what its rows are about.
public enum PersonaFact: Sendable, Hashable {
    /// Uses and undone corrections of one dictionary entry.
    case word(UUID)
    /// How dictations into one kind of place are written.
    case style(Destination)
    /// Words heard but not yet learned, which the ledger keeps without their spelling.
    case noticedWords

    /// The rows removing this fact deletes; one fact never reaches another fact's rows.
    var kinds: Set<EvidenceRow.Kind> {
        switch self {
        case .word: [.use, .revert, .restore]
        case .style: [.styleMessage, .styleWords, .styleSentences, .styleShortMessage, .styleClosingStop]
        case .noticedWords: [.sighting]
        }
    }

    /// The row subject, or `nil` when the fact spans every subject of its kinds.
    var subject: String? {
        switch self {
        case .word(let id): id.uuidString
        case .style(let destination): destination.rawValue
        case .noticedWords: nil
        }
    }
}

/// One line of the persona list: what the fact is, and the counts behind it.
public struct PersonaItem: Sendable, Equatable, Identifiable {
    public let fact: PersonaFact
    public let title: String
    public let detail: String

    /// Stable across reads, so removing one row never moves focus to another's identity.
    public var id: String {
        switch fact {
        case .word(let id): "word.\(id.uuidString)"
        case .style(let destination): "style.\(destination.rawValue)"
        case .noticedWords: "noticed"
        }
    }
}

/// Projects ledger rows into the list; it reports sums of recorded rows and infers nothing further.
enum PersonaProfile {
    /// Words first, most used first, then each kind of place, then words still being watched.
    static func items(from rows: [EvidenceRow], entries: [DictionaryEntry]) -> [PersonaItem] {
        words(rows, entries) + styles(rows) + noticed(rows)
    }

    private static func words(_ rows: [EvidenceRow], _ entries: [DictionaryEntry]) -> [PersonaItem] {
        var uses: [UUID: Int] = [:]
        var undone: [UUID: Int] = [:]
        for row in rows {
            guard let id = UUID(uuidString: row.subject) else { continue }
            switch row.kind {
            case .use: uses[id, default: 0] += row.weight
            case .revert: undone[id, default: 0] += row.weight
            default: continue
            }
        }
        let spelled = Dictionary(entries.map { ($0.id, $0.word) }, uniquingKeysWith: { first, _ in first })
        let ids = Set(uses.keys).union(undone.keys).filter { (uses[$0] ?? 0) > 0 || (undone[$0] ?? 0) > 0 }
        return
            ids
            .map { id -> (Int, PersonaItem) in
                let used = uses[id] ?? 0
                let reverted = undone[id] ?? 0
                var detail = "Used \(times(used))"
                if reverted > 0 { detail += ", undone \(times(reverted))" }
                let title = spelled[id] ?? "A word no longer in your dictionary"
                return (used, PersonaItem(fact: .word(id), title: title, detail: detail))
            }
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1.title < $1.1.title }
            .map(\.1)
    }

    private static func styles(_ rows: [EvidenceRow]) -> [PersonaItem] {
        Destination.allCases.compactMap { destination in
            let signals = StyleSignals.project(rows, for: destination)
            guard signals.messages > 0 else { return nil }
            var parts = [counted(signals.messages, "dictation", "dictations")]
            if let length = signals.meanSentenceLength {
                parts.append("about \(Int(length.rounded())) words a sentence")
            }
            if let rate = signals.closingStopRate {
                parts.append("\(Int((rate * 100).rounded()))% of short ones end with a full stop")
            }
            return PersonaItem(
                fact: .style(destination),
                title: "Writing in \(SettingsDestinations.phrase(of: destination))",
                detail: parts.joined(separator: ", "))
        }
    }

    private static func noticed(_ rows: [EvidenceRow]) -> [PersonaItem] {
        var net: [String: Int] = [:]
        for row in rows where row.kind == .sighting { net[row.subject, default: 0] += row.weight }
        let watched = net.values.count { $0 > 0 }
        guard watched > 0 else { return [] }
        return [
            PersonaItem(
                fact: .noticedWords, title: "Words heard but not learned yet",
                detail: "\(counted(watched, "word", "words")), kept without their spelling")
        ]
    }

    private static func times(_ count: Int) -> String { count == 1 ? "once" : "\(count) times" }

    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
