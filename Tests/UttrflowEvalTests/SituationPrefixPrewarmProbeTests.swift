// Measures whether prewarming Apple's model with the situation lines as a prompt prefix shortens the first token.
import Foundation
import FoundationModels
import Testing
import UttrflowCore

@testable import UttrflowAI

/// Runs only with UTTRFLOW_PREFIX_PROBE=1, since it makes hundreds of live model calls.
@Suite("Situation prefix prewarm probe", .serialized)
struct SituationPrefixPrewarmProbeTests {
    static let environment = ProcessInfo.processInfo.environment
    static let enabled = environment["UTTRFLOW_PREFIX_PROBE"] == "1"
    static let warmRuns = Int(environment["UTTRFLOW_PREFIX_PROBE_RUNS"] ?? "") ?? 100
    static let idleRuns = Int(environment["UTTRFLOW_PREFIX_PROBE_IDLE_RUNS"] ?? "") ?? 0

    /// How the session is made before the request reaches it.
    enum Configuration: String, CaseIterable {
        case noPrewarm, instructionsOnly, situationPrefix
    }

    static let situation = Situation(
        app: AppContext(applicationName: "Mail", bundleIdentifier: "com.apple.mail"),
        insertion: InsertionPoint(precedingText: "Hi team, quick update on the release plan and"),
        destination: .email)

    static let utterances: [String: String] = [
        "10w": "um so the build is green now and we can ship",
        "40w": "so um basically the build is green now and I think we can ship it on Thursday "
            + "uh assuming the last two reviews come back clean and nobody finds anything new in the "
            + "settings window which honestly I doubt at this point",
    ]

    @Test("reports median and p95 first-token and total time per configuration", .enabled(if: enabled))
    func measure() async throws {
        guard #available(macOS 26, *) else { return }
        guard await AppleFoundationCleanupModel().availability(for: .english).isAvailable else { return }
        let builder = PromptBuilder.standard
        let instructions = builder.instructions(for: Self.situation.destination)
        let prefix = builder.situationBlock(for: Self.situation).joined(separator: "\n") + "\n"
        for (label, words) in Self.utterances.sorted(by: { $0.key < $1.key }) {
            let prompt = prefix + "Spoken: \"\(words)\""
            for (state, runs, idle) in [("warm", Self.warmRuns, 0), ("idle60s", Self.idleRuns, 60)]
            where runs > 0 {
                // Configurations interleave per run so machine load falls on all three alike.
                var firsts: [Configuration: [Double]] = [:]
                var totals: [Configuration: [Double]] = [:]
                var outputs: [Configuration: Set<String>] = [:]
                for _ in 0..<runs {
                    for configuration in Configuration.allCases {
                        if idle > 0 { try await Task.sleep(for: .seconds(idle)) }
                        let session = LanguageModelSession(instructions: instructions)
                        switch configuration {
                        case .noPrewarm: break
                        case .instructionsOnly: session.prewarm()
                        case .situationPrefix: session.prewarm(promptPrefix: Prompt(prefix))
                        }
                        // The pipeline warms at key-down, well before the first piece is ready.
                        try await Task.sleep(for: .seconds(1))
                        let start = ContinuousClock.now
                        var first: Duration?
                        var text = ""
                        let stream = session.streamResponse(
                            to: prompt, generating: CleanedDictation.self,
                            options: GenerationOptions(temperature: 0.0))
                        for try await snapshot in stream {
                            if first == nil, snapshot.content.text != nil {
                                first = ContinuousClock.now - start
                            }
                            text = snapshot.content.text ?? text
                        }
                        let total = ContinuousClock.now - start
                        firsts[configuration, default: []].append(Self.milliseconds(first ?? total))
                        totals[configuration, default: []].append(Self.milliseconds(total))
                        outputs[configuration, default: []].insert(text)
                    }
                }
                for configuration in Configuration.allCases {
                    let first = firsts[configuration] ?? []
                    let total = totals[configuration] ?? []
                    let texts = outputs[configuration] ?? []
                    Self.report(
                        "PREFIX-PROBE \(label) \(state) \(configuration.rawValue) n=\(runs) "
                            + "first p50=\(Self.percentile(first, 0.5)) p95=\(Self.percentile(first, 0.95)) "
                            + "total p50=\(Self.percentile(total, 0.5)) p95=\(Self.percentile(total, 0.95)) "
                            + "distinctOutputs=\(texts.count) | \(texts.sorted().joined(separator: " || "))")
                }
            }
        }
    }

    /// Writes unbuffered, so a run cut short still leaves every finished row.
    static func report(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func percentile(_ values: [Double], _ fraction: Double) -> Int {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        return Int(
            sorted[min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))].rounded())
    }
}
