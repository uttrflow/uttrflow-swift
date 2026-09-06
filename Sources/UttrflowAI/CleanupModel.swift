public import UttrflowCore

/// A language model that rewrites one short text; the boundary that keeps prompt and guards testable.
public protocol CleanupModel: Sendable {
    /// Whether this model can handle a request, chiefly whether it knows the language.
    func availability(for language: LanguageCode?) async -> TransformerAvailability

    /// Rewrites `text` under `instructions` with no wrapper or commentary, or throws `transformFailed`.
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
