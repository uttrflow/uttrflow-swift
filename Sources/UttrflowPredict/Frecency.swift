import struct Foundation.Date
import func Foundation.log
import func Foundation.pow

/// Scores a candidate by how much evidence stands behind it, never by whether it is correct.
enum Frecency {
    /// How long a single use takes to lose half its weight.
    static let halfLifeInDays = 21.0

    /// What an entry counts for when it was taken from us rather than typed, so we do not learn from ourselves.
    static let selfSourcedWeight = 0.25

    /// How much a perfect acceptance record lifts a candidate, and how much an entirely refused one lowers it.
    static let acceptanceLift = 0.6

    /// The least the acceptance factor may fall to, so refusal lowers a line without ever erasing it.
    static let acceptanceFloor = 0.1

    /// What the environment is worth on its own, being true but not necessarily wanted.
    static let environmentWeight = 1.0

    /// The score of one candidate at a moment in time.
    static func score(_ candidate: Candidate, now: Date) -> Double {
        guard let evidence = candidate.evidence else { return environmentWeight / distancePenalty(candidate) }
        let uses = effectiveCount(evidence)
        guard uses > 0 else { return 0 }
        return log(1 + uses) * decay(evidence.lastUsed, now: now) * acceptance(evidence)
            / distancePenalty(candidate)
    }

    /// Uses, with the ones we suggested ourselves discounted so acceptance cannot feed itself.
    static func effectiveCount(_ evidence: Entry) -> Double {
        let typed = Double(max(evidence.count - evidence.selfSourced, 0))
        let taken = Double(min(evidence.selfSourced, evidence.count))
        return typed + taken * selfSourcedWeight
    }

    /// How much a use is still worth, halving every `halfLifeInDays`.
    static func decay(_ lastUsed: Date, now: Date) -> Double {
        let days = now.timeIntervalSince(lastUsed) / 86_400
        guard days > 0 else { return 1 }
        return pow(2, -days / halfLifeInDays)
    }

    /// How the candidate has fared when offered: 1 until it has been, then within [1 - lift, 1 + lift], never below the floor.
    static func acceptance(_ evidence: Entry) -> Double {
        let offered = evidence.accepted + evidence.rejected
        guard offered > 0 else { return 1 }
        let balance = Double(evidence.accepted - evidence.rejected) / Double(offered)
        return max(1 + acceptanceLift * balance, acceptanceFloor)
    }

    /// How much a fuzzy match is worth against an exact one, since a typo means less certainty.
    static func distancePenalty(_ candidate: Candidate) -> Double {
        Double(1 + candidate.editDistance * 2)
    }
}
