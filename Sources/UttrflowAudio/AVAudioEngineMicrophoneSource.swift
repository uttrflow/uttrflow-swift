// Delivers converted microphone samples from an AVAudioEngine input tap.
private import AVFoundation
private import Foundation
public import UttrflowCore
private import Synchronization

/// The real microphone, verifiable only by speaking into a Mac and so not covered.
public final class AVAudioEngineMicrophoneSource: MicrophoneSource {
    /// Holds the live engine, which AVFoundation will not let cross a thread on its own.
    private final class Running: @unchecked Sendable {
        let engine: AVAudioEngine
        let inputBus: AVAudioNodeBus
        var observer: (any NSObjectProtocol)?

        init(engine: AVAudioEngine, inputBus: AVAudioNodeBus) {
            self.engine = engine
            self.inputBus = inputBus
        }
    }

    private static let tapBufferSize: AVAudioFrameCount = 4096

    private let running = Mutex<Running?>(nil)

    /// Where samples go, kept so the tap can be rebuilt without the caller knowing.
    private let sink = Mutex<(@Sendable ([Float]) -> Void)?>(nil)

    public init() {}

    public func start(onSamples: @escaping @Sendable ([Float]) -> Void) throws(AudioCaptureError) {
        sink.withLock { $0 = onSamples }
        do {
            try open()
        } catch {
            sink.withLock { $0 = nil }
            throw error
        }
    }

    /// Builds an engine for whatever the current input device is, and starts it.
    private func open() throws(AudioCaptureError) {
        guard let onSamples = sink.withLock({ $0 }) else { throw .notRecording }

        let engine = AVAudioEngine()
        let inputBus: AVAudioNodeBus = 0
        let format = engine.inputNode.inputFormat(forBus: inputBus)

        // A missing input device reports a zero-rate format rather than failing.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw .noInputDevice
        }
        guard let resampler = AudioResampler(inputFormat: format) else {
            throw .unsupportedInputFormat
        }

        engine.inputNode.installTap(onBus: inputBus, bufferSize: Self.tapBufferSize, format: format) {
            buffer, _ in
            // On the audio thread: a dropped buffer costs milliseconds, a throw the recording.
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

        let live = Running(engine: engine, inputBus: inputBus)
        // On the main queue, not whichever thread CoreAudio noticed the change on.
        live.observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.hardwareChanged()
        }
        running.withLock { $0 = live }
    }

    /// Rebuilds the engine that macOS stopped under it. See `Docs/microphone.md`.
    private func hardwareChanged() {
        guard sink.withLock({ $0 }) != nil else { return }
        close()
        // A device gone and not replaced leaves nothing arriving, which reads as silence.
        try? open()
    }

    public func stop() {
        sink.withLock { $0 = nil }
        close()
    }

    /// Tears the engine down without forgetting where samples were going.
    private func close() {
        guard
            let live = running.withLock({ running -> Running? in
                defer { running = nil }
                return running
            })
        else { return }

        if let observer = live.observer { NotificationCenter.default.removeObserver(observer) }
        live.engine.inputNode.removeTap(onBus: live.inputBus)
        live.engine.stop()
    }
}
