import ArgumentParser
import Foundation
import Synchronization
import UttrflowAI
import UttrflowCore
import UttrflowEval
import UttrflowLocalModel

/// Measures every candidate clean-up engine against one corpus. See `Docs/bakeoff-method.md`.
@main
struct Bakeoff: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uttrflow-bakeoff",
        abstract: "Score clean-up engines against the evaluation corpus.",
        subcommands: [
            Footprint.self, Profile.self, Complete.self, Score.self, GPUMemory.self, ReloadLeaks.self,
            SpeechShape.self, Marks.self,
        ]
    )

    @Option(name: .shortAndLong, help: "Comma-separated candidates. Defaults to every one.")
    var models: String?

    @Flag(name: .long, help: "Measure only the baselines, not the local models.")
    var baselinesOnly = false

    @Flag(name: .long, help: "Print what has already been measured and stop.")
    var summarise = false

    @Flag(name: .long, help: "Print every failed case, not just the summary.")
    var verbose = false

    @Flag(name: .long, help: "Show what a model actually writes, before any scoring.")
    var sample = false

    /// Context is a claim, and withholding it is the only way to find out whether it earns its place.
    @Flag(name: .long, help: "Withhold what is on screen, to measure whether it helps.")
    var ignoreContext = false

    @Option(name: .long, help: "Where results are kept between runs; comparisons use a -compared sibling.")
    var resultsPath = ".bakeoff"

    @Option(name: .long, help: "Comma-separated quality layers to run, in place of those on by default.")
    var layers: String?

    @Option(name: .long, help: "Comma-separated quality layers to switch off, to measure what each adds.")
    var without: String?

    /// The layers this run measures; `validate` has refused a name that is not one.
    private var running: QualityLayers {
        QualityLayers.ablation(only: layers, without: without) ?? QualityLayers()
    }

    func validate() throws {
        guard QualityLayers.ablation(only: layers, without: without) != nil else {
            let valid = QualityLayer.allCases.map(\.rawValue).joined(separator: ", ")
            throw ValidationError("Unknown quality layer in --layers or --without. Choose from \(valid).")
        }
    }

    @Option(
        name: .long,
        help: "Compare each measured candidate with this saved result JSON and fail on regressions.")
    var against: String?

    @Option(
        name: .long,
        help:
            "With --against, fields allowed to differ from the baseline: corpus, system, hardware, context, layers."
    )
    var allowDifference: String?

    @Option(
        name: .long,
        help: "Write the last stored run per prompt version and macOS build to this Markdown file.")
    var ledger: String?

    /// Kept apart so a with-context run cannot overwrite a without-context one.
    private var storeDirectory: String {
        let context = ignoreContext ? resultsPath + "-no-context" : resultsPath
        guard running != QualityLayers() else { return context }
        return context + "-layers-" + running.names.joined(separator: "+")
    }

    func run() async throws {
        let store = ResultStore(directory: URL(fileURLWithPath: storeDirectory))
        let outputStore = ResultStore(
            directory: URL(fileURLWithPath: against == nil ? storeDirectory : storeDirectory + "-compared"))
        guard against == nil || (!summarise && !sample) else {
            throw CleanExit.message("--against applies to a new bake-off run, not --summarise or --sample.")
        }

        let baselineURL = against.map { URL(fileURLWithPath: $0).standardizedFileURL }
        let baseline = try baselineURL.map { try ResultStore.load(from: $0) }

        if summarise {
            report(try store.all())
            return
        }

        if let ledger {
            try ResultLedger.markdown(of: try store.history()).write(
                to: URL(fileURLWithPath: ledger), atomically: true, encoding: .utf8)
            print("Wrote \(ledger).")
            return
        }

        if sample {
            try await showSamples()
            return
        }

        let header = RunHeader.current(contextWithheld: ignoreContext, layers: running)
        if let baseline {
            try Self.refuseUnintendedDifferences(
                header, baseline: baseline, allowing: try allowedDifferences())
        }
        let contextNote = ignoreContext ? ", context withheld" : ""
        print(
            "Bake-off — \(EvaluationCorpus.all.count) cases, prompt \(PromptBuilder.version)"
                + "\(contextNote)")
        print(header.summary)
        print(Self.provenance(of: EvaluationCorpus.all) + "\n")

        var measured: [Measurement] = []
        if models == nil {
            measured.append(await measureBaseline(kind: .rules, description: .rules))
            await compareShapes()
            measured.append(await measureBaseline(kind: .foundationModels, description: .appleOnDevice))
            measured.append(await measureShipping())
        }
        if !baselinesOnly {
            for model in try selectedModels() {
                measured.append(await measureLocal(model))
            }
        }

        for index in measured.indices { measured[index].header = header }
        for measurement in measured {
            if let baselineURL,
                outputStore.fileURL(for: measurement).standardizedFileURL == baselineURL
            {
                throw CleanExit.message(
                    "Comparison output would overwrite its baseline; choose a different --results-path."
                )
            }
            try outputStore.save(measurement)
        }

        if against != nil {
            report(measured)
        } else {
            report(try store.all())
        }
        if let baseline {
            let comparisons = measured.compactMap { RegressionComparison.compare($0, against: baseline) }
            guard !comparisons.isEmpty else {
                throw CleanExit.message(
                    "No measured candidate matches baseline \(baseline.description.name) \(baseline.description.parameters)."
                )
            }
            for line in comparisons.first?.corpusReport ?? [] { print(line) }
            let verdicts = measured.filter { $0.description.fileName == baseline.description.fileName }
                .map { SplitVerdict.judge($0, against: baseline) }
            for line in verdicts.flatMap(\.lines) { print(line) }
            let regressions = comparisons.flatMap(\.regressions)
            if regressions.isEmpty {
                print(
                    "\nNo regressions against \(baseline.description.name) \(baseline.description.parameters)."
                )
            } else {
                print(
                    "\nRegressions against \(baseline.description.name) \(baseline.description.parameters):")
                for regression in regressions { print("  \(regression)") }
                throw CleanExit.message("Bake-off comparison found \(regressions.count) regression(s).")
            }
            if verdicts.contains(where: { $0.outcome == .overfitted }) {
                FileHandle.standardError.write(
                    Data("Bake-off comparison is over-fitted: the held-out score fell.\n".utf8))
                throw ExitCode.failure
            }
        }
    }

    /// Prints raw model output for a handful of cases, because a score never says why.
    private func showSamples() async throws {
        for model in try selectedModels() {
            print("=== \(model.shortName) ===")
            let cleanup = MLXCandidateScorer(model: model)
            try await cleanup.prepare()

            let sampled =
                Array(EvaluationCorpus.cases(in: .everyday).prefix(2))
                + EvaluationCorpus.cases(in: .multilingual)
            for testCase in sampled {
                let request = request(for: testCase)
                let raw =
                    (try? await cleanup.rewrite(
                        PromptBuilder.standard.userPrompt(for: request),
                        instructions: PromptBuilder.standard.instructions(for: request.situation.destination),
                        kind: .localModel
                    )) ?? "<failed>"
                print("  spoken   \(testCase.spoken)")
                print("  wanted   \(testCase.expected)")
                print("  produced \(raw.replacingOccurrences(of: "\n", with: " ⏎ "))\n")
            }
        }
    }

    /// The `--allow-difference` names, refusing one that is not a field.
    private func allowedDifferences() throws -> Set<RunHeader.Field> {
        let names = (allowDifference ?? "").split(separator: ",").map { String($0).trimmed }
            .filter { !$0.isEmpty }
        return Set(
            try names.map { name in
                guard let field = RunHeader.Field(rawValue: name) else {
                    let valid = RunHeader.Field.allCases.map(\.rawValue).joined(separator: ", ")
                    throw CleanExit.message(
                        "Unknown field '\(name)' for --allow-difference. Choose from \(valid).")
                }
                return field
            })
    }

    /// Stops a comparison whose runs differ in a field nobody asked to vary, naming each one.
    static func refuseUnintendedDifferences(
        _ header: RunHeader, baseline: Measurement, allowing allowed: Set<RunHeader.Field>
    ) throws {
        guard let previous = baseline.header else {
            print("Baseline was stored before run headers; its configuration cannot be checked.")
            return
        }
        let differences = header.differences(from: previous, allowing: allowed)
        guard !differences.isEmpty else { return }
        throw CleanExit.message(
            "Refusing to compare runs that differ in a field the change did not intend to vary:\n  "
                + differences.joined(separator: "\n  ")
                + "\nPass --allow-difference with the field names to compare anyway.")
    }

    // MARK: Candidates

    private func selectedModels() throws -> [LocalModel] {
        guard let models else { return LocalModel.candidates }
        let names = models.split(separator: ",").map { String($0).trimmed }
        guard !names.isEmpty else {
            throw CleanExit.message("No models selected. Pass one or more model names to --models.")
        }
        return try names.map { name in
            guard let model = LocalModel.named(name) else {
                let validNames = ["gemma3Small", "llama32", "qwen3", "ministral3", "gemma3"]
                throw CleanExit.message(
                    "Unknown model '\(name)'. Choose a catalogue name (\(validNames.joined(separator: ", "))), a repository identifier, or a repository short name."
                )
            }
            return model
        }
    }

    private func measureBaseline(
        kind: TransformerKind, description: CandidateDescription
    ) async -> Measurement {
        var configuration = EngineConfiguration.default
        configuration.transformerPreference = [kind]
        let router = TextTransformers.router(configuration: configuration)
        let engine = TextTransformers.all().first { $0.kind == kind }

        print("· \(description.name)")
        let refusals = RefusalTally()
        let report = await EvaluationRunner().run(label: description.name) { testCase in
            let request = request(for: testCase)
            // An engine that declines a language has behaved well, not answered wrongly.
            if let engine, await engine.availability(for: request).isAvailable == false {
                return .declined
            }
            return .produced(
                try await formatted(request) { request in
                    let result = try await router.transform(request)
                    refusals.add(result.cleaning?.refusals ?? [], in: testCase.category)
                    return result.text
                })
        }
        for line in refusals.lines { print(line) }
        return Measurement(description: description, report: report)
    }

    /// Scores the rules floor on bare and recogniser-shaped input side by side, naming what only the shape breaks.
    private func compareShapes() async {
        let rules = RuleBasedTransformer()
        var reports: [InputShape: EvaluationReport] = [:]
        for shape in InputShape.allCases {
            reports[shape] = await EvaluationRunner(shape: shape).run(label: shape.rawValue) { testCase in
                .produced(try await formatted(request(for: testCase)) { try await rules.transform($0).text })
            }
        }
        guard let bare = reports[.bare], let shaped = reports[.recogniser] else { return }
        print("  input shape: bare \(percent(bare.passRate)), recogniser \(percent(shaped.passRate))")
        let passedShaped = Set(shaped.scores.filter(\.passed).map(\.caseID))
        for score in bare.scores where score.passed && !passedShaped.contains(score.caseID) {
            print("  fails only shaped: \(score.caseID)")
        }
    }

    /// Measures the whole router as the app configures it, fallback included.
    private func measureShipping() async -> Measurement {
        let router = TextTransformers.router(configuration: .default)
        print("· \(CandidateDescription.shipping.name)")
        // No availability pre-check: a router that produces nothing is a real failure.
        let report = await EvaluationRunner().run(label: CandidateDescription.shipping.name) {
            testCase in
            .produced(try await formatted(request(for: testCase)) { try await router.transform($0).text })
        }
        return Measurement(description: .shipping, report: report)
    }

    private func measureLocal(_ model: LocalModel) async -> Measurement {
        let description = CandidateDescription(model)
        print("· \(description.name) — \(gigabytes(model.downloadBytes))")

        let cleanup = MLXCandidateScorer(model: model)
        let clock = ContinuousClock()
        let loadStart = clock.now
        do {
            try await cleanup.prepare { fraction in
                FileHandle.standardError.write(Data("\r  fetching \(Int(fraction * 100))% ".utf8))
            }
        } catch {
            FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
            print("  could not load: \(error)")
            return Measurement(
                description: description,
                report: EvaluationReport(label: description.name, scores: [], durations: [])
            )
        }
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
        print("  ready in \(seconds(loadStart.duration(to: clock.now)))s")

        let transformer = TextTransformers.local(cleanup)
        let report = await EvaluationRunner().run(
            label: description.name,
            onCase: { _ in FileHandle.standardError.write(Data(".".utf8)) }
        ) { testCase in
            let request = request(for: testCase)
            if await transformer.availability(for: request).isAvailable == false {
                return .declined
            }
            do {
                return .produced(try await formatted(request) { try await transformer.transform($0).text })
            } catch {
                // Say why: a rewrite thrown away for the wrong reason is invisible in a score.
                FileHandle.standardError.write(
                    Data("\n  ! \(testCase.id): \(error)\n".utf8))
                throw error
            }
        }
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
        return Measurement(description: description, report: report)
    }

    /// What a candidate writes, or the words as heard when the formatting layer is off, as the pipeline leaves them.
    private func formatted(
        _ request: TransformationRequest, by tidy: (TransformationRequest) async throws -> String
    ) async throws -> String {
        guard running.isOn(.formatting) else { return request.transcription.text }
        return try await tidy(request)
    }

    private func request(for testCase: EvaluationCase) -> TransformationRequest {
        testCase.transformationRequest(withholdingContext: ignoreContext)
    }

    // MARK: Reporting

    private func report(_ measurements: [Measurement]) {
        guard !measurements.isEmpty else {
            print("Nothing measured yet.")
            return
        }

        let header =
            "candidate".padded(to: 17) + "version".padded(to: 11) + "params".padded(to: 8)
            + "quant".padded(to: 11) + "size".padded(to: 8) + "pass".padded(to: 7)
            + "words".padded(to: 7) + "marks".padded(to: 7) + "case".padded(to: 7)
            + "typical".padded(to: 9) + "slowest".padded(to: 9)
            + "declined".padded(to: 10) + "lost"
        print("\n" + header)
        print(String(repeating: "─", count: header.count + 4))

        for measurement in measurements.sorted(by: { $0.report.passRate > $1.report.passRate }) {
            let description = measurement.description
            let report = measurement.report
            print(
                description.name.padded(to: 17)
                    + description.version.padded(to: 11)
                    + description.parameters.padded(to: 8)
                    + description.quantisation.padded(to: 11)
                    + description.size.padded(to: 8)
                    + percent(report.passRate).padded(to: 7)
                    + percent(report.meanSimilarity).padded(to: 7)
                    + (report.meanMarkAccuracy.map(percent) ?? "n/a").padded(to: 7)
                    + (report.meanCaseAccuracy.map(percent) ?? "n/a").padded(to: 7)
                    + "\(seconds(report.medianDuration))s".padded(to: 9)
                    + "\(seconds(report.slowestDuration))s".padded(to: 9)
                    + "\(report.declinedCount)".padded(to: 10)
                    + "\(report.lostWordCount)"
            )
        }

        print("\nn/p — Apple publishes neither figure for its on-device model.")

        // Built from the enum, so a new category cannot go unreported.
        let byMultilingual = measurements.sorted(by: {
            ($0.report.passRate(in: .multilingual) ?? -1, $0.report.passRate)
                > ($1.report.passRate(in: .multilingual) ?? -1, $1.report.passRate)
        })
        printBreakdown(
            "By category", columns: EvaluationCase.Category.allCases.map(\.rawValue), of: byMultilingual
        ) { report, category in
            report.passRate(in: EvaluationCase.Category(rawValue: category) ?? .everyday)
        }
        // Held out apart from development, so a gain that only tuning bought shows as a gap between the two.
        printBreakdown(
            "By split", columns: CorpusSplit.allCases.map(\.rawValue), of: byMultilingual
        ) { report, split in
            report.passRate(in: CorpusSplit(rawValue: split) ?? .development)
        }
        // Per destination, because a block that helps one place can cost another and the total would hide it.
        printBreakdown(
            "By destination", columns: Destination.allCases.map(\.rawValue), of: byMultilingual
        ) { report, destination in
            report.passRate(for: Destination(rawValue: destination) ?? .plain)
        }

        printCapitalisation(of: byMultilingual)
        printMarks(of: byMultilingual)

        if verbose {
            for measurement in measurements {
                // The stored verdict, not one rebuilt from it, so a file older than a reason still lists the case.
                let worst = measurement.report.cases.filter { !$0.declined && !$0.passed }
                guard !worst.isEmpty else { continue }
                // Two candidates can share a family name, so the size tells the Gemmas apart.
                print(
                    "\n\(measurement.description.name) \(measurement.description.parameters)"
                        + " failed \(worst.count):")
                for result in worst {
                    print("  \(result.caseID.padded(to: 26)) \(percent(result.similarity))\(result.reasons)")
                }
            }
        }
    }

    /// Case accuracy per capitalisation class beside the do-nothing and recogniser floors, so a mean is read against them.
    private func printCapitalisation(of measurements: [Measurement]) {
        let header =
            "candidate".padded(to: 17) + "params".padded(to: 8) + "class".padded(to: 16)
            + "words".padded(to: 8) + "case".padded(to: 8) + "lower".padded(to: 8) + "spoken"
        print(
            "\nCapitalisation by class — accuracy over aligned words,"
                + " beside all-lower-case and recogniser output\n")
        print(header)
        print(String(repeating: "─", count: header.count + 4))
        for measurement in measurements {
            let report = measurement.report
            guard let tally = report.capitalisation, let lower = report.lowerCaseBaseline,
                let spoken = report.spokenBaseline
            else {
                print(measurement.description.name.padded(to: 17) + "(stored before classes were counted)")
                continue
            }
            for wordClass in CapitalisationClass.allCases {
                guard let count = tally.matched[wordClass] else { continue }
                print(
                    measurement.description.name.padded(to: 17)
                        + measurement.description.parameters.padded(to: 8)
                        + wordClass.rawValue.padded(to: 16) + "\(count)".padded(to: 8)
                        + (tally.accuracy(of: wordClass).map(percent) ?? "n/a").padded(to: 8)
                        + (lower.accuracy(of: wordClass).map(percent) ?? "n/a").padded(to: 8)
                        + (spoken.accuracy(of: wordClass).map(percent) ?? "n/a"))
            }
            let below = tally.mostDegraded(comparedWith: spoken).map(\.rawValue) ?? "none"
            print(
                measurement.description.name.padded(to: 17) + measurement.description.parameters.padded(to: 8)
                    + "all".padded(to: 16) + "".padded(to: 8) + percent(tally.accuracy).padded(to: 8)
                    + percent(lower.accuracy).padded(to: 8) + percent(spoken.accuracy)
                    + "  furthest below the recogniser: \(below)")
        }
    }

    /// Precision, recall and F1 per punctuation mark over aligned words, then which mark was written for which.
    private func printMarks(of measurements: [Measurement]) {
        let header =
            "candidate".padded(to: 17) + "params".padded(to: 8) + "mark".padded(to: 13)
            + "wanted".padded(to: 8) + "made".padded(to: 8) + "prec".padded(to: 8) + "recall".padded(to: 8)
            + "F1"
        print("\nPunctuation by mark — placed by word alignment, so a dropped word moves no other mark\n")
        print(header)
        print(String(repeating: "─", count: header.count + 4))
        for measurement in measurements {
            let name =
                measurement.description.name.padded(to: 17) + measurement.description.parameters.padded(to: 8)
            guard let tally = measurement.report.marks else {
                print(name + "(stored before marks were counted)")
                continue
            }
            for mark in MarkClass.allCases {
                guard let f1 = tally.f1(of: mark) else { continue }
                print(
                    name + mark.rawValue.padded(to: 13) + "\(tally.wanted[mark] ?? 0)".padded(to: 8)
                        + "\(tally.produced[mark] ?? 0)".padded(to: 8)
                        + (tally.precision(of: mark).map(percent) ?? "n/a").padded(to: 8)
                        + (tally.recall(of: mark).map(percent) ?? "n/a").padded(to: 8) + percent(f1))
            }
            let swaps = tally.substitutions.flatMap { wanted, written in
                written.map { "\(wanted.rawValue) as \($0.key.rawValue) \($0.value)" }
            }.sorted()
            print(name + "written in place: " + (swaps.isEmpty ? "none" : swaps.joined(separator: ", ")))
        }
    }

    /// One pass-rate table, a column per slice; "declined" where the engine attempted nothing in it.
    private func printBreakdown(
        _ title: String, columns: [String], of measurements: [Measurement],
        rate: (StoredReport, String) -> Double?
    ) {
        let header =
            "candidate".padded(to: 17) + "params".padded(to: 8) + columns.map { $0.padded(to: 15) }.joined()
        print("\n\(title) — pass rate over cases the engine attempted\n")
        print(header)
        print(String(repeating: "─", count: header.count + 4))
        for measurement in measurements {
            print(
                measurement.description.name.padded(to: 17)
                    + measurement.description.parameters.padded(to: 8)
                    + columns.map { (rate(measurement.report, $0).map(percent) ?? "declined").padded(to: 15) }
                    .joined()
            )
        }
    }

    /// How many cases each origin and split holds, so a score is read against where its cases came from.
    static func provenance(of cases: [EvaluationCase]) -> String {
        let origins = EvaluationCase.Origin.allCases.map { origin in
            "\(origin.rawValue) \(cases.count(where: { $0.origin == origin }))"
        }
        let splits = CorpusSplit.allCases.map { split in
            "\(split.rawValue) \(cases.count(where: { $0.split == split }))"
        }
        return "origin: " + origins.joined(separator: ", ") + "; split: " + splits.joined(separator: ", ")
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
    private func gigabytes(_ bytes: Int64) -> String { String(format: "%.1fGB", Double(bytes) / 1e9) }
    private func seconds(_ duration: Duration) -> String {
        String(
            format: "%.2f",
            duration.inSeconds)
    }
}

