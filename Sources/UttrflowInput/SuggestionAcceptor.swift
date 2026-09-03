public import UttrflowCore
private import UttrflowPredict

/// Puts an accepted suggestion into the field, and never onto the clipboard. See `Docs/predict-accept.md`.
public struct SuggestionAcceptor: Sendable {
    private let coordinator: TextInsertionCoordinator

    public init(coordinator: TextInsertionCoordinator) {
        self.coordinator = coordinator
    }

    /// The strategies this will try, so a caller can prove the clipboard is not among them.
    public var route: [TextInsertionMethod] { coordinator.route }

    /// Inserts what the suggestion adds to what is typed, or nothing when it adds nothing.
    @discardableResult
    public func accept(
        _ suggestion: String, after typed: String
    ) async throws(TextInsertionError) -> TextInsertionMethod? {
        guard let remainder = Acceptance.remainder(of: suggestion, after: typed) else { return nil }
        return try await coordinator.insert(remainder)
    }
}
