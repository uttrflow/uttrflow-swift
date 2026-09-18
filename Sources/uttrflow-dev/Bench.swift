// The `bench` command: many dictations through the real pipeline with the recogniser loaded once.
import ArgumentParser
import Foundation
import Synchronization
import UttrflowAI
import UttrflowAudio
import UttrflowCore
import UttrflowEval
import UttrflowPipeline
import UttrflowSpeech

/// Plays a list of clips through `DictationPipeline` and prints one JSON line per dictation. See `Docs/performance.md`.
struct Bench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Dictate a list of clips through the whole pipeline, loading the recogniser once.",
        discussion: """
            Each line of JOBS is tab-separated: id, WAV path, vocabulary (comma-separated, may be empty), \
            mode (rt plays in real time, fast hands the file over at once), cleaner (shipping or rules), and \
            the languages the speaker speaks (comma-separated codes, default en). \
            Output is one line per event on standard output, prefixed BENCH and holding JSON.
            """
    )

    @Argument(help: "The jobs file.")
    var jobs: String

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .long, help: "Seconds between looks at the recording for a piece to work ahead on.")
    var earlyPoll: Double = 1

    func validate() throws {
        guard earlyPoll.isFinite, earlyPoll >= 0.01, earlyPoll <= 60 else {
            throw ValidationError("--early-poll must be between 0.01 and 60 seconds.")
        }
    }

    func run() async throws {
        let model = try resolve(modelVariant)
        let store = FileSystemSpeechModelStore.whisperKit()
        guard store.isInstalled(model) else {
            throw CleanExit.message("\(model.variant) is not installed. Run: uttrflow-dev models install")
        }
        let parsed = try String(contentsOfFile: jobs, encoding: .utf8)
            .split(separator: "\n").filter { !$0.isEmpty }.map { try BenchJob(line: String($0)) }

        let log = BenchLog()
        let recogniser = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        let speech = TimedSpeech(inner: recogniser, log: log)
        let shipping = TimedCleaner(inner: TextTransformers.router(), log: log)
        let rules = TimedCleaner(
            inner: TextTransformers.router(
                configuration: EngineConfiguration(speech: .whisperKit, transformerPreference: [.rules])),
            log: log)

        let started = ContinuousClock.now
        let before = CPUFootprint.reading()
        try await recogniser.prepare()
        let loaded = started.duration(to: .now).inSeconds
        let loadCost = CPUCost.between(before, CPUFootprint.reading(), wallSeconds: loaded)
        emit([
            "event": "loaded", "seconds": loaded, "cpu": loadCost?.cpuSeconds ?? -1,
            "footprintMB": megabytes(MemoryFootprint.current()),
        ])

        for job in parsed {
            emit(try await dictate(job, speech: speech, cleaner: job.rulesOnly ? rules : shipping, log: log))
        }
    }

    /// Runs one clip from key-down to the words, answering what was measured.
    private func dictate(
        _ job: BenchJob, speech: TimedSpeech, cleaner: TimedCleaner, log: BenchLog
    ) async throws -> [String: Any] {
        let audio = try AudioFileReader.read(contentsOf: URL(fileURLWithPath: job.wav))
        let playback = PlaybackCaptureEngine(audio: audio, sharesEarly: true, realTime: job.realTime)
        let vocabulary = job.vocabulary
        let pipeline = DictationPipeline(
            capture: playback, speech: speech, cleaner: cleaner, context: NoScreen(),
            inserter: PrintingInserter(), speechWords: { _ in vocabulary },
            profile: UserProfile(preferredLanguages: job.languages),
            earlyPoll: .milliseconds(Int(earlyPoll * 1000)))
        let states = await pipeline.states()
        let watcher = Task { () -> (DictationState, ContinuousClock.Instant) in
            for await state in states where !state.isBusy && state != .idle { return (state, .now) }
            return (.idle, .now)
        }
        let peak = PeakFootprint()
        let sampler = Task {
            while !Task.isCancelled {
                peak.sample()
                try? await Task.sleep(for: .milliseconds(20))
            }
        }

        let before = CPUFootprint.reading()
        let keyDown = ContinuousClock.now
        log.begin(at: keyDown)
        await pipeline.startRecording()
        await playback.playedOut()
        let keyUp = ContinuousClock.now
        log.mark("keyup")
        await pipeline.finishRecording()
        let (ended, at) = await watcher.value
        sampler.cancel()
        peak.sample()
        let cost = CPUCost.between(
            before, CPUFootprint.reading(), wallSeconds: keyDown.duration(to: at).inSeconds)

        var result: [String: Any] = [
            "event": "result", "id": job.id, "mode": job.realTime ? "rt" : "fast",
            "cleaner": job.rulesOnly ? "rules" : "shipping",
            "languages": job.languages.map(\.value).joined(separator: ","), "audio": audio.duration.inSeconds,
            "wait": keyUp.duration(to: at).inSeconds, "cpu": cost?.cpuSeconds ?? -1,
            "peakMB": megabytes(peak.bytes), "events": log.events(),
        ]
        switch ended {
        case .inserted(let outcome):
            result["text"] = outcome.text
            result["by"] = outcome.cleanedBy.rawValue
        case .failed(let failure):
            result["failed"] = failure.message
        default:
            result["failed"] = "\(ended)"
        }
        return result
    }
}

