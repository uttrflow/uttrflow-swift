public import Foundation
import OSLog
private import Synchronization
private import UttrflowCore

/// Runs the gates in order, remembers what they decided, and never makes a keystroke wait.
public actor Verifier {
    private static let log = Logger(subsystem: "com.uttrflow.Uttrflow", category: "predict")
    private static let supersessionLimit = 32
    /// What this machine says it has, which is the gate nothing below may overrule.
    private let index: EnvironmentIndex
    /// The model that judges a candidate's likelihood, absent where there is none.
    private let scoring: (any CandidateScoring)?
    /// The store told when a candidate is wrong for good, absent where nothing is listening.
    private let supersession: (any SupersessionRecording)?
    /// How long the model has to judge one keystroke's candidates, held so a test need not wait it out.
    private let budgetInMilliseconds: Int
    /// Starts one budget on the clock supplied at initialization.
    private let startBudget: @Sendable (Duration) -> Budget
    /// The verdicts already reached, so most keystrokes cost nothing at all.
    private var cache = VerdictCache()
    /// Invalidates verdicts still being computed when a forget action arrives.
    private var forgetGeneration: UInt64 = 0
    /// Candidate lines whose durable refusal has not yet landed.
    private var pendingSupersessions: [PendingSupersession] = []
    private var nextSupersessionID: UInt64 = 0
    private var isRetryingSupersessions = false
    private var isForgetting = false
    private var activeSupersessionOperations = 0
    private var supersessionDrainWaiters: [CheckedContinuation<Void, Never>] = []
    private var forgetWaiters: [CheckedContinuation<Void, Never>] = []
    /// Candidate lines kept out of this session while their refusal write is pending.
    private var refusedThisSession: Set<RefusedCandidate> = []
    /// What a terminal line has to name on disk before it is shown, asked by stat and never by running a program.
    private let lines: TerminalLineCheck

    /// A verifier over one machine, with a model and a store only where there are any.
    public init<C: Clock<Duration>>(
        index: EnvironmentIndex, scoring: (any CandidateScoring)? = nil,
        supersession: (any SupersessionRecording)? = nil,
        budgetInMilliseconds: Int = Verification.budgetInMilliseconds,
        clock: C = ContinuousClock(),
        files: any FileSystemProbing = CachedFileSystem(SystemFileSystem())
    ) {
        self.lines = TerminalLineCheck(files: files)
        self.index = index
        self.scoring = scoring
        self.supersession = supersession
        self.budgetInMilliseconds = budgetInMilliseconds
        self.startBudget = { Budget.starting($0, on: clock) }
    }

    /// Every candidate the gates allow, in the form they allow it, the wrong ones dropped.
    public func verified(
        _ candidates: [Candidate], in surface: Surface, typed: String, now: Date
    ) async -> [Candidate] {
        let generation = forgetGeneration
        await retryPendingSupersessions()
        guard generation == forgetGeneration else { return [] }
        let deadline = deadline()
        var kept: [Candidate] = []
        for candidate in candidates {
            // A keystroke that cancelled this turn's task makes every candidate after this one moot.
            guard !Task.isCancelled else { break }
            guard !refusedThisSession.contains(RefusedCandidate(text: candidate.text, surface: surface))
            else { continue }
            let allowed = await allowed(candidate, in: surface, typed: typed, now: now, before: deadline)
            guard generation == forgetGeneration else { return [] }
            guard let allowed else { continue }
            if let same = kept.firstIndex(where: { $0.text == allowed.text }) {
                kept[same] = Self.combine(kept[same], allowed)
            } else {
                kept.append(allowed)
            }
        }
        return kept
    }

    /// A converged text sums its evidence and keeps the nearest source, favoring the first on a tie.
    private static func combine(_ first: Candidate, _ second: Candidate) -> Candidate {
        let nearest = first.editDistance <= second.editDistance ? first : second
        let evidence: Entry?
        if let firstEvidence = first.evidence, let secondEvidence = second.evidence {
            evidence = Entry(
                text: first.text, count: firstEvidence.count + secondEvidence.count,
                accepted: firstEvidence.accepted + secondEvidence.accepted,
                rejected: firstEvidence.rejected + secondEvidence.rejected,
                selfSourced: firstEvidence.selfSourced + secondEvidence.selfSourced,
                lastUsed: max(firstEvidence.lastUsed, secondEvidence.lastUsed))
        } else {
            evidence = first.evidence ?? second.evidence
        }
        return Candidate(
            text: first.text, source: nearest.source, evidence: evidence,
            editDistance: nearest.editDistance, isIrreversible: nearest.isIrreversible)
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
        before deadline: Budget
    ) async -> Verdict {
        let generation = forgetGeneration
        let key = VerdictCache.Key(
            candidate: candidate.text, context: Self.context(of: surface, typed: typed))
        if let remembered = cache.verdict(for: key) { return remembered }
        guard let token = CompletionToken(candidate.text) else { return .plausible }

        // Each lookup asks about its own word among its own kinds, so a path's name is not sought among whole paths.
        var judged: (word: String, prefix: String, known: Set<String>, caseSensitive: Bool)?
        var complete = true
        for lookup in Verification.attestation(for: token)?.lookups ?? [] {
            guard
                let (known, lookupComplete) = await knownAndComplete(
                    of: lookup.kinds, in: surface, now: now)
            else {
                complete = false
                continue
            }
            complete = complete && lookupComplete
            let caseSensitive = lookup.kinds.contains(where: Self.requiresCaseSensitiveMatch)
            // Each kind attests under its own case rule, so a branch lookup cannot make a file name case-sensitive.
            guard !(await attests(lookup, in: surface, now: now)) else {
                if generation == forgetGeneration { cache.remember(.attested, for: key) }
                return .attested
            }
            if judged == nil { judged = (lookup.word, lookup.prefix, known, caseSensitive) }
        }

        let plausibility = await self.plausibility(
            of: candidate.text, following: typed, before: deadline)
        guard plausibility != .overBudget else { return .rejected }

        // Only a machine that answered can condemn a line for good; the model alone refuses it this time only.
        let verdict = await reported(
            Verification.verdict(
                word: judged?.word ?? token.token, known: judged?.known ?? [],
                modelObjects: Verification.objects(to: plausibility),
                caseSensitive: judged?.caseSensitive ?? false),
            on: candidate.text, leading: token.leading + (judged?.prefix ?? ""), in: surface,
            // A listing still unanswered may yet hold the word, so the verdict stands this time only and is not cached.
            forGood: complete && judged != nil && Verification.isClosedVocabulary(for: token),
            generation: generation)
        if complete, generation == forgetGeneration { cache.remember(verdict, for: key) }
        return verdict
    }

    /// The verdict in the whole line's terms, told to the store whenever it condemns the candidate for good.
    private func reported(
        _ verdict: Verdict, on text: String, leading: String, in surface: Surface, forGood: Bool,
        generation: UInt64
    ) async -> Verdict {
        switch verdict {
        case .corrected(let word):
            let corrected = leading + word
            // A file or branch the machine does not know today may exist tomorrow, so only a closed vocabulary supersedes.
            if forGood, generation == forgetGeneration {
                await record(
                    .supersede(text, corrected), candidate: text, in: surface, generation: generation)
            }
            return .corrected(corrected)
        case .rejected:
            if forGood, generation == forgetGeneration {
                await record(.reject(text), candidate: text, in: surface, generation: generation)
            }
            return .rejected
        case .attested, .plausible:
            return verdict
        }
    }

    /// Writes a final refusal and holds it for retry when the store fails.
    private func record(
        _ write: SupersessionWrite, candidate: String, in surface: Surface, generation: UInt64
    ) async {
        guard let supersession else { return }
        await beginSupersessionOperation()
        defer { endSupersessionOperation() }
        guard generation == forgetGeneration else { return }
        do {
            try await apply(write, using: supersession, in: surface)
        } catch {
            pendingSupersessions.append(
                PendingSupersession(
                    id: claimSupersessionID(), write: write, surface: surface))
            if pendingSupersessions.count > Self.supersessionLimit { pendingSupersessions.removeFirst() }
            refusedThisSession.insert(RefusedCandidate(text: candidate, surface: surface))
            Self.log.error(
                "A refused suggestion's corpus write failed and is held for retry: \(Self.failure(error), privacy: .public)"
            )
        }
    }

    /// Retries held refusals in order and leaves them suppressed at the first repeated failure.
    private func retryPendingSupersessions() async {
        guard let supersession, !isRetryingSupersessions else { return }
        await beginSupersessionOperation()
        guard !isRetryingSupersessions else {
            endSupersessionOperation()
            return
        }
        isRetryingSupersessions = true
        defer {
            isRetryingSupersessions = false
            endSupersessionOperation()
        }
        while let pending = pendingSupersessions.first {
            do {
                try await apply(pending.write, using: supersession, in: pending.surface)
                if pendingSupersessions.first?.id == pending.id { pendingSupersessions.removeFirst() }
                let candidate = Self.candidate(of: pending.write)
                if !pendingSupersessions.contains(where: {
                    $0.surface == pending.surface && Self.candidate(of: $0.write) == candidate
                }) {
                    refusedThisSession.remove(RefusedCandidate(text: candidate, surface: pending.surface))
                }
            } catch {
                Self.log.error(
                    "A refused suggestion's corpus retry failed: \(Self.failure(error), privacy: .public)"
                )
                return
            }
        }
    }

    /// Gives each held write an identity so an in-flight retry survives a forget or queue trim.
    private func claimSupersessionID() -> UInt64 {
        defer { nextSupersessionID &+= 1 }
        return nextSupersessionID
    }

    /// Starts a corpus operation after any active forget has finished.
    private func beginSupersessionOperation() async {
        while isForgetting {
            await withCheckedContinuation { forgetWaiters.append($0) }
        }
        activeSupersessionOperations += 1
    }

    /// Lets a waiting forget proceed after every active write and queue update completes.
    private func endSupersessionOperation() {
        activeSupersessionOperations -= 1
        guard activeSupersessionOperations == 0 else { return }
        let waiters = supersessionDrainWaiters
        supersessionDrainWaiters = []
        waiters.forEach { $0.resume() }
    }

    /// Whether a forget is waiting for an active write, exposed to deterministic regression coverage.
    var isWaitingToForgetSupersessionWrites: Bool {
        isForgetting && activeSupersessionOperations > 0
    }

    /// Applies one pending supersession or rejection.
    private func apply(
        _ write: SupersessionWrite, using store: any SupersessionRecording, in surface: Surface
    ) async throws {
        switch write {
        case .supersede(let text, let replacement):
            try await store.recordSupersession(of: text, by: replacement, in: surface)
        case .reject(let text):
            try await store.recordRejection(of: text, in: surface)
        }
    }

    /// The candidate whose refusal a store operation makes durable.
    private static func candidate(of write: SupersessionWrite) -> String {
        switch write {
        case .supersede(let text, _), .reject(let text): text
        }
    }

    /// Names an error type and case without exposing a text payload.
    private static func failure(_ error: any Error) -> String {
        ErrorLog.failure(error)
    }

    /// Forgets verifier state and runs the corpus clear before new persistence may begin.
    public func forgetEverything(then clearCorpus: @Sendable () async throws -> Void) async throws {
        while isForgetting {
            await withCheckedContinuation { forgetWaiters.append($0) }
        }
        isForgetting = true
        defer {
            isForgetting = false
            let waiters = forgetWaiters
            forgetWaiters = []
            waiters.forEach { $0.resume() }
        }
        if activeSupersessionOperations > 0 {
            await withCheckedContinuation { supersessionDrainWaiters.append($0) }
        }
        forgetGeneration &+= 1
        cache.forgetEverything()
        pendingSupersessions = []
        refusedThisSession = []
        await scoring?.forgetEverything()
        try await clearCorpus()
    }

    /// Forgets every verdict when no corpus clear is needed.
    public func forgetEverything() async {
        try? await forgetEverything(then: {})
    }

    /// How many verdicts are remembered, which is what says a keystroke skipped the gates.
    public var rememberedCount: Int { cache.count }

    /// One candidate as the gates leave it, absent when they refuse it.
    private func allowed(
        _ candidate: Candidate, in surface: Surface, typed: String, now: Date,
        before deadline: Budget
    ) async -> Candidate? {
        guard !candidate.isIrreversible, await admits(candidate.text, in: surface, now: now) else {
            return nil
        }
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

    /// What the next word may be, from the machine: anything, one of the values here that begin the way it does, or nothing.
    public func options(for typed: String, in surface: Surface, now: Date) async -> ArgumentOptions {
        guard EnvironmentSource.workingDirectory(of: surface) != nil else { return .open }
        let token = CompletionToken(typed) ?? CompletionToken(leading: typed, token: "")
        guard let choices = Verification.choices(for: token) else { return .open }
        var offered: [String] = []
        var answered = false
        var everyLookupComplete = true
        for lookup in choices.lookups {
            guard let (known, complete) = await knownAndComplete(of: lookup.kinds, in: surface, now: now)
            else { continue }
            answered = true
            if !complete { everyLookupComplete = false }
            // A word already whole and known may be continued freely; the model is held only while the word is open.
            if await attests(lookup, in: surface, now: now) { return .open }
            var values = known.filter { Self.begins($0, as: lookup.word) }.map { lookup.prefix + $0 }
            // A runner's `run` takes a script, so where the scripts are listed each `run script` is offered whole and bare `run` is not.
            if case .subcommand(let program)? = lookup.kinds.first,
                CommandGrammar.scriptRunners.contains(program),
                values.contains("run"),
                let scripts = await self.known(
                    of: [.subcommand(of: "\(program) run")], in: surface, now: now),
                !scripts.isEmpty
            {
                values.removeAll { $0 == "run" }
                values += scripts.sorted().map { "run \($0)" }
            }
            offered += values
        }
        guard answered else { return .open }
        var seen: Set<String> = []
        let distinct = offered.filter { seen.insert($0).inserted }.sorted { ($0.count, $0) < ($1.count, $1) }
        // Nothing offered while a relevant kind is still unanswered is not proof there is nothing: stay open rather than say none.
        guard !distinct.isEmpty || everyLookupComplete else { return .open }
        return distinct.isEmpty ? .none : .among(Array(distinct.prefix(Verification.mostChoices)))
    }

    /// Whether a value continues the word: it begins as the word does, and a word not yet begun is not offered the hidden names.
    private static func begins(_ value: String, as word: String) -> Bool {
        word.isEmpty ? !value.hasPrefix(".") : value.hasPrefix(word) && value != word
    }

    /// The model's whole lines whose every word past the typing the machine can stand behind; a line naming what this machine does not have is dropped.
    public func standing(
        _ completions: [String], after typed: String, in surface: Surface, now: Date
    ) async -> [String] {
        var standing: [String] = []
        for completion in completions {
            if await stands(completion, after: typed, in: surface, now: now) { standing.append(completion) }
        }
        return standing
    }

    /// Each generated line's mean log-probability per token from the pass that wrote it, absent where no pass measured it or no model is loaded.
    public func scoreCompletions(_ completions: [String]) async -> [String: Double] {
        guard let scoring else { return [:] }
        var scores: [String: Double] = [:]
        for completion in completions {
            if let value = await scoring.confidence(ofGenerated: completion) {
                scores[completion] = value
            }
        }
        return scores
    }

    /// Whether every word the model added is one the machine names, or one no listing could deny; a listing not yet answered vouches for nothing.
    private func stands(
        _ completion: String, after typed: String, in surface: Surface, now: Date
    ) async -> Bool {
        guard await admits(completion, in: surface, now: now) else { return false }
        // A field that is not a directory has no listings, so nothing it holds is looked up.
        guard EnvironmentSource.workingDirectory(of: surface) != nil else { return true }
        for token in Verification.words(of: completion, addedAfter: typed) {
            guard let attestation = Verification.attestation(for: token) else { continue }
            var vouched = false
            for lookup in attestation.lookups where !vouched {
                let answer = await knownAndComplete(of: lookup.kinds, in: surface, now: now)
                if await attests(lookup, in: surface, now: now) {
                    vouched = true
                } else if answer?.complete != true {
                    // A listing still out is no proof either way, so only the disk itself may vouch meanwhile.
                    vouched = lines.confirms(lookup, in: surface.scope)
                }
            }
            guard vouched else { return false }
        }
        return true
    }

    /// Whether a whole line may be shown at all: never when it destroys, and in a terminal only when everything it names exists from there. See `Docs/predict-terminal-paths.md`.
    private func admits(_ line: String, in surface: Surface, now: Date) async -> Bool {
        let terminal = TerminalApplications.contains(surface.bundleIdentifier)
        guard !DestructiveCommand.matches(line, failClosedOnUnresolved: terminal) else { return false }
        guard terminal else { return true }
        // A remote session's files are on another machine, so nothing this disk could say stands behind the line.
        guard !RemoteSession.names(surface.scope) else { return false }
        // Aliases are read from the shell's configuration as text; until they are, an alias is not a command.
        let aliases = await index.values(of: .alias, in: surface.scope ?? "~", now: now) ?? []
        return lines.allows(line, in: surface.scope, aliases: Set(aliases))
    }

    /// Everything the machine vouches for among these kinds here, absent when none has answered yet or the field is not a directory.
    private func known(
        of kinds: [EnvironmentKind], in surface: Surface, now: Date
    ) async -> Set<String>? {
        await knownAndComplete(of: kinds, in: surface, now: now)?.known
    }

    /// Git names are case-sensitive even on a case-insensitive filesystem.
    private func attests(_ lookup: Verification.Lookup, in surface: Surface, now: Date) async -> Bool {
        for kind in lookup.kinds {
            guard let known = await known(of: [kind], in: surface, now: now) else { continue }
            if Verification.attests(
                lookup.word, known, caseSensitive: Self.requiresCaseSensitiveMatch(kind))
            {
                return true
            }
        }
        return false
    }

    private static func requiresCaseSensitiveMatch(_ kind: EnvironmentKind) -> Bool {
        switch kind {
        case .branch, .gitAlias: true
        case .subcommand(of: "git"): true
        case .entries, .directories, .executable, .alias, .subcommand: false
        }
    }

    /// The same union, plus whether every kind asked has actually answered, so a still-refreshing kind is never read as a "no".
    private func knownAndComplete(
        of kinds: [EnvironmentKind], in surface: Surface, now: Date
    ) async -> (known: Set<String>, complete: Bool)? {
        guard let directory = EnvironmentSource.workingDirectory(of: surface) else { return nil }
        var known: Set<String>?
        var complete = true
        for kind in kinds {
            guard let values = await index.values(of: kind, in: directory, now: now) else {
                complete = false
                continue
            }
            known = (known ?? []).union(values)
        }
        guard let known else { return nil }
        return (known, complete)
    }

    /// What the model says, silent when it is not up and over budget when it did not answer in time.
    private func plausibility(
        of candidate: String, following context: String, before deadline: Budget
    ) async -> Plausibility {
        guard let scoring, await scoring.isReady else { return .silent }
        guard !deadline.hasRunOut() else { return .overBudget }
        return await Self.raced(candidate, following: context, by: scoring, before: deadline)
    }

    /// The model against the clock: the scorer is signalled, not awaited, so a noncooperative one cannot hold up the verdict.
    private static func raced(
        _ candidate: String, following context: String, by scoring: any CandidateScoring,
        before deadline: Budget
    ) async -> Plausibility {
        let race = PlausibilityRace()
        var scorer: Task<Void, Never>?
        await withCheckedContinuation { continuation in
            // Armed before either racer exists, so neither can arrive at an empty race.
            race.arm(continuation)
            scorer = Task {
                guard let score = await scoring.logLikelihood(of: candidate, following: context) else {
                    return race.finish(.silent)
                }
                race.finish(.scored(score))
            }
            Task {
                await deadline.runsOut()
                race.finish(.overBudget)
            }
        }
        // Not awaited: whatever GPU work is already in flight keeps the model alive on its own past this return.
        scorer?.cancel()
        return race.result()
    }

    /// When this keystroke's whole set of candidates has to have been judged by.
    private func deadline() -> Budget {
        startBudget(.milliseconds(budgetInMilliseconds))
    }

    /// What a verdict is remembered against, which is this field and what has been typed into it.
    static func context(of surface: Surface, typed: String) -> String {
        [
            surface.bundleIdentifier, surface.role, surface.locator ?? "", surface.scope ?? "", typed,
        ].joined(separator: "\u{0}")
    }
}

private enum SupersessionWrite: Sendable {
    case supersede(String, String)
    case reject(String)
}

private struct PendingSupersession: Sendable {
    let id: UInt64
    let write: SupersessionWrite
    let surface: Surface
}

private struct RefusedCandidate: Hashable, Sendable {
    let text: String
    let surface: Surface
}

/// One keystroke's budget on the verifier's clock: whether it has run out, and a wait until it does.
struct Budget: Sendable {
    let hasRunOut: @Sendable () -> Bool
    let runsOut: @Sendable () async -> Void

    /// A budget of `duration` from now, on `clock`.
    static func starting<C: Clock<Duration>>(_ duration: Duration, on clock: C) -> Budget {
        let end = clock.now.advanced(by: duration)
        return Budget(
            hasRunOut: { clock.now >= end },
            runsOut: { try? await clock.sleep(until: end, tolerance: nil) })
    }
}

/// Whichever of the model and the deadline answers a keystroke's plausibility first.
private final class PlausibilityRace: Sendable {
    /// The waiting caller and the first answer, kept together under one lock.
    private struct State {
        var waiting: CheckedContinuation<Void, Never>?
        var outcome: Plausibility?
    }

    private let state = Mutex(State())

    /// Parks the caller until the first answer.
    func arm(_ continuation: CheckedContinuation<Void, Never>) {
        state.withLock { $0.waiting = continuation }
    }

    /// Records an answer, and wakes the caller for the first one only.
    func finish(_ outcome: Plausibility) {
        let waiting = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard state.outcome == nil else { return nil }
            state.outcome = outcome
            defer { state.waiting = nil }
            return state.waiting
        }
        waiting?.resume()
    }

    /// The winner's answer, silent if somehow reached before either racer finished.
    func result() -> Plausibility {
        state.withLock { $0.outcome } ?? .silent
    }
}
