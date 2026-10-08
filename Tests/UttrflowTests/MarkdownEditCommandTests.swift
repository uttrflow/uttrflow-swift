import Synchronization
import Testing
import UttrflowCore
import UttrflowInput
import UttrflowPipeline

@testable import Uttrflow

/// A focused field that keeps every selection write.
private final class RecordingField: FocusedTextField, Sendable {
    private let written = Mutex<[String]>([])
    var writes: [String] { written.withLock { $0 } }
    func replaceSelection(with text: String) throws(TextInsertionError) {
        written.withLock { $0.append(text) }
    }
}

/// Focus on one recording field, or on nothing.
private struct FieldFocus: AccessibilityFocus {
    let field: RecordingField?
    func focusedTextField() -> (any FocusedTextField)? { field }
    func hasFocusedElement() -> Bool { field != nil }
    func isSelfFrontmost() -> Bool { false }
    func focusedApplication() -> InsertionDestination? { nil }
    func focusedElementKind() -> FocusedElementKind { .textEntry }
}

@Suite("A Markdown command said under the command key writes its edit over the selection")
struct MarkdownEditCommandTests {
    private let field = RecordingField()
    private var command: MarkdownEditCommand { MarkdownEditCommand(focus: FieldFocus(field: field)) }

    @Test("the registry runs a Markdown row and the planned edit replaces the selection")
    func writesPlannedEdit() async throws {
        let registry = EditCommandRegistry([command])
        let outcome = try await registry.run(
            "Bold.", on: AppContext(documentName: "notes.md", selectedText: "ship it", precedingText: "\n"))
        #expect(outcome == .ran)
        #expect(field.writes == ["**ship it**"])
    }

    @Test("the same words outside a Markdown document, or in a secure field, write nothing")
    func refusesWithoutWriting() async {
        await #expect(throws: TextInsertionError.self) {
            try await command.run("bold", on: AppContext(documentName: "main.swift", selectedText: "ship it"))
        }
        await #expect(throws: TextInsertionError.self) {
            try await command.run(
                "bold", on: AppContext(documentName: "notes.md", selectedText: "ship it", isSecure: true))
        }
        #expect(field.writes.isEmpty)
    }

    @Test("only a whole Markdown row is accepted, so other command words reach the other commands")
    func acceptsOnlyRows() {
        #expect(command.accepts("heading two"))
        #expect(!command.accepts("make it bold"))
        #expect(!command.accepts("delete that"))
    }

    @Test("with no focused field the edit refuses")
    func noField() async {
        let unfocused = MarkdownEditCommand(focus: FieldFocus(field: nil))
        await #expect(throws: TextInsertionError.noFocusedTextField) {
            try await unfocused.run("bold", on: AppContext(documentName: "notes.md", selectedText: "ship it"))
        }
    }
}
