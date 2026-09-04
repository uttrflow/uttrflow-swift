public import struct Foundation.Date

/// Runs the gates in order, remembers what they decided, and never makes a keystroke wait.
public actor Verifier {
    private let index: EnvironmentIndex
    private let scoring: (any CandidateScoring)?
    private let supersession: (any SupersessionRecording)?
    /// How long the model has to judge one keystroke's candidates, held so a test need not wait it out.
    private let budgetInMilliseconds: Int
    private var cache = VerdictCache()

    public init(
        index: EnvironmentIndex, scoring: (any CandidateScoring)? = nil,
        supersession: (any SupersessionRecording)? = nil,
        budgetInMilliseconds: Int = Verification.budgetInMilliseconds
    ) {
        self.index = index
        self.scoring = scoring
        self.supersession = supersession
        self.budgetInMilliseconds = budgetInMilliseconds
    }

    /// Every candidate the gates allow, in the form they allow it, the wrong ones dropped.
    public func verified(
        _ candidates: [Candidate], in surface: Surface, typed: String, now: Date
    ) async -> [Candidate] {
        let deadline = deadline()
        var kept: [Candidate] = []
        for candidate in candidates {
            guard
                let allowed = await allowed(
                    candidate, in: surface, typed: typed, now: now, before: deadline)
            else { continue }
            // A corrected typo and the genuine line can land on the same text; the one typed as-is is the real one.
            if let same = kept.firstIndex(where: { $0.text == allowed.text }) {
                if allowed.editDistance < kept[same].editDistance { kept[same] = allowed }
            } else {
                kept.append(allowed)
            }
        }
        return kept
    }

    /// The verdict on one candidate, taken from the cache whenever the gates have already reached it.
    public func verdict(
        for candidate: Candidate, in surface: Surface, typed: String, now: Date
    ) async -> Verdict {
        await verdict(for: candidate, in: surface, typed: typed, now: now, before: deadline())
    }

    /// The same verdict, against a budget one keystroke's whole set of candidates has to share.
    private func verdict(
        for candidate: Candidate, in surface: Surface, typed: String, now: Date,
        before deadline: ContinuousClock.Instant
    ) async -> Verdict {
        let key = VerdictCache.Key(
            candidate: candidate.text, context: Self.context(of: surface, typed: typed))
        if let remembered = cache.verdict(for: key, now: now) { return remembered }
        guard let token = CompletionToken(candidate.text) else { return .plausible }

        let known = await known(for: token, in: surface, now: now)
        guard !Verification.attests(token.token, known) else {
            cache.remember(.attested, for: key, now: now)
            return .attested
        }

        let plausibility = await self.plausibility(
            of: candidate.text, following: typed, before: deadline)
        guard plausibility != .overBudget else { return .rejected }

        let verdict = await reported(
            Verification.verdict(
                word: token.token, known: known,
                modelObjects: Verification.objects(to: plausibility)),
            on: candidate.text, leading: token.leading, in: surface,
            forGood: Verification.isClosedVocabulary(Verification.attestingKinds(for: token)))
        cache.remember(verdict, for: key, now: now)
        return verdict
    }

    /// The verdict in the whole line's terms, told to the store whenever it condemns the candidate for good.
    private func reported(
        _ verdict: Verdict, on text: String, leading: String, in surface: Surface, forGood: Bool
    ) async -> Verdict {
        switch verdict {
        case .corrected(let word):
            let corrected = leading + word
            // A file or branch the machine does not know today may exist tomorrow, so only a closed vocabulary supersedes.
            if forGood { await supersession?.recordSupersession(of: text, by: corrected, in: surface) }
            return .corrected(corrected)
        case .rejected:
            await supersession?.recordRejection(of: text, in: surface)
            return .rejected
        case .attested, .plausible:
            return verdict
        }
    }

    /// Forgets every verdict, which is what leaving a field and the reset in Settings both ask for.
    public func forgetEverything() {
        cache.forgetEverything()
    }

    /// How many verdicts are remembered, which is what says a keystroke skipped the gates.
    public var rememberedCount: Int { cache.count }

    /// One candidate as the gates leave it, absent when they refuse it.
    private func allowed(
        _ candidate: Candidate, in surface: Surface, typed: String, now: Date,
        before deadline: ContinuousClock.Instant
    ) async -> Candidate? {
        switch await verdict(
            for: candidate, in: surface, typed: typed, now: now, before: deadline)
        {
        case .attested, .plausible:
            return candidate
        case .rejected:
            return nil
        case .corrected(let text):
            return Candidate(
                text: text, source: candidate.source, evidence: candidate.evidence,
                editDistance: candidate.editDistance + 1, isIrreversible: candidate.isIrreversible)
        }
    }

    /// Everything the machine vouches for in this position, empty when it has not answered yet.
    private func known(
        for token: CompletionToken, in surface: Surface, now: Date
    ) async -> Set<String> {
        guard let directory = EnvironmentSource.workingDirectory(of: surface) else { return [] }
        var known: Set<String> = []
        for kind in Verification.attestingKinds(for: token) {
            known.formUnion(await index.values(of: kind, in: directory, now: now))
        }
        return known
    }

    /// What the model says, silent when it is not up and over budget when it did not answer in time.
    private func plausibility(
        of candidate: String, following context: String, before deadline: ContinuousClock.Instant
    ) async -> Plausibility {
        guard let scoring, await scoring.isReady else { return .silent }
        guard ContinuousClock.now < deadline else { return .overBudget }
        return await Self.raced(candidate, following: context, by: scoring, before: deadline)
    }

    /// The model against the clock, so a slow answer costs the candidate rather than the keystroke.
    private static func raced(
        _ candidate: String, following context: String, by scoring: any CandidateScoring,
        before deadline: ContinuousClock.Instant
    ) async -> Plausibility {
        await withTaskGroup(of: Plausibility.self, returning: Plausibility.self) { group in
            group.addTask {
                guard let score = await scoring.logLikelihood(of: candidate, following: context) else {
                    return .silent
                }
                return .scored(score)
            }
            group.addTask {
                try? await Task.sleep(until: deadline, clock: .continuous)
                return .overBudget
            }
            let first = await group.next() ?? .overBudget
            group.cancelAll()
            return first
        }
    }

    /// When this keystroke's whole set of candidates has to have been judged by.
    private func deadline() -> ContinuousClock.Instant {
        .now + .milliseconds(budgetInMilliseconds)
    }

    /// What a verdict is remembered against, which is this field and what has been typed into it.
    static func context(of surface: Surface, typed: String) -> String {
        [
            surface.bundleIdentifier, surface.role, surface.locator ?? "", surface.scope ?? "", typed,
        ].joined(separator: "\u{0}")
    }
}
