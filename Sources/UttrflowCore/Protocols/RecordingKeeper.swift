// The keeper that holds a dictation's audio for retry, and the keeper that holds none.

public import struct Foundation.Date
public import struct Foundation.UUID

/// Keeps each dictation's audio on this Mac until its words land, so a lost dictation can be run again.
public protocol RecordingKeeper: Sendable {
    /// The recording written for the dictation that just stopped, if one was.
    func current() async -> KeptRecording?

    /// Deletes a recording: its words landed, or there is nothing in it worth retrying.
    func discard(_ id: UUID) async

    /// Every recording still waiting to become text, newest first, with anything stale deleted.
    func waiting(now: Date) async -> [KeptRecording]

    /// The audio of a waiting recording, in the shape the microphone delivers it.
    func audio(of id: UUID) async throws(AudioCaptureError) -> AudioSamples
}

/// A keeper that keeps nothing, for callers that have no disk to write to.
public struct RecordingsNotKept: RecordingKeeper {
    /// A keeper with nothing to set up.
    public init() {}

    public func current() async -> KeptRecording? { nil }

    public func discard(_ id: UUID) async {}

    public func waiting(now: Date) async -> [KeptRecording] { [] }

    public func audio(of id: UUID) async throws(AudioCaptureError) -> AudioSamples {
        throw .engineFailed(description: "no recording was kept")
    }
}
