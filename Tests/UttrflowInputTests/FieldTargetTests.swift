import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

@Suite("Field-level insertion target")
struct FieldTargetTests {
    static let read = FieldIdentity(processIdentifier: 7, windowNumber: 1, element: 3)
    static let otherTab = FieldIdentity(processIdentifier: 7, windowNumber: 1, element: 4)
    static let otherWindow = FieldIdentity(processIdentifier: 7, windowNumber: 2, element: 3)
    static let destination = InsertionDestination(
        applicationName: "Browser", bundleIdentifier: "com.example.browser", field: read)

    @Test("refuses a different field in the same application and writes nothing")
    func refusesAnotherFieldOfTheSameApplication() async {
        let field = FakeTextField()
        let focus = FieldSwitchFocus(field: field, focused: Self.otherTab)

        await #expect(throws: TextInsertionError.insertionTargetChanged) {
            try await AccessibilityTextInsertionEngine(focus: focus).insert(
                "hello", targeting: Self.destination)
        }
        #expect(field.replacements.isEmpty)
    }

    @Test("refuses the same element hash in another window of the same application")
    func refusesAnotherWindow() async {
        let field = FakeTextField()
        let focus = FieldSwitchFocus(field: field, focused: Self.otherWindow)

        await #expect(throws: TextInsertionError.insertionTargetChanged) {
            try await AccessibilityTextInsertionEngine(focus: focus).insert(
                "hello", targeting: Self.destination)
        }
        #expect(field.replacements.isEmpty)
    }

    @Test("writes when the field read with the context is still focused")
    func writesIntoTheSameField() async throws {
        let field = FakeTextField()
        let focus = FieldSwitchFocus(field: field, focused: Self.read)

        _ = try await AccessibilityTextInsertionEngine(focus: focus).insert(
            "hello", targeting: Self.destination)
        #expect(field.replacements == ["hello"])
    }

    @Test("checks the application only when the field cannot be read now")
    func skipsAnUnreadableField() async throws {
        let field = FakeTextField()
        let focus = FieldSwitchFocus(field: field, focused: nil)

        _ = try await AccessibilityTextInsertionEngine(focus: focus).insert(
            "hello", targeting: Self.destination)
        #expect(field.replacements == ["hello"])
    }

    @Test("refuses as a closed field when the window it was read in is gone, and writes nothing")
    func refusesAClosedWindow() async {
        let field = FakeTextField()
        let focus = FieldSwitchFocus(field: field, focused: nil, openWindows: [])

        await #expect(throws: TextInsertionError.insertionFieldClosed) {
            try await AccessibilityTextInsertionEngine(focus: focus).insert(
                "hello", targeting: Self.destination)
        }
        #expect(field.replacements.isEmpty)
        #expect(TextInsertionError.insertionFieldClosed.stopsFallback)
        #expect(TextInsertionError.insertionFieldClosed.recovery == .showHistory)
    }

    @Test("writes when the window it was read in is still open")
    func writesWhileTheWindowIsOpen() async throws {
        let field = FakeTextField()
        let focus = FieldSwitchFocus(field: field, focused: Self.read, openWindows: [1])

        _ = try await AccessibilityTextInsertionEngine(focus: focus).insert(
            "hello", targeting: Self.destination)
        #expect(field.replacements == ["hello"])
    }

    @Test("a window only one read could name does not make two fields differ")
    func unnamedWindowStillMatches() {
        let unnamed = FieldIdentity(processIdentifier: 7, windowNumber: nil, element: 3)
        #expect(unnamed.isSameField(as: Self.read))
        #expect(Self.read.isSameField(as: unnamed))
        #expect(!unnamed.isSameField(as: Self.otherTab))
        #expect(!Self.read.isSameField(as: FieldIdentity(processIdentifier: 8, windowNumber: 1, element: 3)))
    }
}

/// One application in front throughout, whose focused field is whichever the test names.
private final class FieldSwitchFocus: AccessibilityFocus, Sendable {
    private let field: any FocusedTextField
    private let focused: FieldIdentity?
    private let openWindows: Set<UInt32>?

    init(field: any FocusedTextField, focused: FieldIdentity?, openWindows: Set<UInt32>? = nil) {
        self.field = field
        self.focused = focused
        self.openWindows = openWindows
    }

    func focusedTextField() -> (any FocusedTextField)? { field }
    func focusedTextField(in destination: InsertionDestination) -> (any FocusedTextField)? { field }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func focusedApplication() -> InsertionDestination? {
        InsertionDestination(applicationName: "Browser", bundleIdentifier: "com.example.browser")
    }
    func focusedFieldIdentity() -> FieldIdentity? { focused }
    func windowIsOpen(_ windowNumber: UInt32) -> Bool? { openWindows.map { $0.contains(windowNumber) } }
}
