// Whether the wrong forms other voices produce for a term predict the wrong form one more voice produces.

/// Leave-one-speaker-out coverage of a term's wrong forms by every other speaker's wrong forms for it.
public struct SyntheticPathCoverage: Sendable, Equatable {
    /// Of one speaker's misheard terms, how many were written in a form another speaker also produced.
    public let covered: Proportion
    /// Distinct wrong forms harvested per term, over terms with at least one; the paths a trie would hold.
    public let pathsPerTerm: Double
    /// Terms every speaker heard right, which would add no path.
    public let termsAlwaysRight: Int

    /// Measures `utterances`, each one term read alone; the reference words joined are the term.
    public init(_ utterances: [HarvestUtterance]) {
        func form(_ words: [String]) -> String { words.joined(separator: " ") }
        var wrong: [String: [String: Set<String>]] = [:]
        var terms = Set<String>()
        for utterance in utterances {
            let term = form(utterance.reference)
            terms.insert(term)
            let heard = form(utterance.recognised)
            if heard != term { wrong[term, default: [:]][heard, default: []].insert(utterance.speaker) }
        }
        var hits = 0
        var total = 0
        for utterance in utterances {
            let term = form(utterance.reference)
            let heard = form(utterance.recognised)
            guard heard != term else { continue }
            total += 1
            if wrong[term]?[heard]?.contains(where: { $0 != utterance.speaker }) == true { hits += 1 }
        }
        covered = Proportion(hits: hits, of: total)
        let counts = wrong.values.map(\.count)
        pathsPerTerm = counts.isEmpty ? 0 : Double(counts.reduce(0, +)) / Double(counts.count)
        termsAlwaysRight = terms.count - wrong.count
    }
}
