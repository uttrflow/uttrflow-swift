public import struct Foundation.Date
public import struct Foundation.UUID

/// A dictation's audio, written to this Mac beside the live buffer so its words can be retried.
public struct KeptRecording: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    /// When the microphone opened.
    public let when: Date
    /// How much was said, read from the file rather than remembered.
    public let duration: Duration

    public init(id: UUID, when: Date, duration: Duration) {
        self.id = id
        self.when = when
        self.duration = duration
    }
}