/// What a candidate is, for the report's identifying columns.
struct CandidateDescription: Codable, Sendable {
    let name: String
    let version: String
    let parameters: String
    let quantisation: String
    let size: String

    /// Keyed by size as well as name, since Gemma 3 ships at both 1B and 4B.
    var fileName: String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(
            "\(name)-\(parameters)".unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        )
    }

    init(name: String, version: String, parameters: String, quantisation: String, size: String) {
        self.name = name
        self.version = version
        self.parameters = parameters
        self.quantisation = quantisation
        self.size = size
    }

    init(_ model: LocalModel) {
        self.init(
            name: model.family,
            version: model.version,
            parameters: model.parameterLabel,
            quantisation: model.quantisation.rawValue,
            size: String(format: "%.1fGB", Double(model.downloadBytes) / 1e9)
        )
    }

    /// What the app ships: Apple's model, then a local model, then rules as the floor.
    static let shipping = CandidateDescription(
        name: "shipping", version: "router", parameters: "—", quantisation: "—", size: "—"
    )

    static let rules = CandidateDescription(
        name: "rules", version: "—", parameters: "—", quantisation: "—", size: "0"
    )

    /// Says "unpublished" rather than repeating a parameter count Apple has never given.
    static let appleOnDevice = CandidateDescription(
        name: "Apple", version: "on-device", parameters: "n/p", quantisation: "n/p", size: "bundled"
    )
}

