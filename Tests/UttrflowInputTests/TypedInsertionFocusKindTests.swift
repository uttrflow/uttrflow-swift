import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowInput

/// Reports a focused element of a chosen kind in one application.
private final class KindFocus: AccessibilityFocus, @unchecked Sendable {
    private let kind: Mutex<FocusedElementKind>

    init(_ kind: FocusedElementKind) { self.kind = Mutex(kind) }

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { kind.withLock { $0 } != .unpublished }
    func isSelfFrontmost() -> Bool { false }
    func focusedApplication() -> InsertionDestination? {
        InsertionDestination(applicationName: "Files", bundleIdentifier: "example.files")
    }
    func focusedElementKind() -> FocusedElementKind { kind.withLock { $0 } }

    func become(_ next: FocusedElementKind) { kind.withLock { $0 = next } }
}

/// Counts every key event posted.
private final class CountingTypist: KeystrokeTyping, @unchecked Sendable {
    private let posted = Mutex<[String]>([])
    private let afterChunk: @Sendable (Int) -> Void

    init(afterChunk: @escaping @Sendable (Int) -> Void = { _ in }) { self.afterChunk = afterChunk }

    var typed: [String] { posted.withLock { $0 } }

    func type(_ text: String) throws(TextInsertionError) {
        let count = posted.withLock {
            $0.append(text); return $0.count
        }
        afterChunk(count)
    }

    func deleteBackwards(_ count: Int) throws(TextInsertionError) {
        posted.withLock { $0.append("⌫\(count)") }
    }
}

@Suite("Typing only into a text field or an app that publishes none")
struct TypedInsertionFocusKindTests {
    @Test("A focused control that is not a text field gets zero key events.")
    func controlIsRefused() async {
        let typist = CountingTypist()
        let engine = TypedTextInsertionEngine(focus: KindFocus(.control), typist: typist)

        #expect(await engine.canInsert() == false)
        await #expect(throws: TextInsertionError.noFocusedTextField) { _ = try await engine.insert("jk gg") }
        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await engine.write("x", replacing: "")
        }
        #expect(typist.typed.isEmpty)
    }

    @Test(
        "A text field and an app that publishes no element still take typing.",
        arguments: [
            FocusedElementKind.textEntry, .unpublished,
        ])
    func fieldAndUnpublishedAreTyped(kind: FocusedElementKind) async throws {
        let typist = CountingTypist()
        let engine = TypedTextInsertionEngine(focus: KindFocus(kind), typist: typist)

        #expect(await engine.canInsert())
        _ = try await engine.insert("hello")
        #expect(typist.typed == ["hello"])
    }

    @Test("Focus moving to a control partway stops typing.")
    func controlPartwayStops() async {
        let length = TypedTextInsertionEngine.chunkLength
        let focus = KindFocus(.textEntry)
        let typist = CountingTypist { chunk in if chunk == 1 { focus.become(.control) } }
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)

        await #expect(throws: TextInsertionError.insertionInterrupted(typed: length, total: length * 3)) {
            _ = try await engine.insert(String(repeating: "a", count: length * 3))
        }
        #expect(typist.typed.count == 1)
    }

    @Test("Roles classify into the three kinds.")
    func classifiesRoles() {
        #expect(FocusedElementKind.of(role: "AXTextArea", isPublished: true) == .textEntry)
        #expect(FocusedElementKind.of(role: "AXWebArea", isPublished: true) == .control)
        #expect(FocusedElementKind.of(role: nil, isPublished: true) == .control)
        #expect(FocusedElementKind.of(role: nil, isPublished: false) == .unpublished)
    }
}
