import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowEval
import UttrflowLocalModel

/// Measures the local model's lift over rules per rule-visible cue, to choose when the tidier needs the model. See `Docs/bakeoff.md`.
struct TidyGate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tidy-gate",
        abstract:
            "Score rules and the local model per cue and category, and what gating the model on a cue saves."
    )

    @Option(name: .long, help: "Which local model to run: a catalogue or repository name.")
    var model = "gemma3"

    @Option(
        name: .long, help: "Score only the first this many cases of each category; 0 scores the whole corpus."
    )
    var perCategory = 0

    func run() async throws {
        guard let chosen = LocalModel.named(model) else { throw CleanExit.message("no such model: \(model)") }
        let cases = Self.sample(EvaluationCorpus.all, perCategory: perCategory)
        print(
            "Tidy gate — \(cases.count) of \(EvaluationCorpus.all.count) cases, \(chosen.shortName), prompt \(PromptBuilder.version)"
        )

        let cleanup = MLXCandidateScorer(model: chosen)
        try await cleanup.prepare()
        let local = TextTransformers.local(cleanup)
        let rules = RuleBasedTransformer()
        let clock = ContinuousClock()
        var rows: [TidyGateRow] = []
        for testCase in cases {
            FileHandle.standardError.write(
                Data("\r\u{1B}[2K\(rows.count + 1)/\(cases.count) \(testCase.id)".utf8))
            let request = testCase.transformationRequest()
            guard await local.availability(for: request).isAvailable else { continue }
            let rulesStart = clock.now
            let ruled = (try? await rules.transform(request).text) ?? ""
            let rulesSeconds = rulesStart.duration(to: clock.now).inSeconds
            let modelStart = clock.now
            let modelled = (try? await local.transform(request).text) ?? ""
            rows.append(
                TidyGateRow(
                    category: testCase.category.rawValue, cues: TidyCue.cues(in: testCase.spoken),
                    words: WordTokens.words(testCase.spoken, .display).count,
                    rulesPassed: Scorer.score(ruled, against: testCase).passed,
                    modelPassed: Scorer.score(modelled, against: testCase).passed,
                    rulesSeconds: rulesSeconds, modelSeconds: modelStart.duration(to: clock.now).inSeconds))
        }
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
        for line in TidyGateReport(rows: rows).lines { print(line) }
    }

    /// The first `perCategory` cases of each category in corpus order, or every case when it is zero.
    static func sample(_ cases: [EvaluationCase], perCategory: Int) -> [EvaluationCase] {
        guard perCategory > 0 else { return cases }
        var taken: [EvaluationCase.Category: Int] = [:]
        return cases.filter { testCase in
            taken[testCase.category, default: 0] += 1
            return taken[testCase.category, default: 0] <= perCategory
        }
    }
}

/// One case scored both ways.
struct TidyGateRow: Sendable {
    let category: String
    let cues: Set<TidyCue>
    let words: Int
    let rulesPassed: Bool
    let modelPassed: Bool
    let rulesSeconds: Double
    let modelSeconds: Double

    /// The gate under test: call the model only when the rules pass saw a cue.
    var callsModel: Bool { !cues.isEmpty }
    var gatedPassed: Bool { callsModel ? modelPassed : rulesPassed }
    var gatedSeconds: Double { callsModel ? modelSeconds : rulesSeconds }
}

/// The lift table, the gate's skip share and the tail it saves, as printed lines.
struct TidyGateReport {
    let rows: [TidyGateRow]

    /// Spoken words standing for a 5 s and a 30 s piece, at about two and a half words a second.
    static let shortPieceWords = 0...15
    static let longPieceWords = 60...Int.max

    var lines: [String] {
        var out = [
            "",
            "slice".padded(to: 18) + "n".padded(to: 6) + "rules".padded(to: 8) + "model".padded(to: 8)
                + "lift [95% interval]",
        ]
        func row(_ name: String, _ slice: [TidyGateRow]) {
            let lift = PassRateLift(base: slice.map(\.rulesPassed), candidate: slice.map(\.modelPassed))
            out.append(
                name.padded(to: 18) + "\(lift.cases)".padded(to: 6)
                    + Self.percent(lift.basePassRate).padded(to: 8)
                    + Self.percent(lift.candidatePassRate).padded(to: 8) + Self.signed(lift))
        }
        for cue in TidyCue.allCases { row("cue " + cue.rawValue, rows.filter { $0.cues.contains(cue) }) }
        row("no cue", rows.filter { $0.cues.isEmpty })
        for category in Set(rows.map(\.category)).sorted() {
            row(category, rows.filter { $0.category == category })
        }
        row("all", rows)

        let skipping = rows.count(where: { !$0.callsModel })
        let gated = PassRateLift(base: rows.map(\.modelPassed), candidate: rows.map(\.gatedPassed))
        out += [
            "",
            "gate: model only on a cue — skips \(skipping) of \(rows.count) (\(Self.percent(Self.share(skipping, rows.count)))); "
                + "pass \(Self.percent(gated.candidatePassRate)) against always-model \(Self.percent(gated.basePassRate)), "
                + "change \(Self.signed(gated))",
            "",
            "piece".padded(to: 18) + "n".padded(to: 6) + "skip".padded(to: 8) + "model p50/p95".padded(to: 18)
                + "gated p50/p95",
        ]
        for (name, range) in [
            ("~5 s", Self.shortPieceWords), ("~30 s", Self.longPieceWords), ("all", 0...Int.max),
        ] {
            let slice = rows.filter { range.contains($0.words) }
            let model = slice.map(\.modelSeconds)
            let gatedTimes = slice.map(\.gatedSeconds)
            out.append(
                name.padded(to: 18) + "\(slice.count)".padded(to: 6)
                    + Self.percent(Self.share(slice.count(where: { !$0.callsModel }), slice.count)).padded(
                        to: 8)
                    + "\(Self.seconds(model, 0.5))/\(Self.seconds(model, 0.95))".padded(to: 18)
                    + "\(Self.seconds(gatedTimes, 0.5))/\(Self.seconds(gatedTimes, 0.95))")
        }
        return out
    }

    static func share(_ part: Int, _ whole: Int) -> Double { whole == 0 ? 0 : Double(part) / Double(whole) }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    static func signed(_ lift: PassRateLift) -> String {
        let points = { (value: Double) in String(format: "%+.0f", value * 100) }
        guard let interval = lift.interval else { return points(lift.lift) }
        return "\(points(lift.lift)) [\(points(interval.lowerBound)), \(points(interval.upperBound))]"
    }

    /// The nearest-rank quantile in seconds, or a dash for an empty slice.
    static func seconds(_ values: [Double], _ fraction: Double) -> String {
        guard !values.isEmpty else { return "—" }
        let sorted = values.sorted()
        let rank = min(sorted.count - 1, max(0, Int((fraction * Double(sorted.count)).rounded(.up)) - 1))
        return String(format: "%.2fs", sorted[rank])
    }
}
