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
    /// A heard-to-meant pair the correction gate weighs, named by its ledger subject.
    case pair(String)
    /// A respelling the user's edits taught between two spellings of one listed word, named by its ledger subject.
    case spelling(String)

    /// The rows removing this fact deletes; one fact never reaches another fact's rows.
    var kinds: Set<EvidenceRow.Kind> {
        switch self {
        case .word: [.use, .revert, .restore]
        case .style: [.styleMessage, .styleWords, .styleSentences, .styleShortMessage, .styleClosingStop]
        case .noticedWords: [.sighting]
        case .pair: [.pairConfirmed, .pairVetoed, .pairAllowed, .pairRetried]
        case .spelling: [.spellingPreference, .spellingPreferenceCleared]
        }
    }

    /// The row subject, or `nil` when the fact spans every subject of its kinds.
    var subject: String? {
        switch self {
        case .word(let id): id.uuidString
        case .style(let destination): destination.rawValue
        case .noticedWords: nil
        case .pair(let subject), .spelling(let subject): subject
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
        case .pair(let subject): "pair.\(subject)"
        case .spelling(let subject): "spelling.\(subject)"
        }
    }
}

/// Projects ledger rows into the list; it reports sums of recorded rows and infers nothing further.
enum PersonaProfile {
    /// Words first, most used first, then each kind of place, then words still being watched, then pairs and respellings.
    static func items(from rows: [EvidenceRow], entries: [DictionaryEntry]) -> [PersonaItem] {
        words(rows, entries) + styles(rows) + noticed(rows) + pairs(rows) + spellings(rows)
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

    /// One item per heard-to-meant pair with any row, counting the separate days it was kept and undone.
    private static func pairs(_ rows: [EvidenceRow]) -> [PersonaItem] {
        var kept: [String: Set<Int>] = [:]
        var undone: [String: Set<Int>] = [:]
        var subjects: Set<String> = []
        for row in rows {
            switch row.kind {
            case .pairConfirmed: kept[row.subject, default: []].insert(row.day)
            case .pairVetoed: undone[row.subject, default: []].insert(row.day)
            case .pairAllowed, .pairRetried: break
            default: continue
            }
            subjects.insert(row.subject)
        }
        return subjects.sorted().compactMap { subject in
            guard let sides = sides(of: subject) else { return nil }
            var parts: [String] = []
            if let days = kept[subject] { parts.append("kept on \(counted(days.count, "day", "days"))") }
            if let days = undone[subject] { parts.append("undone on \(counted(days.count, "day", "days"))") }
            let detail = parts.isEmpty ? "allowed again after being undone" : parts.joined(separator: ", ")
            return PersonaItem(
                fact: .pair(subject), title: "Heard \(sides.0), meant \(sides.1)",
                detail: detail.prefix(1).uppercased() + detail.dropFirst())
        }
    }

    /// One item per respelling that edits taught and the user has not deleted, with the days it was seen on.
    private static func spellings(_ rows: [EvidenceRow]) -> [PersonaItem] {
        var days: [String: Set<Int>] = [:]
        var cleared: [String: Int] = [:]
        for row in rows {
            switch row.kind {
            case .spellingPreference where row.weight > 0: days[row.subject, default: []].insert(row.day)
            case .spellingPreferenceCleared: cleared[row.subject] = max(cleared[row.subject] ?? .min, row.day)
            default: continue
            }
        }
        return days.keys.sorted().compactMap { subject in
            let live = (days[subject] ?? []).filter { $0 > (cleared[subject] ?? .min) }
            guard !live.isEmpty, let sides = sides(of: subject) else { return nil }
            return PersonaItem(
                fact: .spelling(subject), title: "Writing \(sides.1) for \(sides.0)",
                detail: "Seen on \(counted(live.count, "day", "days")) in your edits")
        }
    }

    /// The two words a pair subject joins with `>`, or `nil` for a subject of another shape.
    private static func sides(of subject: String) -> (String, String)? {
        let parts = subject.split(separator: ">", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    private static func times(_ count: Int) -> String { count == 1 ? "once" : "\(count) times" }

    private static func counted(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
