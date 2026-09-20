// Tests for when a row's hover-revealed controls are drawn.

import Testing

@testable import Uttrflow

@Suite("Hover-revealed row controls")
struct RowRevealTests {
    @Test("drawn under the pointer, as before")
    func drawnWhenHovered() {
        #expect(RowReveal.isDrawn(isHovered: true, focusedControl: nil))
    }

    @Test("drawn while one of the row's controls has keyboard focus, with the pointer elsewhere")
    func drawnWhenFocused() {
        #expect(RowReveal.isDrawn(isHovered: false, focusedControl: "Delete"))
    }

    @Test("hidden when neither the pointer nor the keyboard is on the row")
    func hiddenAtRest() {
        #expect(!RowReveal.isDrawn(isHovered: false, focusedControl: nil))
    }
}
