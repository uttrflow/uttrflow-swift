// A SpeechEngine that answers as scripted.
public import UttrflowCore

/// A ``SpeechEngine`` that returns a scripted transcription.
public actor FakeSpeechEngine: SpeechEngine {
    public struct TranscribeCall: Sendable, Equatable {
        public let audio: AudioSamples
        public let options: TranscriptionOptions
    }

    public let kind: SpeechEngineKind
    public let prepareCalls = CallLog<Void>()
    public let transcribeCalls = CallLog<TranscribeCall>()

    private var prepareOutcome: ScriptedOutcome<Void, SpeechEngineError>
    private var transcribeOutcome: ScriptedOutcome<Transcription, SpeechEngineError>

    public init(
        kind: SpeechEngineKind = .whisperKit,
        prepareOutcome: ScriptedOutcome<Void, SpeechEngineError> = .ok,
        transcribeOutcome: ScriptedOutcome<Transcription, SpeechEngineError> = .success(.fixture())
    ) {
        self.kind = kind
        self.prepareOutcome = prepareOutcome
        self.transcribeOutcome = transcribeOutcome
    }

    public func prepare() async throws(SpeechEngineError) {
        await prepareCalls.append(())
        try prepareOutcome.resolve()
    }

    public func transcribe(
        _ audio: AudioSamples,
        options: TranscriptionOptions
    ) async throws(SpeechEngineError) -> Transcription {
        await transcribeCalls.append(.init(audio: audio, options: options))
        return try transcribeOutcome.resolve()
    }

    // MARK: Scripting

    public func setPrepareOutcome(_ outcome: ScriptedOutcome<Void, SpeechEngineError>) {
        prepareOutcome = outcome
    }

    public func setTranscribeOutcome(_ outcome: ScriptedOutcome<Transcription, SpeechEngineError>) {
        transcribeOutcome = outcome
    }
}
