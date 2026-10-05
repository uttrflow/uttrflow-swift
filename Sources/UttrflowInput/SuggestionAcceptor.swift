public import UttrflowCore
public import UttrflowPredict

/// Puts an accepted suggestion into the field, and never onto the clipboard. See `Docs/predict-accept.md`.
public struct SuggestionAcceptor: Sendable {
    /// What checking the field comes to, before a single key is sent.
    public enum Aim: Sendable, Equatable {
        /// The field is the line the suggestion was drawn for, and this is what it still needs.
        case write(Acceptance.Edit)
        /// The field already holds the whole suggestion, or nothing was offered, so nothing is written.
        case nothing
        /// The field cannot be shown to be that line, so nothing is written and the key belongs to the application.
        case refused(String)
    }

    private let completion: CompletionRoute
    private let focus: (any AccessibilityFocus)?

    /// Checks the field before writing when `focus` is given, since a read can lag the last keystroke.
    public init(completion: CompletionRoute, focus: (any AccessibilityFocus)? = nil) {
        self.completion = completion
        self.focus = focus
    }

    /// The strategies this will try, so a caller can prove the clipboard is not among them.
    public var route: [TextInsertionMethod] { completion.route }

    /// Waits for an insertion already in progress before the application terminates.
    public func finishWrites() async { await completion.finishWrites() }

    /// Does to the field exactly what the drawn suggestion promised, or nothing when it promised nothing.
    @discardableResult
    public func accept(
        _ suggestion: Suggestion, after typed: String, expectedWindowNumber: UInt32? = nil
    ) async throws(TextInsertionError) -> TextInsertionMethod? {
        let (aim, before) = await assess(
            suggestion, after: typed, expectedWindowNumber: expectedWindowNumber)
        switch aim {
        case .write(let edit):
            if let expectedWindowNumber {
                let focusedWindowNumber = await AccessibilityThread.run(orElse: nil) {
                    focus?.acceptanceFocusedWindowNumber()
                }
                guard focusedWindowNumber == expectedWindowNumber else {
                    throw .insertionRejected(
                        description: "the focused field is in a different or unidentified window")
                }
            }
            return try await completion.write(
                edit.inserted, replacing: edit.replaced, confirmedPreceding: before)
        case .nothing: return nil
        case .refused(let reason): throw .insertionRejected(description: reason)
        }
    }

    /// Writes an edit `aim` returned, adding its text and taking back what it replaces.
    public func write(
        _ edit: Acceptance.Edit, expectedWindowNumber: UInt32? = nil
    ) async throws(TextInsertionError) -> TextInsertionMethod? {
        if let expectedWindowNumber {
            let focusedWindowNumber = await AccessibilityThread.run(orElse: nil) {
                focus?.focusedWindowNumber()
            }
            guard focusedWindowNumber == expectedWindowNumber else {
                throw .insertionRejected(
                    description: "the focused field is in a different or unidentified window")
            }
        }
        return try await completion.write(edit.inserted, replacing: edit.replaced)
    }

    /// The drawn edit rebased onto the field as it is now, refused unless the field can be read and is that line.
    public func aim(
        _ suggestion: Suggestion, after typed: String, expectedWindowNumber: UInt32? = nil
    ) async -> Aim {
        await assess(suggestion, after: typed, expectedWindowNumber: expectedWindowNumber).aim
    }

    /// Reads the field once and carries the verified replacement suffix into the write.
    private func assess(
        _ suggestion: Suggestion, after typed: String, expectedWindowNumber: UInt32? = nil
    ) async -> (aim: Aim, confirmedPreceding: String?) {
        guard let drawn = suggestion.edit(after: typed) else { return (.nothing, nil) }
        guard let focus else { return (.write(drawn), nil) }
        // Asked first so the refusal names why, rather than reading as a field that will not answer.
        let isSecure = await AccessibilityThread.run(orElse: true) { focus.focusedFieldIsSecure() }
        if isSecure { return (.refused("the focused field hides what is typed"), nil) }
        let reach = max(typed.count + drawn.inserted.count, 1)
        let reading: (windowNumber: UInt32?, tail: FieldTail) = await AccessibilityThread.run(
            orElse: (windowNumber: nil, tail: FieldTail.unreadable)
        ) {
            focus.acceptanceWindowNumberAndTail(upTo: reach)
        }
        if let expectedWindowNumber {
            guard reading.windowNumber == expectedWindowNumber else {
                return (.refused("the focused field is in a different or unidentified window"), nil)
            }
        }
        // A ghost is drawn only where the field was read, so a field that cannot be read now is not the one it was drawn in.
        guard case .text(let before) = reading.tail else {
            return (.refused("the focused field cannot be read"), nil)
        }
        if let rebased = Acceptance.rebase(drawn, after: typed, onto: before) {
            let preceding = rebased.replaced.isEmpty ? nil : String(before.suffix(rebased.replaced.count))
            return (.write(rebased), preceding)
        }
        // The whole suggestion already being there means the keys got ahead of the read, and there is nothing left to do.
        if before.hasSuffix(typed + drawn.inserted), !drawn.isReplacement { return (.nothing, nil) }
        return (.refused("the text before the caret is not the line the suggestion was drawn for"), nil)
    }
}
