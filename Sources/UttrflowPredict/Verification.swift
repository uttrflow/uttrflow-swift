/// What the gates decided about one candidate, which is the last word on whether it may be shown.
public enum Verdict: Sendable, Equatable {
    /// The machine itself says it exists, so nothing below may interfere with it.
    case attested
    /// Nothing objected, so it stands in the form the corpus offered it.
    case plausible
    /// It is wrong, and this is the form to offer instead.
    case corrected(String)
    /// It is wrong and nothing near it is right, so it is not offered at all.
    case rejected

    /// Whether the machine vouched for it, which is all a verification over budget may still show.
    public var isAttested: Bool { self == .attested }

    /// Whether anything at all may be drawn from it.
    public var allowsOffering: Bool { self != .rejected }
}

/// Scores how likely a candidate is where it stands, which is the one thing frequency cannot say.
public protocol CandidateScoring: Sendable {
    /// Whether the model can answer at once, since a keystroke may never wait on one still loading.
    var isReady: Bool { get async }

    /// The candidate's mean log-likelihood per token in context, in one pass, abandoned when cancelled.
    func logLikelihood(of candidate: String, following context: String) async -> Double?
}

/// Marks a candidate wrong wherever it is remembered, so it stops accruing weight.
public protocol SupersessionRecording: Sendable {
    /// Records that one text is replaced by another, which is what stops it being proposed again.
    func recordSupersession(of text: String, by replacement: String, in surface: Surface) async

    /// Records that one text is wrong with nothing on this machine to put in its place.
    func recordRejection(of text: String, in surface: Surface) async
}

/// What the model managed to say about a candidate inside the budget.
public enum Plausibility: Sendable, Equatable {
    /// It scored the candidate, and this is the score.
    case scored(Double)
    /// It is up but had nothing to say, so the statistical tiers answer alone.
    case silent
    /// The budget ran out, so only what the machine already attested may be shown.
    case overBudget
}

/// Correctness in ordered gates, because frequency says what the user does rather than what is right.
public enum Verification {
    /// How long a verdict has before a candidate stands on the machine's word alone.
    public static let budgetInMilliseconds = 20

    /// How unlikely, per token, a candidate may be before the model's objection counts.
    public static let plausibilityFloor = -4.0

    /// The dearest slip a correction may explain away, which is one plain insertion or deletion.
    public static let correctionCeiling = TypoModel.indelCost

    /// The program whose subcommands and aliases the machine is asked about by name.
    static let gitCommand = "git"

    /// The verdict the gates reach together, from what the machine knows and whether the model objects.
    public static func verdict(word: String, known: Set<String>, modelObjects: Bool) -> Verdict {
        guard !attests(word, known) else { return .attested }
        if let neighbour = nearestNeighbour(of: word, among: known) { return .corrected(neighbour) }
        return modelObjects ? .rejected : .plausible
    }

    /// Whether the machine vouches for a word, ignoring case, so a capitalised first letter still attests.
    public static func attests(_ word: String, _ known: Set<String>) -> Bool {
        let lowered = word.lowercased()
        return known.contains { $0.lowercased() == lowered }
    }

    /// Whether the model finds a candidate too unlikely to stand, false whenever it has no opinion.
    public static func objects(to plausibility: Plausibility) -> Bool {
        guard case .scored(let score) = plausibility else { return false }
        return score < plausibilityFloor
    }

    /// The nearest name the machine knows, when one slip cheap enough explains the difference.
    public static func nearestNeighbour(of word: String, among known: Set<String>) -> String? {
        let typed = Array(word.utf8)
        guard FuzzyMatch.budget(forQueryOfLength: typed.count) > 0 else { return nil }
        let width = FuzzyMatch.maskWidth(forQueryOfLength: typed.count, within: 1)
        let queryMask = FuzzyMatch.mask(typed)

        var best: String?
        var bestScore = -Double.infinity
        let lowered = word.lowercased()
        for candidate in known.sorted() {
            // A difference only of case is not a typo, so it is never corrected or superseded.
            guard candidate.lowercased() != lowered else { continue }
            let bytes = Array(candidate.utf8)
            let mask = FuzzyMatch.mask(bytes.prefix(width))
            guard FuzzyMatch.couldMatch(query: queryMask, candidate: mask, within: 1) else { continue }
            let score = TypoModel.logLikelihood(typed: word, meant: candidate)
            guard score >= -correctionCeiling, score > bestScore else { continue }
            best = candidate
            bestScore = score
        }
        return best
    }

    /// What could vouch for a word, which is decided by where in the line the word sits.
    static func attestingKinds(for token: CompletionToken) -> [EnvironmentKind] {
        guard !token.isFirstWord else { return [.executable, .alias] }
        guard token.precedingWords == 1, token.command == gitCommand else { return [.branch, .file] }
        return [.gitSubcommand, .gitAlias]
    }
}
