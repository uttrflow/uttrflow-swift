import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowAudio
import UttrflowCore
import UttrflowEval
import UttrflowSpeech

/// Reports what a dictation costs this Mac, in memory and in seconds.
///
/// Sits alongside ``Footprint``, which answers a different question: that one is "will
/// both models fit", this one is "what does using them feel like, and does repeating it
/// leak". Every decision — the order of the phases, what counts as a leak, whether cost
/// is linear in utterance length — lives in ``PerformanceProfiler`` and the types around
/// it, where a test can reach them. What is left here is the wiring and the table.
struct Profile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "profile",
        abstract: "Measure memory, peak, latency by utterance length, and check for a leak."
    )

    @Option(name: .long, help: "Where synthesised speech is cached between runs.")
    var audioDirectory = ".build/profile-audio"

    @Option(name: .long, help: "Voice the passages are read in. Any `say -v ?` name.")
    var voice = "Samantha"

    @Option(name: .long, help: "How many times each utterance length is timed.")
    var repetitions = 3

    @Option(name: .long, help: "Consecutive dictations the leak check watches.")
    var dictations = 10

    @Option(name: .long, help: "A built Uttrflow.app to include in the disk figure.")
    var app: String?

    @Flag(name: .long, help: "Time transcription alone, without the clean-up pass.")
    var transcribeOnly = false

    func run() async throws {
        let store = FileSystemSpeechModelStore.whisperKit()
        let model = SpeechModel.default
        guard store.isInstalled(model) else {
            throw CleanExit.message("Speech model not installed. Run: uttrflow-dev models install")
        }

        // Read before anything is measured, so the timings are transcription and
        // clean-up rather than the disk. The decoded samples are a few megabytes and are
        // already resident when the "idle" reading is taken — see Docs/performance.md.
        let spoken = try SpokenPassages(
            directory: URL(fileURLWithPath: audioDirectory), voice: voice
        ).prepare(ProfileCorpus.all)
        let recordings = spoken.map {
            ProfileRecording(passage: $0.passage, audioSeconds: $0.samples.duration.inSeconds)
        }
        let audio = Dictionary(uniqueKeysWithValues: spoken.map { ($0.passage.length, $0.samples) })

        let engines = EngineBox()
        let router = TextTransformers.router()
        let clock = ContinuousClock()

        let profiler = PerformanceProfiler(
            configuration: .init(
                repetitions: repetitions, leakRepetitions: dictations, leakLength: .medium))

        let report = await profiler.run(
            recordings: recordings,
            disk: DiskFootprint(
                speechModelBytes: store.bytesOnDisk(model) ?? 0,
                applicationBytes: app.flatMap { Self.bytes(under: URL(fileURLWithPath: $0)) }
            ),
            readCPU: CPUFootprint.reading,
            clock: clock,
            onPhase: { announce($0) },
            loadSpeechModel: {
                let engine = SpeechEngineFactory.make(
                    kind: .whisperKit, model: model, modelFolder: store.location(of: model))
                do {
                    try await engine.prepare()
                } catch {
                    FileHandle.standardError.write(Data("\n  ! could not load: \(error)\n".utf8))
                    return false
                }
                engines.current = engine
                return true
            },
            dictate: { recording in
                guard let engine = engines.current, let samples = audio[recording.passage.length]
                else { return [] }
                let recorder = CollectingMetricsRecorder()
                let transcription = try? await recorder.measuring(.transcription, clock: clock) {
                    try await engine.transcribe(samples, options: .automatic)
                }
                if !transcribeOnly, let transcription, !transcription.isBlank {
                    _ = try? await recorder.measuring(.transformation, clock: clock) {
                        try await router.transform(TransformationRequest(transcription: transcription))
                    }
                }
                return await recorder.drain()
            }
        )

        clearProgress()
        ProfilePrinter(report: report, model: model, includesCleanup: !transcribeOnly).emit()
    }

    // MARK: Progress

    private func announce(_ phase: PerformanceProfiler.Phase) {
        let text =
            switch phase {
            case .loadingModel: "loading the speech model"
            case .warmingUp: "warming up"
            case .repeating(let index, let total): "dictation \(index) of \(total)"
            case .timing(let length, let run, let total):
                "timing \(length.rawValue) — run \(run) of \(total)"
            case .measuringWarmLoad: "measuring a warm load"
            }
        FileHandle.standardError.write(Data("\r\u{1B}[2K  \(text)".utf8))
    }

    private func clearProgress() {
        FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))
    }

    /// Total bytes of every regular file under `directory`, or `nil` when it is absent.
    private static func bytes(under directory: URL) -> Int64? {
        guard FileManager.default.fileExists(atPath: directory.path),
            let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
        else { return nil }
        return enumerator.compactMap { $0 as? URL }.reduce(Int64(0)) { total, url in
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { return total }
            return total + Int64(values?.fileSize ?? 0)
        }
    }
}

/// Holds the recogniser the profiler most recently loaded.
///
/// The profiler asks for a *fresh* engine twice — once cold, once warm — and the
/// dictation closure needs whichever is current. A reference box rather than a captured
/// `var` because the two closures are separate captures of the same thing.
private final class EngineBox: @unchecked Sendable {
    var current: (any SpeechEngine)?
}
