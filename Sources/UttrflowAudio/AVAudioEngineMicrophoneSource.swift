private import AVFoundation
public import UttrflowCore
private import Synchronization

/// The real microphone.
///
/// Deliberately the thinnest file in the module: it starts an `AVAudioEngine`, hands
/// each tapped buffer to an ``AudioResampler``, and forwards the result. Every rule
/// worth testing lives on the other side of ``MicrophoneSource`` — this part can only
/// be verified by actually speaking into a Mac, which is what `uttrflow-dev record` is
/// for. It is excluded from the coverage gate for exactly that reason.
public final class AVAudioEngineMicrophoneSource: MicrophoneSource {
    /// Holds the live engine. Non-Sendable AVFoundation objects live here and are
    /// only ever touched under the lock.
    private final class Running: @unchecked Sendable {
        let engine: AVAudioEngine
        let inputBus: AVAudioNodeBus

        init(engine: AVAudioEngine, inputBus: AVAudioNodeBus) {
            self.engine = engine
            self.inputBus = inputBus
        }
    }

    private static let tapBufferSize: AVAudioFrameCount = 4096

    private let running = Mutex<Running?>(nil)

    public init() {}

    public func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws(AudioCaptureError) {
        let engine = AVAudioEngine()
        let inputBus: AVAudioNodeBus = 0
        let format = engine.inputNode.inputFormat(forBus: inputBus)

        // A missing or unavailable input device reports a zero-rate format rather
        // than failing outright.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw .noInputDevice
        }
        guard let resampler = AudioResampler(inputFormat: format) else {
            throw .unsupportedInputFormat
        }

        engine.inputNode.installTap(onBus: inputBus, bufferSize: Self.tapBufferSize, format: format) {
            buffer, _ in
            // Runs on the audio thread. A dropped buffer costs a few milliseconds of
            // speech; throwing here would tear down the recording entirely.
            guard let samples = try? resampler.resample(buffer) else { return }
            onSamples(samples)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: inputBus)
            throw .engineFailed(description: error.localizedDescription)
        }

        running.withLock { $0 = Running(engine: engine, inputBus: inputBus) }
    }

    public func stop() {
        guard
            let running = running.withLock({ running -> Running? in
                defer { running = nil }
                return running
            })
        else { return }

        running.engine.inputNode.removeTap(onBus: running.inputBus)
        running.engine.stop()
    }
}
