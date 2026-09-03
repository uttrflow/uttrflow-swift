public import UttrflowCore
public import UttrflowPredict

/// Puts an accepted suggestion into the field, and never onto the clipboard. See `Docs/predict-accept.md`.
public struct SuggestionAcceptor: Sendable {
    private let completion: CompletionRoute

    public init(completion: CompletionRoute) {
        self.completion = completion
    }

    /// The strategies this will try, so a caller can prove the clipboard is not among them.
    public var route: [TextInsertionMethod] { completion.route }

    /// Does to the field exactly what the drawn suggestion promised, or nothing when it promised nothing.
    @discardableResult
    public func accept(
        _ suggestion: Suggestion, after typed: String
    ) async throws(TextInsertionError) -> TextInsertionMethod? {
        guard let edit = suggestion.edit(after: typed) else { return nil }
        return try await completion.write(edit.inserted, replacing: edit.replacedCount)
    }
}