/// One candidate's identity and its result.
struct Measurement: Codable, Sendable {
    let description: CandidateDescription
    var report: StoredReport
    /// What produced the result; absent from results stored before run headers.
    var header: RunHeader?

    init(description: CandidateDescription, report: EvaluationReport, header: RunHeader? = nil) {
        self.description = description
        self.report = StoredReport(report)
        self.header = header
    }
}

/// A report flattened for storage, so a finished run survives a later stall.
struct StoredReport: Codable, Sendable {
    let passRate: Double
    let meanSimilarity: Double
    /// Absent from result files written before surface metrics were recorded.
    let meanMarkAccuracy: Double?
    /// Absent from result files written before surface metrics were recorded.
    let meanCaseAccuracy: Double?
    /// Case agreement per capitalisation class; `nil` in a result file older than the classes.
    let capitalisation: CapitalisationTally?
    /// What an all-lower-case output scores on the same cases; `nil` like `capitalisation`.
    let lowerCaseBaseline: CapitalisationTally?
    /// What the recogniser's own case scores on the same cases; `nil` like `capitalisation`.
    let spokenBaseline: CapitalisationTally?
    /// Punctuation agreement per mark; `nil` in a result file older than the marks.
    let marks: PunctuationTally?
    let medianSeconds: Double
    let slowestSeconds: Double
    let declinedCount: Int
    let lostWordCount: Int
    var cases: [CaseResult]
    /// The fingerprint of the corpus scored; absent from results stored before cases were fingerprinted.
    var corpusIdentity: String?

