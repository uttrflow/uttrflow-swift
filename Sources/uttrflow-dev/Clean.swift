// The `clean` command: runs clean-up on typed text.
import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowEval

/// Cleans up text without recording anything, so the transformation can be judged on its own.
struct Clean: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Tidy a raw transcript, as if it had just been dictated."
    )

    @Argument(help: "The raw transcript. Reads standard input when omitted.")
    var text: String?

    @Option(name: .shortAndLong, help: "Force one transformer: foundationModels or rules.")
    var engine: String?

    // Context changes the output, so it has to be reachable from here without running the bake-off.
    @Option(name: .long, help: "Pretend the frontmost app is this one.")
    var app: String?

    @Option(name: .long, help: "Pretend the frontmost app has this bundle identifier.")
    var bundleID: String?

    @Option(name: .long, help: "Pretend the frontmost window is titled this.")
    var document: String?

    @Option(name: .long, help: "Pretend this text is selected on screen.")
    var selection: String?

    @Option(name: .long, help: "Pretend this text sits before the caret.")
    var before: String?

    // Being unsure is the condition for the screen's spelling to be offered, so it has to be sayable here.
    @Option(
        name: .long,
        help: "Pretend the recogniser was unsure of this run, word for word. Repeatable.")
    var doubtful: [String] = []

    @Flag(name: .long, help: "Also show the model's answer before anything unwraps or judges it.")
    var showModel = false

    func run() async throws {
        let raw = try readInput()
        guard !raw.isEmpty else { throw CleanExit.message("Nothing to clean.") }

        var configuration = EngineConfiguration.default
        if let engine {
            guard let kind = TransformerKind(rawValue: engine), TransformerKind.selectable.contains(kind)
            else {
                throw ValidationError(
                    "Unknown transformer '\(engine)'. Known: "
                        + TransformerKind.selectable.map(\.rawValue).joined(separator: ", ")
                )
            }
            configuration.transformerPreference = [kind]
        }

        let router = TextTransformers.router(configuration: configuration)
        let clock = ContinuousClock()
        let start = clock.now
        let context = AppContext(
            applicationName: app, bundleIdentifier: bundleID,
            documentName: document, selectedText: selection, precedingText: before
        )
        let request = try TransformationRequest(transcription: transcription(of: raw), context: context)
        let result = try await router.transform(request)
        let elapsed = start.duration(to: clock.now)
        let doubtfulSpans = await spans(in: request)

        print("  raw    \(raw)")
        // Printed from the context rather than the flags, so these are the lines the model is given.
        for line in PromptBuilder.standard.situationBlock(for: request.situation, doubtful: doubtfulSpans) {
            print("  seen   \(line)")
        }
        print("  as     \(request.situation.destination.rawValue)")
        print("  clean  \(result.text)")
        print("  by     \(result.producedBy.rawValue) in \(format(elapsed))s")
        if showModel {
            let builder = PromptBuilder.standard
            let spoken = CleaningPipeline.beforeModel.run(Draft(transcription: request.transcription)).text
            let answer = try await AppleFoundationCleanupModel().rewrite(
                builder.userPrompt(for: request, spoken: spoken, doubtful: doubtfulSpans),
                instructions: builder.instructions(for: request.situation.destination),
                kind: .foundationModels)
            print("  model  \(answer.replacingOccurrences(of: "\n", with: "⏎"))")
        }
    }

    /// The transcript as the recogniser would have reported it, scored word by word once a run is named doubtful.
    private func transcription(of raw: String) throws -> Transcription {
        guard !doubtful.isEmpty else { return Transcription(text: raw) }
        let spoken = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let unsure = try unsureWords(in: spoken)
        let words = spoken.enumerated().map {
            TranscribedWord(
                text: $1, confidence: unsure.contains($0) ? EvaluationCase.doubtfulConfidence : 1)
        }
        return Transcription(
            text: raw, segments: [TranscriptionSegment(text: raw, start: .zero, end: .zero, words: words)])
    }

    /// Where each named run falls, so the same word said elsewhere in the transcript stays certain.
    private func unsureWords(in spoken: [String]) throws -> Set<Int> {
        let runs = doubtful.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .filter { !$0.isEmpty }
        var refused: Set<Attempt> = []
        if let marked = placing(runs[...], in: spoken, around: [], refused: &refused) { return marked }
        if let missing = runs.first(where: { starts(of: $0, in: spoken).isEmpty }) {
            throw ValidationError(
                "The transcript does not read '\(missing.joined(separator: " "))' anywhere, so that cannot be "
                    + "a run the recogniser was unsure of. It has to match word for word.")
        }
        throw ValidationError(
            "Every named run is in the transcript, but they cannot all be given an occurrence of their own. "
                + "Name a run once per occurrence you mean.")
    }

    /// One occurrence per named run, none overlapping, searched so the order the runs were given cannot decide it.
    private func placing(
        _ runs: ArraySlice<[String]>, in spoken: [String], around taken: Set<Int>,
        refused: inout Set<Attempt>
    ) -> Set<Int>? {
        guard let run = runs.first else { return taken }
        // Runs that read alike reach the same arrangement by many paths, so a refusal is remembered, not retried.
        let attempt = Attempt(remaining: runs.startIndex, taken: taken)
        guard !refused.contains(attempt) else { return nil }
        for start in starts(of: run, in: spoken) where taken.isDisjoint(with: start..<(start + run.count)) {
            let next = taken.union(start..<(start + run.count))
            if let marked = placing(runs.dropFirst(), in: spoken, around: next, refused: &refused) {
                return marked
            }
        }
        refused.insert(attempt)
        return nil
    }

    /// Every place the transcript reads this run, whether or not another run has claimed it.
    private func starts(of run: [String], in spoken: [String]) -> [Int] {
        guard spoken.count >= run.count else { return [] }
        return (0...(spoken.count - run.count)).filter { Array(spoken[$0..<($0 + run.count)]) == run }
    }

    /// The runs the sources offer a reading for, recomputed here so the printed lines are the ones the model is given.
    private func spans(in request: TransformationRequest) async -> [DoubtfulSpan] {
        let draft = CleaningPipeline.beforeModel.run(Draft(transcription: request.transcription))
        return await DoubtfulWords.standard.spans(in: draft, for: request.situation)
    }

    private func readInput() throws -> String {
        if let text { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func format(_ duration: Duration) -> String {
        String(
            format: "%.2f",
            duration.inSeconds)
    }
}

/// A point the placement search has already stood at: the runs still to place, and the words already spoken for.
private struct Attempt: Hashable {
    let remaining: Int
    let taken: Set<Int>
}
