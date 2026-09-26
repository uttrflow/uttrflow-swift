private import UttrflowCore
private import UttrflowPredict

/// Which endings of a field's life finish its value, decided per field by whoever knows the application.
public struct CommitPolicy: Sendable {
    private let admitting: @Sendable (CommitReason, FieldReading) -> Bool

    /// A policy that finishes a field exactly where this answers true.
    public init(admitting: @escaping @Sendable (CommitReason, FieldReading) -> Bool) {
        self.admitting = admitting
    }

    /// Every ending finishes every field, which is right for anything that does not rewrite its own line.
    public static let everyEnding = CommitPolicy { _, _ in true }

    /// Return alone finishes a field where the words are sent rather than kept: a shell, and a chat composer.
    public static let whereReturnSends = CommitPolicy { reason, reading in
        reason == .returnPressed || !sendsOnReturn(reading.bundleIdentifier)
    }

    /// Whether this application's fields are sent with Return, so a line left in one was never a value.
    static func sendsOnReturn(_ bundleIdentifier: String) -> Bool {
        if TerminalApplications.contains(bundleIdentifier) { return true }
        // The destination table already knows which applications are conversations. See `Docs/predict.md`.
        return DestinationClassifier.classify(AppContext(bundleIdentifier: bundleIdentifier))
            == .messaging
    }

    /// Whether a value that ended this way in this field is one the person finished.
    public func admits(_ reason: CommitReason, in reading: FieldReading) -> Bool {
        admitting(reason, reading)
    }
}
