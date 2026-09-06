/// Which endings of a field's life finish its value, decided per field by whoever knows the application.
public struct CommitPolicy: Sendable {
    private let admitting: @Sendable (CommitReason, FieldReading) -> Bool

    public init(admitting: @escaping @Sendable (CommitReason, FieldReading) -> Bool) {
        self.admitting = admitting
    }

    /// Every ending finishes every field, which is right for anything that does not rewrite its own line.
    public static let everyEnding = CommitPolicy { _, _ in true }

    /// Return alone finishes a field in these applications, since a shell rewrites the line on the way out.
    public static func returnOnly(in bundleIdentifiers: Set<String>) -> CommitPolicy {
        CommitPolicy { reason, reading in
            reason == .returnPressed || !bundleIdentifiers.contains(reading.bundleIdentifier)
        }
    }

    /// Whether a value that ended this way in this field is one the person finished.
    public func admits(_ reason: CommitReason, in reading: FieldReading) -> Bool {
        admitting(reason, reading)
    }
}
