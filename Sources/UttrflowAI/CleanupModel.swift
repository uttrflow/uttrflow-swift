public import UttrflowCore

/// A language model that can rewrite one short piece of text.
///
/// The boundary that keeps every rule about *using* a model — the prompt, the
/// meaning checks, the tidying afterwards — testable without one.
public protocol CleanupModel: Sendable {
    /// Whether this model can handle a request, chiefly whether it knows the language.
    func availability(for language: LanguageCode?) async -> TransformerAvailability

    /// Rewrites `text` under `instructions`.
    ///
    /// - Returns: The rewritten text, with no wrapper or commentary.
    /// - Throws: ``TransformationError/transformFailed(kind:description:)``.
    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String

    /// Gets ready to rewrite under `instructions`, so the next ``rewrite`` does not pay for that.
    func warm(instructions: String) async
}

extension CleanupModel {
    /// Nothing to prepare, which is what a hosted model has.
    public func warm(instructions: String) async {}
}