    struct CaseResult: Codable, Sendable {
        let caseID: String
        let category: String
        /// Absent from results stored before the corpus named destinations.
        let destination: String?
        let similarity: Double
        /// Absent from result files written before mark accuracy was recorded.
        let markAccuracy: Double?
        /// Absent from result files written before case accuracy was recorded.
        let caseAccuracy: Double?
        let lost: [String]
        /// Absent from results stored before the reasons were kept, like `destination`, so an older file still decodes.
        let invented: [String]?
        /// Absent from results stored before the reasons were kept.
        let brokeShape: [String]?
        let passed: Bool
        let declined: Bool
        /// The fingerprint of the case as scored; absent from results stored before cases were fingerprinted.
        var identity: String?

        /// Why the case failed, one clause per reason, or a note when the file is too old to say.
        var reasons: String {
            let named = [("lost", lost), ("invented", invented ?? []), ("shape", brokeShape ?? [])]
                .filter { !$0.1.isEmpty }
                .map { "  \($0.0) \($0.1.joined(separator: ", "))" }
                .joined()
            return named.isEmpty && invented == nil ? "  (stored before its reasons were kept)" : named
        }
    }

    /// Pass rate within one category, which is the axis an overall figure hides.
    func passRate(in category: EvaluationCase.Category) -> Double? {
        passRate(over: cases.filter { $0.category == category.rawValue })
    }

