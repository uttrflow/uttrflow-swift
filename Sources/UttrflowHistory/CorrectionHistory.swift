// What the Corrections page draws: one change joined to its dictation, a scope, and the list of them.
public import struct Foundation.Date
public import struct Foundation.UUID

/// One change joined to its dictation, for pages to draw; not `Codable`, so nothing writes the projection.
public struct Correction: Sendable, Equatable, Identifiable {
    /// The stored change's own identifier.
    public let id: UUID
    /// The dictation this happened in, so the row can say where and the badge can lead back here.
    public let dictation: UUID
    /// What the recogniser produced.
    public let heard: String
    /// What was written in its place.
    public let wrote: String
    /// Why the word was changed.
    public let reason: CorrectionReason
    /// When the dictation happened.
    public let when: Date
    /// The application the dictation went into, when known.
    public let applicationName: String?
    /// Whether the user has already put it back.
    public let isUndone: Bool

    /// Builds the projection field by field.
    public init(
        id: UUID = UUID(),
        dictation: UUID,
        heard: String,
        wrote: String,
        reason: CorrectionReason,
        when: Date,
        applicationName: String? = nil,
        isUndone: Bool = false
    ) {
        self.id = id
        self.dictation = dictation
        self.heard = heard
        self.wrote = wrote
        self.reason = reason
        self.when = when
        self.applicationName = applicationName
        self.isUndone = isUndone
    }

    /// One stored change, read out of the record that holds it.
    public init(_ made: RecordedCorrection, in record: DictationRecord) {
        self.init(
            id: made.id, dictation: record.id, heard: made.heard, wrote: made.wrote,
            reason: made.reason, when: record.when, applicationName: record.applicationName,
            isUndone: made.isUndone)
    }
}

/// Which changes are being listed.
public enum CorrectionsScope: String, Sendable, Equatable, CaseIterable {
    /// Every change.
    case all
    /// Changes still applied.
    case applied
    /// Changes the user put back.
    case undone

    /// What the pop-up calls the scope.
    public var title: String {
        switch self {
        case .all: "All changes"
        case .applied: "Still applied"
        case .undone: "Undone"
        }
    }

    /// The changes this scope lists; kept here so the store and the page cannot narrow the list differently.
    public func matching(_ corrections: [Correction]) -> [Correction] {
        switch self {
        case .all: corrections
        case .applied: corrections.filter { !$0.isUndone }
        case .undone: corrections.filter(\.isUndone)
        }
    }
}

/// Every change across records already in hand, so the window does not read the history file a second time.
public struct CorrectionHistory: Sendable {
    /// Newest dictation first, and within one dictation in the order the words were spoken.
    public let corrections: [Correction]

    /// Lists the changes in `records` (newest first, as the store returns them) that fall inside `scope`.
    public init(of records: [DictationRecord], in scope: CorrectionsScope = .all) {
        corrections = scope.matching(
            records.flatMap { record in
                (record.changes?.corrections ?? []).map { Correction($0, in: record) }
            })
    }
}
