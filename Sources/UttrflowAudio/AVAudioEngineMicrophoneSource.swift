// Delivers converted microphone samples from an AVAudioEngine input tap.
private import AVFoundation
private import AudioToolbox
private import Foundation
public import UttrflowCore
private import Synchronization

/// The hardware-change handler, internal so tests can check that reading it leaves it as it was.
final class ChangeHandler: Sendable {
    /// The closure in a struct, since a bare closure read out of a `Mutex` is re-wrapped and written back.
    private struct Handler: Sendable {
        let call: @Sendable () -> Void
    }

    private let handler = Mutex<Handler?>(nil)

    func set(_ call: @escaping @Sendable () -> Void) { handler.withLock { $0 = Handler(call: call) } }

    func current() -> (@Sendable () -> Void)? { handler.withLock { $0 }?.call }

    /// The current handler, called only while `isCurrent` holds, since removing an observer leaves a queued block to run.
    func current(while isCurrent: @escaping @Sendable () -> Bool) -> @Sendable () -> Void {
        let call = current()
        return {
            guard isCurrent() else { return }
            call?()
        }
    }
}

/// The engine behind the microphone, opened and closed on demand so a session can reopen it.
private final class EngineDevice: InputDevice, @unchecked Sendable {
    /// One engine and the sink it feeds, so a transition publishes both or unwinds both.
    private final class Live: @unchecked Sendable {
        let engine: AVAudioEngine
        let inputBus: AVAudioNodeBus
        /// Carries this engine's samples off the tap thread, finished once the tap is removed.
        let handoff: TapHandoff
        var observer: (any NSObjectProtocol)?

        init(engine: AVAudioEngine, inputBus: AVAudioNodeBus, handoff: TapHandoff) {
            self.engine = engine
            self.inputBus = inputBus
            self.handoff = handoff
        }
    }

    /// One recording's sink, compared by identity so a tap from an earlier recording cannot reach a later one.
    private final class Sink: Sendable {
        let call: @Sendable ([Float]) -> Void
        init(_ call: @escaping @Sendable ([Float]) -> Void) { self.call = call }
    }

    private struct State {
        /// Where samples go, kept so the tap can be rebuilt without the caller knowing.
        var sink: Sink?
        var live: Live?
        /// What the latest open resolved to, so a fallback can be reported.
        var selection: InputSelection?
    }

    private static let tapBufferSize: AVAudioFrameCount = 4096

    /// One lock for one invariant: at most one engine, alive exactly while a sink is installed.
    private let state = Mutex(State())
    /// Counts blocks off the tap, so key-up can wait for the one the hardware is still filling.
    private let drainer = TapDrain()
    /// Called when macOS changes the hardware under the engine, which only the session knows what to do about.
    private let changed = ChangeHandler()
    /// Called when the tap's own clock shows a hole too long to fill, which only the session can report.
    private let broken = ChangeHandler()
    /// The user's chosen device UID, read at every open so a reopen sees a device that went.
    private let preferredUID: @Sendable () -> String?
    private let catalog: any AudioInputDeviceCatalog

    init(preferredUID: @escaping @Sendable () -> String?, catalog: any AudioInputDeviceCatalog) {
        self.preferredUID = preferredUID
        self.catalog = catalog
    }

    var selection: InputSelection? { state.withLock(\.selection) }

    func whenChanged(_ handle: @escaping @Sendable () -> Void) {
        changed.set(handle)
    }

    func whenBroken(_ handle: @escaping @Sendable () -> Void) {
        broken.set(handle)
    }

    func deliver(to onSamples: (@Sendable ([Float]) -> Void)?) {
        state.withLock { $0.sink = onSamples.map(Sink.init) }
    }

    /// Delivers only to the sink the tap was opened for, on the handoff's thread so the tap never waits on this lock.
    private func emit(_ samples: [Float], for owner: Sink, after clock: TapClock) {
        // Before the samples, so the hole is reported where it is rather than after the audio that follows it.
        if clock.takeBreak() { broken.current()?() }
        state.withLock { $0.sink === owner ? owner : nil }?.call(samples)
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
        guard let owner = state.withLock(\.sink) else { throw .notRecording }
        // Read before the engine: a refused microphone reports a working format and taps silence.
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw .microphoneDenied
        }

        let engine = AVAudioEngine()
        let inputBus: AVAudioNodeBus = 0
        let selection = Self.select(
            InputSelection.resolve(preferredUID: preferredUID(), present: catalog.inputDevices()), on: engine)
        state.withLock { $0.selection = selection }
        // Read after the device is set, since the format belongs to whichever device the node is on.
        let format = engine.inputNode.inputFormat(forBus: inputBus)

        // A missing input device reports a zero-rate format rather than failing.
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw .noInputDevice
        }
        guard let resampler = AudioResampler(inputFormat: format) else {
            throw .unsupportedInputFormat
        }

        let clock = TapClock(sampleRate: format.sampleRate)
        let handoff = TapHandoff { [weak self] samples in self?.emit(samples, for: owner, after: clock) }
        engine.inputNode.installTap(onBus: inputBus, bufferSize: Self.tapBufferSize, format: format) {
            buffer, time in
            // On the audio thread: checked against the hardware clock, converted, and copied into the handoff.
            clock.deliver(
                buffer, at: time.isSampleTimeValid ? time.sampleTime : nil, through: resampler, into: handoff)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: inputBus)
            handoff.finish()
            throw .engineFailed(description: error.localizedDescription)
        }

        let live = Live(engine: engine, inputBus: inputBus, handoff: handoff)
        let changed = changed.current { [weak self, weak live] in
            guard let self, let live else { return false }
            return self.state.withLock { $0.live === live }
        }
        // On the main queue, not whichever thread CoreAudio noticed the change on.
        live.observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { _ in
            changed()
        }

        // Published only if the recording is still wanted, so a stop that raced this cannot strand it.
        let published = state.withLock { state -> Bool in
            guard state.sink === owner else { return false }
            state.live = live
            return true
        }
        guard published else {
            unwind(live)
            throw .notRecording
        }
    }

    /// Points the input node at the chosen device, falling back to the default when it cannot.
    private static func select(_ selection: InputSelection, on engine: AVAudioEngine) -> InputSelection {
        guard let uid = selection.deviceUID else { return selection }
        guard var id = SystemInputDeviceCatalog.deviceID(forUID: uid),
            let unit = engine.inputNode.audioUnit
        else { return .fellBack }
        let status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        return status == noErr ? selection : .fellBack
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
        live.handoff.finish()
    }
}

/// The real microphone, verifiable only by speaking into a Mac and so not covered.
public final class AVAudioEngineMicrophoneSource: MicrophoneSource {
    private let device: EngineDevice
    /// Internal so a test can see it go when the source does.
    let session: InputDeviceSession

    /// Opens `preferredUID()` when present, else the system default; nil chooses the default.
    public init(
        preferredUID: @escaping @Sendable () -> String? = { nil },
        catalog: any AudioInputDeviceCatalog = SystemInputDeviceCatalog()
    ) {
        device = EngineDevice(preferredUID: preferredUID, catalog: catalog)
        session = InputDeviceSession(device: device)
        // Weak, as the session owns the device; a failed reopen silences the notice and the retry replaces it.
        device.whenChanged { [weak session] in session?.deviceChanged() }
        device.whenBroken { [weak session] in session?.timelineBroke() }
    }

    /// What the latest open resolved to, nil before the first; never logged, as it can carry a device UID.
    public var inputSelection: InputSelection? { device.selection }

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
