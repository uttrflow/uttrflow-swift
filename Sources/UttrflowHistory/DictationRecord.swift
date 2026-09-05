public import struct Foundation.Date
public import struct Foundation.UUID

/// One finished dictation as it is kept on disk; no audio and no path to any. See `Docs/recordings.md`.
public struct DictationRecord: Sendable, Equatable, Identifiable, Codable {
    /// Identifies the dictation across the history and its corrections.
    public let id: UUID
    /// The inserted text after tidying; module-settable so ``undoing(_:)`` edits a copy, never a rebuild.
    public internal(set) var text: String
    /// When the dictation finished.
    public let when: Date
    /// The application the text went into, when that was known.
    public let applicationName: String?
    /// That application's bundle identifier, when known; what its icon is looked up by.
    public let applicationIdentifier: String?
    /// How long the speaker talked, when measured.
    public let spokenFor: Duration?
    /// What Uttrflow changed; empty is "as spoken", `nil` is unmeasured. See Docs/core-history-accuracy.md.
    public var changes: RecordedChanges?
    /// Whether the user has said this came out wrong; the one judgement here Uttrflow does not make.
    public var isFlagged: Bool

    /// Builds a record; every field after `text` and `when` defaults to unknown or unflagged.
    public init(
        id: UUID = UUID(), text: String, when: Date, applicationName: String? = nil,
        applicationIdentifier: String? = nil, spokenFor: Duration? = nil,
        changes: RecordedChanges? = nil, isFlagged: Bool = false
    ) {
        self.id = id
        self.text = text
        self.when = when
        self.applicationName = applicationName
        self.applicationIdentifier = applicationIdentifier
        self.spokenFor = spokenFor
        self.changes = changes
        self.isFlagged = isFlagged
    }

    /// Reads ``isFlagged`` as `false` when absent, since the store discards a file it cannot decode.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        when = try values.decode(Date.self, forKey: .when)
        applicationName = try values.decodeIfPresent(String.self, forKey: .applicationName)
        applicationIdentifier = try values.decodeIfPresent(
            String.self, forKey: .applicationIdentifier)
        spokenFor = try values.decodeIfPresent(Duration.self, forKey: .spokenFor)
        changes = try values.decodeIfPresent(RecordedChanges.self, forKey: .changes)
        isFlagged = try values.decodeIfPresent(Bool.self, forKey: .isFlagged) ?? false
    }

    /// Whether this is still within `days` of `now`; the one place "deleted after N days" is decided.
    public func survives(days: Int, now: Date) -> Bool {
        guard days > 0 else { return false }
        return when.addingTimeInterval(Double(days) * 86_400) > now
    }
}