    /// Pass rate within one split, read from the case id so a result stored before splits existed still divides.
    func passRate(in split: CorpusSplit) -> Double? {
        passRate(over: cases.filter { CorpusSplit(caseID: $0.caseID) == split })
    }

    /// Pass rate over the cases dictated into one kind of place; a result stored before the corpus named destinations is in no column.
    func passRate(for destination: Destination) -> Double? {
        passRate(over: cases.filter { $0.destination == destination.rawValue })
    }

    private func passRate(over slice: [CaseResult]) -> Double? {
        let attempted = slice.filter { !$0.declined }
        guard !attempted.isEmpty else { return nil }
        return Double(attempted.count(where: \.passed)) / Double(attempted.count)
    }

    init(_ report: EvaluationReport) {
        passRate = report.passRate
        meanSimilarity = report.meanSimilarity
        meanMarkAccuracy = report.meanMarkAccuracy
        meanCaseAccuracy = report.meanCaseAccuracy
        capitalisation = report.capitalisation
        lowerCaseBaseline = report.lowerCaseBaseline
        spokenBaseline = report.spokenBaseline
        marks = report.marks
        medianSeconds = Self.seconds(report.medianDuration)
        slowestSeconds = Self.seconds(report.slowestDuration)
        declinedCount = report.declinedCount
        lostWordCount = report.casesLosingRequiredWords.count
        let corpus = Dictionary(uniqueKeysWithValues: EvaluationCorpus.all.map { ($0.id, $0) })
        corpusIdentity = EvaluationCase.corpusIdentity(of: EvaluationCorpus.all)
        cases = report.scores.map {
            CaseResult(
                caseID: $0.caseID, category: corpus[$0.caseID]?.category.rawValue ?? "unknown",
                destination: corpus[$0.caseID]?.destination.rawValue,
                similarity: $0.similarity,
                markAccuracy: $0.markAccuracy, caseAccuracy: $0.caseAccuracy,
                lost: $0.lost, invented: $0.invented,
                brokeShape: $0.brokeShape, passed: $0.passed, declined: $0.declined,
                identity: corpus[$0.caseID]?.identity)
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        duration.inSeconds
    }

    var medianDuration: Duration { .seconds(medianSeconds) }
    var slowestDuration: Duration { .seconds(slowestSeconds) }
    var attempted: [CaseScore] {
        cases.filter { !$0.declined }.map {
            CaseScore(
                caseID: $0.caseID, similarity: $0.similarity,
                markAccuracy: $0.markAccuracy ?? 1, caseAccuracy: $0.caseAccuracy ?? 1,
                keptEverythingRequired: $0.lost.isEmpty, lost: $0.lost, isExact: false,
                declined: $0.declined, invented: $0.invented ?? [], brokeShape: $0.brokeShape ?? [])
        }
    }

}

/// Keeps each finished measurement on disk, one directory per run, so a later run never overwrites an earlier one.
struct ResultStore {
    let directory: URL

