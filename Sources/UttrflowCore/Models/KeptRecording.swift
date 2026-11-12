public import struct Foundation.Date
public import struct Foundation.UUID

/// A dictation's audio, written to this Mac beside the live buffer so its words can be retried.
public struct KeptRecording: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    /// When the microphone opened.
    public let when: Date
    /// How much was said, read from the file rather than remembered.
    public let duration: Duration
    /// The non-sensitive destination facts used to resolve a retry's situation.
    public let destination: AppIdentity?
    /// The formatter destination seen during the original dictation, or `nil` for older recordings.
    public let fieldKind: Destination?
    /// Whether the original dictation was in a private-browsing window, so a retry learns nothing either.
    package let fromPrivateWindow: Bool

    public init(
        id: UUID, when: Date, duration: Duration, destination: AppIdentity? = nil,
        fieldKind: Destination? = nil, fromPrivateWindow: Bool = false
    ) {
        self.fromPrivateWindow = fromPrivateWindow
        self.id = id
        self.when = when
        self.duration = duration
        self.destination = destination
        self.fieldKind = fieldKind
    }
}
