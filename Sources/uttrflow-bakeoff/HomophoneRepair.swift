import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowDictionary
import UttrflowEval
import UttrflowLocalModel

/// Prints each clean-up engine's homophone repair and harm rate per decider tag; see `Docs/eval-methodology.md`.
struct HomophoneRepair: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "homophones",
        abstract: "Print repair and harm rates per decider tag over the generated homophone cases."
    )

    @Option(
        name: .long, help: "Comma-separated local models to add to the rules, Apple and shipping engines.")
    var models: String?

    @Option(name: .long, help: "Score only the first N cases, for a quick run.")
    var limit: Int?

    func run() async throws {
        let classes = Self.classes(of: HomophoneCarriers.all)
        let all = HomophoneCaseSet.cases(classes: classes)
        let cases = limit.map { Array(all.prefix($0)) } ?? all
        print("Homophone repair — \(cases.count) of \(all.count) cases, \(classes.count) classes")
        print("engine".padded(to: 26) + "decider".padded(to: 9) + "cases".padded(to: 7) + "repair  harm")

        for engine in TextTransformers.all() {
            await report(String(describing: engine.kind), cases) { request in
                guard await engine.availability(for: request).isAvailable else { return nil }
                return try await engine.transform(request).text
            }
        }
        let shipping = TextTransformers.router(configuration: .default)
        await report("shipping", cases) { try await shipping.transform($0).text }

        for name in models.map({ $0.split(separator: ",").map(String.init) }) ?? [] {
            guard let model = LocalModel.named(name) else {
                throw CleanExit.message("Unknown model '\(name)'.")
            }
            let scorer = MLXCandidateScorer(model: model)
            do {
                try await scorer.prepare { _ in }
            } catch {
                print("\(name.padded(to: 26))could not load: \(error)")
                continue
            }
            let local = TextTransformers.local(scorer)
            await report(name, cases) { request in
                guard await local.availability(for: request).isAvailable else { return nil }
                return try await local.transform(request).text
            }
        }
    }

    /// The hand-kept class of every carrier's spelling, once each.
    static func classes(of carriers: [HomophoneCarrier]) -> [[String]] {
        var seen: [[String]] = []
        for carrier in carriers {
            if let group = Homophones.group(containing: carrier.spelling), !seen.contains(group) {
                seen.append(group)
            }
        }
        return seen
    }

    /// Runs one engine on each case's wrong and meant sentence and prints a row per decider tag; a throw changes nothing.
    private func report(
        _ name: String, _ cases: [HomophoneCase],
        _ tidy: (TransformationRequest) async throws -> String?
    ) async {
        var outcomes: [HomophoneOutcome] = []
        var declined = 0
        for homophoneCase in cases {
            func output(_ text: String) async -> String {
                let request = TransformationRequest(transcription: Transcription(text: text))
                guard let written = try? await tidy(request) else {
                    declined += 1
                    return text
                }
                return written
            }
            let fromInput = await output(homophoneCase.input)
            let fromExpected = await output(homophoneCase.expected)
            outcomes.append(HomophoneOutcome(homophoneCase, fromInput: fromInput, fromExpected: fromExpected))
        }
        for row in HomophoneRepairRates.rows(outcomes) {
            print(
                name.padded(to: 26) + row.decider.rawValue.padded(to: 9) + "\(row.cases)".padded(to: 7)
                    + String(format: "%5.1f%%  %5.1f%%", row.repairRate * 100, row.harmRate * 100))
        }
        if declined > 0 {
            print("\(name.padded(to: 26))declined or failed \(declined) of \(cases.count * 2) runs")
        }
    }
}
