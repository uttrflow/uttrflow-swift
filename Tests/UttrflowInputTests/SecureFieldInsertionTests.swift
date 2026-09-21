import Testing

@testable import UttrflowCore
@testable import UttrflowInput

/// Words written into a field that hides what is typed are marked so, and never left on the clipboard in plain sight.
@Suite("Insertion into a secure field")
struct SecureFieldInsertionTests {
    @Test("the coordinator reports a secure field, asked before the write")
    func coordinatorReportsSecure() async throws {
        let focus = FakeFocus(field: FakeTextField(), secure: true)
        let coordinator = TextInsertionCoordinator(
            strategies: [AccessibilityTextInsertionEngine(focus: focus)], focus: focus)

        let attempt = try await coordinator.insert("open sesame")

        #expect(attempt.intoSecureField)
    }

    @Test("the coordinator reports an ordinary field as not secure")
    func coordinatorReportsOrdinary() async throws {
        let focus = FakeFocus(field: FakeTextField())
        let coordinator = TextInsertionCoordinator(
            strategies: [AccessibilityTextInsertionEngine(focus: focus)], focus: focus)

        let attempt = try await coordinator.insert("see you at noon")

        #expect(attempt.intoSecureField == false)
    }

    @Test("a coordinator with no reader cannot tell, and says not secure")
    func coordinatorWithoutFocus() async throws {
        let coordinator = TextInsertionCoordinator(strategies: [
            ClipboardTextInsertionEngine(pasteboard: FakePasteboard())
        ])

        let attempt = try await coordinator.insert("see you at noon")

        #expect(attempt.intoSecureField == false)
    }

    @Test("the paste route marks the clipboard concealed for a secure field")
    func pasteConceals() async throws {
        let pasteboard = FakePasteboard()
        let engine = PasteboardTextInsertionEngine(
            focus: FakeFocus(field: FakeTextField(), secure: true), pasteboard: pasteboard,
            keystrokes: FakeKeystrokeSender())

        _ = try await engine.insert("open sesame")

        #expect(pasteboard.concealed == ["open sesame"])
    }

    @Test("the paste route writes an ordinary field's words unmarked")
    func pasteLeavesOrdinaryUnmarked() async throws {
        let pasteboard = FakePasteboard()
        let engine = PasteboardTextInsertionEngine(
            focus: FakeFocus(field: FakeTextField()), pasteboard: pasteboard,
            keystrokes: FakeKeystrokeSender())

        _ = try await engine.insert("see you at noon")

        #expect(pasteboard.writes == ["see you at noon"])
        #expect(pasteboard.concealed.isEmpty)
    }

    @Test("the clipboard floor leaves a secure field's words concealed")
    func floorConceals() async throws {
        let pasteboard = FakePasteboard()
        let engine = ClipboardTextInsertionEngine(
            pasteboard: pasteboard, focus: FakeFocus(field: nil, secure: true))

        _ = try await engine.insert("open sesame")

        #expect(pasteboard.concealed == ["open sesame"])
        #expect(pasteboard.text() == "open sesame")
    }

    @Test("the clipboard floor writes an ordinary field's words unmarked")
    func floorLeavesOrdinaryUnmarked() async throws {
        let pasteboard = FakePasteboard()
        let engine = ClipboardTextInsertionEngine(
            pasteboard: pasteboard, focus: FakeFocus(field: nil))

        _ = try await engine.insert("see you at noon")

        #expect(pasteboard.concealed.isEmpty)
        #expect(pasteboard.writes == ["see you at noon"])
    }

    @Test("the built route asks the same reader at the floor")
    func builtRouteConcealsAtTheFloor() async throws {
        let pasteboard = FakePasteboard()
        let focus = FakeFocus(field: nil, isSelf: true, secure: true)
        let coordinator = TextInsertion.coordinator(
            focus: focus, pasteboard: pasteboard, keystrokes: FakeKeystrokeSender())

        let attempt = try await coordinator.insert("open sesame")

        #expect(attempt.method == .clipboard)
        #expect(attempt.intoSecureField)
        #expect(pasteboard.concealed == ["open sesame"])
    }

    @Test("a reader that cannot see the field says it is not secure")
    func defaultReaderSaysNotSecure() {
        #expect(CountingFocus(answer: "").focusedFieldIsSecure() == false)
    }
}
