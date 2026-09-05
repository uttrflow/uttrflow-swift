public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.UUID

/// A ``RecordingKeeper`` that answers with scripted recordings and records what was discarded.
public actor FakeRecordingKeeper: RecordingKeeper {
    public private(set) var discarded: [UUID] = []
    public private(set) var audioRequests: [UUID] = []

    private var currentRecording: KeptRecording?
    private var waitingRecordings: [KeptRecording]
    private var audioOutcome: ScriptedOutcome<AudioSamples, AudioCaptureError>

    public init(
        current: KeptRecording? = nil,
        waiting: [KeptRecording] = [],
        audioOutcome: ScriptedOutcome<AudioSamples, AudioCaptureError> = .success(.silence(seconds: 1))
    ) {
        self.currentRecording = current
        self.waitingRecordings = waiting
        self.audioOutcome = audioOutcome
    }

    public func current() -> KeptRecording? { currentRecording }

    public func discard(_ id: UUID) {
        discarded.append(id)
        waitingRecordings.removeAll { $0.id == id }
        if currentRecording?.id == id { currentRecording = nil }
    }

    public func waiting(now: Date) -> [KeptRecording] { waitingRecordings }

    public func audio(of id: UUID) throws(AudioCaptureError) -> AudioSamples {
        audioRequests.append(id)
        return try audioOutcome.resolve()
    }

    // MARK: Scripting

    public func setCurrent(_ recording: KeptRecording?) {
        currentRecording = recording
    }
}
