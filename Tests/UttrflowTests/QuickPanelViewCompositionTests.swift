// Tests for the panel's keys when an input method is composing text in the field.

import Testing

@testable import Uttrflow

/// Return, Escape, ↑↓ must pass through to the input method while it is composing.
@Suite("The quick panel: Return, Escape and the arrows during input-method composition")
struct QuickPanelViewCompositionTests {
    @Test("marked text hands the panel key to the input method")
    func composingHandsKeyToInputMethod() {
        #expect(QuickPanelView.panelKeyResult(hasMarkedText: true) == .ignored)
    }

    /// Outside composition the panel keeps its four keys, so the loop is unchanged.
    @Test("no marked text keeps the panel key for the controller")
    func nonComposingKeepsKeyForPanel() {
        #expect(QuickPanelView.panelKeyResult(hasMarkedText: false) == .handled)
    }
}
