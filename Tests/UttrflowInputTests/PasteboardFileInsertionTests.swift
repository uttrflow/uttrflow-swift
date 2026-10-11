// Tests for putting copied files back on the clipboard and pasting them.

import AppKit
import Foundation
import Testing

@testable import UttrflowCore
@testable import UttrflowInput

@Suite("PasteboardFileInsertionEngine")
struct PasteboardFileInsertionEngineTests {
    private static let editor = InsertionDestination(
        applicationName: "Editor", bundleIdentifier: "com.example.editor")
    private static let notes = InsertionDestination(
        applicationName: "Notes", bundleIdentifier: "com.example.notes")
    private let files = [URL(filePath: "/tmp/one.txt"), URL(filePath: "/tmp/two.txt")]

    @Test("the captured application still in front receives the files and one paste")
    func pastesIntoTheCapturedApplication() throws {
        let pasteboard = FakePasteboard()
        let keystrokes = FakeKeystrokeSender()
        let sut = PasteboardFileInsertionEngine(
            focus: SequencedFrontmostFocus([Self.editor]), pasteboard: pasteboard, keystrokes: keystrokes)

        try sut.insert(files, targeting: Self.editor)

        #expect(pasteboard.files == [files])
        #expect(keystrokes.pasteCount == 1)
    }

    @Test("a refused write posts no paste")
    func refusedWrite() {
        let pasteboard = FakePasteboard(refusesWrites: true)
        let keystrokes = FakeKeystrokeSender()
        let sut = PasteboardFileInsertionEngine(
            focus: FakeFocus(field: FakeTextField()), pasteboard: pasteboard, keystrokes: keystrokes)

        #expect(throws: TextInsertionError.clipboardUnavailable) { try sut.insert(files) }
        #expect(pasteboard.files.isEmpty)
        #expect(keystrokes.pasteCount == 0)
    }

    @Test("a switch made before the write leaves the clipboard alone")
    func switchBeforeTheWrite() {
        let pasteboard = FakePasteboard()
        let keystrokes = FakeKeystrokeSender()
        let sut = PasteboardFileInsertionEngine(
            focus: SequencedFrontmostFocus([Self.notes]), pasteboard: pasteboard, keystrokes: keystrokes)

        #expect(throws: TextInsertionError.insertionTargetChanged) {
            try sut.insert(files, targeting: Self.editor)
        }
        #expect(pasteboard.files.isEmpty)
        #expect(keystrokes.pasteCount == 0)
    }

    @Test("a switch between the write and the keystroke posts no paste")
    func switchDuringTheWrite() {
        let pasteboard = FakePasteboard()
        let keystrokes = FakeKeystrokeSender()
        let sut = PasteboardFileInsertionEngine(
            focus: SequencedFrontmostFocus([Self.editor, Self.notes]), pasteboard: pasteboard,
            keystrokes: keystrokes)

        #expect(throws: TextInsertionError.insertionTargetChanged) {
            try sut.insert(files, targeting: Self.editor)
        }
        #expect(keystrokes.pasteCount == 0)
    }

    @Test("Uttrflow in front leaves the clipboard alone")
    func selfInFront() {
        let pasteboard = FakePasteboard()
        let keystrokes = FakeKeystrokeSender()
        let sut = PasteboardFileInsertionEngine(
            focus: FakeFocus(isSelf: true), pasteboard: pasteboard, keystrokes: keystrokes)

        #expect(throws: TextInsertionError.noFocusedTextField) { try sut.insert(files) }
        #expect(pasteboard.files.isEmpty)
    }

    @Test("a copy from another app during the write is not pasted over")
    func clipboardChangedDuringTheWrite() {
        let pasteboard = FakePasteboard(onFileWrite: { $0.copyFromAnotherApp("a newer copy") })
        let keystrokes = FakeKeystrokeSender()
        let sut = PasteboardFileInsertionEngine(
            focus: SwitchableFocus(), pasteboard: pasteboard, keystrokes: keystrokes)

        #expect(throws: TextInsertionError.clipboardChanged) { try sut.insert(files) }
        #expect(keystrokes.pasteCount == 0)
    }

    @Test("cancellation after the write removes the files before posting paste")
    func cancellation() async {
        let pasteboard = FakePasteboard(onFileWrite: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        let keystrokes = FakeKeystrokeSender()
        let sut = PasteboardFileInsertionEngine(
            focus: SwitchableFocus(), pasteboard: pasteboard, keystrokes: keystrokes)
        let urls = files
        let task = Task { try sut.insert(urls) }

        await #expect(throws: TextInsertionError.insertionCancelled) { try await task.value }

        #expect(keystrokes.pasteCount == 0)
    }

    @Test("Copy writes the files and sends no paste")
    func copyOnly() throws {
        let pasteboard = FakePasteboard()
        let keystrokes = FakeKeystrokeSender()
        let sut = PasteboardFileInsertionEngine(
            focus: FakeFocus(isSelf: true), pasteboard: pasteboard, keystrokes: keystrokes)

        try sut.copy(files)

        #expect(pasteboard.files == [files])
        #expect(keystrokes.pasteCount == 0)
    }

    @Test("Copy on a refusing clipboard says so")
    func copyRefused() {
        let sut = PasteboardFileInsertionEngine(
            focus: FakeFocus(), pasteboard: FakePasteboard(refusesWrites: true),
            keystrokes: FakeKeystrokeSender())

        #expect(throws: TextInsertionError.clipboardUnavailable) { try sut.copy(files) }
    }
}

@Suite("SystemPasteboard files")
struct SystemPasteboardFilesTests {
    private func makeFiles(_ names: [String]) throws -> (folder: URL, urls: [URL]) {
        let folder = URL.temporaryDirectory.appending(
            path: "uttrflow-pasteboard-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = try names.map { name in
            let url = folder.appending(path: name, directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            return url
        }
        return (folder, urls)
    }

    @Test("the files come back from the pasteboard in the order they went")
    func roundTrip() throws {
        let made = try makeFiles(["b.txt", "a.txt"])
        defer { try? FileManager.default.removeItem(at: made.folder) }
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let result = SystemPasteboard.writeFiles(made.urls, to: pasteboard)

        #expect(result.didWrite)
        let back =
            pasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        #expect(back?.map(\.lastPathComponent) == ["b.txt", "a.txt"])
    }

    @Test("no files is a refusal, never an emptied clipboard")
    func emptyIsRefused() {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("kept", forType: .string)

        #expect(SystemPasteboard.writeFiles([], to: pasteboard) == .refused)
        #expect(pasteboard.string(forType: .string) == "kept")
    }
}
