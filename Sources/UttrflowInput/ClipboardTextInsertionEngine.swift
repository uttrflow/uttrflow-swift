public import UttrflowCore

/// The last resort: leaves the text on the clipboard and says so, so the words are never lost.
public struct ClipboardTextInsertionEngine: TextInsertionEngine {
    /// Not `.pasteboard`: this says the words are waiting, where that says a paste landed.
    public let method: TextInsertionMethod = .clipboard

    private let pasteboard: any Pasteboard
    /// Asked whether the field the words were meant for is secure, so what is left behind is concealed.
    private let focus: (any AccessibilityFocus)?

    public init(pasteboard: any Pasteboard, focus: (any AccessibilityFocus)? = nil) {
        self.pasteboard = pasteboard
        self.focus = focus
    }

    /// Always. A clipboard is always available, which is the point of having this.
    public func canInsert() async -> Bool { true }

    /// Answers `.notReported`: nothing was sent anywhere, so there is no arrival to have an opinion about.
    public func insert(_ text: String) async throws(TextInsertionError) -> InsertionArrival {
        // Even the floor: the words are already kept under Recent, and the clipboard is the user's.
        guard !Task.isCancelled else {
            throw .insertionRejected(description: TextInsertion.dictationEnded)
        }
        if focus?.focusedFieldIsSecure() == true {
            pasteboard.setConcealedText(text)
        } else {
            pasteboard.setText(text)
        }
        guard pasteboard.text() == text else { throw .clipboardUnavailable }
        return .notReported
    }
}
