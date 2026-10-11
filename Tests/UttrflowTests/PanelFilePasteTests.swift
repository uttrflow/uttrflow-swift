// Tests for what the panel does with a file clip, and what it asks of the machine about the list.

import Foundation
import Testing
import UttrflowClipboard
import UttrflowCore
import UttrflowUX

@testable import Uttrflow

@Suite("A file clip on Return")
struct PanelFilePasteTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)
    private let failed = PanelNotice(symbolName: "x", message: "failed")

    private func clip(_ urls: [URL]) -> Clip {
        Clip(
            text: urls.map(\.lastPathComponent).joined(separator: "\n"), kind: .file, copiedAt: noon,
            files: urls.map(ClipFileReference.init(url:)))
    }

    private func made(_ names: [String]) throws -> (folder: URL, urls: [URL]) {
        let folder = URL.temporaryDirectory.appending(
            path: "uttrflow-panel-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = try names.map { name in
            let url = folder.appending(path: name, directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            return url
        }
        return (folder, urls)
    }

    @Test("every file is resolved in copy order while all are there")
    func resolvesInOrder() throws {
        let files = try made(["b.txt", "a.txt"])
        defer { try? FileManager.default.removeItem(at: files.folder) }

        guard case .files(let resolved) = PanelFilePaste.resolve(clip(files.urls)) else {
            Issue.record("expected every file to resolve")
            return
        }
        #expect(resolved.map(\.lastPathComponent) == ["b.txt", "a.txt"])
    }

    @Test("one gone file refuses the whole selection and names it")
    func refusesAll() throws {
        let files = try made(["here.txt", "gone.txt"])
        defer { try? FileManager.default.removeItem(at: files.folder) }
        let chosen = clip(files.urls)
        try FileManager.default.removeItem(at: files.urls[1])

        guard case .refused(let notice) = PanelFilePaste.resolve(chosen) else {
            Issue.record("a missing file did not refuse the selection")
            return
        }
        #expect(notice.message == "gone.txt is no longer on this Mac")
    }

    @Test("a clip that holds no files resolves to nothing to place")
    func notAFileClip() {
        #expect(PanelFilePaste.resolve(Clip(text: "words", kind: .text, copiedAt: noon)) == .files([]))
    }

    @Test("a paste that went through says nothing")
    func pasted() {
        #expect(
            PanelFilePaste.landing(.paste, failure: nil, copyFailed: failed)
                == .init(effect: nil, report: nil))
    }

    @Test("a paste the clipboard took no part in says the clipboard is unchanged")
    func pasteBeforeTheClipboardWasTouched() {
        for failure in [TextInsertionError.clipboardUnavailable, .clipboardChanged, .insertionCancelled] {
            #expect(
                PanelFilePaste.landing(.paste, failure: failure, copyFailed: failed).report
                    == .textCouldNotPaste)
        }
    }

    @Test("a paste that could not be posted says the files are on the clipboard")
    func pasteNotPosted() {
        #expect(
            PanelFilePaste.landing(.paste, failure: .insertionTargetChanged, copyFailed: failed).report
                == .filesRefused)
    }

    @Test("a copy with a reason says it and stays up; a plain copy closes and reports")
    func copies() {
        let notice = PanelNotice(symbolName: "doc.on.clipboard", message: "Copied")

        #expect(
            PanelFilePaste.landing(.copyAndSay(notice), failure: nil, copyFailed: failed)
                == .init(effect: .say(notice), report: nil))
        #expect(
            PanelFilePaste.landing(.copy, failure: nil, copyFailed: failed)
                == .init(effect: .close, report: .copied(.files)))
    }

    @Test("a copy the clipboard refused says so, whichever copy it was")
    func copyRefused() {
        let notice = PanelNotice(symbolName: "doc.on.clipboard", message: "Copied")

        for placement in [PanelFilePlacement.copy, .copyAndSay(notice)] {
            #expect(
                PanelFilePaste.landing(placement, failure: .clipboardUnavailable, copyFailed: failed)
                    == .init(effect: .say(failed), report: nil))
        }
    }
}

@Suite("What the machine says about the panel's list")
struct PanelListFactsTests {
    private struct Formatter: CodeFormatting {
        let has: Set<CodeLanguage>
        func isAvailable(for language: CodeLanguage) async -> Bool { has.contains(language) }
        func format(_ text: String, as language: CodeLanguage) async -> String? { nil }
    }

    @Test("gone files and installed formatters are found, and plain text asks nothing")
    func facts() async throws {
        let folder = URL.temporaryDirectory.appending(
            path: "uttrflow-facts-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ClipboardStore(file: ClipboardStore.defaultFile(in: folder))
        let kept = folder.appending(path: "kept.txt")
        try Data("x".utf8).write(to: kept)
        let present = Clip(
            text: "kept.txt", kind: .file, copiedAt: .now, files: [ClipFileReference(url: kept)])
        let absent = Clip(
            text: "gone.txt", kind: .file, copiedAt: .now,
            files: [ClipFileReference(path: folder.appending(path: "gone.txt").path())])
        let code = Clip(text: "let x = 1", kind: .code, copiedAt: .now, language: .swift)
        let text = Clip(text: "words", kind: .text, copiedAt: .now)

        let facts = await PanelListFacts.about(
            [present, absent, code, text], clipboard: store, formatter: Formatter(has: [.swift]))

        #expect(facts.missingFiles == [absent.id: ["gone.txt"]])
        #expect(facts.formattable == [.swift])
        #expect(facts.missingPictures.isEmpty)
    }

    @Test("a picture whose file is not in the store is missing")
    func missingPicture() async throws {
        let folder = URL.temporaryDirectory.appending(
            path: "uttrflow-facts-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ClipboardStore(file: ClipboardStore.defaultFile(in: folder))
        let picture = Clip(
            text: "", kind: .image, copiedAt: .now,
            image: ClipImage(file: "absent.png", width: 4, height: 4, bytes: 10))

        let facts = await PanelListFacts.about([picture], clipboard: store, formatter: Formatter(has: []))

        #expect(facts.missingPictures == [picture.id])
    }
}
