// Measures what a minute idle costs Apple's model, and whether a real request at key-down wins it back.
import Foundation
import FoundationModels
import Testing
import UttrflowCore

@testable import UttrflowAI

/// Runs only with UTTRFLOW_COLD_PROBE=1, since each idle run waits more than a minute on a live model.
@Suite("Idle cold tidy probe", .serialized)
struct IdleColdTidyProbeTests {
    static let environment = ProcessInfo.processInfo.environment
    static let enabled = environment["UTTRFLOW_COLD_PROBE"] == "1"
    static let runs = Int(environment["UTTRFLOW_COLD_PROBE_RUNS"] ?? "") ?? 4
    static let idleSeconds = Int(environment["UTTRFLOW_COLD_PROBE_IDLE"] ?? "") ?? 65
    /// The recording between key-down and the first piece; the issue's shortest clip is about 1.7 s.
    static let headStart = Double(environment["UTTRFLOW_COLD_PROBE_HEAD_START"] ?? "") ?? 2

    /// How the session is made at key-down, before the request reaches it.
    enum Configuration: String, CaseIterable {
        /// What shipped: a fresh session and `prewarm()`.
        case prewarmOnly
        /// The model's own residency is restored by a one-token answer on a throwaway session first.
        case respondThenPrewarm
    }

    static let prompt = "Spoken: \"um can you send me the report today\""

    @Test("reports a prompt's token count after a minute idle against warm", .enabled(if: enabled))
    func measureTokenizer() async throws {
        guard #available(macOS 26.4, *) else { return }
        guard await AppleFoundationCleanupModel().availability(for: .english).isAvailable else { return }
        var counts: [String: [Double]] = [:]
        for run in 0..<Self.runs {
            try await Task.sleep(for: .seconds(Self.idleSeconds))
            for state in ["cold", "warm"] {
                let start = ContinuousClock.now
                _ = try await SystemLanguageModel.default.tokenCount(for: Prompt(Self.prompt + " \(run)\(state)"))
                counts[state, default: []].append(Self.milliseconds(ContinuousClock.now - start))
            }
        }
        for (label, values) in counts.sorted(by: { $0.key < $1.key }) {
            Self.report(
                "COLD-PROBE tokenCount idle=\(Self.idleSeconds)s \(label) n=\(values.count) "
                    + "p50=\(Self.percentile(values, 0.5)) p95=\(Self.percentile(values, 0.95)) ms")
        }
    }

    @Test("reports the tidy after a minute idle per key-down configuration, and warm", .enabled(if: enabled))
    func measure() async throws {
        guard #available(macOS 26, *) else { return }
        guard await AppleFoundationCleanupModel().availability(for: .english).isAvailable else { return }
        let instructions = PromptBuilder.standard.instructions(for: .plain)
        var totals: [String: [Double]] = [:]
        var warmUps: [Double] = []
        for _ in 0..<Self.runs {
            // Configurations interleave per run so machine load falls on both alike.
            for configuration in Configuration.allCases {
                try await Task.sleep(for: .seconds(Self.idleSeconds))
                let keyDown = ContinuousClock.now
                let warmUp = Task { () -> Double in
                    if configuration == .respondThenPrewarm {
                        let start = ContinuousClock.now
                        _ = try? await LanguageModelSession().respond(
                            to: "Say ok.", options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 1))
                        return Self.milliseconds(ContinuousClock.now - start)
                    }
                    return 0
                }
                let session = LanguageModelSession(instructions: instructions)
                session.prewarm()
                try await Task.sleep(until: keyDown + .seconds(Self.headStart))
                totals[configuration.rawValue, default: []].append(try await Self.tidy(session))
                let spent = await warmUp.value
                if configuration == .respondThenPrewarm { warmUps.append(spent) }
                // A warm tidy straight after, on the same machine load, is the target.
                let warm = LanguageModelSession(instructions: instructions)
                warm.prewarm()
                try await Task.sleep(for: .seconds(Self.headStart))
                totals["warm", default: []].append(try await Self.tidy(warm))
            }
        }
        for (label, values) in totals.sorted(by: { $0.key < $1.key }) {
            Self.report(
                "COLD-PROBE idle=\(Self.idleSeconds)s \(label) n=\(values.count) "
                    + "p50=\(Self.percentile(values, 0.5)) p95=\(Self.percentile(values, 0.95)) ms")
        }
        Self.report(
            "COLD-PROBE warm-up respond p50=\(Self.percentile(warmUps, 0.5)) "
                + "p95=\(Self.percentile(warmUps, 0.95)) ms")
    }

    /// The milliseconds one tidy takes, from the request to the whole answer.
    @available(macOS 26, *)
    static func tidy(_ session: LanguageModelSession) async throws -> Double {
        let start = ContinuousClock.now
        _ = try await session.respond(
            to: prompt, generating: CleanedDictation.self,
            options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 64))
        return milliseconds(ContinuousClock.now - start)
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
