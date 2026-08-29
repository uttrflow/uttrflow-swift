public import struct Foundation.Date
public import struct Foundation.UUID

/// One change Uttrflow made, and the dictation it was made in.
///
/// The join of a ``RecordedCorrection`` with the ``DictationRecord`` that holds it, done
/// once here rather than at each page: the change knows what was swapped, the record
/// knows when it happened and where the words went, and every page that lists changes
/// wants both. Nothing on it can undo anything — the range and the entry to blame stay
/// on the stored value, because a page has no business with either.
///
/// Not `Codable`, unlike the value it is drawn from. Nothing writes this shape down, and
/// a persistence conformance on a projection is an invitation to write the projection
/// instead of the record.
public struct Correction: Sendable, Equatable, Identifiable {
    public let id: UUID
    /// The dictation this happened in, so the row can say where and the badge on that
    /// dictation can lead back here.
    public let dictation: UUID
    public let heard: String
    public let wrote: String
    public let reason: CorrectionReason
    public let when: Date
    public let applicationName: String?
    /// Whether the user has already put it back.
    public let isUndone: Bool

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
    case all
    case applied
    case undone

    public var title: String {
        switch self {
        case .all: "All changes"
        case .applied: "Still applied"
        case .undone: "Undone"
        }
    }

    /// The changes this scope lists.
    ///
    /// On the scope rather than on whatever is doing the listing, because the store and
    /// the page both narrow the same list and two implementations of "still applied" is
    /// two chances for the pop-up to disagree with the rows under it.
    public func matching(_ corrections: [Correction]) -> [Correction] {
        switch self {
        case .all: corrections
        case .applied: corrections.filter { !$0.isUndone }
        case .undone: corrections.filter(\.isUndone)
        }
    }
}

/// Every change Uttrflow made across a run of dictations, and whether that is all of them.
///
/// A value over records already in hand rather than only a method on the store, because
/// the window that draws these has just read the history to list the dictations
/// themselves: making it ask again would be a second file read for something already
/// answered, and a second answer that could differ from the first.
public struct CorrectionHistory: Sendable {
    /// Newest dictation first, and within one dictation in the order the words were
    /// spoken — which is the order they read in the sentence, and the only order a
    /// single utterance has.
    public let corrections: [Correction]

    /// - Parameters:
    ///   - records: The dictations to read, newest first — the order they come out of
    ///     ``DictationHistoryStore`` in, and the order the changes keep.
    ///   - scope: Which of them to list.
    public init(of records: [DictationRecord], in scope: CorrectionsScope = .all) {
        corrections = scope.matching(
            records.flatMap { record in
                (record.changes?.corrections ?? []).map { Correction($0, in: record) }
            })
    }
}
