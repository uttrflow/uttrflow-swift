// A RecordingKeeper that keeps recordings in memory.
public import UttrflowCore
public import struct Foundation.Date
public import struct Foundation.UUID

/// A ``RecordingKeeper`` that answers with scripted recordings and records what was discarded.
public actor FakeRecordingKeeper: RecordingKeeper {
    public private(set) var discarded: [UUID] = []
    public private(set) var audioRequests: [UUID] = []

    private var currentRecording: KeptRecording?
    private var waitingRecordings: [KeptRecording]
    /// Recordings whose words landed and are kept for a fix: readable, never listed as waiting.
    private var finishedRecordings: [KeptRecording]
    private var audioOutcome: ScriptedOutcome<AudioSamples, AudioCaptureError>

    public init(
        current: KeptRecording? = nil,
        waiting: [KeptRecording] = [],
        finished: [KeptRecording] = [],
        audioOutcome: ScriptedOutcome<AudioSamples, AudioCaptureError> = .success(.silence(seconds: 1))
    ) {
        self.currentRecording = current
        self.waitingRecordings = waiting
        self.finishedRecordings = finished
        self.audioOutcome = audioOutcome
    }

    public func current() -> KeptRecording? { currentRecording }

    public func setDestination(
        _ destination: AppContext, fieldKind: Destination, privateWindow: Bool, for id: UUID
    ) {
        let facts = (destination: destination, fieldKind: fieldKind, privateWindow: privateWindow)
        if let currentRecording, currentRecording.id == id {
            self.currentRecording = Self.recording(currentRecording, with: facts)
        }
        waitingRecordings = waitingRecordings.map { $0.id == id ? Self.recording($0, with: facts) : $0 }
        finishedRecordings = finishedRecordings.map { $0.id == id ? Self.recording($0, with: facts) : $0 }
    }

    public func discard(_ id: UUID) {
        discarded.append(id)
        waitingRecordings.removeAll { $0.id == id }
        finishedRecordings.removeAll { $0.id == id }
        if currentRecording?.id == id { currentRecording = nil }
    }

    public func waiting(now: Date) -> [KeptRecording] { waitingRecordings }

    public func audio(
        of id: UUID
    ) throws(AudioCaptureError)
        -> (audio: AudioSamples, recording: KeptRecording?)
    {
        audioRequests.append(id)
        let kept = ([currentRecording].compactMap { $0 } + waitingRecordings + finishedRecordings)
            .first { $0.id == id }
        guard let kept else { throw .engineFailed(description: "no recording kept for \(id)") }
        return (try audioOutcome.resolve(), kept)
    }

    // MARK: Scripting

    public func setCurrent(_ recording: KeptRecording?) {
        currentRecording = recording
    }

    private static func recording(
        _ recording: KeptRecording,
        with facts: (destination: AppContext, fieldKind: Destination, privateWindow: Bool)
    ) -> KeptRecording {
        KeptRecording(
            id: recording.id, when: recording.when, duration: recording.duration,
            destination: facts.destination.identity, fieldKind: facts.fieldKind,
            fromPrivateWindow: facts.privateWindow)
    }
}
