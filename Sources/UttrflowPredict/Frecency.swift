public import struct Foundation.Date
public import func Foundation.log
public import func Foundation.pow

/// Scores a candidate by how much evidence stands behind it, never by whether it is correct.
public enum Frecency {
    /// How long a single use takes to lose half its weight.
    static let halfLifeInDays = 21.0

    /// What an entry counts for when we offered it rather than the user typing it, so it cannot feed itself.
    static let selfSourcedWeight = 0.25

    /// How much a perfect acceptance record lifts a candidate, and how much an entirely refused one lowers it.
    static let acceptanceLift = 0.6

    /// The factor an always-refused candidate settles at until refusal retires it.
    static let acceptanceFloor = 1 - acceptanceLift

    /// How many refusals, for each acceptance plus one, retire a line until the person types it again by hand.
    static let retiringRefusals = 3

    /// What the environment is worth on its own, being true but not necessarily wanted.
    static let environmentWeight = 1.0

    /// The score of one candidate at a moment in time.
    public static func score(_ candidate: Candidate, now: Date) -> Double {
        guard let evidence = candidate.evidence else { return environmentWeight / distancePenalty(candidate) }
        guard !isRetiredByRefusal(evidence) else { return 0 }
        let uses = effectiveCount(evidence)
        let learned = uses > 0 ? log(1 + uses) * decay(evidence.lastUsed, now: now) * acceptance(evidence) : 0
        let confirmed = candidate.isConfirmedByEnvironment ? environmentWeight : 0
        return (learned + confirmed) / distancePenalty(candidate)
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

    /// Whether the person has typed past the line so often, against so few acceptances, that it is no longer offered.
    static func isRetiredByRefusal(_ evidence: Entry) -> Bool {
        evidence.rejected >= retiringRefusals * (evidence.accepted + 1)
    }

    /// How offers affect the score: positive lift follows typed evidence; refusal lowers it by its full share.
    static func acceptance(_ evidence: Entry) -> Double {
        let offered = evidence.accepted + evidence.rejected
        guard offered > 0 else { return 1 }
        let balance = Double(evidence.accepted - evidence.rejected) / Double(offered)
        let typed = max(evidence.count - evidence.selfSourced, 0)
        let typedShare = evidence.count > 0 ? Double(typed) / Double(evidence.count) : 0
        let lift = balance > 0 ? acceptanceLift * typedShare : acceptanceLift
        return 1 + lift * balance
    }

    /// How much a fuzzy match is worth against an exact one, since a typo means less certainty.
    static func distancePenalty(_ candidate: Candidate) -> Double {
        Double(1 + candidate.editDistance * 2)
    }
}