    func save(_ measurement: Measurement) throws {
        let url = fileURL(for: measurement)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(measurement).write(to: url)
    }

    /// The latest stored result of each candidate.
    func all() throws -> [Measurement] {
        var latest: [String: Measurement] = [:]
        for measurement in try history() {
            let key = measurement.description.fileName
            if let kept = latest[key], (kept.header?.runID ?? "") >= (measurement.header?.runID ?? "") {
                continue
            }
            latest[key] = measurement
        }
        return Array(latest.values)
    }

    /// Every stored result: each run's directory, plus older files at the top level.
    func history() throws -> [Measurement] {
        let runs = Self.files(in: directory.appending(path: Self.runsDirectory), withExtension: nil)
        return ([directory] + runs).flatMap { Self.files(in: $0, withExtension: "json") }.compactMap { url in
            try? Self.decoder.decode(Measurement.self, from: Data(contentsOf: url))
        }
    }

    static func load(from url: URL) throws -> Measurement {
        do {
            return try decoder.decode(Measurement.self, from: Data(contentsOf: url))
        } catch {
            throw CleanExit.message("Could not read saved bake-off result at \(url.path): \(error)")
        }
    }

    func fileURL(for measurement: Measurement) -> URL {
        let folder = measurement.header.map {
            directory.appending(path: Self.runsDirectory).appending(path: $0.runID)
        }
        return (folder ?? directory).appending(path: "\(measurement.description.fileName).json")
    }

