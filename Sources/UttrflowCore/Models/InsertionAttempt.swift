// What an insertion strategy answers: how the words were sent, and whether they were seen to arrive.

/// Whether the words were seen to reach the caret, which only a strategy that reads back can answer.
public enum InsertionArrival: String, Sendable, Equatable, CaseIterable, Codable {
    /// The words were read back from where they were sent, so they are on screen.
    case confirmed
    /// The target will not say what it holds, so nothing is proved either way. See `Docs/insertion.md`.
    case notReported
    /// The wait ran out with no sign of them, and they are still on the clipboard.
    case unconfirmed
}

/// Where the words were written, read at the moment of the write rather than remembered from the recording.
public struct InsertionDestination: Sendable, Equatable, Codable {
    public let applicationName: String?
    public let bundleIdentifier: String?

    public init(applicationName: String?, bundleIdentifier: String?) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
    }

    /// Whether the destination says anything at all, since a reader that will not answer gives two nils.
    public var isKnown: Bool { applicationName != nil || bundleIdentifier != nil }
}

/// How finished text was sent and whether it arrived, which one value so neither can be reported without the other.
public struct InsertionAttempt: Sendable, Equatable {
    public let method: TextInsertionMethod
    public let arrival: InsertionArrival
    /// What was in front when the words were written, or nil where nothing could say. See `Docs/insertion.md`.
    public let destination: InsertionDestination?

    public init(
        _ method: TextInsertionMethod, arrival: InsertionArrival = .notReported,
        destination: InsertionDestination? = nil
    ) {
        self.method = method
        self.arrival = arrival
        self.destination = destination
    }
}
