import Synchronization
import Testing

@testable import UttrflowCore
@testable import UttrflowInput
@testable import UttrflowPredict

/// A field that keeps what was written into it.
private final class WrittenField: FocusedTextField, @unchecked Sendable {
    private let written = Mutex<[String]>([])
    var text: [String] { written.withLock { $0 } }
    func replaceSelection(with text: String) throws(TextInsertionError) {
        written.withLock { $0.append(text) }
    }
}

/// A reader that is not an `AcceptanceFieldReader`, so the protocol's own window-aware read runs.
private struct WindowedFocus: AccessibilityFocus {
    let field: WrittenField
    let tail: FieldTail
    /// The window the tail was read in.
    let readWindow: UInt32?
    /// The window the write would land in, read again just before it.
    let writeWindow: UInt32?
    func focusedTextField() -> (any FocusedTextField)? { field }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func windowNumberAndTail(upTo count: Int) -> (windowNumber: UInt32?, tail: FieldTail) {
        (readWindow, tail)
    }
    func focusedWindowNumber() -> UInt32? { writeWindow }
    func acceptanceFocusedWindowNumber() -> UInt32? { writeWindow }
}

@Suite("Accepting into the window the ghost was drawn in")
struct SuggestionAcceptorWindowTests {
    private func acceptor(
        _ field: WrittenField, tail: FieldTail = .text("git com"), readWindow: UInt32? = 41,
        writeWindow: UInt32? = 41
    ) -> SuggestionAcceptor {
        let focus = WindowedFocus(
            field: field, tail: tail, readWindow: readWindow, writeWindow: writeWindow)
        return SuggestionAcceptor(
            completion: TextInsertion.completion(focus: focus, typist: UnusedTypist()), focus: focus)
    }

    @Test("a field that moved to another window between the read and the write is refused, writing nothing")
    func refusesAWindowThatChangedBeforeTheWrite() async {
        let field = WrittenField()
        await #expect(throws: TextInsertionError.self) {
            try await acceptor(field, writeWindow: 42)
                .accept(.certain("git commit"), after: "git com", expectedWindowNumber: 41)
        }
        #expect(field.text.isEmpty)
    }

    @Test("a field still in the drawn window takes the accepted words")
    func writesWhenTheWindowHolds() async throws {
        let field = WrittenField()
        let method = try await acceptor(field)
            .accept(.certain("git commit"), after: "git com", expectedWindowNumber: 41)
        #expect(method == .accessibility)
        #expect(field.text == ["mit"])
    }

    @Test("a drawn edit is written only into the window it was drawn for")
    func writesAnAimedEditOnlyIntoItsWindow() async throws {
        let edit = Acceptance.Edit(replaced: "", inserted: "mit")
        let elsewhere = WrittenField()
        await #expect(throws: TextInsertionError.self) {
            try await acceptor(elsewhere, writeWindow: 7).write(edit, expectedWindowNumber: 41)
        }
        #expect(elsewhere.text.isEmpty)

        let here = WrittenField()
        let method = try await acceptor(here).write(edit, expectedWindowNumber: 41)
        #expect(method == .accessibility)
        #expect(here.text == ["mit"])
    }

    @Test("an edit with no window to check is written wherever the field is")
    func writesWithoutAWindowToCheck() async throws {
        let field = WrittenField()
        _ = try await acceptor(field, writeWindow: nil)
            .write(Acceptance.Edit(replaced: "", inserted: "mit"))
        #expect(field.text == ["mit"])
    }

    @Test("a reader that is not the system's reports an unreadable tail as unreadable")
    func fallbackReaderRefusesAnUnreadableTail() async {
        let aim = await acceptor(WrittenField(), tail: .unreadable)
            .aim(.certain("git commit"), after: "git com")
        #expect(aim == .refused("the focused field cannot be read"))
    }

    @Test("a guarded read stops at a secure field, and keeps the window of one it cannot read")
    func guardedReadKeepsTheWindow() {
        let secure = AcceptanceFieldRead.guarded(windowNumber: 9, isSecure: { true }, tail: { "x" })
        let unreadable = AcceptanceFieldRead.guarded(windowNumber: 9, isSecure: { false }, tail: { nil })
        let readable = AcceptanceFieldRead.guarded(windowNumber: 9, isSecure: { false }, tail: { "x" })
        #expect(Self.describe(secure) == "secure")
        #expect(Self.describe(unreadable) == "unreadable in 9")
        #expect(Self.describe(readable) == "x in 9")
    }

    private static func describe(_ read: AcceptanceFieldRead) -> String {
        switch read {
        case .secure: "secure"
        case .unreadable(let window): "unreadable in \(window.map(String.init) ?? "no window")"
        case .text(let window, let tail): "\(tail) in \(window.map(String.init) ?? "no window")"
        }
    }
}

private final class UnusedTypist: KeystrokeTyping, @unchecked Sendable {
    func type(_ text: String) throws(TextInsertionError) {}
    func deleteBackwards(_ count: Int) throws(TextInsertionError) {}
}
