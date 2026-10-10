// What the recogniser heard paired with what the user meant, kept as evidence rows and projected on read.

public import UttrflowCore

/// The one record of heard-to-meant pairs that veto, alias and preference read. See `Docs/learned-state.md`.
public enum ConfusionPairs {
    /// Separate days a pair must be kept on before it counts, so a lone event changes nothing.
    public static let daysBeforeConfirming = 3

    /// New pairs that may start counting on one day, so a field rewritten in bulk cannot teach many at once.
    public static let maximumNewPairsPerDay = 10

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
        // Dictation writes only Latin letters, so a replacement in another script is no word to learn.
        guard LatinScript.isLatin(meant) else { return [] }
        return row(.pairConfirmed, heard: heard, meant: meant, day: day, provenance: provenance)
    }

    /// The row one undo of a rewrite writes: the user took `meant` back to what was heard.
    public static func vetoing(heard: String, meant: String, day: Int) -> [EvidenceRow] {
        row(.pairVetoed, heard: heard, meant: meant, day: day, provenance: .undo)
    }

    /// The row the user's "Allow" writes: every undo of the pair on or before `day` stops counting.
    public static func allowing(heard: String, meant: String, day: Int) -> [EvidenceRow] {
        row(.pairAllowed, heard: heard, meant: meant, day: day, provenance: .user)
    }

    /// The feature for each pair with one, keyed by ``key(heard:meant:)``; a pair with equal days is inert.
    public static func project(_ rows: [EvidenceRow]) -> [String: Feature] {
        var allowed: [String: Int] = [:]
        for row in rows where row.kind == .pairAllowed {
            allowed[row.subject] = max(allowed[row.subject] ?? .min, row.day)
        }
        var confirmed: [String: Set<Int>] = [:]
        var vetoed: [String: Set<Int>] = [:]
        var started: [Int: Int] = [:]
        // Stable by day, so the first pairs written on a day are the ones that start counting on it.
        let ordered = rows.enumerated().sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }
        for row in ordered.map(\.element) {
            switch row.kind {
            case .pairConfirmed where confirmed[row.subject] != nil:
                confirmed[row.subject, default: []].insert(row.day)
            case .pairConfirmed where started[row.day, default: 0] < maximumNewPairsPerDay:
                started[row.day, default: 0] += 1
                confirmed[row.subject] = [row.day]
            case .pairVetoed where row.day > (allowed[row.subject] ?? .min):
                vetoed[row.subject, default: []].insert(row.day)
            default: continue
            }
        }
        var features: [String: Feature] = [:]
        for key in Set(confirmed.keys).union(vetoed.keys) {
            let kept = confirmed[key]?.count ?? 0
            let undone = vetoed[key]?.count ?? 0
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

    private static let separator: Character = ">"
}
