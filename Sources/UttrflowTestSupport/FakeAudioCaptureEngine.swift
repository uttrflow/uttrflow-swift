public import UttrflowCore

/// An ``AudioCaptureEngine`` that records its lifecycle calls and returns scripted audio.
public actor FakeAudioCaptureEngine: AudioCaptureEngine {
    public enum Event: Sendable, Equatable {
        case start
        case stop
        case cancel
    }

    public let calls = CallLog<Event>()

    private var currentState: AudioCaptureState = .idle
    private var startOutcome: ScriptedOutcome<Void, AudioCaptureError>
    private var stopOutcome: ScriptedOutcome<AudioSamples, AudioCaptureError>

    public init(
        startOutcome: ScriptedOutcome<Void, AudioCaptureError> = .ok,
        stopOutcome: ScriptedOutcome<AudioSamples, AudioCaptureError> = .success(.silence(seconds: 1))
    ) {
        self.startOutcome = startOutcome
        self.stopOutcome = stopOutcome
    }

    public var state: AudioCaptureState { currentState }

    public func start() async throws(AudioCaptureError) {
        await calls.append(.start)
        try startOutcome.resolve()
        currentState = .recording
    }

    public func stop() async throws(AudioCaptureError) -> AudioSamples {
        await calls.append(.stop)
        let samples = try stopOutcome.resolve()
        currentState = .idle
        return samples
    }

    public func cancel() async {
        await calls.append(.cancel)
        currentState = .idle
    }

    // MARK: Scripting

    public func setStartOutcome(_ outcome: ScriptedOutcome<Void, AudioCaptureError>) {
        startOutcome = outcome
    }

    public func setStopOutcome(_ outcome: ScriptedOutcome<AudioSamples, AudioCaptureError>) {
        stopOutcome = outcome
    }
}
