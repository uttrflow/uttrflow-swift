import ArgumentParser
import Foundation
import UttrflowLocalModel
import UttrflowPredict

/// Asks the local model to complete a partial line, or holds it to the whole fixture set, outside the app.
struct Complete: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "complete",
        abstract: "Show the completions the local model generates, or measure it over the fixture set."
    )

    @Argument(help: "The partial text to complete. Omitted when --fixtures is given.")
    var typed: String?

    @Option(name: .long, help: "The application the caret is in, e.g. Terminal, DBeaver, Safari.")
    var application = "Terminal"

    @Option(name: .long, help: "The page or directory the field belongs to, if any.")
    var document: String?

    @Option(name: .long, help: "Which model to run: gemma3, gemma3Small, apple, or a repository name.")
    var model = "gemma3"

    @Flag(name: .long, help: "Run every fixture and report hit rate, register conformance and latency.")
    var fixtures = false

    @Flag(name: .long, help: "Run the seeded history/environment/model arbitration fixtures.")
    var sources = false

    @Option(name: .long, help: "Only fixtures whose name starts with this, e.g. chat/ or terminal/.")
    var only: String?

    @Option(name: .long, help: "Run only the first N fixtures left after --only.")
    var limit: Int?

    @Option(name: .long, help: "Write every fixture's result and the summary as JSON to this path.")
    var json: String?

    @Flag(
        name: .long, help: "Record how each pass ended and every word the model wrote, so a miss can be read."
    )
    var raw = false

    @Flag(
        name: .long,
        help:
            "Also time the scorer's second pass over each first line and record its score, beside the pass's own."
    )
    var judge = false

    @Option(name: .long, help: "Run only the fixtures that missed in this earlier run's JSON.")
    var failedIn: String?

    @Flag(
        name: .long,
        help:
            "Where the first pass leaves nothing, spend a second, wider pass and record what it rescues and what it costs."
    )
    var secondOpinion = false

    func validate() throws {
        if let limit, limit < 1 {
            throw ValidationError("--limit must be at least 1.")
        }
    }

    func run() async throws {
        let generator: any CandidateGenerating
        if model == "apple" {
            // Apple's model is bundled with the system and loads itself; there is nothing to download or warm.
            let apple = AppleCandidateGenerator()
            guard await apple.isReady else {
                print("Apple's on-device model is not available: turn on Apple Intelligence and try again")
                return
            }
            generator = apple
        } else {
            guard let chosen = Self.model(named: model) else {
                print("no such model: \(model)")
                return
            }
            let scorer = MLXCandidateScorer(model: chosen)
            try await scorer.prepare { fraction in
                FileHandle.standardError.write(Data("\r  loading \(Int(fraction * 100))% ".utf8))
            }
            FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
            generator = scorer
        }
        if fixtures || sources {
            try await measure(with: generator)
        } else {
            await complete(typed ?? "", with: generator)
        }
    }

    /// One line, printed with everything the model offered for it.
    private func complete(_ typed: String, with scorer: any CandidateGenerating) async {
        let situation = GenerationSituation(application: application, document: document)
        print("completions for \(typed.debugDescription) in \(application):")
        let completions: [String]
        do {
            completions = try await scorer.completions(for: typed, in: situation)
        } catch {
            print("  failed: \(error)")
            return
        }
        guard !completions.isEmpty else {
            print("  (none)")
            return
        }
        for completion in completions { print("  \(completion)") }
    }

    /// Every chosen fixture in turn, each timed, then the rates that decide whether a phase held and the failures.
    private func measure(with scorer: any CandidateGenerating) async throws {
        var chosen = (sources ? SourceFixtures.all : Fixture.all).filter {
            only.map($0.name.hasPrefix) ?? true
        }
        if let failedIn {
            guard let missed = Self.misses(recordedIn: failedIn) else {
                print("could not read the earlier run at \(failedIn)")
                return
            }
            chosen = chosen.filter { missed.contains($0.name) }
        }
        if let limit { chosen = Array(chosen.prefix(limit)) }
        // One pass first, so the Metal kernels are compiled before anything is timed.
        if let first = chosen.first {
            _ = try? await scorer.completions(for: first.typed, in: first.situation)
        }
        var results: [FixtureResult] = []
        for fixture in chosen {
            let result = await Self.runFixture(
                fixture, scorer: scorer, raw: raw, sources: sources,
                secondOpinion: secondOpinion, judge: judge)
            results.append(result)
            print(result.row)
        }
        let report = FixtureReport(results: results)
        report.printSummary()
        report.printFloors()
        report.printFailures()
        // An errored pass fails the run so the gate that protects the correct-or-not-shown promise is not passed by a broken model.
        if report.summary.errors > 0 {
            FileHandle.standardError.write(
                Data("\n\(report.summary.errors) error(s); run exits non-zero.\n".utf8))
            throw ExitCode.failure
        }
        guard let json else { return }
        do {
            try report.write(to: json)
            print("\nwritten to \(json)")
        } catch {
            print("\ncould not write \(json): \(error)")
        }
    }

    /// Run the measurement loop over the given fixtures and return the per-fixture results alongside the count of errored fixtures; the unit a test exercises when it runs the bake-off with a generator that throws.
    internal static func measure(
        fixtures: [Fixture], generator: any CandidateGenerating, sources: Bool
    ) async -> (results: [FixtureResult], errors: Int) {
        // One pass first, so the Metal kernels are compiled before anything is timed.
        if let first = fixtures.first {
            _ = try? await generator.completions(for: first.typed, in: first.situation)
        }
        var results: [FixtureResult] = []
        for fixture in fixtures {
            let result = await Self.runFixture(
                fixture, scorer: generator, raw: false, sources: sources,
                secondOpinion: false, judge: false)
            results.append(result)
        }
        let errors = results.filter { $0.error != nil }.count
        return (results, errors)
    }

    /// Run the model pass for one fixture and produce the result row; the smallest unit `measure` repeats, so a throwing generator's failure is observable from one fixture alone.
    internal static func runFixture(
        _ fixture: Fixture, scorer: any CandidateGenerating, raw: Bool, sources: Bool,
        secondOpinion: Bool, judge: Bool
    ) async -> FixtureResult {
        let started = ContinuousClock.now
        // A pass that fails is a miss whose answer names the error, so the report tells it from a model with nothing to say.
        var completions: [String] = []
        var failure: String?
        var words: String?
        var lengthStopped = false
        var alternativesLengthStopped = false
        var invented = false
        var rescued = false
        var secondMs: Int?
        var confidence: Double?
        var judgeScore: Double?
        var judgeMs: Int?
        var shownSource: String?
        // A fixture on a machine is asked what the word may be first, and its answer is sieved after, as the app does both.
        let grounding = await Grounding(for: fixture)
        var situation = fixture.situation
        var denied = false
        switch await grounding?.options(for: fixture.typed) {
        case .none?: denied = true
        case .among(let values)?: situation = situation.choosing(values)
        case .open?, nil: break
        }
        do {
            if sources {
                let arbitration = await Self.arbitrate(
                    fixture, generator: scorer, scoring: scorer as? any CandidateScoring)
                completions = arbitration.lines
                shownSource = arbitration.source
                words = "[production arbitration] \(completions.joined(separator: " | "))"
                if let arbitrationError = arbitration.error { failure = arbitrationError }
            } else {
                if denied {
                    words = "[not on this machine]"
                } else if raw, let scorer = scorer as? any PassShowing {
                    let pass = try await scorer.pass(for: fixture.typed, in: situation)
                    completions = pass?.completions ?? []
                    lengthStopped = pass?.stopReason == "length"
                    words = pass.map { "[\($0.stopReason)] \($0.text)" } ?? "[not asked]"
                } else {
                    completions = try await scorer.completions(for: fixture.typed, in: situation)
                }
                if let grounding {
                    let standing = await grounding.standing(completions, after: fixture.typed)
                    invented = standing.count < completions.count
                    completions = standing
                }
                // The second opinion is the wider pass the person would never wait for, measured here to see whether it earns its place.
                if secondOpinion, completions.isEmpty, !denied {
                    let again = ContinuousClock.now
                    var others: [String]
                    if raw, let passShowing = scorer as? any AlternativePassShowing {
                        let pass = try await passShowing.alternativesPass(
                            for: fixture.typed, in: situation, excluding: "")
                        others = pass?.completions ?? []
                        alternativesLengthStopped = pass?.stopReason == "length"
                    } else {
                        others = try await scorer.alternatives(
                            for: fixture.typed, in: situation, excluding: "")
                    }
                    if let grounding { others = await grounding.standing(others, after: fixture.typed) }
                    secondMs = Int((ContinuousClock.now - again) / .milliseconds(1))
                    rescued = fixture.hits(others)
                    completions = others
                }
            }
        } catch {
            failure = "error: \(error)"
        }
        let scoring = scorer as? any CandidateScoring
        var scores: [String: Double] = [:]
        if let scoring {
            for completion in completions {
                if let score = await scoring.confidence(ofGenerated: completion) {
                    scores[completion] = score
                }
            }
        }
        confidence = completions.first.flatMap { scores[$0] }
        let decision = SuggestionSession.generatedDecision(
            completions, typed: fixture.typed, scores: scores)
        let drawn: [String]
        switch decision {
        case .noCandidate, .unsure:
            drawn = []
        case .certain(let line):
            drawn = [line]
        case .choice(let leader, let others):
            drawn = [leader] + others
        }
        let held = !completions.isEmpty && decision == .unsure
        let elapsed = Int((ContinuousClock.now - started) / .milliseconds(1))
        // The second pass the gate no longer spends is timed apart from the turn, to show what it would cost.
        if judge, let scoring, let first = completions.first {
            let judging = ContinuousClock.now
            judgeScore = await scoring.logLikelihood(of: first, following: fixture.typed)
            judgeMs = Int((ContinuousClock.now - judging) / .milliseconds(1))
        }
        if !sources { shownSource = nil }
        return FixtureResult(
            name: fixture.name, category: fixture.category, typed: fixture.typed,
            hit: fixture.hits(drawn), judged: fixture.isJudged,
            conforms: fixture.conforms(drawn), elapsedMs: elapsed,
            first: failure ?? completions.first, drawn: drawn, source: shownSource,
            raw: words, invented: invented, rescued: rescued,
            secondOpinionMs: secondMs, lengthStopped: lengthStopped,
            alternativesLengthStopped: alternativesLengthStopped,
            error: failure,
            gate: FixtureResult.Gate(
                confidence: confidence, held: held, hitIfDrawn: fixture.hits(completions),
                judgeScore: judgeScore, judgeMs: judgeMs))
    }

    /// Runs the shared coordinator selection, session ranking, verifier, and model fallback for one seeded fixture.
    private static func arbitrate(
        _ fixture: Fixture, generator: any CandidateGenerating, scoring: (any CandidateScoring)?
    ) async -> (lines: [String], source: String?, error: String?) {
        let directory = fixture.situation.document ?? "/Users/me/project"
        let surface = Surface(
            bundleIdentifier: fixture.situation.application == "Terminal"
                ? "com.apple.Terminal" : "com.apple.TextEdit",
            role: fixture.situation.application == "Terminal" ? "AXTextArea" : "AXTextView",
            scope: fixture.situation.application == "Terminal" ? directory : nil)
        let store = FixturePredictionStore(candidates: fixture.seededCandidates)
        let index = EnvironmentIndex(reader: FixtureArbitrationMachine(answers: fixture.machine ?? [:]))
        let environment = EnvironmentSource(index: index)
        // The first ask starts the reads the source will want; the second finds them answered.
        _ = await environment.candidates(for: surface, matching: fixture.typed, now: Date())
        await index.settle()
        let now = Date()
        let candidates = await CandidateSources.candidates(
            from: store, environment: environment, for: surface, matching: fixture.typed, now: now)
        let verifier = Verifier(index: index, scoring: scoring)
        var session = SuggestionSession()
        let query: SuggestionQuery
        switch session.turn(in: surface, at: PredictionContext(typed: fixture.typed)).step {
        case .query(let value): query = value
        case .settled(let update): return (update.suggestion.accepting.map { [$0] } ?? [], nil, nil)
        }
        guard
            let resolution = session.resolve(
                candidates, for: query, now: now, elapsedMilliseconds: 0)
        else { return ([], nil, nil) }
        switch resolution {
        case .settled(let update):
            if let line = update.suggestion.accepting {
                return (Self.drawnLines(update.suggestion), sourceName(of: candidates, line: line), nil)
            }
        case .verify(let request):
            let verified = await verifier.verified(
                request.candidates, in: request.surface, typed: request.typed, now: now)
            if let update = session.resolve(
                verified, for: request, now: now, elapsedMilliseconds: 0),
                let line = update.suggestion.accepting
            {
                return (Self.drawnLines(update.suggestion), sourceName(of: verified, line: line), nil)
            }
        }
        guard
            ModelPass.shouldAsk(
                after: .init(suggestion: .silent, armed: [], silence: .nothingOffered),
                hasGenerator: true, isReady: await generator.isReady)
        else { return ([], nil, nil) }
        let options = await verifier.options(for: fixture.typed, in: surface, now: now)
        let situation: GenerationSituation
        switch options {
        case .none: return ([], nil, nil)
        case .among(let values): situation = fixture.situation.choosing(values)
        case .open: situation = fixture.situation
        }
        // The model's pass is recorded rather than swallowed, so a generator that throws fails the case the same way it would in the non-sources path.
        let generated: [String]
        do {
            generated = try await generator.completions(for: fixture.typed, in: situation)
        } catch {
            return ([], nil, "error: \(error)")
        }
        let standing = await verifier.standing(
            generated, after: fixture.typed, in: surface, now: now)
        let scores = await verifier.scoreCompletions(standing)
        guard
            let update = session.resolveGenerated(
                standing, for: query, elapsedMilliseconds: 0, scores: scores),
            update.suggestion.accepting != nil
        else { return ([], nil, nil) }
        return (Self.drawnLines(update.suggestion), "model", nil)
    }

    /// Lists every line visible in a certain suggestion or a choice, led by the accepted line.
    private static func drawnLines(_ suggestion: Suggestion) -> [String] {
        switch suggestion {
        case .certain(let line): [line]
        case .choice(let leader, let others): [leader] + others
        case .silent, .minimised: []
        }
    }

    /// Names the remembered source that survived production ranking.
    private static func sourceName(of candidates: [Candidate], line: String) -> String? {
        candidates.first(where: { $0.text == line }).map { String(describing: $0.source) }
    }

    /// The names of the fixtures an earlier run's JSON records as missed, or nothing when the file cannot be read.
    private static func misses(recordedIn path: String) -> Set<String>? {
        struct Earlier: Decodable {
            struct Result: Decodable {
                let name: String
                let hit: Bool
            }
            let results: [Result]
        }
        guard let data = FileManager.default.contents(atPath: path),
            let earlier = try? JSONDecoder().decode(Earlier.self, from: data)
        else { return nil }
        return Set(earlier.results.filter { !$0.hit }.map(\.name))
    }

    /// The names the app's two Gemma sizes go by, beside every repository name the bake-off knows.
    private static func model(named name: String) -> LocalModel? {
        switch name {
        case "gemma3": .gemma3
        case "gemma3Small": .gemma3Small
        default: LocalModel.named(name)
        }
    }
}

extension String {
    /// The string with spaces in front until it is this wide, so a column of numbers lines up.
    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