    private static let runsDirectory = "runs"

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func files(in folder: URL, withExtension pathExtension: String?) -> [URL] {
        let entries =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return entries.filter { url in
            guard let pathExtension else {
                return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            return url.pathExtension == pathExtension
        }
    }
}

/// A saved result against a new one, judged only on cases whose question is unchanged.
struct RegressionComparison {
    let regressions: [String]
    /// Cases scored now and absent from the baseline.
    var added: [String] = []
    /// Cases in the baseline and no longer scored.
    var removed: [String] = []
    /// Cases whose fingerprint differs, so the two scores answer different questions.
    var changed: [String] = []
    /// Whether the two runs scored different corpora; `false` when either result predates fingerprints.
    var corpusChanged = false

    static func compare(_ current: Measurement, against baseline: Measurement) -> RegressionComparison? {
        guard current.description.fileName == baseline.description.fileName else { return nil }
        let previous = Dictionary(uniqueKeysWithValues: baseline.report.cases.map { ($0.caseID, $0) })
        let latest = Dictionary(uniqueKeysWithValues: current.report.cases.map { ($0.caseID, $0) })
        var regressions: [String] = []
        var changed: [String] = []
        var paired: [(old: StoredReport.CaseResult, new: StoredReport.CaseResult)] = []

        for (caseID, old) in previous {
            guard let new = latest[caseID] else { continue }
            if let before = old.identity, let after = new.identity, before != after {
                changed.append(caseID)
                continue
            }
            paired.append((old, new))
            if old.passed && !new.passed {
                regressions.append("\(caseID): previously passing case now fails")
            }
            if new.lost.count > old.lost.count {
                regressions.append(
                    "\(caseID): lost words increased from \(old.lost.count) to \(new.lost.count)")
            }
        }
        regressions += markAndCaseDrops(paired)
        let before = baseline.report.corpusIdentity
        let after = current.report.corpusIdentity
        return RegressionComparison(
            regressions: regressions.sorted(),
            added: latest.keys.filter { previous[$0] == nil }.sorted(),
            removed: previous.keys.filter { latest[$0] == nil }.sorted(),
            changed: changed.sorted(),
            corpusChanged: before != nil && after != nil && before != after)
    }

