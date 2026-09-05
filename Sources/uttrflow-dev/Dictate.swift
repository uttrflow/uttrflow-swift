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

    @Argument(help: "A 16 kHz mono WAV to play into the pipeline.")
    var file: String

    @Flag(name: .long, help: "Do all the work after the key comes up, the way it used to be done.")
    var allAtOnce = false

    @Option(name: .customLong("model"), help: "Model variant. Defaults to the shipping model.")
    var modelVariant: String?

    func run() async throws {
        let model = try resolve(modelVariant)
        let store = FileSystemSpeechModelStore.whisperKit()
        guard store.isInstalled(model) else {
            throw CleanExit.message("\(model.variant) is not installed. Run: uttrflow-dev models install")
        }
        let audio = try AudioFileReader.read(contentsOf: URL(fileURLWithPath: file))
        guard !audio.isEmpty else { throw CleanExit.message("The file holds no audio.") }

        let speech = SpeechEngineFactory.make(
            kind: .whisperKit, model: model, modelFolder: store.location(of: model))
        let playback = PlaybackCaptureEngine(audio: audio, sharesEarly: !allAtOnce)
        let inserter = PrintingInserter()
        let pipeline = DictationPipeline(
            capture: playback, speech: speech, cleaner: TextTransformers.router(),
            context: NoScreen(), inserter: inserter,
            windowing: allAtOnce ? .onePiece : .standard)

        print("Loading the recogniser…")
        await pipeline.prepare()
        guard await pipeline.isReady else { throw CleanExit.message("The recogniser did not load.") }

        let states = await pipeline.states()
        let watcher = Task { () -> (DictationState, ContinuousClock.Instant) in
            for await state in states where !state.isBusy && state != .idle {
                return (state, ContinuousClock.now)
            }
            return (.idle, ContinuousClock.now)
        }

        let how = allAtOnce ? ", all work at key-up" : ""
        print("Playing \(seconds(audio.duration))s of audio as if spoken\(how)…")
        await pipeline.startRecording()
        await playback.playedOut()
        let keyUp = ContinuousClock.now
        await pipeline.finishRecording()
        let (ended, at) = await watcher.value
        let wait = keyUp.duration(to: at)

        switch ended {
        case .inserted(let outcome):
            print("\n\(outcome.text)\n")
            print("  audio        \(seconds(audio.duration))s")
            print("  wait         \(seconds(wait))s after the key came up")
            print("  tidied by    \(outcome.cleanedBy.rawValue)")
        case .failed(let failure):
            print("\nFailed: \(failure.message)")
            print("  wait         \(seconds(wait))s after the key came up")
        default:
            print("\nEnded in \(ended)")
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

/// A microphone that plays a file at real time, so working ahead has something to work on.
private actor PlaybackCaptureEngine: AudioCaptureEngine {
    private let audio: AudioSamples
    private let sharesEarly: Bool
    private let accumulator = SampleAccumulator()
    private var currentState: AudioCaptureState = .idle
    private var feeder: Task<Void, Never>?

    init(audio: AudioSamples, sharesEarly: Bool) {
        self.audio = audio
        self.sharesEarly = sharesEarly
    }

    var state: AudioCaptureState { currentState }

    func start() async throws(AudioCaptureError) {
        guard currentState == .idle else { throw .alreadyRecording }
        accumulator.reset()
        currentState = .recording
        let block = audio.sampleRate / 10
        let samples = audio.samples
        let accumulator = self.accumulator
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
}

/// Nothing on screen, which is what the command line has.
private struct NoScreen: ContextEngine {
    func currentContext() async -> AppContext { AppContext() }
}

/// Puts the words on standard output rather than into another app.
private struct PrintingInserter: TextInserting {
    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        .pasteboard
    }
}
