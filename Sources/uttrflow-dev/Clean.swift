// The `clean` command: runs clean-up on typed text.
import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowDictionary
import UttrflowEval
import UttrflowPipeline

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

    @Flag(
        name: .long,
        help: "Also ask the on-device model and print every guard check's verdict on its finished answer.")
    var explain = false

    // Joining and the dictionary run only in the pipeline, so either one sends the transcript through it.
    @Flag(
        name: .long,
        help: "Cut the transcript into pieces at each '|', as pauses do, and clean it as a dictation does.")
    var pieces = false

    @Option(
        name: .long,
        help:
            "Pretend the personal dictionary holds this word, written word or word=how it sounds. Repeatable."
    )
    var dictionary: [String] = []

    func validate() throws {
        guard explain, pieces || !dictionary.isEmpty else { return }
        throw ValidationError(
            "--explain judges one transcript whole; it does not combine with --pieces or --dictionary.")
    }

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
        let context = AppContext(
            applicationName: app, bundleIdentifier: bundleID,
            documentName: document, selectedText: selection, precedingText: before
        )
        if pieces || !dictionary.isEmpty {
            try await cleanAsDictation(raw, by: router, seeing: context)
            return
        }
        let clock = ContinuousClock()
        let start = clock.now
        let request = try TransformationRequest(
            transcription: transcriptions(of: [raw])[0], context: context)
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
            let spoken = CleaningPipeline.beforeModel(
                for: .standard(for: request.situation), situation: request.situation
            ).run(Draft(transcription: request.transcription)).text
            let answer = try await AppleFoundationCleanupModel().rewrite(
                builder.userPrompt(for: request, spoken: spoken, doubtful: doubtfulSpans),
                instructions: builder.instructions(for: request.situation.destination),
                kind: .foundationModels)
            print("  model  \(answer.replacingOccurrences(of: "\n", with: "⏎"))")
        }
        if explain { try await explainGuard(request) }
    }

    /// Prints the on-device model's answer and each guard check's verdict on it, as the transformer judges it.
    private func explainGuard(_ request: TransformationRequest) async throws {
        guard
            let model = TextTransformers.all().lazy.compactMap({ $0 as? GenerativeTextTransformer })
                .first(where: { $0.kind == .foundationModels })
        else { throw CleanExit.message("This build has no on-device model to explain.") }
        let judged = try await model.explainGuard(request)
        print("  answer \(judged.answer.replacingOccurrences(of: "\n", with: "⏎"))")
        print("  judged \(judged.finished.replacingOccurrences(of: "\n", with: "⏎"))")
        let width = judged.checks.map(\.name.count).max() ?? 0
        for check in judged.checks {
            let name = check.name.padding(toLength: width, withPad: " ", startingAt: 0)
            switch check.verdict {
            case .accepted: print("  check  \(name)  passed")
            case .rejected(let reason, let kind): print("  check  \(name)  refused (\(kind)): \(reason)")
            }
        }
    }

    /// Runs the pieces through the dictation pipeline's own clean-up, printing each piece and then the whole.
    private func cleanAsDictation(
        _ raw: String, by cleaner: any TranscriptCleaning, seeing context: AppContext
    ) async throws {
        let said = pieces ? raw.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) } : [raw]
        guard !said.contains(where: \.isEmpty) else {
            throw ValidationError("A piece between two '|' is empty; every piece needs words.")
        }
        let index = PhoneticIndex(entries: try dictionaryEntries())
        let pipeline = DictationPipeline(
            capture: PlaybackCaptureEngine(audio: .empty, sharesEarly: false), speech: NoRecogniser(),
            cleaner: cleaner, context: FixedScreen(context: context), inserter: PrintingInserter(),
            corrector: DictionaryCorrections { index })
        let cleaned = await pipeline.clean(try transcriptions(of: said), seeing: context)

        print("  raw    \(raw)")
        print("  as     \(SituationResolver.resolve(from: context).destination.rawValue)")
        for (number, piece) in cleaned.pieces.enumerated() {
            print("  piece \(number + 1) \(piece)")
        }
        print("  clean  \(cleaned.text ?? "(nothing writable, refused as silence)")")
    }

    /// The entries named on the command line, each written as the user would type it into Settings.
    private func dictionaryEntries() throws -> [DictionaryEntry] {
        try dictionary.map { named in
            let parts = named.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let word = parts[0]
            let sound = parts.count > 1 && !parts[1].isEmpty ? parts[1] : nil
            guard !word.isEmpty, PhoneticIndex.supports(word: word, pronunciation: sound) else {
                throw ValidationError("'\(named)' is not a dictionary entry the app would accept.")
            }
            return DictionaryEntry(word: word, pronunciation: sound, origin: .added, firstSeen: Date())
        }
    }

    /// Each piece as the recogniser would have reported it, scored word by word once a run or the dictionary needs it.
    private func transcriptions(of said: [String]) throws -> [Transcription] {
        // An unscored transcript gets no dictionary corrections, so a dictionary alone scores every word certain.
        guard !doubtful.isEmpty || !dictionary.isEmpty else { return said.map { Transcription(text: $0) } }
        let spoken = said.map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
        // Placed across the whole transcript, so a run may straddle a pause as speech can.
        let unsure = doubtful.isEmpty ? [] : try unsureWords(in: spoken.flatMap { $0 })
        var offset = 0
        return zip(said, spoken).map { text, words in
            let scored = words.enumerated().map {
                TranscribedWord(
                    text: $1,
                    confidence: unsure.contains(offset + $0) ? EvaluationCase.doubtfulConfidence : 1)
            }
            offset += words.count
            return Transcription(
                text: text,
                segments: [TranscriptionSegment(text: text, start: .zero, end: .zero, words: scored)])
        }
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
        let draft = CleaningPipeline.beforeModel(
            for: .standard(for: request.situation), situation: request.situation
        ).run(Draft(transcription: request.transcription))
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

/// A recogniser for a pipeline that is only ever handed words, never audio.
struct NoRecogniser: SpeechEngine {
    let kind = SpeechEngineKind.whisperKit

    func prepare() async throws(SpeechEngineError) {}

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        throw .nothingHeard
    }
}

/// A point the placement search has already stood at: the runs still to place, and the words already spoken for.
private struct Attempt: Hashable {
    let remaining: Int
    let taken: Set<Int>
}
