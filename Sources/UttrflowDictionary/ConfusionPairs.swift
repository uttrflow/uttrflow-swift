// What the recogniser heard paired with what the user meant, kept as evidence rows and projected on read.

public import UttrflowCore

/// The one record of heard-to-meant pairs that veto, alias and preference read. See `Docs/learned-state.md`.
public enum ConfusionPairs {
    /// Separate days a pair must be kept on before it counts, so a lone event changes nothing.
    public static let daysBeforeConfirming = 3

    /// How alike, as the Dice coefficient of the two heard word lists, a dictation must be to the one before to respeak it.
    public static let respeakSimilarity = 0.6
    /// The most pairs one re-dictation writes against, so a whole respoken paragraph cannot touch every pair at once.
    public static let retriedPairsPerDictation = 3
    /// Separate days a pair must be respoken on before its re-dictations count at all, so one retry changes nothing.
    public static let daysBeforeRetryCounts = 2
    /// The most undone days re-dictations add to a pair, so they never outweigh a single kept day.
    public static let retriedDaysCap = 1

    /// One correction a dictation applied: what the recogniser heard and the word written in its place.
    public struct Pair: Sendable, Equatable {
        public let heard: String
        public let meant: String

        public init(heard: String, meant: String) {
            self.heard = heard
            self.meant = meant
        }
    }

    /// What a pair's evidence says to the correction gate; a feature, never a rewrite on its own.
    public enum Feature: Sendable, Equatable {
        /// Kept on enough separate days, and on more days than it is undone.
        case confirmed
        /// Undone on more days than kept.
        case vetoed
    }

    /// The row one kept correction writes: a selection correction or a later edit of `heard` into `meant`.
    public static func confirming(
        heard: String, meant: String, day: Int, provenance: EvidenceRow.Provenance = .dictation
    ) -> [EvidenceRow] {
        row(.pairConfirmed, heard: heard, meant: meant, day: day, provenance: provenance)
    }

    /// The row one undo of a rewrite writes: the user took `meant` back to what was heard.
    public static func vetoing(heard: String, meant: String, day: Int) -> [EvidenceRow] {
        row(.pairVetoed, heard: heard, meant: meant, day: day, provenance: .undo)
    }

    /// The row the user's "Allow" writes: every undo of the pair on or before `day` stops counting.
    public static func allowing(heard: String, meant: String, day: Int) -> [EvidenceRow] {
        row(.pairAllowed, heard: heard, meant: meant, day: day, provenance: .user)
    }

    /// The capped `pairRetried` rows when the retry respeaks `heard` and drops a pair's written word; the caller checks timing.
    public static func retrying(
        _ applied: [Pair], heard: String, retryHeard: String, retryWrote: String, day: Int
    ) -> [EvidenceRow] {
        guard similarity(words(of: heard), words(of: retryHeard)) >= respeakSimilarity else { return [] }
        let written = words(of: retryWrote)
        let dropped = applied.filter { pair in
            let meant = words(of: pair.meant)
            return !meant.isEmpty && !contains(meant, in: written)
        }
        return Array(
            dropped.flatMap {
                row(.pairRetried, heard: $0.heard, meant: $0.meant, day: day, provenance: .dictation)
            }
            .prefix(retriedPairsPerDictation))
    }

    /// The feature for each pair with one, keyed by ``key(heard:meant:)``; a pair with equal days is inert.
    public static func project(_ rows: [EvidenceRow]) -> [String: Feature] {
        var allowed: [String: Int] = [:]
        for row in rows where row.kind == .pairAllowed {
            allowed[row.subject] = max(allowed[row.subject] ?? .min, row.day)
        }
        var confirmed: [String: Set<Int>] = [:]
        var vetoed: [String: Set<Int>] = [:]
        var retried: [String: Set<Int>] = [:]
        for row in rows {
            switch row.kind {
            case .pairConfirmed: confirmed[row.subject, default: []].insert(row.day)
            case .pairVetoed where row.day > (allowed[row.subject] ?? .min):
                vetoed[row.subject, default: []].insert(row.day)
            case .pairRetried where row.day > (allowed[row.subject] ?? .min):
                retried[row.subject, default: []].insert(row.day)
            default: continue
            }
        }
        var features: [String: Feature] = [:]
        for key in Set(confirmed.keys).union(vetoed.keys).union(retried.keys) {
            let kept = confirmed[key]?.count ?? 0
            let undoneDays = vetoed[key] ?? []
            let retriedDays = (retried[key] ?? []).subtracting(undoneDays).count
            let undone = undoneDays.count + (retriedDays >= daysBeforeRetryCounts ? retriedDaysCap : 0)
            if undone > kept {
                features[key] = .vetoed
            } else if kept > undone, kept >= daysBeforeConfirming {
                features[key] = .confirmed
            }
        }
        return features
    }

    /// The pair's key: the heard words closed up by `ReadingRestraint.closedUp`, then the meant word.
    public static func key(heard: String, meant: String) -> String {
        ReadingRestraint.closedUp(heard) + String(separator) + meant
    }

    private static func row(
        _ kind: EvidenceRow.Kind, heard: String, meant: String, day: Int, provenance: EvidenceRow.Provenance
    ) -> [EvidenceRow] {
        let heardKey = ReadingRestraint.closedUp(heard)
        // A pair with an empty side, or one that changes nothing once closed up, records no confusion.
        guard !heardKey.isEmpty, !meant.isEmpty, heardKey != ReadingRestraint.closedUp(meant) else {
            return []
        }
        return [
            EvidenceRow(
                kind: kind, subject: key(heard: heard, meant: meant), day: day, provenance: provenance)
        ]
    }

    /// Closed-up words, so case and punctuation never decide whether a word was respoken or written.
    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { ReadingRestraint.closedUp(String($0)) }
            .filter { !$0.isEmpty }
    }

    /// The Dice coefficient of two word lists counted as multisets; 0 when either is empty.
    private static func similarity(_ first: [String], _ second: [String]) -> Double {
        guard !first.isEmpty, !second.isEmpty else { return 0 }
        var counts: [String: Int] = [:]
        for word in first { counts[word, default: 0] += 1 }
        var shared = 0
        for word in second where (counts[word] ?? 0) > 0 {
            counts[word, default: 0] -= 1
            shared += 1
        }
        return 2 * Double(shared) / Double(first.count + second.count)
    }

    /// Whether `run` occurs, in order and adjacent, inside `words`.
    private static func contains(_ run: [String], in words: [String]) -> Bool {
        guard run.count <= words.count else { return false }
        return (0...(words.count - run.count)).contains { Array(words[$0..<($0 + run.count)]) == run }
    }

    private static let separator: Character = ">"
}