/// One line of the jobs file.
struct BenchJob {
    let id: String
    let wav: String
    let vocabulary: [String]
    let realTime: Bool
    let rulesOnly: Bool
    /// The profile's languages, which decide how each piece is given its language.
    let languages: [LanguageCode]

    init(line: String) throws {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 2 else {
            throw ValidationError("A job needs at least an id and a WAV: \(line)")
        }
        id = fields[0]
        wav = fields[1]
        vocabulary = fields.count > 2 ? fields[2].split(separator: ",").map(String.init) : []
        let mode = fields.count > 3 ? fields[3] : "rt"
        let cleaner = fields.count > 4 ? fields[4] : "shipping"
        // A typo must stop the run, or its dictations would be scored as the default.
        guard ["rt", "fast"].contains(mode), ["shipping", "rules"].contains(cleaner) else {
            throw ValidationError("Mode must be rt or fast and cleaner shipping or rules: \(line)")
        }
        realTime = mode == "rt"
        rulesOnly = cleaner == "rules"
        let codes =
            fields.count > 5 && !fields[5].isEmpty ? fields[5].split(separator: ",").map(String.init) : ["en"]
        languages = codes.compactMap(LanguageCode.init)
        guard languages.count == codes.count else {
            throw ValidationError("Languages must be codes like en,hi: \(line)")
        }
    }
}

/// Prints one event as a line of JSON behind a fixed prefix, so a reader can skip everything else.
private func emit(_ event: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
        let line = String(data: data, encoding: .utf8)
    else { return }
    print("BENCH " + line)
    fflush(stdout)
}

/// Bytes as megabytes, or -1 when the reading failed.
private func megabytes(_ bytes: Int64?) -> Double {
    bytes.map { Double($0) / 1_048_576 } ?? -1
}

/// The highest footprint seen across the samples of one dictation.
private final class PeakFootprint: Sendable {
    private let highest = Mutex<Int64?>(nil)

    func sample() {
        guard let now = MemoryFootprint.current() else { return }
        highest.withLock { $0 = max($0 ?? 0, now) }
    }

    var bytes: Int64? { highest.withLock { $0 } }
}

/// What happened during one dictation, timed from its key-down.
final class BenchLog: Sendable {
    private let state = Mutex<(start: ContinuousClock.Instant, events: [[String: String]])>((.now, []))

    func begin(at start: ContinuousClock.Instant) {
        state.withLock { $0 = (start, []) }
    }

    /// Seconds since key-down, as the text every event carries.
    func now() -> String {
        String(format: "%.3f", state.withLock { $0.start.duration(to: .now).inSeconds })
    }

    func add(_ event: [String: String]) {
        state.withLock { $0.events.append(event) }
    }

    func mark(_ kind: String) {
        add(["kind": kind, "t": now()])
    }

    func events() -> [[String: String]] {
        state.withLock { $0.events }
    }
}

/// The recogniser, with each call's span, audio length, words and language written to the log.
private struct TimedSpeech: SpeechEngine {
    let inner: BackedSpeechEngine
    let log: BenchLog

    var kind: SpeechEngineKind { inner.kind }

    func prepare() async throws(SpeechEngineError) {
        try await inner.prepare()
    }

    func transcribe(
        _ audio: AudioSamples, options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        let start = log.now()
        let seconds = String(format: "%.2f", audio.duration.inSeconds)
        do {
            let heard = try await inner.transcribe(audio, options: options)
            log.add([
                "kind": "asr", "t0": start, "t1": log.now(), "audio": seconds, "text": heard.text,
                "language": heard.detectedLanguage?.code.value ?? "",
            ])
            return heard
        } catch {
            log.add([
                "kind": "asr-error", "t0": start, "t1": log.now(), "audio": seconds, "error": "\(error)",
            ])
            throw error
        }
    }
}

/// A cleaner, with each tidy's span, words in and out, and engine written to the log.
private struct TimedCleaner: TranscriptCleaning {
    let inner: TransformerRouter
    let log: BenchLog

    func clean(_ request: TransformationRequest) async throws(TransformationError) -> TransformationResult {
        let start = log.now()
        do {
            let result = try await inner.clean(request)
            log.add([
                "kind": "clean", "t0": start, "t1": log.now(), "in": request.transcription.text,
                "out": result.text, "by": result.producedBy.rawValue,
            ])
            return result
        } catch {
            log.add(["kind": "clean-error", "t0": start, "t1": log.now()])
            throw error
        }
    }

    func warm(for situation: Situation?) async {
        let start = log.now()
        await inner.warm(for: situation)
        log.add(["kind": "warm", "t0": start, "t1": log.now()])
    }

    func finishMessage(_ text: String, for request: TransformationRequest) async -> String {
        await inner.finishMessage(text, for: request)
    }
}
