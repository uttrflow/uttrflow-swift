public import UttrflowCore
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
    /// What a flag names as wrong; `nil` on a flagged record is an unlabelled flag.
    public var flagReason: FlagReason?
    /// Which engine tidied the words, so a flagged record tells clean-up apart from mis-hearing; `nil` is unrecorded.
    public let cleanedBy: TransformerKind?
    /// Whether the words reached the field; `nil` is unrecorded, as in an older file.
    public let arrival: RecordedArrival?
    /// Where each rules pass changed the written words, holding no word; `nil` is unlocated. See Docs/core-history-undo.md.
    public let changeLedger: [ChangeLedgerEntry]?
    /// Why the wait after key-up ran past its target, kept on this Mac only; `nil` is kept to it or untimed.
    public let slowCause: SlowDictationCause?
    /// The recogniser's words before clean-up, so a wrong dictation tells mis-hearing apart from clean-up; `nil` is unrecorded or unchanged.
    public let heard: String?

    /// Builds a record; every field after `text` and `when` defaults to unknown or unflagged.
    public init(
        id: UUID = UUID(), text: String, when: Date, applicationName: String? = nil,
        applicationIdentifier: String? = nil, spokenFor: Duration? = nil,
        changes: RecordedChanges? = nil, isFlagged: Bool = false,
        flagReason: FlagReason? = nil, cleanedBy: TransformerKind? = nil,
        arrival: RecordedArrival? = nil, changeLedger: [ChangeLedgerEntry]? = nil,
        slowCause: SlowDictationCause? = nil, heard: String? = nil
    ) {
        self.id = id
        self.text = text
        self.when = when
        self.applicationName = applicationName
        self.applicationIdentifier = applicationIdentifier
        self.spokenFor = spokenFor
        self.changes = changes
        self.isFlagged = isFlagged
        self.flagReason = flagReason
        self.cleanedBy = cleanedBy
        self.arrival = arrival
        self.changeLedger = changeLedger
        self.slowCause = slowCause
        self.heard = heard
    }

    /// Reads ``isFlagged`` as `false` and ``flagReason`` as unlabelled when absent, since the store discards a file it cannot decode.
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
        flagReason = try values.decodeIfPresent(FlagReason.self, forKey: .flagReason)
        cleanedBy = try values.decodeIfPresent(TransformerKind.self, forKey: .cleanedBy)
        // Read as text so an arrival a newer build adds becomes unknown instead of discarding the file.
        arrival = try values.decodeIfPresent(String.self, forKey: .arrival)
            .flatMap(RecordedArrival.init(rawValue:))
        // A ledger a newer build wrote with a kind this one lacks is unlocated, never a discarded file.
        changeLedger = try? values.decodeIfPresent([ChangeLedgerEntry].self, forKey: .changeLedger)
        // Read as text so a cause a newer build adds becomes unknown instead of discarding the file.
        slowCause = try values.decodeIfPresent(String.self, forKey: .slowCause)
            .flatMap(SlowDictationCause.init(rawValue:))
        heard = try values.decodeIfPresent(String.self, forKey: .heard)
    }

    /// Whether this is still within `days` of `now`; the one place "deleted after N days" is decided.
    public func survives(days: Int, now: Date) -> Bool {
        RetentionWindow(days: days, now: now).keeps(when)
    }
}
