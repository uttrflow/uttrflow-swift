import Foundation
import Testing
import UttrflowContext
import UttrflowPredict
import UttrflowPredictStore

@testable import UttrflowPredictCapture

private let moment = Date(timeIntervalSince1970: 1_800_000_000)
private let editor = FieldReading(
    bundleIdentifier: "com.example.editor", role: FocusedFieldSnapshot.proseRole,
    document: "file:///Users/someone/work/notes.rtf")

/// A document with the caret at its very end, which is where a person typing one leaves it.
private func document(_ value: String) -> FocusedFieldSnapshot {
    FocusedFieldSnapshot(
        bundleIdentifier: "com.example.editor", applicationName: "Editor",
        role: FocusedFieldSnapshot.proseRole, document: "file:///Users/someone/work/notes.rtf",
        value: value, selection: NSRange(location: value.utf16.count, length: 0))
}

/// A corpus of its own per test, removed when the test ends.
private struct Corpus: ~Copyable {
    let path: String

    init() {
        path = NSTemporaryDirectory() + "uttrflow-line-\(UUID().uuidString).sqlite"
    }

    deinit {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) }
    }
}

@Suite("What a document remembers is what it can be asked for")
struct LineCaptureTests {
    @Test("A committed line comes back when its opening is typed on the next line.")
    func aCommittedLineIsFoundByItsPrefix() async throws {
        let corpus = Corpus()
        let scratch = Scratch()
        let store = try PredictStore(path: corpus.path)
        let session = CaptureSession(
            sink: store, preferencesFile: CapturePreferencesFile(path: scratch.preferencesPath))
        try await session.record(.allowed, for: "com.example.editor")
        let first = document("The quick brown fox jumps over the lazy dog")
        _ = try await session.handle(.keystroke(first.currentLine, at: moment), in: editor)
        let outcome = try await session.handle(.returnPressed(at: moment), in: editor)
        #expect(outcome == .recorded("The quick brown fox jumps over the lazy dog"))

        let second = document("The quick brown fox jumps over the lazy dog\nThe qui")
        let surface = try #require(editor.surface)
        let found = try await store.candidates(for: surface, matching: second.currentLine)
        #expect(found.map(\.text) == ["The quick brown fox jumps over the lazy dog"])
    }

    @Test("The whole document is never stored, so what is stored can always be retrieved.")
    func theWholeDocumentIsNeverStored() async throws {
        let corpus = Corpus()
        let scratch = Scratch()
        let store = try PredictStore(path: corpus.path)
        let session = CaptureSession(
            sink: store, preferencesFile: CapturePreferencesFile(path: scratch.preferencesPath))
        try await session.record(.allowed, for: "com.example.editor")
        for line in ["Deploy the notes", "Deploy the notes\nThe quick brown fox"] {
            _ = try await session.handle(
                .keystroke(document(line).currentLine, at: moment), in: editor)
            _ = try await session.handle(.returnPressed(at: moment), in: editor)
        }
        let surface = try #require(editor.surface)
        let deploy = try await store.candidates(for: surface, matching: "Deploy")
        let quick = try await store.candidates(for: surface, matching: "The q")
        #expect(deploy.map(\.text) == ["Deploy the notes"])
        #expect(quick.map(\.text) == ["The quick brown fox"])
    }

    @Test("Two documents in one folder share what either of them taught.")
    func oneFolderIsOneCorpus() throws {
        let other = FieldReading(
            bundleIdentifier: "com.example.editor", role: FocusedFieldSnapshot.proseRole,
            document: "file:///Users/someone/work/plan.rtf")
        #expect(editor.surface == other.surface)
    }
}
