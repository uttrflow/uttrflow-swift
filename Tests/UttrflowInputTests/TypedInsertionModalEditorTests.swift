import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowInput

/// A focused text area in one chosen application.
private struct AppFocus: AccessibilityFocus {
    let application: InsertionDestination

    func focusedTextField() -> (any FocusedTextField)? { nil }
    func hasFocusedElement() -> Bool { true }
    func isSelfFrontmost() -> Bool { false }
    func focusedApplication() -> InsertionDestination? { application }
    func focusedElementKind() -> FocusedElementKind { .textEntry }
}

/// Records every key event posted.
private final class RecordingTypist: KeystrokeTyping, @unchecked Sendable {
    private let posted = Mutex<[String]>([])
    var typed: [String] { posted.withLock { $0 } }
    func type(_ text: String) throws(TextInsertionError) { posted.withLock { $0.append(text) } }
    func deleteBackwards(_ count: Int) throws(TextInsertionError) {
        posted.withLock { $0.append("⌫\(count)") }
    }
}

@Suite("A modal editor never receives dictated words as typed keys")
struct TypedInsertionModalEditorTests {
    private static let macVim = InsertionDestination(
        applicationName: "MacVim", bundleIdentifier: "org.vim.MacVim")

    @Test(
        "A row marked as reading keys as commands gets zero key events.",
        arguments: [
            macVim, InsertionDestination(applicationName: "Neovim", bundleIdentifier: "example.neovide"),
        ])
    func modalEditorIsRefused(application: InsertionDestination) async {
        let typist = RecordingTypist()
        let engine = TypedTextInsertionEngine(focus: AppFocus(application: application), typist: typist)

        #expect(await engine.canInsert() == false)
        await #expect(throws: TextInsertionError.noFocusedTextField) {
            _ = try await engine.insert("delete the old branch")
        }
        #expect(typist.typed.isEmpty)
    }

    @Test("A code editor without the mark still takes typing.")
    func plainEditorIsTyped() async throws {
        let typist = RecordingTypist()
        let focus = AppFocus(
            application: InsertionDestination(applicationName: "Zed", bundleIdentifier: "dev.zed.Zed"))
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)

        _ = try await engine.insert("hello")
        #expect(typist.typed == ["hello"])
    }

    @Test(
        "Dictation refused by a modal editor keeps the words for explicit copy and shows the existing notice."
    )
    func refusalMessage() async {
        let typist = RecordingTypist()
        let coordinator = TextInsertion.dictation(focus: AppFocus(application: Self.macVim), typist: typist)

        let expected = TextInsertionError.insertionNeedsCopy(
            description: TextInsertionError.noFocusedTextField.userMessage)
        await #expect(throws: expected) { _ = try await coordinator.insert("delete the old branch") }
        #expect(expected.userMessage == "The text couldn't be inserted. Your clipboard is unchanged.")
        #expect(typist.typed.isEmpty)
    }

    @Test("The table, not an app name in code, marks the modal editor row.")
    func tableCarriesTheFlag() {
        #expect(DestinationClassifier.keysMayBeCommands(in: AppContext(bundleIdentifier: "org.vim.MacVim")))
        #expect(
            !DestinationClassifier.keysMayBeCommands(in: AppContext(bundleIdentifier: "com.microsoft.VSCode"))
        )
        #expect(
            DestinationClassifier.kind(for: AppContext(bundleIdentifier: "org.vim.MacVim")) == .codeEditor)
    }
}
