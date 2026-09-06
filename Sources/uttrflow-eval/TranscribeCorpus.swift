// The `transcribe` command: measures a recogniser against the recorded corpus.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval
private import UttrflowSpeech

/// Measures a recogniser against the recorded corpus and gates it. See Docs/eval-methodology.md.
struct TranscribeCorpus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe",
        abstract: "Score a recogniser against the recorded corpus."
    )

    @Option(name: .long, help: "Where the recorded corpus lives.")
    var corpusPath = TranscriptionCorpusStore.defaultDirectoryName

    @Option(name: .long, help: "Where results are kept between runs.")
    var resultsPath = ".uttrflow-eval"

    @Option(name: .shortAndLong, help: "Recogniser to use: whisperKit or appleSpeech.")
    var engine = SpeechEngineKind.whisperKit.rawValue

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    /// Off by default because the product detects the language rather than being told it.
    @Flag(name: .long, help: "Tell the engine each passage's language instead of letting it detect.")
    var hintLanguage = false

    /// Times the recogniser plus clean-up, which is what the user waits for.
    @Flag(name: .long, help: "Also run clean-up, so the whole shipping path is timed.")
    var shipping = false

    @Flag(name: .long, help: "Print what has already been measured and stop.")
    var summarise = false

    @Flag(name: .long, help: "Show every passage's transcript and word-level diff.")
    var verbose = false

    @OptionGroup var connection: CorpusConnection

    /// Measures the backend catalogue with the same runner and report as the local recordings.
    @Flag(name: .long, help: "Measure the corpus catalogue from the backend instead of the local recordings.")
    var fromCatalogue = false

    @Option(name: .long, help: "How many recurring findings to print.")
    var findings = 20

    @Option(name: .long, help: "How many individual passages to list, worst first.")
    var passageLimit = 25

    @Option(name: .long, help: "Compare with a stored baseline at this path.")
    var baseline: String?

    /// Writes the baseline only on request, so the gate never compares a change with itself.
    @Flag(name: .long, help: "Write this run to --baseline as the new point of comparison.")
    var saveBaseline = false

    @Flag(name: .long, help: "Exit non-zero when any slice has got worse. For CI.")
    var failOnRegression = false

    @Option(name: .long, help: "How many percentage points a rate may move before it counts.")
    var tolerance = 0.5

    func validate() throws {
        if saveBaseline || failOnRegression, baseline == nil {
            throw ValidationError("--save-baseline and --fail-on-regression need --baseline <path>.")
        }
        guard SpeechEngineKind(rawValue: engine) != nil else {
            throw ValidationError(
                "Unknown engine '\(engine)'. Known: "
                    + SpeechEngineKind.allCases.map(\.rawValue).joined(separator: ", "))
        }
    }

    func run() async throws {
        guard let kind = SpeechEngineKind(rawValue: engine) else { return }
        let model = try resolveModel()
        let results = JSONRecordStore<PassageScore>(directory: URL(fileURLWithPath: resultsDirectory()))

        if summarise {
            // Stored results come back in file-system order, so they are put back into corpus order.
            let stored = TranscriptionCorpus.inCorpusOrder(try results.all())
            try compare(reporting: TranscriptionReport(label: label(model), scores: stored))
            return
        }

        let source = try await source()
        let recordings = source.recordings
        guard !recordings.isEmpty else {
            throw CleanExit.message(
                "Nothing to measure. Run: uttrflow-eval record   (or: uttrflow-eval pull --backend …)")
        }

        let speech = try await prepared(kind: kind, model: model)
        let router: (any TranscriptCleaning)? = shipping ? TextTransformers.router() : nil
        let metrics = CollectingMetricsRecorder()
        let clock = ContinuousClock()

        print("Measuring \(recordings.count) passages with \(label(model))…")
        let measured = await TranscriptionRunner().run(
            label: label(model),
            over: recordings,
            onScore: { score in
                Terminal.show(".")
                do { try results.save(score) } catch { print("\n  ! could not save \(score.id): \(error)") }
            }
        ) { recording in
            await measure(
                recording, with: speech, router: router, metrics: metrics, clock: clock,
                audioAt: source.audioURL)
        }
        Terminal.clearLine()

        try compare(reporting: measured)
    }

    // MARK: Where the audio comes from

    /// The recordings to measure and the directory holding each one's audio.
    private struct Source {
        let recordings: [RecordedPassage]
        let audioURL: @Sendable (String) -> URL
    }

    private func source() async throws -> Source {
        guard fromCatalogue else {
            let corpus = TranscriptionCorpusStore(directory: URL(fileURLWithPath: corpusPath))
            let missing = corpus.remaining()
            if !missing.isEmpty {
                print(
                    "Note: \(counted(missing.count, "passage")) never recorded — "
                        + missing.map(\.id).joined(separator: ", "))
            }
            return Source(recordings: try corpus.all(), audioURL: { corpus.audioURL(for: $0) })
        }

        let library = try connection.library()
        let samples: [CorpusSample]
        do {
            samples = try await library.samples()
        } catch {
            throw CleanExit.message("\(error)")
        }
        let held = library.held(of: samples)
        guard held.cached == samples.count else {
            // Refuses rather than downloads: a fetch inside a measurement run puts broadband in the latency.
            throw CleanExit.message(
                "\(samples.count - held.cached) of \(samples.count) samples are not on this Mac yet. "
                    + "Run: uttrflow-eval pull --backend …")
        }
        let cache = CorpusCache(directory: URL(fileURLWithPath: connection.cachePath))
        return Source(
            recordings: samples.map(recorded), audioURL: { cache.audioURL(for: $0) })
    }

    /// A catalogue sample as the runner wants it; `recordedAt` is the run time, the catalogue has none.
    private func recorded(_ sample: CorpusSample) -> RecordedPassage {
        RecordedPassage(
            passage: sample.passage, recordedAt: Date(),
            durationSeconds: Double(sample.durationMs) / 1000, sampleRate: sample.sampleRateHz,
            cohort: sample.cohort.map { RecordingCohort(id: $0, speaker: $0, setting: "from the catalogue") })
    }

    // MARK: Measuring one passage

    private func measure(
        _ recording: RecordedPassage,
        with speech: any SpeechEngine,
        router: (any TranscriptCleaning)?,
        metrics: CollectingMetricsRecorder,
        clock: ContinuousClock,
        audioAt audioURL: @Sendable (String) -> URL
    ) async -> TranscriptionRunner.Attempt {
        let audio: AudioSamples
        do {
            audio = try AudioFileReader.read(contentsOf: audioURL(recording.id))
        } catch {
            // Not timed as capture: reading a file off disk is not what the microphone costs.
            return .failed(.audioUnreadable(error.userMessage), stages: await metrics.drain())
        }

        let options = TranscriptionOptions(
            languageHint: hintLanguage ? recording.passage.language.code : nil)
        let transcription: Transcription
        do {
            // The thrown type is spelled out so `measuring` keeps the engine's error, not `any Error`.
            transcription = try await metrics.measuring(.transcription, clock: clock) {
                () async throws(SpeechEngineError) -> Transcription in
                try await speech.transcribe(audio, options: options)
            }
        } catch {
            return .failed(.engineFailed(error.userMessage), stages: await metrics.drain())
        }

        if let router {
            // Timed but not scored: clean-up changes the words on purpose. See Docs/eval-methodology.md.
            _ = try? await metrics.measuring(.transformation, clock: clock) {
                try await router.clean(TransformationRequest(transcription: transcription))
            }
        }
        return .transcribed(transcription.text, stages: await metrics.drain())
    }

    private func prepared(kind: SpeechEngineKind, model: SpeechModel) async throws -> any SpeechEngine {
        let store = FileSystemSpeechModelStore.whisperKit()
        if kind == .whisperKit, !store.isInstalled(model) {
            throw CleanExit.message("\(model.variant) is not installed. Run: uttrflow-dev models install")
        }
        let speech = SpeechEngineFactory.make(
            kind: kind, model: model, modelFolder: store.location(of: model))
        let clock = ContinuousClock()
        let start = clock.now
        try await speech.prepare()
        // Reported on its own: model loading is paid once at launch, not per passage.
        print("engine ready in \(seconds(start.duration(to: clock.now)))s")
        return speech
    }

    // MARK: The regression gate

    /// Prints the run, then says whether it is better or worse than the stored baseline.
    private func compare(reporting measured: TranscriptionReport) throws {
        report(measured)
        guard let baseline else { return }

        let url = URL(fileURLWithPath: baseline)
        if saveBaseline {
            try AccuracyBaseline.capture(measured).write(to: url)
            print("\nBaseline written to \(baseline). Later runs are measured against it.")
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CleanExit.message(
                "No baseline at \(baseline). Write one with --save-baseline once you are happy "
                    + "with these numbers.")
        }

        let stored = try AccuracyBaseline.read(from: url)
        let comparison = stored.compare(
            with: measured, tolerance: RegressionTolerance(percentagePoints: tolerance))
        printComparison(comparison, against: stored)

        if failOnRegression, comparison.isRegression { throw ExitCode.failure }
    }

    private func printComparison(_ comparison: BaselineComparison, against baseline: AccuracyBaseline) {
        print(
            "\n\nAgainst the baseline taken "
                + baseline.recordedAt.formatted(date: .abbreviated, time: .shortened)
                + " (\(baseline.label))")
        if let reason = comparison.reason {
            print("  no verdict: \(reason)")
            return
        }

        printChanges("overall", [comparison.overall])
        printChanges("by language", comparison.byLanguage)
        printChanges("by stress", comparison.byStress)
        printChanges("by cohort", comparison.byCohort)

        if !comparison.added.isEmpty || !comparison.removed.isEmpty {
            print(
                "\n  measured over the \(comparison.overall.referenceWordCount) words the two runs "
                    + "share: \(comparison.added.count) sample(s) are new since the baseline and "
                    + "\(comparison.removed.count) have gone.")
        }
        if !comparison.newlyUnscorable.isEmpty {
            print(
                "\n  \(comparison.newlyUnscorable.count) sample(s) used to produce a transcript and "
                    + "now produce nothing: "
                    + comparison.newlyUnscorable.prefix(5).joined(separator: ", "))
        }
        printMoved("worse", comparison.regressed)
        printMoved("better", comparison.improved)

        print("\nverdict: \(comparison.verdict.rawValue)")
    }

    private func printChanges(_ heading: String, _ changes: [BaselineComparison.Change]) {
        guard !changes.isEmpty else { return }
        print(
            "\n" + heading.padded(to: 22) + "was".padded(to: 9) + "now".padded(to: 9)
                + "change".padded(to: 10) + "words")
        for change in changes {
            let movement = change.delta.map { String(format: "%+.1f pp", $0 * 100) } ?? "n/a"
            print(
                change.label.padded(to: 22) + percent(change.before).padded(to: 9)
                    + percent(change.after).padded(to: 9) + movement.padded(to: 10)
                    + "\(change.referenceWordCount)"
                    + (change.isUnderpowered ? "  (too few words to judge)" : "")
                    + (change.verdict == .worsened ? "  ← worse" : ""))
        }
    }

    /// Prints the individual samples that moved, capped, as evidence for the verdict.
    private func printMoved(_ direction: String, _ changes: [BaselineComparison.Change]) {
        guard !changes.isEmpty else { return }
        print("\n  \(changes.count) sample(s) \(direction), worst first:")
        for change in changes.prefix(10) {
            print(
                "    " + change.label.padded(to: 26) + percent(change.before).padded(to: 9) + "→ "
                    + percent(change.after))
        }
        if changes.count > 10 { print("    and \(changes.count - 10) more") }
    }

    // MARK: Reporting

    private func report(_ report: TranscriptionReport) {
        guard !report.scores.isEmpty else {
            print("Nothing measured yet.")
            return
        }

        print("\n\(report.label) — \(report.scores.count) passages\n")
        printNormalisation(report)
        printRates(report)
        printFindings(report)
        printLatency(report)
        printFailures(report)
        printPassages(report)
    }

    /// Prints the normalisation rules before the numbers, because a rate means nothing without them.
    private func printNormalisation(_ report: TranscriptionReport) {
        print("Normalisation applied to both sides")
        for rule in report.normalisation { print("  · \(rule.explanation)") }
        if report.hasMixedNormalisation {
            print(
                "  ! these passages were not all measured under the same rules — re-run without --summarise")
        }
        print("")
    }

    private func printRates(_ report: TranscriptionReport) {
        let overall = report.overall
        print(
            "Word error rate  \(percent(overall.rate))   "
                + "\(overall.substitutions) substituted, \(overall.deletions) deleted, "
                + "\(overall.insertions) inserted over \(overall.referenceWordCount) words\n")

        printSlices("by language", report.byLanguage, width: 16)
        printSlices("by stress", report.byStress, width: 22)
        print(
            "  rows overlap: a sample stressing two things is counted under both, so these\n"
                + "  do not sum to the corpus.")

        printSlices("by cohort", report.byCohort, width: 22)

        let devanagari = report.answeredInDevanagari
        if !devanagari.isEmpty {
            print(
                "\n\(counted(devanagari.count, "passage")) came back in Devanagari. Uttrflow's output is "
                    + "romanised Hinglish, so\nthose transcripts are scored against the Devanagari "
                    + "reading of the passage — the recogniser\nheard them, and romanising them is "
                    + "clean-up's job, measured separately.")
        }
        let upperBounds = report.upperBounds
        if !upperBounds.isEmpty {
            print(
                "\n\(counted(upperBounds.count, "passage")) had no reference in the script they came back "
                    + "in and were transliterated:\ntheir rates are upper bounds — "
                    + upperBounds.map(\.caseID).joined(separator: ", "))
        }
    }

    /// Prints one breakdown, each slice with the word count it rests on.
    private func printSlices(_ heading: String, _ slices: [ReportSlice], width: Int) {
        guard !slices.isEmpty else { return }
        print(
            "\n" + heading.padded(to: width) + "WER".padded(to: 9) + "words".padded(to: 8)
                + "passages")
        for slice in slices {
            print(
                slice.label.padded(to: width) + percent(slice.rate.rate).padded(to: 9)
                    + "\(slice.referenceWordCount)".padded(to: 8) + "\(slice.passages)")
        }
    }

    /// Prints the failures that keep happening as findings rather than as rows.
    private func printFindings(_ report: TranscriptionReport) {
        let (shown, hiddenOccurrences, hidden) = report.topFindings(findings)
        guard !shown.isEmpty else {
            print("\nNothing went wrong anywhere. Check the corpus is really being read.")
            return
        }
        print("\nrecurring findings".padded(to: 46) + "times".padded(to: 8) + "samples")
        for finding in shown {
            let seenIn =
                finding.samples.prefix(3).joined(separator: ", ")
                + (finding.sampleCount > 3 ? ", +\(finding.sampleCount - 3)" : "")
            print(
                finding.signature.description.truncated(to: 44).padded(to: 46)
                    + "\(finding.occurrences)".padded(to: 8) + seenIn)
        }
        if hidden > 0 {
            print(
                "  and \(counted(hidden, "more finding")) accounting for "
                    + "\(hiddenOccurrences) further errors — raise --findings to see them.")
        }
    }

    private func printLatency(_ report: TranscriptionReport) {
        print("\nstage".padded(to: 16) + "typical".padded(to: 10) + "slowest".padded(to: 10) + "samples")
        for latency in report.latencies {
            print(
                latency.stage.rawValue.padded(to: 16) + "\(seconds(latency.typical))s".padded(to: 10)
                    + "\(seconds(latency.slowest))s".padded(to: 10) + "\(latency.samples)"
                    + (latency.failures > 0 ? "  (\(latency.failures) failed)" : ""))
        }
        for stage in report.unmeasuredStages {
            print(stage.rawValue.padded(to: 16) + "not measured — \(whyNotMeasured(stage))")
        }
    }

    /// Names why a stage has no timing, since a zero in a latency table reads as "instant".
    private func whyNotMeasured(_ stage: PipelineStage) -> String {
        switch stage {
        case .capture: "audio is read from disk here; what capture costs is timed in the app"
        case .transcription: "no passage reached the recogniser"
        case .correction: "no dictionary is consulted here; corrections are the app's"
        case .transformation: "clean-up was not run — pass --shipping"
        case .expansion: "no snippets are expanded here; expansion is the app's"
        case .insertion: "nothing is typed into another app during an evaluation"
        }
    }

    private func printFailures(_ report: TranscriptionReport) {
        let counts = report.failureCounts
        guard !counts.isEmpty else {
            print("\nNo failures.")
            return
        }
        print("\nfailures")
        for kind in TranscriptionFailure.Kind.allCases {
            guard let count = counts[kind] else { continue }
            print("  \(kind.rawValue.padded(to: 20)) \(count)")
        }
        // The counts above are the finding; only enough individual lines to look into are printed.
        let failed = report.scores.filter { $0.failure != nil }
        for score in failed.prefix(passageLimit) {
            print("  \(score.caseID.padded(to: 20)) \(score.failure?.detail ?? "")")
        }
        if failed.count > passageLimit {
            print("  and \(failed.count - passageLimit) more — raise --passages to see them.")
        }
    }

    /// Prints the per-passage table, worst first and bounded.
    private func printPassages(_ report: TranscriptionReport) {
        let worst = report.scores
            .sorted { ($1.wordErrorRate?.rate ?? -1, $0.caseID) < ($0.wordErrorRate?.rate ?? -1, $1.caseID) }
        let shown = worst.prefix(passageLimit)
        print(
            "\n\(shown.count == worst.count ? "every passage" : "worst \(shown.count) passages")"
                .padded(to: 22) + "WER".padded(to: 8) + "S/D/I".padded(to: 12)
                + "words".padded(to: 8) + "notes")
        for score in shown {
            let rate = score.wordErrorRate
            let notes = [
                score.lost.isEmpty ? nil : "lost \(score.lost.joined(separator: ", "))",
                score.answeredIn == .devanagari ? "Devanagari" : nil,
                score.isUpperBound ? "upper bound" : nil,
                score.failure.map { $0.kind.rawValue },
            ].compactMap(\.self)
            print(
                score.caseID.padded(to: 22) + percent(rate?.rate).padded(to: 8)
                    + "\(rate?.substitutions ?? 0)/\(rate?.deletions ?? 0)/\(rate?.insertions ?? 0)"
                    .padded(to: 12)
                    + "\(rate?.referenceWordCount ?? 0)".padded(to: 8)
                    + notes.joined(separator: ", "))
        }
        if worst.count > shown.count {
            print("  \(worst.count - shown.count) more, better than these — raise --passages to see them.")
        }
        guard verbose else { return }
        for score in shown {
            print("\n\(score.caseID)\n  heard  \(score.transcript)")
            guard let rate = score.wordErrorRate else { continue }
            let diff = rate.alignment.compactMap(difference).joined(separator: "  ")
            if !diff.isEmpty { print("  diff   \(diff)") }
        }
    }

    /// Renders one edit the way a person reads a diff; matches are left out.
    private func difference(_ operation: WordErrorRate.Operation) -> String? {
        switch operation {
        case .match: nil
        case .substitution(let reference, let hypothesis): "\(reference)→\(hypothesis)"
        case .deletion(let word): "-\(word)"
        case .insertion(let word): "+\(word)"
        }
    }

    // MARK: Names and numbers

    private func resolveModel() throws -> SpeechModel {
        guard let modelVariant else { return .default }
        guard let model = SpeechModel.named(modelVariant) else {
            throw ValidationError(
                "Unknown model '\(modelVariant)'. Known: "
                    + SpeechModel.catalogue.map(\.variant).joined(separator: ", "))
        }
        return model
    }

    /// Keeps results per configuration, so a hinted run cannot overwrite a detected one.
    private func resultsDirectory() -> String {
        let model = (try? resolveModel())?.variant ?? "default"
        return "\(resultsPath)/\(engine)-\(model)\(hintLanguage ? "-hinted" : "")"
    }

    private func label(_ model: SpeechModel) -> String {
        "\(engine) \(model.variant)\(hintLanguage ? ", language hinted" : ", language detected")"
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(String(format: "%.1f", $0 * 100))%" } ?? "n/a"
    }

    private func seconds(_ duration: Duration) -> String {
        String(
            format: "%.2f",
            duration.inSeconds)
    }
}
