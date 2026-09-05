import ArgumentParser
private import Foundation
private import UttrflowAudio
private import UttrflowCore
private import UttrflowEval

/// Walks the operator through reading the corpus aloud, once.
///
/// The recordings are the expensive half of Phase 8 and the only half a machine cannot
/// do: roughly twenty minutes of somebody's afternoon, after which every transcription
/// measurement for the rest of the project runs unattended off the same audio.
///
/// So the session is built to be interrupted. Each take is written to disk the moment it
/// is accepted, and the next run starts from what is missing — five passages in and
/// called away is five passages banked, not a session to repeat.
///
/// Uploading is layered on top of that and never underneath it. The local write is the
/// commit: a take reaches the disk before the corpus service is told anything, so a dead
/// connection, a backend without the endpoint, or a laptop closed mid-sentence costs an
/// upload and never a recording. What has not gone up is worked out by comparing the
/// recordings on disk with the receipts beside them, and `--sync` sends the difference,
/// tomorrow or next week.
struct RecordCorpus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "record",
        abstract: "Read the evaluation passages aloud and keep them. Resumable, and uploadable."
    )

    @OptionGroup var connection: CorpusConnection

    @Option(name: .long, help: "Where the recorded corpus lives.")
    var corpusPath = TranscriptionCorpusStore.defaultDirectoryName

    /// Short and slug-safe, because it becomes part of the sample's name in the bucket.
    /// Validated before a word is spoken — see ``validate()``.
    @Option(name: .long, help: "Which recording cohort this sitting belongs to, e.g. naveen-quiet.")
    var cohort: String?

    @Option(name: .long, help: "Who is reading, as a label rather than a name.")
    var speaker: String?

    @Option(name: .long, help: "The room and the microphone, e.g. 'quiet room, built-in mic'.")
    var setting: String?

    @Flag(name: .long, help: "Send each take to the corpus service as it is accepted.")
    var upload = false

    @Flag(name: .long, help: "Send everything not yet accepted by the corpus service, and stop.")
    var sync = false

    @Flag(name: .long, help: "Print what has already been recorded and stop.")
    var summarise = false

    @Flag(name: .long, help: "Print the passages and stop, to read through before starting.")
    var listPassages = false

    @Option(name: .long, help: "Re-record one passage by id, e.g. hi-numbers.")
    var redo: String?

    @Option(name: .long, help: "Only one language: english, hindi or hinglish.")
    var language: String?

    func validate() throws {
        if let language, TranscriptionCase.Language(rawValue: language) == nil {
            throw ValidationError(
                "Unknown language '\(language)'. Known: "
                    + TranscriptionCase.Language.allCases.map(\.rawValue).joined(separator: ", "))
        }
        if let redo, TranscriptionCorpus.passage(redo) == nil {
            throw ValidationError("No passage called '\(redo)'.")
        }
        // Checked here rather than at upload time, which is the whole reason it is
        // checked at all: a name the catalogue refuses is discovered at the end of a
        // sitting, after somebody has read forty passages, and by then the useful moment
        // to fix it has gone.
        if let cohort, !CorpusSlug.isValid(cohort) {
            throw ValidationError(
                "'\(cohort)' is not a name the corpus catalogue accepts. Two to sixty-four "
                    + "lowercase letters, digits and hyphens — try '\(CorpusSlug.sanitised(cohort))'.")
        }
        for passage in TranscriptionCorpus.all {
            let slug = CorpusSlug.make(passage: passage.id, cohort: cohort)
            if !CorpusSlug.isValid(slug) {
                throw ValidationError(
                    "Passage '\(passage.id)' would upload as '\(slug)', which the "
                        + "catalogue refuses. Shorten the cohort name.")
            }
        }
    }

    func run() async throws {
        let store = TranscriptionCorpusStore(directory: URL(fileURLWithPath: corpusPath))
        let corpus = selectedCorpus()

        if listPassages {
            for passage in corpus { show(passage, position: nil, of: corpus.count) }
            return
        }
        if sync {
            try await flush(outbox(store))
            return
        }
        if summarise {
            try printProgress(store, corpus: corpus)
            return
        }

        let queue = try queued(from: store, corpus: corpus)
        guard !queue.isEmpty else {
            print("Everything is recorded. \(corpusPath) holds \(try store.all().count) passages.")
            return
        }

        print(
            """
            \(counted(queue.count, "passage")) to read, about \
            \(minutes(estimatedTime(of: queue))).

            Read each one at your normal speaking pace — this is measuring dictation, not \
            elocution. Read it as written, false starts included: they are in there because \
            they are what breaks recognisers.
            """)

        let sender = upload ? try outbox(store) : nil
        for (offset, passage) in queue.enumerated() {
            try await record(
                passage, position: offset + 1, of: queue.count, into: store, sending: sender)
        }
        try printProgress(store, corpus: TranscriptionCorpus.all)
    }

    // MARK: One passage

    private func record(
        _ passage: TranscriptionCase,
        position: Int,
        of total: Int,
        into store: TranscriptionCorpusStore,
        sending outbox: CorpusUploadOutbox?
    ) async throws {
        while true {
            show(passage, position: position, of: total)
            print("Press return to start recording…", terminator: "")
            _ = readLine()

            let engine = AVAudioCaptureEngine(source: AVAudioEngineMicrophoneSource())
            do {
                try await engine.start()
            } catch {
                throw CleanExit.message(error.userMessage)
            }
            print("  ● recording — read the passage, then press return.", terminator: "")
            _ = readLine()
            let audio = try await engine.stop()

            let peak = audio.samples.reduce(0) { Swift.max($0, Swift.abs($1)) }
            let seconds = Double(audio.samples.count) / Double(audio.sampleRate)
            print(
                "  \(String(format: "%.1f", seconds))s captured, loudest sample "
                    + String(format: "%.3f", peak))
            for warning in warnings(peak: peak, seconds: seconds, passage: passage) {
                print("  ! \(warning)")
            }

            print("  Return to keep it, or 'r' then return to read it again: ", terminator: "")
            if readLine()?.trimmingCharacters(in: .whitespaces).lowercased() == "r" { continue }

            let recorded = RecordedPassage(
                passage: passage, recordedAt: Date(), durationSeconds: seconds,
                sampleRate: audio.sampleRate, cohort: recordingCohort())
            // Disk first, always. Everything after this line can fail without costing
            // the take, and that ordering is what makes a sixty-minute sitting over a
            // domestic connection a reasonable thing to ask of somebody.
            try store.save(recorded, audio: WAVEncoder.encode(audio))
            print("  kept as \(passage.id).wav")

            if let outbox {
                let receipt = await outbox.send(recorded)
                switch receipt.outcome {
                case .uploaded: print("  uploaded as \(receipt.slug)")
                case .heldBack(let reason):
                    print("  ! not uploaded — \(reason)")
                    print("    It is safe on disk. Send it later with: uttrflow-eval record --sync")
                case .rejected(let reason):
                    print("  ! the corpus service refused it — \(reason)")
                    print("    It is safe on disk, and retrying will not help until that is fixed.")
                }
            }
            print("")
            return
        }
    }

    /// What is worth saying about a take before the operator decides to keep it.
    ///
    /// Said here rather than discovered weeks later in a report: a recording made with no
    /// microphone access is silent, and finding that out after eighteen passages would
    /// waste the entire session.
    private func warnings(peak: Float, seconds: Double, passage: TranscriptionCase) -> [String] {
        var warnings: [String] = []
        if peak < 0.001 {
            warnings.append(
                "Silent. Check the input device, and that this tool has microphone access in "
                    + "System Settings › Privacy & Security › Microphone.")
        } else if peak < 0.05 {
            warnings.append("Very quiet — worth reading it again closer to the microphone.")
        }
        if peak > 0.99 { warnings.append("Clipping. Move back a little and read it again.") }
        // Two words a second is slow even for dictation, so anything under this means the
        // recording was stopped before the passage ended.
        let expected = Double(TranscriptionCorpus.wordCount(of: passage)) / 2.5
        if seconds < expected * 0.6 {
            warnings.append("That looks short for this passage — did it get cut off?")
        }
        return warnings
    }

    // MARK: Choosing what to read

    private func selectedCorpus() -> [TranscriptionCase] {
        guard let language, let chosen = TranscriptionCase.Language(rawValue: language) else {
            return TranscriptionCorpus.all
        }
        return TranscriptionCorpus.cases(in: chosen)
    }

    private func queued(
        from store: TranscriptionCorpusStore, corpus: [TranscriptionCase]
    ) throws
        -> [TranscriptionCase]
    {
        if let redo, let passage = TranscriptionCorpus.passage(redo) { return [passage] }
        let drifted = try store.drifted(from: corpus).map(\.id)
        if !drifted.isEmpty {
            print(
                "Note: \(drifted.joined(separator: ", ")) changed since they were read. "
                    + "Re-record with --redo when convenient.\n")
        }
        return store.remaining(from: corpus)
    }

    // MARK: Uploading

    private func recordingCohort() -> RecordingCohort? {
        guard let cohort else { return nil }
        // Defaulted rather than demanded: a cohort with no description is still a cohort
        // worth telling apart, and refusing to record until somebody has typed a
        // sentence about their room would be the wrong place to be strict.
        return RecordingCohort(
            id: cohort, speaker: speaker ?? cohort, setting: setting ?? "not recorded")
    }

    private func outbox(_ store: TranscriptionCorpusStore) throws -> CorpusUploadOutbox {
        CorpusUploadOutbox(
            recordings: store, uploader: try connection.client(), cohort: recordingCohort())
    }

    /// Sends everything the corpus service has not accepted, and says what is left.
    private func flush(_ outbox: CorpusUploadOutbox) async throws {
        let outstanding = try outbox.pending()
        guard !outstanding.isEmpty else {
            print("Everything recorded has been accepted by the corpus service.")
            return
        }
        print("\(counted(outstanding.count, "recording")) to send…")

        let summary = try await outbox.flush { receipt in
            Terminal.show(receipt.outcome == .uploaded ? "." : "!")
        }
        Terminal.clearLine()

        print("\(summary.uploaded.count) uploaded.")
        // Grouped by reason: nine hundred recordings behind one unreachable backend is
        // one line, not nine hundred.
        report("held back, and will be retried", summary.heldBack)
        report("refused, and need somebody to look", summary.rejected)
        if summary.outstanding > 0 {
            print(
                "\n\(summary.outstanding) still to go. Every one of them is on disk in "
                    + "\(corpusPath); nothing has been lost.")
        }
    }

    private func report(_ headline: String, _ receipts: [UploadReceipt]) {
        guard !receipts.isEmpty else { return }
        print("\n\(receipts.count) \(headline):")
        let byReason = Dictionary(grouping: receipts) { $0.outcome.detail ?? "no reason given" }
        for (reason, group) in byReason.sorted(by: { $0.key < $1.key }) {
            print("  \(group.count) × \(reason)")
            print("    " + group.map(\.passageID).listed())
        }
    }

    // MARK: Printing

    private func show(_ passage: TranscriptionCase, position: Int?, of total: Int) {
        let counter = position.map { "\($0)/\(total)  " } ?? ""
        print(
            "\n\(counter)\(passage.id)  ·  \(passage.language.rawValue)  ·  "
                + "\(passage.stressor.rawValue)\n")
        print(wrapped(passage.prompt))
        print("")
    }

    private func printProgress(_ store: TranscriptionCorpusStore, corpus: [TranscriptionCase]) throws {
        let recorded = try store.all()
        let remaining = store.remaining(from: corpus)
        print("\(recorded.count) of \(corpus.count) recorded in \(corpusPath)")
        for passage in recorded {
            print(
                "  \(passage.id.padded(to: 22)) \(String(format: "%5.1f", passage.durationSeconds))s"
                    + "  \(passage.recordedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        if remaining.isEmpty {
            print("\nNothing left to read.")
        } else {
            print(
                "\n\(remaining.count) left, about \(minutes(estimatedTime(of: remaining))): "
                    + remaining.map(\.id).joined(separator: ", "))
        }
        let drifted = try store.drifted(from: corpus)
        if !drifted.isEmpty {
            print("\nEdited since recording: " + drifted.map(\.id).joined(separator: ", "))
        }

        let cohorts = Dictionary(grouping: recorded.compactMap { $0.cohort?.id }, by: { $0 })
        if !cohorts.isEmpty {
            let unattributed = recorded.count { $0.cohort == nil }
            print(
                "\nby cohort: "
                    + cohorts.map { "\($0.key) \($0.value.count)" }.sorted().joined(separator: ", ")
                    + (unattributed > 0 ? ", \(RecordingCohort.unattributed) \(unattributed)" : ""))
        }

        // Printed here rather than only under --sync so that "how much of this sitting is
        // actually in the corpus" is answered by the command somebody already runs.
        guard
            let receipts = try? CorpusUploadOutbox(
                recordings: store, uploader: NoUploader()
            ).allReceipts(), !receipts.isEmpty
        else { return }
        let sent = receipts.count { $0.outcome == .uploaded }
        print("\n\(sent) of \(recorded.count) accepted by the corpus service")
        for receipt in receipts where receipt.outcome != .uploaded {
            print("  \(receipt.passageID.padded(to: 22)) \(receipt.outcome.detail ?? "")")
        }
    }

    /// Stands in when the receipts are only being *read*.
    ///
    /// ``CorpusUploadOutbox`` needs an uploader to exist, and `--summarise` must work
    /// with no backend flag and no network — that is the whole point of the receipts
    /// being on disk. Refusing rather than pretending, so a stray call site cannot
    /// silently do nothing and report success.
    private struct NoUploader: CorpusUploading {
        func register(_ sample: CorpusSample) async throws(CorpusError) -> CorpusUpload {
            throw .unreachable("no corpus service was configured for this command")
        }

        func upload(_ audio: Data, to upload: CorpusUpload) async throws(CorpusError) {
            throw .unreachable("no corpus service was configured for this command")
        }
    }

    /// Wrapped to something a person can read off a terminal without losing their place.
    private func wrapped(_ text: String, width: Int = 76) -> String {
        var lines: [String] = []
        var line = ""
        for word in text.split(whereSeparator: \.isWhitespace) {
            if line.isEmpty {
                line = String(word)
            } else if line.count + word.count + 1 <= width {
                line += " \(word)"
            } else {
                lines.append(line)
                line = String(word)
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines.map { "    \($0)" }.joined(separator: "\n")
    }

    private func estimatedTime(of passages: [TranscriptionCase]) -> Duration {
        TranscriptionCorpus.estimatedReadingTime(of: passages)
    }

    private func minutes(_ duration: Duration) -> String {
        let seconds = Double(duration.components.seconds)
        return seconds < 90
            ? "\(Int(seconds.rounded())) seconds" : "\(Int((seconds / 60).rounded())) minutes"
    }
}
