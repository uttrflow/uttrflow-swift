import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowEval
import UttrflowLocalModel

/// Measures every candidate clean-up engine against the same corpus.
///
/// A separate executable, not a subcommand of `uttrflow-dev`, because it links MLX —
/// which needs Metal shaders that Swift Package Manager's command line cannot build.
/// Keeping it apart means the everyday tool stays buildable with `swift run`.
/// Build this one with `make bakeoff`.
///
/// Each candidate's result is written to disk as it finishes, so a model that stalls
/// mid-download costs only its own run. `--summarise` prints everything measured so far.
@main
struct Bakeoff: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uttrflow-bakeoff",
        abstract: "Score clean-up engines against the evaluation corpus.",
        subcommands: [Footprint.self, Profile.self, Complete.self]
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

    /// Context is a claim, not a given. Running the corpus with it withheld is the only
    /// way to find out whether it earns its place or merely adds words to the prompt.
    @Flag(name: .long, help: "Withhold what is on screen, to measure whether it helps.")
    var ignoreContext = false

    @Option(name: .long, help: "Where results are kept between runs.")
    var resultsPath = ".bakeoff"

    /// Kept apart so a with-context run cannot overwrite a without-context one.
    private var storeDirectory: String { ignoreContext ? resultsPath + "-no-context" : resultsPath }

    func run() async throws {
        let store = ResultStore(directory: URL(fileURLWithPath: storeDirectory))

        if summarise {
            report(try store.all())
            return
        }

        if sample {
            try await showSamples()
            return
        }

        let contextNote = ignoreContext ? ", context withheld" : ""
        print(
            "Bake-off — \(EvaluationCorpus.all.count) cases, prompt v\(CleanupPrompt.version)"
                + "\(contextNote)\n")

        if models == nil {
            try store.save(await measureBaseline(kind: .rules, description: .rules))
            try store.save(await measureBaseline(kind: .foundationModels, description: .appleOnDevice))
            try store.save(await measureShipping())
        }
        if !baselinesOnly {
            for model in selectedModels() {
                try store.save(await measureLocal(model))
            }
        }

        report(try store.all())
    }

    /// Prints raw model output for a handful of cases.
    ///
    /// A score says a model did badly; only its actual words say why — and whether the
    /// fault is the model or the way it is being asked.
    private func showSamples() async throws {
        for model in selectedModels() {
            print("=== \(model.shortName) ===")
            let cleanup = MLXCleanupModel(model: model)
            try await cleanup.prepare()

            let sampled =
                Array(EvaluationCorpus.cases(in: .everyday).prefix(2))
                + EvaluationCorpus.cases(in: .multilingual)
            for testCase in sampled {
                let raw =
                    (try? await cleanup.rewrite(
                        CleanupPrompt.current.userPrompt(
                            for: request(for: testCase)),
                        instructions: CleanupPrompt.current.instructions,
                        kind: .localModel
                    )) ?? "<failed>"
                print("  spoken   \(testCase.spoken)")
                print("  wanted   \(testCase.expected)")
                print("  produced \(raw.replacingOccurrences(of: "\n", with: " ⏎ "))\n")
            }
        }
    }

    // MARK: Candidates

    private func selectedModels() -> [LocalModel] {
        guard let models else { return LocalModel.candidates }
        return models.split(separator: ",")
            .compactMap { LocalModel.named(String($0).trimmed) }
    }

    private func measureBaseline(
        kind: TransformerKind, description: CandidateDescription
    ) async -> Measurement {
        var configuration = EngineConfiguration.default
        configuration.transformerPreference = [kind]
        let router = TextTransformers.router(configuration: configuration)
        let engine = TextTransformers.all().first { $0.kind == kind }

        print("· \(description.name)")
        let report = await EvaluationRunner().run(label: description.name) { testCase in
            let request = request(for: testCase)
            // Ask first: an engine that says it cannot handle a language has behaved
            // well, and must not be scored as though it answered wrongly.
            if let engine, await engine.availability(for: request).isAvailable == false {
                return .declined
            }
            return .produced(try await router.transform(request).text)
        }
        return Measurement(description: description, report: report)
    }

    /// Measures the whole router, exactly as the app configures it.
    ///
    /// Every other candidate is pinned to one engine so its own strengths can be read
    /// off. That is the right way to compare engines and the wrong way to predict what
    /// a user gets, because it removes the fallback. Apple's model refuses the
    /// `injection` case outright; pinned, that scores zero, and the shipping router
    /// hands the case to rules and gets it right. Without this row the report would
    /// understate the product by describing a configuration nobody runs.
    private func measureShipping() async -> Measurement {
        let router = TextTransformers.router(configuration: .default)
        print("· \(CandidateDescription.shipping.name)")
        // No availability pre-check here: declining is what the *engines* do, and the
        // router's whole job is to have somewhere to decline to. A router that produced
        // nothing would be a real failure, so it is scored as one.
        let report = await EvaluationRunner().run(label: CandidateDescription.shipping.name) {
            testCase in
            .produced(try await router.transform(request(for: testCase)).text)
        }
        return Measurement(description: .shipping, report: report)
    }

    private func measureLocal(_ model: LocalModel) async -> Measurement {
        let description = CandidateDescription(model)
        print("· \(description.name) — \(gigabytes(model.downloadBytes))")

        let cleanup = MLXCleanupModel(model: model)
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

        let transformer = GenerativeTextTransformer(kind: .localModel, model: cleanup)
        let report = await EvaluationRunner().run(
            label: description.name,
            onCase: { _ in FileHandle.standardError.write(Data(".".utf8)) }
        ) { testCase in
            let request = request(for: testCase)
            if await transformer.availability(for: request).isAvailable == false {
                return .declined
            }
            do {
                return .produced(try await transformer.transform(request).text)
            } catch {
                // Say why. A rewrite thrown away for the wrong reason is invisible in
                // a score, and has already happened twice in this project.
                FileHandle.standardError.write(
                    Data("\n  ! \(testCase.id): \(error)\n".utf8))
                throw error
            }
        }
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
        return Measurement(description: description, report: report)
    }

    private func request(for testCase: EvaluationCase) -> TransformationRequest {
        TransformationRequest(
            transcription: Transcription(
                text: testCase.spoken,
                detectedLanguage: DetectedLanguage(code: testCase.language)
            ),
            context: ignoreContext ? .unknown : testCase.context
        )
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
            + "close".padded(to: 7) + "typical".padded(to: 9) + "slowest".padded(to: 9)
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
                    + "\(seconds(report.medianDuration))s".padded(to: 9)
                    + "\(seconds(report.slowestDuration))s".padded(to: 9)
                    + "\(report.declinedCount)".padded(to: 10)
                    + "\(report.lostWordCount)"
            )
        }

        print("\nn/p — Apple publishes neither figure for its on-device model.")

        // Built from the enum rather than a fixed list, so a new category cannot be
        // added to the corpus and then quietly go unreported.
        let categories = EvaluationCase.Category.allCases
        let categoryHeader =
            "candidate".padded(to: 17) + "params".padded(to: 8)
            + categories.map { $0.rawValue.padded(to: 15) }.joined()
        print("\nBy category — pass rate over cases the engine attempted\n")
        print(categoryHeader)
        print(String(repeating: "─", count: categoryHeader.count + 4))
        for measurement in measurements.sorted(by: {
            ($0.report.passRate(in: .multilingual) ?? -1, $0.report.passRate)
                > ($1.report.passRate(in: .multilingual) ?? -1, $1.report.passRate)
        }) {
            let report = measurement.report
            func rate(_ category: EvaluationCase.Category) -> String {
                report.passRate(in: category).map(percent) ?? "declined"
            }
            print(
                measurement.description.name.padded(to: 17)
                    + measurement.description.parameters.padded(to: 8)
                    + categories.map { rate($0).padded(to: 15) }.joined()
            )
        }

        if verbose {
            for measurement in measurements {
                let worst = measurement.report.attempted.filter { !$0.passed }
                guard !worst.isEmpty else { continue }
                // Two candidates can share a family name, so the size has to be here
                // or the two Gemma listings are indistinguishable.
                print(
                    "\n\(measurement.description.name) \(measurement.description.parameters)"
                        + " failed \(worst.count):")
                for score in worst {
                    let lost = score.lost.isEmpty ? "" : "  lost \(score.lost.joined(separator: ", "))"
                    print("  \(score.caseID.padded(to: 26)) \(percent(score.similarity))\(lost)")
                }
            }
        }
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

    /// Two candidates can share a family name — Gemma 3 ships at 1B and 4B — so the
    /// stored file is keyed by size as well, or one would silently overwrite the other.
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

    /// The configuration the app actually ships: Apple's model first, a local model for
    /// what it cannot do, rules as the floor that always answers.
    static let shipping = CandidateDescription(
        name: "shipping", version: "router", parameters: "—", quantisation: "—", size: "—"
    )

    static let rules = CandidateDescription(
        name: "rules", version: "—", parameters: "—", quantisation: "—", size: "0"
    )

    /// Apple publishes neither the parameter count nor the quantisation of its
    /// on-device model, so this says so rather than repeating a number from elsewhere.
    static let appleOnDevice = CandidateDescription(
        name: "Apple", version: "on-device", parameters: "n/p", quantisation: "n/p", size: "bundled"
    )
}

