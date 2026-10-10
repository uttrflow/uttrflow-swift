// The `transcribe` command: measures a recogniser against the recorded corpus.
import ArgumentParser
private import Foundation
private import UttrflowAI
private import UttrflowAudio
private import UttrflowCore
private import UttrflowDictionary
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

    /// The recogniser's name, which keys the results directory and the run label.
    private var engine: String { SpeechEngineKind.whisperKit.rawValue }

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    /// Measures a variant the app does not install, so candidates are compared before one is pinned.
    @Option(name: .long, help: "Load the model from this folder instead of the installed one.")
    var modelFolder: String?

    @Option(name: .long, help: "Where each model stage runs: shipping, gpu, neuralEngine, all or cpu.")
    var compute = SpeechComputePlan.shipping.rawValue

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

    /// Measures the noise floor a regression verdict has to clear. See Docs/eval-methodology.md.
    @Option(
        name: .customLong("repeat"),
        help: "Run the corpus this many times and print how far the runs disagree.")
    var runs = 1

    func validate() throws {
        if findings < 0 {
            throw ValidationError("--findings must be zero or greater.")
        }
        if passageLimit < 0 {
            throw ValidationError("--passage-limit must be zero or greater.")
        }
        if runs < 1 {
            throw ValidationError("--repeat must be one or greater.")
        }
        // One run is the gate's subject; several are its noise floor, and a gate on either alone misleads.
        if runs > 1, summarise || baseline != nil {
            throw ValidationError(
                "--repeat measures spread; it cannot be combined with --summarise or --baseline.")
        }
        if saveBaseline || failOnRegression, baseline == nil {
            throw ValidationError("--save-baseline and --fail-on-regression need --baseline <path>.")
        }
        guard SpeechComputePlan(rawValue: compute) != nil else {
            throw ValidationError(
                "Unknown compute plan '\(compute)'. Known: "
                    + SpeechComputePlan.allCases.map(\.rawValue).joined(separator: ", "))
        }
    }

    func run() async throws {
        let model = try resolveModel()
        let results = JSONRecordStore<PassageScore>(directory: URL(fileURLWithPath: resultsDirectory()))

        if summarise {
            // Stored results come back in file-system order, so they are put back into corpus order.
            let stored = TranscriptionCorpus.inCorpusOrder(try results.all())
            try compare(
                reporting: TranscriptionReport(
                    label: label(model), recogniser: model.recogniserPins, scores: stored))
            return
        }

        let source = try await source()
        let recordings = source.recordings
        guard !recordings.isEmpty else {
            throw CleanExit.message(
                "Nothing to measure. Run: uttrflow-eval record   (or: uttrflow-eval pull --backend …)")
        }

        let speech = try await prepared(model: model)
        let decoded = Decoded(store: source.dumps, engine: decodeIdentity(model))
        let router: (any TranscriptCleaning)? = shipping ? TextTransformers.router() : nil
        let metrics = CollectingMetricsRecorder()
        let clock = ContinuousClock()

        var measured: [TranscriptionReport] = []
        for run in 1...runs {
            let pass = runs > 1 ? " (run \(run) of \(runs))" : ""
            print("Measuring \(recordings.count) passages with \(label(model))\(pass)…")
            measured.append(
                await TranscriptionRunner().run(
                    label: label(model),
                    recogniser: model.recogniserPins,
                    over: recordings,
                    onScore: { score in
                        Terminal.show(".")
                        do { try results.save(score) } catch {
                            print("\n  ! could not save \(score.id): \(error)")
                        }
                    }
                ) { recording in
                    await measure(
                        recording, with: speech, router: router, metrics: metrics, clock: clock,
                        audioAt: source.audioURL, keeping: decoded)
                })
            Terminal.clearLine()
        }
        printDumpSize(decoded.store)

        guard let first = measured.first else { return }
        try compare(reporting: first)
        if runs > 1 { printSpread(RunToRunSpread(runs: measured)) }
    }

    /// Prints how far repeated runs disagree, ending with the row the methodology table records.
    private func printSpread(_ spread: RunToRunSpread) {
        print(
            "\nrun-to-run".padded(to: 23) + "identical".padded(to: 11) + "transcripts".padded(to: 13)
                + "spread")
        for passage in spread.differing {
            print(
                passage.id.padded(to: 22) + percent(passage.identicalTextRate).padded(to: 11)
                    + "\(passage.distinctTranscripts)".padded(to: 13)
                    + (passage.spreadPercentagePoints.map { String(format: "%.1f pts", $0) } ?? "n/a"))
        }
        if spread.differing.isEmpty { print("  every run gave every passage the same transcript") }
        print("\nFor Docs/eval-methodology.md:\n" + spread.tableRow(on: .current()))
    }

    // MARK: Where the audio comes from

    /// The recordings to measure and the directory holding each one's audio.
    private struct Source {
        let recordings: [RecordedPassage]
        let audioURL: @Sendable (String) -> URL
        /// Where each decode's evidence is kept, beside the audio it came from.
        let dumps: DecodeDumpStore
    }

    /// Where decodes are kept and the engine identity they are filed under.
    private struct Decoded {
        let store: DecodeDumpStore
        let engine: DecodeEngineIdentity
    }

    /// The identity the dumps are filed under; `word-doubt --from-dumps` builds the same one to read them.
    private func decodeIdentity(_ model: SpeechModel) -> DecodeEngineIdentity {
        .corpusDecode(
            variant: model.variant, weightsRevision: model.weightsRevision,
            tokenizerRevision: model.tokenizerRevision, compute: compute, hintLanguage: hintLanguage)
    }

    /// Prints how much the kept decodes take, since they are new data on this Mac.
    private func printDumpSize(_ store: DecodeDumpStore) {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: store.directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = files.compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
        print("decode dumps: \(counted(files.count, "file")), \(bytes / 1024) KB in \(store.directory.path)")
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
            return Source(
                recordings: try corpus.all(), audioURL: { corpus.audioURL(for: $0) },
                dumps: DecodeDumpStore(corpusDirectory: URL(fileURLWithPath: corpusPath)))
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
            recordings: samples.map(recorded), audioURL: { cache.audioURL(for: $0) },
            dumps: DecodeDumpStore(corpusDirectory: URL(fileURLWithPath: connection.cachePath)))
    }

    /// A catalogue sample as the runner wants it; `recordedAt` is the run time, the catalogue has none.
    private func recorded(_ sample: CorpusSample) -> RecordedPassage {
        RecordedPassage(
            passage: sample.passage, recordedAt: Date(),
            durationSeconds: Double(sample.durationMs) / 1000, sampleRate: sample.sampleRateHz,
            cohort: sample.cohort.map { RecordingCohort(id: $0, speaker: $0, setting: "from the catalogue") },
            recordingIdentity: RecordingIdentity.forCatalogueSample(s3Key: sample.s3Key),
            recordID: sample.slug)
    }

    // MARK: Measuring one passage

    private func measure(
        _ recording: RecordedPassage,
        with speech: any SpeechEngine,
        router: (any TranscriptCleaning)?,
        metrics: CollectingMetricsRecorder,
        clock: ContinuousClock,
        audioAt audioURL: @Sendable (String) -> URL,
        keeping decoded: Decoded
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
        if let identity = recording.recordingIdentity {
            // Kept so a fit reads this decode instead of decoding again; a later run adds a file, never replaces it.
            do {
                try decoded.store.save(
                    DecodeDump(
                        recordingIdentity: identity, engine: decoded.engine, transcription: transcription))
            } catch {
                print("\n  ! could not keep the decode of \(recording.id): \(error)")
            }
        }

        if let router {
            // Timed but not scored: clean-up changes the words on purpose. See Docs/eval-methodology.md.
            _ = try? await metrics.measuring(.transformation, clock: clock) {
                try await router.clean(TransformationRequest(transcription: transcription))
            }
        }
        return .transcribed(transcription.text, stages: await metrics.drain())
    }

    private func prepared(model: SpeechModel) async throws -> any SpeechEngine {
        let store = FileSystemSpeechModelStore.whisperKit()
        if modelFolder == nil, !store.isInstalled(model) {
            throw CleanExit.message("\(model.variant) is not installed. Run: uttrflow-dev models install")
        }
        let folder = modelFolder.map { URL(fileURLWithPath: $0) } ?? store.location(of: model)
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: folder,
            compute: SpeechComputePlan(rawValue: compute) ?? .shipping)
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
        try BaselineGate(path: baseline, saveBaseline: saveBaseline, failOnRegression: failOnRegression)
            .judge(AccuracyBaseline.capture(measured))
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
        printErrorClasses(report)
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
            printOutputRates(report)
        }
        let upperBounds = report.upperBounds
        if !upperBounds.isEmpty {
            print(
                "\n\(counted(upperBounds.count, "passage")) had no reference in the script they came back "
                    + "in and were transliterated:\ntheir rates are upper bounds — "
                    + upperBounds.map(\.caseID).joined(separator: ", "))
        }
    }

    /// Prints the rate on the romanised text the user receives beside the recogniser's, per language.
    private func printOutputRates(_ report: TranscriptionReport) {
        print("\nOutput word error rate (romanised, exact spelling; recogniser rate on the same passages)")
        for language in TranscriptionCase.Language.allCases {
            let passages = report.scored.filter {
                $0.language == language && $0.outputWordErrorRate != nil
            }
            guard let output = report.outputWordErrorRate(in: language), !passages.isEmpty else {
                continue
            }
            let heard = WordErrorRate.combined(passages.compactMap(\.wordErrorRate))
            print("  \(language.rawValue)  \(percent(output.rate))  (\(percent(heard.rate)))")
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

    /// Prints each error's linguistic class beside the rate, so effort follows the largest share.
    private func printErrorClasses(_ report: TranscriptionReport) {
        let rows = report.errorClasses(by: ErrorClassifier(sameSound: PhonemeLexicon.shared.soundsSame))
        guard !rows.isEmpty else { return }
        print("\nerror class".padded(to: 18) + "count".padded(to: 8) + "share")
        for row in rows {
            print(row.errorClass.rawValue.padded(to: 17) + "\(row.count)".padded(to: 8) + percent(row.share))
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
        case .microphoneOpen, .keyDownToAudio, .capture:
            "audio is read from disk here; what the microphone costs is timed in the app"
        case .transcription: "no passage reached the recogniser"
        case .correction: "no dictionary is consulted here; corrections are the app's"
        case .transformation: "clean-up was not run — pass --shipping"
        case .expansion: "no snippets are expanded here; expansion is the app's"
        case .insertion: "nothing is typed into another app during an evaluation"
        case .drain: "nothing is worked ahead here; a passage is transcribed whole"
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
            print("  and \(failed.count - passageLimit) more — raise --passage-limit to see them.")
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
            print(
                "  \(worst.count - shown.count) more, better than these — "
                    + "raise --passage-limit to see them.")
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
        if let modelFolder { return .measured(folder: URL(fileURLWithPath: modelFolder)) }
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
        return "\(resultsPath)/\(engine)-\(model)\(planSuffix("-"))\(hintLanguage ? "-hinted" : "")"
    }

    /// Empty for the shipping plan, so labels and baselines recorded before plans existed still match.
    private func planSuffix(_ separator: String) -> String {
        compute == SpeechComputePlan.shipping.rawValue ? "" : separator + compute
    }

    private func label(_ model: SpeechModel) -> String {
        "\(engine) \(model.variant)\(planSuffix(" on "))\(hintLanguage ? ", language hinted" : ", language detected")"
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

extension SpeechModel {
    /// A multilingual model read from a folder the installer never pinned; measured, never shipped.
    fileprivate static func measured(folder: URL) -> SpeechModel {
        SpeechModel(
            variant: folder.lastPathComponent, downloadBytes: 0, isMultilingual: true,
            weightsRepository: "", weightsRevision: "", weightFiles: [:],
            tokenizerRepository: "", tokenizerRevision: "", tokenizerDigests: [:])
    }
}
