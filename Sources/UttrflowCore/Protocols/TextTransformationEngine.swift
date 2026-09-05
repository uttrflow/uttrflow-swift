/// Cleans a raw transcript into the text the user meant to write.
///
/// Implementations must never change the user's meaning. Where an implementation is
/// unsure it returns the original wording, and where it cannot help at all it reports
/// so through ``availability(for:)`` rather than by producing poor output.
public protocol TextTransformationEngine: Sendable {
    var kind: TransformerKind { get }

    /// Whether this engine can handle this particular request — chiefly, whether it
    /// supports the detected language.
    func availability(for request: TransformationRequest) async -> TransformerAvailability

    func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult

    /// Gets ready for a request that is about to come, so the first one is not the slow one.
    func warm() async
}

extension TextTransformationEngine {
    /// Nothing to prepare, which is what a rule-based engine has.
    public func warm() async {}
}