/// One candidate's identity and its result.
struct Measurement: Codable, Sendable {
    let description: CandidateDescription
    let report: StoredReport

    init(description: CandidateDescription, report: EvaluationReport) {
        self.description = description
        self.report = StoredReport(report)
    }
}

/// A report flattened for storage, so a finished run survives a later stall.
struct StoredReport: Codable, Sendable {
    let passRate: Double
    let meanSimilarity: Double
    let medianSeconds: Double
    let slowestSeconds: Double
    let declinedCount: Int
    let lostWordCount: Int
    let cases: [CaseResult]

    struct CaseResult: Codable, Sendable {
        let caseID: String
        let category: String
        let similarity: Double
        let lost: [String]
        let passed: Bool
        let declined: Bool
    }

    /// Pass rate within one category, over the cases this engine attempted.
    ///
    /// The overall figure hides the only axis that decides this product: a model that
    /// is excellent at English and mangles Hindi has not solved the problem a local
    /// model exists to solve.
    func passRate(in category: EvaluationCase.Category) -> Double? {
        let attempted = cases.filter { $0.category == category.rawValue && !$0.declined }
        guard !attempted.isEmpty else { return nil }
        return Double(attempted.count(where: \.passed)) / Double(attempted.count)
    }

    init(_ report: EvaluationReport) {
        passRate = report.passRate
        meanSimilarity = report.meanSimilarity
        medianSeconds = Self.seconds(report.medianDuration)
        slowestSeconds = Self.seconds(report.slowestDuration)
        declinedCount = report.declinedCount
        lostWordCount = report.casesLosingRequiredWords.count
        let categories = Dictionary(
            uniqueKeysWithValues: EvaluationCorpus.all.map { ($0.id, $0.category.rawValue) })
        cases = report.scores.map {
            CaseResult(
                caseID: $0.caseID, category: categories[$0.caseID] ?? "unknown",
                similarity: $0.similarity, lost: $0.lost, passed: $0.passed, declined: $0.declined)
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
                keptEverythingRequired: $0.lost.isEmpty, lost: $0.lost, isExact: false,
                declined: $0.declined)
        }
    }

}

/// Keeps each finished measurement on disk.
struct ResultStore {
    let directory: URL

    func save(_ measurement: Measurement) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(measurement).write(
            to: directory.appending(path: "\(measurement.description.fileName).json"))
    }

    func all() throws -> [Measurement] {
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            try? JSONDecoder().decode(Measurement.self, from: Data(contentsOf: url))
        }
    }
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self + " " : self + String(repeating: " ", count: width - count)
    }
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
