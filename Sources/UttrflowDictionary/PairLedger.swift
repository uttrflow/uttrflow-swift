// What a heard-to-written pair must show before it becomes a dictionary entry. See Docs/app-dictionary.md.

package import UttrflowCore

/// Counts each edited pair by keyed hash and releases it only on enough sightings across separate days.
package struct PairLedger: Sendable {
    /// Sightings a pair needs in total before it becomes an entry.
    static let sightingsBeforeLearning = 3
    /// Separate days those sightings must fall on.
    static let daysBeforeLearning = 2
    /// The most pending pairs kept at once.
    static let maximumPending = 128
    /// The most refusals kept at once; past it the oldest lapses.
    static let maximumRefused = 512

    /// The sightings of each pending pair on each day, by the pair's hash.
    private var pending: [String: [Int: Int]] = [:]
    /// The count of pairs made entries on each day.
    private var learntOnDay: [Int: Int] = [:]
    /// The refused pair keys, lowercased.
    private var refused: Set<String> = []
    /// The refused pair keys oldest first, so the bound lapses the oldest.
    private var refusalOrder: [String] = []
    /// Turns a lowercased pair key into the key it is counted under; `nil` means it cannot be counted privately.
    private let digest: @Sendable (String) -> String?

    /// Starts from earlier refusals, oldest first, and earlier `pairSighting` and `pairLearnt` rows.
    package init(
        refusing earlier: [String] = [], remembering rows: [EvidenceRow] = [],
        digest: @escaping @Sendable (String) -> String? = { $0 }
    ) {
        self.digest = digest
        var net: [String: [Int: Int]] = [:]
        for row in rows {
            switch row.kind {
            case .pairSighting: net[row.subject, default: [:]][row.day, default: 0] += row.weight
            case .pairLearnt: learntOnDay[row.day, default: 0] += row.weight
            default: continue
            }
        }
        for (subject, days) in net {
            let kept = days.filter { $0.value > 0 }
            if !kept.isEmpty { pending[subject] = kept }
        }
        for key in earlier { _ = insertRefusal(key) }
        _ = prune()
    }

    /// How many pairs are waiting now.
    var pendingCount: Int { pending.count }

    /// The refused pair keys oldest first, which a store writes down.
    var refusals: [String] { refusalOrder }

    /// Whether this pair is refused.
    func isRefused(heard: String, meant: String) -> Bool {
        refused.contains(Self.refusalKey(heard: heard, meant: meant))
    }

    /// Refuses a pair, dropping its count and answering the rows that cancel it.
    mutating func refuse(heard: String, meant: String) -> [EvidenceRow] {
        let key = Self.refusalKey(heard: heard, meant: meant)
        _ = insertRefusal(key)
        guard let subject = digest(key) else { return [] }
        return forget(subject)
    }

    /// Lifts the refusal of a pair, answering whether the pair is refused.
    mutating func allow(heard: String, meant: String) -> Bool {
        let key = Self.refusalKey(heard: heard, meant: meant)
        guard refused.remove(key) != nil else { return false }
        refusalOrder.removeAll { $0 == key }
        return true
    }

    /// Counts one edit on `day`, answering the pair when it now meets the rule and the rows to append.
    package mutating func record(
        heard: String, meant: String, on day: Int
    ) -> (learnt: ConfusionPairs.Pair?, rows: [EvidenceRow]) {
        let key = Self.refusalKey(heard: heard, meant: meant)
        guard Self.isCountable(heard: heard, meant: meant), !refused.contains(key), let subject = digest(key)
        else { return (nil, []) }
        var rows: [EvidenceRow] = []
        // A day already holding the total needed adds no evidence, so a burst of edits writes no more rows.
        if (pending[subject]?[day] ?? 0) < Self.sightingsBeforeLearning {
            pending[subject, default: [:]][day, default: 0] += 1
            rows.append(Self.row(.pairSighting, subject, day: day))
        }
        let days = pending[subject] ?? [:]
        var learnt: ConfusionPairs.Pair?
        if days.values.reduce(0, +) >= Self.sightingsBeforeLearning,
            days.count >= Self.daysBeforeLearning,
            learntOnDay[day, default: 0] < ConfusionPairs.maximumNewPairsPerDay
        {
            rows += forget(subject)
            rows.append(Self.row(.pairLearnt, subject, day: day))
            learntOnDay[day, default: 0] += 1
            learnt = ConfusionPairs.Pair(heard: heard, meant: meant)
        }
        rows += prune()
        return (learnt, rows)
    }

    /// Drops every pending pair, keeping refusals, answering the rows that cancel them.
    mutating func clearPending() -> [EvidenceRow] {
        pending.keys.sorted().flatMap { forget($0) }
    }

    /// The key a pair is refused and counted under: the closed-up heard words, then the lowercased written word.
    private static func refusalKey(heard: String, meant: String) -> String {
        ConfusionPairs.key(heard: heard, meant: meant.lowercased()).lowercased()
    }

    /// Whether the pair records a real confusion in Latin letters.
    private static func isCountable(heard: String, meant: String) -> Bool {
        let heardKey = ReadingRestraint.closedUp(heard)
        return !heardKey.isEmpty && !meant.isEmpty && LatinScript.isLatin(meant)
            && heardKey != ReadingRestraint.closedUp(meant)
    }

    private static func row(
        _ kind: EvidenceRow.Kind, _ subject: String, day: Int, weight: Int = 1
    )
        -> EvidenceRow
    {
        EvidenceRow(kind: kind, subject: subject, weight: weight, day: day, provenance: .dictation)
    }

    /// Adds a refusal, lapsing the oldest past the bound; answers whether the pair is new.
    private mutating func insertRefusal(_ key: String) -> Bool {
        guard refused.insert(key).inserted else { return false }
        refusalOrder.append(key)
        if refusalOrder.count > Self.maximumRefused { refused.remove(refusalOrder.removeFirst()) }
        return true
    }

    /// Removes one pending pair, answering a cancelling row for each day it held.
    private mutating func forget(_ subject: String) -> [EvidenceRow] {
        let days = pending.removeValue(forKey: subject) ?? [:]
        return days.sorted { $0.key < $1.key }.map {
            Self.row(.pairSighting, subject, day: $0.key, weight: -$0.value)
        }
    }

    /// Drops the weakest evidence past the bound: fewest days, then oldest, then by key.
    private mutating func prune() -> [EvidenceRow] {
        guard pending.count > Self.maximumPending else { return [] }
        let ranked = pending.sorted {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            let (newest, other) = ($0.value.keys.max() ?? 0, $1.value.keys.max() ?? 0)
            return newest != other ? newest > other : $0.key < $1.key
        }
        return ranked.dropFirst(Self.maximumPending).flatMap { forget($0.key) }
    }
}
