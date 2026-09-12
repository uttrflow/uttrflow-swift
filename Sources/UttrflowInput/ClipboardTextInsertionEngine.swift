public import UttrflowCore

/// The last resort: leaves the text on the clipboard and says so, so the words are never lost.
public struct ClipboardTextInsertionEngine: TextInsertionEngine {
    /// Not `.pasteboard`: this says the words are waiting, where that says a paste landed.
    public let method: TextInsertionMethod = .clipboard

    private let pasteboard: any Pasteboard

    public init(pasteboard: any Pasteboard) {
        self.pasteboard = pasteboard
    }

    /// Always. A clipboard is always available, which is the point of having this.
    public func canInsert() async -> Bool { true }

    /// Answers `.notReported`: nothing was sent anywhere, so there is no arrival to have an opinion about.
    public func insert(_ text: String) async throws(TextInsertionError) -> InsertionArrival {
        // Even the floor: the words are already kept under Recent, and the clipboard is the user's.
        guard !Task.isCancelled else {
            throw .insertionRejected(description: TextInsertion.dictationEnded)
        }
        pasteboard.setText(text)
        guard pasteboard.text() == text else { throw .clipboardUnavailable }
        return .notReported
    }
}
