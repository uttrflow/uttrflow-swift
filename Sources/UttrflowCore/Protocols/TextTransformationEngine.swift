/// Cleans a raw transcript into the text the user meant, never changing the meaning; unsure means unchanged.
public protocol TextTransformationEngine: Sendable {
    /// Which kind this engine is, for routing and for tagging its output.
    var kind: TransformerKind { get }

    /// Whether this engine can handle this request, chiefly whether it supports the detected language.
    func availability(for request: TransformationRequest) async -> TransformerAvailability

    /// Cleans one utterance, or throws when it cannot rather than producing poor output.
    func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult

    /// Gets ready for a request that is about to come, so the first one is not the slow one.
    func warm() async
}

/// The default warm-up: nothing.
extension TextTransformationEngine {
    /// Nothing to prepare, which is what a rule-based engine has.
    public func warm() async {}
}
