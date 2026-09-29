// The two protocols the pipeline drives its last stages through: cleaning a transcript and inserting text.

/// Turns a raw transcript into the words the speaker meant; the pipeline sees this, never the router behind.
public protocol TranscriptCleaning: Sendable {
    /// Cleans one transcript, or throws when no cleaner can.
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult

    /// Gets ready for a request going to `situation`, or to nowhere known, so the first one is not the slow one.
    func warm(for situation: Situation?) async

    /// Finishes a message joined from pieces cleaned at `.piece` scope: its casing and its final stop, asked once.
    func finishMessage(_ text: String, for request: TransformationRequest) async -> String

    /// Reserves the next prepared model session for the final piece of this dictation.
    func reserveFinalPiece(_ situation: Situation?) async
}

extension TranscriptCleaning {
    /// Nothing to prepare, which is what most cleaners have.
    public func warm(for situation: Situation?) async {}

    /// The message as joined, which is right for a cleaner that finishes each piece itself.
    public func finishMessage(_ text: String, for request: TransformationRequest) async -> String {
        text
    }

    /// Does nothing for cleaners without a prepared model session.
    public func reserveFinalPiece(_ situation: Situation?) async {}
}

/// Puts finished text wherever the user is typing and says how; the pipeline never sees the strategies.
public protocol TextInserting: Sendable {
    /// Inserts plain words and reports the method that carried them and whether they arrived.
    @discardableResult
    func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt

    /// Inserts only when the application still matches the destination captured for this insertion.
    @discardableResult
    func insert(
        _ text: String, targeting destination: InsertionDestination
    ) async throws(TextInsertionError) -> InsertionAttempt

    /// Inserts formatted text only when the application still matches the captured destination.
    @discardableResult
    func insert(
        _ text: String, richText: String?, targeting destination: InsertionDestination
    ) async throws(TextInsertionError) -> InsertionAttempt

    /// Inserts text carrying formatting where the clip has any; separate so a dictation stays plain words.
    @discardableResult
    func insert(
        _ text: String, richText: String?
    ) async throws(TextInsertionError)
        -> InsertionAttempt
}

/// The default for inserters that cannot carry formatting: insert the words.
extension TextInserting {
    /// Inserters without destination checks keep their existing behavior.
    @discardableResult
    public func insert(
        _ text: String, targeting destination: InsertionDestination
    ) async throws(TextInsertionError) -> InsertionAttempt {
        try await insert(text)
    }

    /// Inserters without destination checks keep their existing behavior.
    @discardableResult
    public func insert(
        _ text: String, richText: String?, targeting destination: InsertionDestination
    ) async throws(TextInsertionError) -> InsertionAttempt {
        try await insert(text, richText: richText)
    }

    /// Inserts the plain words and drops the rich form.
    @discardableResult
    public func insert(
        _ text: String, richText: String?
    ) async throws(TextInsertionError)
        -> InsertionAttempt
    {
        try await insert(text)
    }
}
