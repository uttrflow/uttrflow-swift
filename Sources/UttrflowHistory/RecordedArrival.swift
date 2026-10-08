public import UttrflowCore

/// Whether a kept dictation's words reached the field, so History can tell a delivered row from a salvaged one.
public enum RecordedArrival: String, Sendable, Equatable, Codable, CaseIterable {
    /// The words were read back from where they were sent.
    case confirmed
    /// The target would not say what it holds, so nothing is proved either way.
    case notReported
    /// The wait ran out with no sign of the words; they were left on the clipboard.
    case unconfirmed
    /// The dictation failed or was cancelled, so the words were kept but never inserted.
    case notInserted

    /// The stored form of an insertion's arrival.
    public init(_ arrival: InsertionArrival) {
        switch arrival {
        case .confirmed: self = .confirmed
        case .notReported: self = .notReported
        case .unconfirmed: self = .unconfirmed
        }
    }
}
