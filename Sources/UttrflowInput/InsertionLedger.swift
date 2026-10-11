// Remembers, in memory only, where the last confirmed dictations landed, so a later command can find them.
private import Synchronization
public import UttrflowCore

/// The focused field and its caret in UTF-16 units, read in one Accessibility pass.
public struct FieldPlace: Sendable, Equatable {
    public let field: FieldIdentity
    public let caret: Int

    public init(field: FieldIdentity, caret: Int) {
        self.field = field
        self.caret = caret
    }
}

/// One confirmed write: the field, the UTF-16 span it now occupies and the words themselves.
public struct InsertionRecord: Sendable, Equatable {
    public let field: FieldIdentity
    public let range: Range<Int>
    public let text: String

    /// Whether the words are still exactly where they were written, in `fieldText` read now.
    public func stillThere(in fieldText: String) -> Bool {
        BackwardSelection.confirms(text, in: fieldText, endingAt: range.upperBound)
    }
}

/// The last few confirmed insertions into one field, never persisted and never sent. See `Docs/insertion.md`.
public final class InsertionLedger: Sendable {
    /// How many insertions are kept, oldest dropped first.
    public static let capacity = 8
    /// The longest insertion kept, in UTF-16 units; a longer one is not remembered at all.
    public static let textLimit = 4_096

    /// The longest a re-dictation can trail an insertion and still be read as respeaking it.
    public static let respeakWindow: Duration = .seconds(30)

    /// One record and the moment its write was confirmed.
    private struct Entry: Sendable {
        let record: InsertionRecord
        let writtenAt: ContinuousClock.Instant
    }

    private let records = Mutex<[Entry]>([])

    public init() {}

    /// Records a confirmed write that ended at `place.caret`; any other kind of write empties the ledger.
    func note(
        _ attempt: InsertionAttempt, text: String, endingAt place: FieldPlace?,
        at now: ContinuousClock.Instant = .now
    ) {
        let units = text.utf16.count
        guard attempt.method == .accessibility, attempt.arrival == .confirmed, !attempt.intoSecureField,
            let place, units > 0, units <= Self.textLimit, place.caret >= units
        else { return clear() }
        let range = (place.caret - units)..<place.caret
        let record = InsertionRecord(field: place.field, range: range, text: text)
        records.withLock { records in
            // A different field starts a fresh ledger, since its offsets mean nothing in the old one.
            if records.last?.record.field != place.field { records.removeAll() }
            records.append(Entry(record: record, writtenAt: now))
            if records.count > Self.capacity { records.removeFirst(records.count - Self.capacity) }
        }
    }

    /// The insertions into `field`, newest last; asking from any other field empties the ledger.
    public func records(in field: FieldIdentity?) -> [InsertionRecord] {
        entries(in: field).map(\.record)
    }

    /// The insertions into `field` confirmed within `respeakWindow` before `now`, newest last.
    public func recentRecords(
        in field: FieldIdentity?, now: ContinuousClock.Instant = .now
    ) -> [InsertionRecord] {
        entries(in: field).filter { now - $0.writtenAt <= Self.respeakWindow }.map(\.record)
    }

    private func entries(in field: FieldIdentity?) -> [Entry] {
        records.withLock { records in
            guard let field, records.last?.record.field == field else {
                records.removeAll()
                return []
            }
            return records
        }
    }

    /// Forgets every insertion.
    public func clear() {
        records.withLock { $0.removeAll() }
    }
}
