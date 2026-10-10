import Synchronization
import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowInput

/// A field whose caret holds what the fake typist let through, or that never says.
private final class TypedField: AccessibilityFocus, @unchecked Sendable {
    private let held = Mutex("earlier words ")
    private let readable: Bool

    init(readable: Bool = true) { self.readable = readable }

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func focusedApplication() -> InsertionDestination? {
        InsertionDestination(applicationName: "Notes", bundleIdentifier: "example.notes")
    }

    func tail(upTo count: Int) -> FieldTail {
        guard readable else { return .unreadable }
        return .text(String(held.withLock { $0 }.suffix(count)))
    }

    func receive(_ text: String) { held.withLock { $0 += text } }
}

/// Types into `field`, or drops every key the way a remote desktop or secure keyboard entry does.
private struct FakeTypist: KeystrokeTyping {
    let field: TypedField
    let dropsKeys: Bool

    func type(_ text: String) throws(TextInsertionError) {
        if !dropsKeys { field.receive(text) }
    }

    func deleteBackwards(_ count: Int) throws(TextInsertionError) {}
}

@Suite("What the typed route reports about arrival")
struct TypedInsertionArrivalTests {
    private let words = "the words I just dictated to the field"

    private func engine(_ field: TypedField, dropsKeys: Bool) -> TypedTextInsertionEngine {
        let clock = ManualClock(advancesWhenSlept: true)
        let confirmation = PasteConfirmation(
            focus: field, clock: clock, budget: .milliseconds(10), interval: .milliseconds(1))
        return TypedTextInsertionEngine(
            focus: field, typist: FakeTypist(field: field, dropsKeys: dropsKeys), confirmation: confirmation)
    }

    @Test("Typed words read back behind the caret are confirmed.")
    func confirmsTypedWords() async throws {
        let field = TypedField()
        #expect(try await engine(field, dropsKeys: false).insert(words) == .confirmed)
    }

    @Test("Keys the target drops end unconfirmed, not in a plain tick.")
    func droppedKeysAreUnconfirmed() async throws {
        let field = TypedField()
        #expect(try await engine(field, dropsKeys: true).insert(words) == .unconfirmed)
    }

    @Test("A field that will not say what it holds is not reported.")
    func unreadableFieldIsNotReported() async throws {
        let field = TypedField(readable: false)
        #expect(try await engine(field, dropsKeys: false).insert(words) == .notReported)
    }
}
