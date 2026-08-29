public import UttrflowCore

/// Writes text straight into the focused field through the Accessibility API.
///
/// Preferred over pasting because it leaves the user's clipboard alone and puts the
/// text exactly where the caret is. It only works where the app exposes a text field
/// to Accessibility, which many do not — hence the strategies beneath it.
public struct AccessibilityTextInsertionEngine: TextInsertionEngine {
    public let method: TextInsertionMethod = .accessibility

    private let focus: any AccessibilityFocus

    public init(focus: any AccessibilityFocus) {
        self.focus = focus
    }

    public func canInsert() async -> Bool {
        focus.focusedTextField() != nil
    }

    public func insert(_ text: String) async throws(TextInsertionError) {
        guard let field = focus.focusedTextField() else { throw .noFocusedTextField }
        try field.replaceSelection(with: text)
    }
}
