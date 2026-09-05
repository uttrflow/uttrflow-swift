/// Turns a raw transcript into the words the speaker meant.
///
/// The pipeline depends on this rather than on the router that implements it, so the
/// whole speak-to-inserted sequence can be tested without a language model anywhere
/// near it — and so that swapping how cleaning is chosen changes nothing above.
public protocol TranscriptCleaning: Sendable {
    func clean(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult

    /// Gets ready for a request going to `situation`, or to nowhere known, so the first one is not the slow one.
    func warm(for situation: Situation?) async
}

extension TranscriptCleaning {
    /// Nothing to prepare, which is what most cleaners have.
    public func warm(for situation: Situation?) async {}
}

/// Puts finished text wherever the user is typing.
///
/// Same reason: the pipeline should not know which strategies exist, only that
/// something will get the words there and say how.
public protocol TextInserting: Sendable {
    @discardableResult
    func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod

    /// E2, B6 — insert, carrying formatting where the clip has any.
    ///
    /// Separate from ``insert(_:)`` rather than an optional parameter on it, so that every
    /// existing caller keeps meaning exactly what it meant: a dictation is words, and has
    /// no rich form to lose.
    @discardableResult
    func insert(
        _ text: String, richText: String?
    ) async throws(TextInsertionError)
        -> TextInsertionMethod
}

extension TextInserting {
    /// Defaulted so every existing inserter and every test double keeps working. One that
    /// cannot carry formatting inserts the words, which is what it always did.
    @discardableResult
    public func insert(
        _ text: String, richText: String?
    ) async throws(TextInsertionError)
        -> TextInsertionMethod
    {
        try await insert(text)
    }
}