    /// A pass is judged on words, so a lost comma or capital fails here instead: a category's mean over unchanged cases never falls.
    static func markAndCaseDrops(
        _ paired: [(old: StoredReport.CaseResult, new: StoredReport.CaseResult)]
    ) -> [String] {
        let measures: [(String, KeyPath<StoredReport.CaseResult, Double?>)] = [
            ("mark accuracy", \.markAccuracy), ("case accuracy", \.caseAccuracy),
        ]
        var drops: [String] = []
        for (category, pairs) in Dictionary(grouping: paired, by: \.new.category) {
            let attempted = pairs.filter { !$0.old.declined && !$0.new.declined }
            for (name, measure) in measures {
                let values = attempted.compactMap { pair in
                    pair.old[keyPath: measure].flatMap { old in pair.new[keyPath: measure].map { (old, $0) } }
                }
                guard !values.isEmpty else { continue }
                let before = values.map(\.0).reduce(0, +) / Double(values.count)
                let after = values.map(\.1).reduce(0, +) / Double(values.count)
                if after < before - 1e-9 {
                    drops.append(
                        "category \(category): \(name) fell from \(percent(before)) to \(percent(after))")
                }
            }
        }
        return drops
    }

    private static func percent(_ fraction: Double) -> String { String(format: "%.1f%%", fraction * 100) }

    /// The corpus change first, then each set of cases left out of the verdict.
    var corpusReport: [String] {
        guard corpusChanged || !added.isEmpty || !removed.isEmpty || !changed.isEmpty else { return [] }
        var lines =
            corpusChanged ? ["Corpus changed since the baseline; only unchanged cases are judged."] : []
        for (label, ids) in [("added", added), ("removed", removed), ("changed", changed)] where !ids.isEmpty
        {
            lines.append("  \(label) (\(ids.count)): \(ids.joined(separator: ", "))")
        }
        return lines
    }
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self + " " : self + String(repeating: " ", count: width - count)
    }
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespaces) }
}

/// Guard refusals counted by kind within each category, since a fallback's pass hides what the model wrote.
final class RefusalTally: Sendable {
    private let counts = Mutex<[String: [RefusalKind: Int]]>([:])

    /// Counts each refusal one case drew.
    func add(_ refusals: [CleaningRecord.Refusal], in category: EvaluationCase.Category) {
        counts.withLock { counts in
            for refusal in refusals { counts[category.rawValue, default: [:]][refusal.kind, default: 0] += 1 }
        }
    }

    /// One line per category that drew a refusal, kinds in name order.
    var lines: [String] {
        counts.withLock { counts in
            counts.keys.sorted().map { category in
                let kinds = (counts[category] ?? [:]).sorted { $0.key.rawValue < $1.key.rawValue }
                return "  refused in \(category): "
                    + kinds.map { "\($0.key.rawValue) \($0.value)" }.joined(separator: ", ")
            }
        }
    }
}
