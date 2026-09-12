// Delivers converted microphone samples from an AVAudioEngine input tap.
private import AVFoundation
private import Foundation
public import UttrflowCore
private import Synchronization

/// The engine behind the microphone, opened and closed on demand so a session can reopen it.
private final class EngineDevice: InputDevice, @unchecked Sendable {
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
    /// Called when macOS changes the hardware under the engine, which only the session knows what to do about.
    private let changed = Mutex<(@Sendable () -> Void)?>(nil)

    func whenChanged(_ handle: @escaping @Sendable () -> Void) {
        changed.withLock { $0 = handle }
    }

    func deliver(to onSamples: (@Sendable ([Float]) -> Void)?) {
        sink.withLock { $0 = onSamples }
    }

    /// Builds an engine for whatever the current input device is, and starts it.
    func open() throws(AudioCaptureError) {
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
        let changed = changed.withLock { $0 }
        // On the main queue, not whichever thread CoreAudio noticed the change on.
        live.observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in
            changed?()
        }
        running.withLock { $0 = live }
    }

    /// Tears the engine down without forgetting where samples were going.
    func close() {
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

/// The real microphone, verifiable only by speaking into a Mac and so not covered.
public final class AVAudioEngineMicrophoneSource: MicrophoneSource {
    private let device: EngineDevice
    private let session: InputDeviceSession

    public init() {
        device = EngineDevice()
        session = InputDeviceSession(device: device)
        let session = session
        // The notification is posted by an engine, so a failed reopen silences it: the retry replaces it.
        device.whenChanged { session.deviceChanged() }
    }

    public func start(
        onSamples: @escaping @Sendable ([Float]) -> Void,
        onFailure: @escaping @Sendable (AudioCaptureError) -> Void
    ) throws(AudioCaptureError) {
        device.deliver(to: onSamples)
        do {
            try session.open(reporting: onFailure)
        } catch {
            device.deliver(to: nil)
            throw error
        }
    }

    public func stop() {
        device.deliver(to: nil)
        session.close()
    }
}
