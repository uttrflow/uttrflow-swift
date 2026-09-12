// Delivers converted microphone samples from an AVAudioEngine input tap.
private import AVFoundation
private import Foundation
public import UttrflowCore
private import Synchronization

/// The engine behind the microphone, opened and closed on demand so a session can reopen it.
private final class EngineDevice: InputDevice, @unchecked Sendable {
    /// One engine and the sink it feeds, so a transition publishes both or unwinds both.
    private final class Live: @unchecked Sendable {
        let engine: AVAudioEngine
        let inputBus: AVAudioNodeBus
        var observer: (any NSObjectProtocol)?

        init(engine: AVAudioEngine, inputBus: AVAudioNodeBus) {
            self.engine = engine
            self.inputBus = inputBus
        }
    }

    private struct State {
        /// Where samples go, kept so the tap can be rebuilt without the caller knowing.
        var sink: (@Sendable ([Float]) -> Void)?
        var live: Live?
    }

    private static let tapBufferSize: AVAudioFrameCount = 4096

    /// One lock for one invariant: at most one engine, alive exactly while a sink is installed.
    private let state = Mutex(State())
    /// Counts blocks off the tap, so key-up can wait for the one the hardware is still filling.
    private let drainer = TapDrain()
    /// Called when macOS changes the hardware under the engine, which only the session knows what to do about.
    private let changed = Mutex<(@Sendable () -> Void)?>(nil)

    func whenChanged(_ handle: @escaping @Sendable () -> Void) {
        changed.withLock { $0 = handle }
    }

    func deliver(to onSamples: (@Sendable ([Float]) -> Void)?) {
        state.withLock { $0.sink = onSamples }
    }

    /// Reads the sink rather than capturing it, so an engine that outlived its sink delivers to nobody.
    private func emit(_ samples: [Float]) {
        state.withLock(\.sink)?(samples)
        drainer.blockDelivered()
    }

    /// Waits out one tap period, or the next block, so the block the hardware is filling is not torn away.
    func drain() async {
        guard let live = state.withLock(\.live) else { return }
        let rate = live.engine.inputNode.inputFormat(forBus: live.inputBus).sampleRate
        await drainer.wait(TapDrain.window(tapFrames: Int(Self.tapBufferSize), sampleRate: rate))
    }

    /// Builds an engine for whatever the current input device is, and starts it.
    func open() throws(AudioCaptureError) {
        guard state.withLock(\.sink) != nil else { throw .notRecording }

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
            [weak self] buffer, _ in
            // On the audio thread: a dropped buffer costs milliseconds, a throw the recording.
            guard let samples = try? resampler.resample(buffer) else { return }
            self?.emit(samples)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: inputBus)
            throw .engineFailed(description: error.localizedDescription)
        }

        let live = Live(engine: engine, inputBus: inputBus)
        let changed = changed.withLock { $0 }
        // On the main queue, not whichever thread CoreAudio noticed the change on.
        live.observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in
            changed?()
        }

        // Published only if the recording is still wanted, so a stop that raced this cannot strand it.
        let published = state.withLock { state -> Bool in
            guard state.sink != nil else { return false }
            state.live = live
            return true
        }
        guard published else {
            unwind(live)
            throw .notRecording
        }
    }

    /// Tears the engine down without forgetting where samples were going.
    func close() {
        let live = state.withLock { state -> Live? in
            defer { state.live = nil }
            return state.live
        }
        guard let live else { return }
        unwind(live)
    }

    /// Stops an engine and forgets its observer, whether or not it was ever published.
    private func unwind(_ live: Live) {
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
        onInterruption: @escaping @Sendable (CaptureInterruption) -> Void
    ) throws(AudioCaptureError) {
        device.deliver(to: onSamples)
        do {
            try session.open(reporting: onInterruption)
        } catch {
            device.deliver(to: nil)
            throw error
        }
    }

    public func stop(draining: Bool) async {
        if draining { await device.drain() }
        device.deliver(to: nil)
        session.close()
    }
}
