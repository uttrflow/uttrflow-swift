import ArgumentParser
import Foundation
import UttrflowAI
import UttrflowAudio
import UttrflowCore
import UttrflowPipeline
import UttrflowSpeech

/// Plays a recording into the real pipeline at real time and reports the wait after the key comes up.
struct Dictate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Dictate an audio file through the whole pipeline, as if it were spoken live."
    )

    @Argument(help: "16 kHz mono WAVs to play into the pipeline.")
    var files: [String]

    @Flag(name: .long, help: "Do all the work after the key comes up, the way it used to be done.")
    var allAtOnce = false

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    @Option(name: .shortAndLong, help: "Force one transformer: foundationModels or rules.")
    var engine: String?

    @OptionGroup var modelsDirectory: ModelsDirectoryOptionGroup

    func run() async throws {
        let model = try resolve(modelVariant)
        let store = try modelsDirectory.store()
        guard store.isInstalled(model) else {
            throw notInstalled(model, in: store)
        }
        var configuration = EngineConfiguration.default
        if let engine {
            guard let kind = TransformerKind(rawValue: engine), TransformerKind.selectable.contains(kind)
            else { throw ValidationError("Unknown transformer '\(engine)'.") }
            configuration.transformerPreference = [kind]
        }
        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        print("Loading the recogniser…")
        var first = true
        for file in files {
        let audio = try AudioFileReader.read(contentsOf: URL(fileURLWithPath: file))
        guard !audio.isEmpty else { throw CleanExit.message("The file holds no audio.") }
        let playback = PlaybackCaptureEngine(audio: audio, sharesEarly: !allAtOnce, realTime: false)
        let inserter = PrintingInserter()
        let pipeline = DictationPipeline(
            capture: playback, speech: speech, cleaner: TextTransformers.router(configuration: configuration),
            context: FixedScreen(), inserter: inserter,
            windowing: allAtOnce ? .onePiece : .standard)
        await pipeline.prepare()
        guard await pipeline.isReady else { throw CleanExit.message("The recogniser did not load.") }
        _ = first; first = false
        let states = await pipeline.states()
        let watcher = Task { () -> (DictationState, ContinuousClock.Instant) in
            for await state in states where !state.isBusy && state != .idle {
                return (state, ContinuousClock.now)
            }
            return (.idle, ContinuousClock.now)
        }
        await pipeline.startRecording()
        await playback.playedOut()
        await pipeline.finishRecording()
        let (ended, _) = await watcher.value
        switch ended {
        case .inserted(let outcome):
            print("RESULT\t\((file as NSString).lastPathComponent)\t\(outcome.text.replacingOccurrences(of: "\n", with: "\\n"))")
        case .failed(let failure):
            print("RESULT\t\((file as NSString).lastPathComponent)\tFAILED \(failure.message)")
        default:
            print("RESULT\t\((file as NSString).lastPathComponent)\tEnded \(ended)")
        }
        }
    }

    private func seconds(_ duration: Duration) -> String {
        String(format: "%.2f", duration.inSeconds)
    }
}

extension SpeechWindowing {
    /// Never cuts, so a recording is recognised and tidied whole at the end.
    fileprivate static let onePiece = SpeechWindowing(
        minimumLength: .infinity, sentencePause: .infinity, comfortableLength: .infinity,
        anyPause: .infinity, maximumLength: .infinity)
}

/// A microphone that plays a file at real time, or hands it over at once, so working ahead has something to work on.
actor PlaybackCaptureEngine: AudioCaptureEngine {
    private let audio: AudioSamples
    private let sharesEarly: Bool
    private let realTime: Bool
    private let accumulator = SampleAccumulator()
    private var currentState: AudioCaptureState = .idle
    private var feeder: Task<Void, Never>?

    init(audio: AudioSamples, sharesEarly: Bool, realTime: Bool = true) {
        self.audio = audio
        self.sharesEarly = sharesEarly
        self.realTime = realTime
    }

    var state: AudioCaptureState { currentState }

    func start() async throws(AudioCaptureError) {
        guard currentState == .idle else { throw .alreadyRecording }
        accumulator.reset()
        currentState = .recording
        let block = audio.sampleRate / 10
        let samples = audio.samples
        let accumulator = self.accumulator
        // All at once is a key held for exactly as long as the file, with nothing left to do but the release.
        guard realTime else {
            accumulator.append(samples)
            return
        }
        feeder = Task {
            var cursor = 0
            let started = ContinuousClock.now
            while cursor < samples.count, !Task.isCancelled {
                let end = Swift.min(cursor + block, samples.count)
                accumulator.append(Array(samples[cursor..<end]))
                cursor = end
                let due = started + .milliseconds(100 * (cursor / block))
                try? await Task.sleep(until: due, clock: .continuous)
            }
        }
    }

    /// Returns once the whole file has been fed, which is when the key would come up.
    func playedOut() async {
        await feeder?.value
    }

    func stop() async throws(AudioCaptureError) -> AudioSamples {
        guard currentState == .recording else { throw .notRecording }
        feeder?.cancel()
        currentState = .idle
        return .canonical(accumulator.take())
    }

    func cancel() async {
        feeder?.cancel()
        accumulator.reset()
        currentState = .idle
    }

    func capturedSoFar() async -> AudioSamples {
        guard sharesEarly, currentState == .recording else { return .empty }
        return .canonical(accumulator.snapshot)
    }

    func capturedSoFar(from start: Int) async -> AudioSamples {
        guard sharesEarly, currentState == .recording else { return .empty }
        return .canonical(accumulator.samples(from: start))
    }
}

/// Nothing on screen, which is what the command line has.
struct FixedScreen: ContextEngine {
    var context = AppContext()

    func currentContext() async -> AppContext { context }
}

/// Puts the words on standard output rather than into another app.
struct PrintingInserter: TextInserting {
    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        InsertionAttempt(.pasteboard)
    }
}
