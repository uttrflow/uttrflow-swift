// The `burst` command: sends bursts of pieces to Apple's model and counts how many it throttles.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowCore
private import UttrflowEval

/// Sends dictation-sized pieces in bursts, as a long or repeated dictation does, and reports rate limits.
struct Burst: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send bursts of pieces to Apple's model and count the requests it throttles."
    )

    @Option(name: .shortAndLong, help: "How many dictations to send.")
    var bursts: Int = 50

    @Option(name: .shortAndLong, help: "How many pieces each dictation sends.")
    var pieces: Int = 5

    @Option(help: "Seconds between one dictation's last answer and the next dictation.")
    var gap: Double = 0

    @Flag(help: "Send a dictation's pieces all at once instead of one after another.")
    var concurrent = false

    /// Ordinary pieces of speech, invented, so the model's work is the size a real piece is.
    private static let said = [
        "so um the meeting moved to thursday because the room was booked",
        "can you send me the notes from last week when you get a chance",
        "i think we should ship the smaller change first and then measure it",
        "the build is green now but the test for the parser still takes too long",
        "let me know if the draft reads well or if it needs another pass",
    ]

    func validate() throws {
        guard (1...1_000).contains(bursts) else { throw ValidationError("--bursts must be 1 to 1000.") }
        guard (1...50).contains(pieces) else { throw ValidationError("--pieces must be 1 to 50.") }
        guard (0...600).contains(gap) else { throw ValidationError("--gap must be 0 to 600.") }
    }

    func run() async throws {
        let instructions = PromptBuilder.standard.instructions(for: .document)
        var tally = ModelBurstTally()
        print("Sending \(bursts) dictations of \(pieces) pieces, \(concurrent ? "at once" : "in a row")…\n")
        for burst in 1...bursts {
            for request in await send(burst: burst, instructions: instructions) { tally.record(request) }
            let throttled = tally.requests.count { $0.burst == burst && $0.failure == .rateLimited }
            print("  \(String(burst).leftPadded(to: 4))  throttled \(throttled) of \(pieces)")
            if gap > 0 { try await Task.sleep(for: .seconds(gap)) }
        }
        report(tally)
    }

    /// One dictation's pieces, timed and classified.
    private func send(burst: Int, instructions: String) async -> [ModelBurstTally.Request] {
        let texts = (0..<pieces).map { Self.said[$0 % Self.said.count] }
        guard concurrent else {
            var sent: [ModelBurstTally.Request] = []
            for (index, text) in texts.enumerated() {
                sent.append(
                    await Self.request(text, burst: burst, piece: index + 1, instructions: instructions))
            }
            return sent
        }
        return await withTaskGroup(of: ModelBurstTally.Request.self) { group in
            for (index, text) in texts.enumerated() {
                group.addTask {
                    await Self.request(text, burst: burst, piece: index + 1, instructions: instructions)
                }
            }
            return await group.reduce(into: []) { $0.append($1) }.sorted { $0.piece < $1.piece }
        }
    }

    /// One request to the model, as the app's clean-up sends it.
    private static func request(
        _ text: String, burst: Int, piece: Int, instructions: String
    ) async -> ModelBurstTally.Request {
        let clock = ContinuousClock()
        let start = clock.now
        var failure: ModelFailureClass?
        do {
            _ = try await AppleFoundationCleanupModel().rewrite(
                text, instructions: instructions, kind: .foundationModels)
        } catch {
            if case .transformFailed(_, let reason) = error { failure = reason } else { failure = .other }
        }
        return ModelBurstTally.Request(
            burst: burst, piece: piece, duration: start.duration(to: clock.now), failure: failure)
    }

    private func report(_ tally: ModelBurstTally) {
        let durations = tally.requests.map(\.duration)
        let summary = DurationSummary.over(durations, failures: tally.failuresByClass.values.reduce(0, +))
        print("\n  requests          \(tally.requests.count)")
        print("  rate limited      \(tally.rateLimited) (\(tally.rateLimitedPerThousand ?? 0) per 1,000)")
        print("  first throttled   \(tally.firstThrottledPiece.map { "piece \($0)" } ?? "none")")
        for (failure, count) in tally.failuresByClass.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            print("  failed            \(failure.rawValue) \(count)")
        }
        if let summary {
            print("  typical / slowest \(Self.seconds(summary.typical)) / \(Self.seconds(summary.slowest))")
        }
    }

    /// A duration as seconds to two places.
    private static func seconds(_ duration: Duration) -> String {
        String(
            format: "%.2f s",
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }
}
