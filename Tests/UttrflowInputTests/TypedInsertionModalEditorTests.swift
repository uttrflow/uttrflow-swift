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
    var title: String? = nil
    func focusedWindowTitle() -> String? { title }
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

    @Test(
        "A terminal whose title names a full-screen editor gets zero key events; a shell prompt is typed.",
        arguments: [
            ("notes.txt — vim — 80×24", false), ("nvim main.swift", false), ("~ — zsh — 80×24", true),
        ])
    func terminalHostedEditorIsRefused(title: String, typable: Bool) async throws {
        let typist = RecordingTypist()
        var focus = AppFocus(
            application: InsertionDestination(
                applicationName: "Terminal", bundleIdentifier: DestinationRules.terminal))
        focus.title = title
        let engine = TypedTextInsertionEngine(focus: focus, typist: typist)

        #expect(await engine.canInsert() == typable)
        if typable {
            _ = try await engine.insert("hello")
            #expect(typist.typed == ["hello"])
        } else {
            await #expect(throws: TextInsertionError.noFocusedTextField) { _ = try await engine.insert("dd") }
            #expect(typist.typed.isEmpty)
        }
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

    @Test("A modal editor never gets typed keys; the words arrive by paste, which is not a command key.")
    func refusalFallsToPaste() async throws {
        let typist = RecordingTypist()
        let keys = FakeKeystrokeSender()
        let coordinator = TextInsertion.dictation(
            focus: AppFocus(application: Self.macVim), typist: typist, pasteboard: FakePasteboard(),
            keystrokes: keys)

        let attempt = try await coordinator.insert("delete the old branch")

        #expect(attempt.method == .pasteboard)
        #expect(keys.pasteCount == 1)
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
