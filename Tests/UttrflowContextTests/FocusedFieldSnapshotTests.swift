import CoreGraphics
import Foundation
import Testing

@testable import UttrflowContext

/// One reading, named only by what each test is about.
private func snapshot(
    role: String = "AXTextField",
    identifier: String? = nil,
    placeholder: String? = nil,
    accessibilityDescription: String? = nil,
    value: String? = "git c",
    selection: NSRange? = NSRange(location: 5, length: 0),
    caret: CGRect? = CGRect(x: 10, y: 20, width: 1, height: 16),
    pointSize: CGFloat? = 13,
    isSecure: Bool = false
) -> FocusedFieldSnapshot {
    FocusedFieldSnapshot(
        bundleIdentifier: "com.apple.Terminal", applicationName: "Terminal", role: role,
        identifier: identifier, placeholder: placeholder,
        accessibilityDescription: accessibilityDescription, value: value, selection: selection,
        caret: caret, pointSize: pointSize, isSecure: isSecure, readMicroseconds: 400)
}

@Suite("What one reading of the focused field says")
struct FocusedFieldSnapshotTests {
    @Test("A field that answers everything takes the inline ghost.")
    func fullyAnsweringFieldsTakeTheGhost() {
        #expect(snapshot().placement == .inlineGhost)
    }

    @Test("A field that hides its styling gets the chip under the caret instead.")
    func noStyleMeansAChip() {
        #expect(snapshot(pointSize: nil).placement == .caretChip)
    }

    @Test("A field that hides its caret leaves only the strip.")
    func noCaretMeansTheStrip() {
        #expect(snapshot(caret: nil).placement == .windowStrip)
    }

    @Test("A field that will not say what it holds can take nothing at all.")
    func nothingToReadMeansNothingDrawn() {
        #expect(snapshot(value: nil).placement == nil)
    }

    @Test("A password field can take nothing, however much else it answers.")
    func secureFieldsTakeNothing() {
        #expect(snapshot(isSecure: true).placement == nil)
    }

    @Test("The reading carries through to the capability the ladder is decided from.")
    func carriesTheReadingThrough() {
        let capability = snapshot(identifier: "search").capability
        #expect(capability.application == "Terminal")
        #expect(capability.locator == "search")
        #expect(capability.readMicroseconds == 400)
    }

    @Test("The locator takes the first name the field publishes.")
    func locatorPrefersTheIdentifier() {
        #expect(snapshot(identifier: "a", placeholder: "b").locator == "a")
        #expect(snapshot(placeholder: "b", accessibilityDescription: "c").locator == "b")
        #expect(snapshot(accessibilityDescription: "c").locator == "c")
        #expect(snapshot().locator == nil)
    }

    @Test("The caret is at the end when nothing follows it.")
    func caretAtTheEnd() {
        #expect(snapshot().caretAtEnd)
        #expect(!snapshot(selection: NSRange(location: 2, length: 0)).caretAtEnd)
    }

    @Test("A selection reaching the end still counts as the end.")
    func aSelectionToTheEndIsTheEnd() {
        #expect(snapshot(selection: NSRange(location: 1, length: 4)).caretAtEnd)
    }

    @Test("A field that says nothing about its caret is not at the end of anything.")
    func noSelectionIsNotTheEnd() {
        #expect(!snapshot(selection: nil).caretAtEnd)
        #expect(!snapshot(value: nil).caretAtEnd)
    }

    @Test("Selected text is text the next keystroke would replace.")
    func selectionIsNoticed() {
        #expect(snapshot(selection: NSRange(location: 0, length: 5)).hasSelection)
        #expect(!snapshot().hasSelection)
        #expect(!snapshot(selection: nil).hasSelection)
    }

    @Test("A multi-line field is the only one that reads as prose.")
    func onlyTextAreasAreProse() {
        #expect(snapshot(role: FocusedFieldSnapshot.proseRole).isProse)
        #expect(!snapshot().isProse)
    }
}
