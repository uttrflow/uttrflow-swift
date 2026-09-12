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
        var marked: Set<Int> = []
        for run in doubtful {
            let wanted = run.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !wanted.isEmpty else { continue }
            // Naming a run twice marks its next occurrence, so a repeated run is sayable one occurrence at a time.
            let starts = spoken.count < wanted.count ? 0..<0 : 0..<(spoken.count - wanted.count + 1)
            let start = starts.first {
                Array(spoken[$0..<($0 + wanted.count)]) == wanted
                    && marked.isDisjoint(with: $0..<($0 + wanted.count))
            }
            guard let start else {
                throw ValidationError(
                    "The transcript has no unmarked run reading '\(run)', so it cannot be one the recogniser "
                        + "was unsure of. It has to match word for word.")
            }
            marked.formUnion(start..<(start + wanted.count))
        }
        return marked
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
