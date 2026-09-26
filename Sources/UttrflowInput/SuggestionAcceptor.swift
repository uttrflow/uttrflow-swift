public import UttrflowCore
public import UttrflowPredict

/// Puts an accepted suggestion into the field, and never onto the clipboard. See `Docs/predict-accept.md`.
public struct SuggestionAcceptor: Sendable {
    private let completion: CompletionRoute
    private let focus: (any AccessibilityFocus)?

    /// Checks the field before writing when `focus` is given, since a read can lag the last keystroke.
    public init(completion: CompletionRoute, focus: (any AccessibilityFocus)? = nil) {
        self.completion = completion
        self.focus = focus
    }

    /// The strategies this will try, so a caller can prove the clipboard is not among them.
    public var route: [TextInsertionMethod] { completion.route }

    /// Does to the field exactly what the drawn suggestion promised, or nothing when it promised nothing.
    @discardableResult
    public func accept(
        _ suggestion: Suggestion, after typed: String
    ) async throws(TextInsertionError) -> TextInsertionMethod? {
        guard let drawn = suggestion.edit(after: typed) else { return nil }
        guard let edit = try aimed(drawn, after: typed) else { return nil }
        return try await completion.write(edit.inserted, replacing: edit.replaced)
    }

    /// The drawn edit rebased onto the field as it is now, refusing when the field has moved away from the line.
    private func aimed(
        _ edit: Acceptance.Edit, after typed: String
    ) throws(TextInsertionError) -> Acceptance.Edit? {
        guard let focus else { return edit }
        let reach = typed.count + edit.inserted.count
        guard case .text(let before) = focus.tail(upTo: max(reach, 1)) else { return edit }
        if let rebased = Acceptance.rebase(edit, after: typed, onto: before) { return rebased }
        // The whole suggestion already being there means the keys got ahead of the read, and there is nothing left to do.
        if before.hasSuffix(typed + edit.inserted), !edit.isReplacement { return nil }
        throw .insertionRejected(
            description: "the text before the caret is not the line the suggestion was drawn for")
    }
}
