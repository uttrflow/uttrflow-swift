import ArgumentParser
import Foundation
import UttrflowEval
import UttrflowLocalModel
import UttrflowPredict

/// Runs the suggestion model over many differently sized moments, some cancelled, and reports MLX's GPU memory after each. See `Docs/performance-suggestions.md`.
struct GPUMemory: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gpu-memory",
        abstract: "Run varied suggestion passes, cancelling some, and print MLX's GPU memory after each."
    )

    @Option(name: .long, help: "How many passes to run.")
    var passes = 40

    @Option(name: .long, help: "Cancel every Nth pass part-way through; 0 cancels none.")
    var cancelEvery = 4

    @Flag(
        name: .long,
        help: "Release the model after the idle reading, report what is left, then time loading it again.")
    var release = false

    @Flag(
        name: .long,
        help:
            "Type one reply a character a pass under one screen of messages, as passes arrive while somebody types."
    )
    var typing = false

    @Flag(name: .long, help: "Print each pass's completions, so two builds can be compared line for line.")
    var show = false

    @Option(name: .long, help: "Which model to run, by repository or short name.")
    var model = LocalModel.gemma3.identifier

    /// How each invented line opens, so the typed text differs from pass to pass as well as the screen.
    private static let openings = [
        "Thanks for sending this over, I will ", "Could we move the review to ", "Sounds good, let",
    ]

    func validate() throws {
        guard passes >= 1 else { throw ValidationError("--passes must be 1 or more.") }
        guard cancelEvery >= 0 else { throw ValidationError("--cancel-every must be 0 or more.") }
    }

    func run() async throws {
        guard let chosen = LocalModel.named(model) else {
            throw ValidationError("Unknown model '\(model)'.")
        }
        let scorer = MLXCandidateScorer(model: chosen)
        try await scorer.prepare()
        print("loaded                    \(Self.row(GPUBufferCache.reading))")
        var times: [Int] = []
        var processor: [Int] = []
        var readings: [BudgetReading] = []
        for pass in 1...passes {
            let cancelled = cancelEvery > 0 && pass % cancelEvery == 0
            let before = Self.processorMilliseconds()
            let ((elapsed, lines), peak) = await PeakMemory.observed {
                await Self.measure(pass: pass, cancelled: cancelled, typing: typing, with: scorer)
            }
            let spent = Self.processorMilliseconds() - before
            processor.append(spent)
            if let peak {
                readings.append(
                    .init(
                        state: .suggestionsPassPeak, label: "pass \(pass)",
                        footprintBytes: peak.footprintBytes))
            }
            let settled = MemoryFootprint.current()
            if let settled {
                readings.append(
                    .init(
                        state: .suggestionsBetweenPasses, label: "after pass \(pass)", footprintBytes: settled
                    ))
            }
            if !cancelled { times.append(elapsed) }
            let kind = cancelled ? "cancelled" : "complete "
            let label =
                "pass \(String(pass).leftPadded(to: 3)) \(kind) \(String(elapsed).leftPadded(to: 5)) ms"
            print(
                Self.passLine(
                    label: label, processorMilliseconds: spent, memory: Self.row(GPUBufferCache.reading),
                    footprintBytes: settled))
            if show, !cancelled { print("  " + lines.debugDescription) }
        }
        try? await Task.sleep(for: .seconds(5))
        print("idle 5 s                  \(Self.row(GPUBufferCache.reading))  \(Self.footprint())")
        if release {
            await scorer.release()
            try? await Task.sleep(for: .seconds(1))
            print("released                  \(Self.row(GPUBufferCache.reading))  \(Self.footprint())")
            if let released = MemoryFootprint.current() {
                readings.append(
                    .init(state: .afterRelease, label: "a second after release", footprintBytes: released))
            }
            let reloading = ContinuousClock.now
            try await scorer.prepare()
            let reload = Int((ContinuousClock.now - reloading) / .milliseconds(1))
            print(
                "reloaded in \(String(reload).leftPadded(to: 5)) ms  \(Self.row(GPUBufferCache.reading))  \(Self.footprint())"
            )
        }
        let sorted = times.sorted()
        if !sorted.isEmpty {
            print(
                "complete passes: median \(sorted[sorted.count / 2]) ms, p95 \(sorted[sorted.count * 95 / 100]) ms, mean \(sorted.reduce(0, +) / sorted.count) ms"
            )
            print(
                "processor: \(processor.reduce(0, +) / processor.count) ms a pass over all \(processor.count) passes"
            )
        }
        try BudgetVerdict.enforce(readings)
    }

    /// Processor time this process has spent on every thread, in milliseconds.
    private static func processorMilliseconds() -> Int {
        Int(clock_gettime_nsec_np(CLOCK_PROCESS_CPUTIME_ID) / 1_000_000)
    }

    /// One generation pass, cancelled part-way when asked, then one score; returns the milliseconds both took and the lines generated.
    private static func measure(
        pass: Int, cancelled: Bool, typing: Bool, with scorer: MLXCandidateScorer
    ) async -> (Int, [String]) {
        let situation = GenerationSituation(
            application: "Mail", windowTitle: "Re: planning",
            surroundings: typing ? screen : thread(words: 120 + pass * 37 % 190),
            isMultiline: true)
        let typed =
            typing
            ? String(reply.prefix(12 + pass % (reply.count - 12)))
            : openings[pass % openings.count] + String(repeating: "and then ", count: pass % 5)
        let started = ContinuousClock.now
        let work = Task { try await scorer.completions(for: typed, in: situation) }
        if cancelled {
            try? await Task.sleep(for: .milliseconds(40 + pass * 13 % 120))
            work.cancel()
        }
        let lines = (try? await work.value) ?? []
        _ = await scorer.judgedTokens(of: typed + thread(words: 4 + pass % 23), following: typed)
        return (Int((ContinuousClock.now - started) / .milliseconds(1)), lines)
    }

    /// One screen of short messages, the same for every pass of a typed reply.
    private static let screen = (0..<14).map { "Sam: " + thread(words: 6 + $0 * 5 % 9) }.joined(
        separator: "\n")

    /// The reply typed a character a pass.
    private static let reply =
        "Thanks for sending the draft over, I will check whether the venue can hold everyone and send the agenda early next week"

    /// The process's footprint, which is what Activity Monitor shows.
    private static func footprint() -> String {
        "footprint \(String((MemoryFootprint.current() ?? 0) / 1_048_576).leftPadded(to: 6)) MB"
    }

    /// One pass's MLX counters and already-sampled settled process footprint.
    static func passLine(
        label: String, processorMilliseconds: Int, memory: String, footprintBytes: Int64?
    ) -> String {
        let footprint = footprintBytes.map { "\($0 / 1_048_576) MB" } ?? "unavailable"
        return
            "\(label)  cpu \(String(processorMilliseconds).leftPadded(to: 5)) ms  \(memory)  footprint \(footprint)"
    }

    /// Active, cache and peak memory in megabytes, in fixed columns.
    private static func row(_ reading: GPUMemoryReading) -> String {
        let columns = [("active", reading.active), ("cache", reading.cache), ("peak", reading.peak)]
        return columns.map { "\($0.0) \(String($0.1 / 1_048_576).leftPadded(to: 6)) MB" }.joined(
            separator: "  ")
    }

    /// An invented message thread of about this many words, so each pass reads a prompt of a different length.
    private static func thread(words count: Int) -> String {
        let words = [
            "the", "draft", "schedule", "for", "next", "week", "looks", "fine", "but", "we", "should",
            "check",
            "whether", "the", "venue", "can", "hold", "everyone", "and", "send", "the", "agenda", "early",
        ]
        return (0..<count).map { words[($0 * 7 + count) % words.count] }.joined(separator: " ")
    }
}
