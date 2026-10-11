// Tests for copied files recorded as references rather than as their names.

import Foundation
import Testing

@testable import UttrflowClipboard

@Suite("A copied file is a file, not its name")
struct CopiedFileTests {
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeFiles(_ names: [String]) throws -> (folder: URL, urls: [URL]) {
        let folder = URL.temporaryDirectory.appending(
            path: "uttrflow-files-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let urls = try names.map { name in
            let url = folder.appending(path: name, directoryHint: .notDirectory)
            try Data("x".utf8).write(to: url)
            return url
        }
        return (folder, urls)
    }

    @Test("a file copy with a name flavour is one file clip, not ordinary text")
    func fileCopyIsNotText() async throws {
        let made = try makeFiles(["report.pdf"])
        defer { try? FileManager.default.removeItem(at: made.folder) }
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(source: clipboard)
        clipboard.write("report.pdf", files: made.urls)

        let clip = try #require(await watcher.newClip(at: noon)?.clip)

        #expect(clip.kind == .file)
        #expect(clip.files?.map(\.name) == ["report.pdf"])
        #expect(clip.text == "report.pdf")
    }

    @Test("several files keep the order they were copied in")
    func orderIsKept() async throws {
        let made = try makeFiles(["b.txt", "a.txt", "c.txt"])
        defer { try? FileManager.default.removeItem(at: made.folder) }
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(source: clipboard)
        clipboard.write("b.txt\na.txt\nc.txt", files: made.urls)

        let clip = try #require(await watcher.newClip(at: noon)?.clip)

        #expect(clip.files?.map(\.name) == ["b.txt", "a.txt", "c.txt"])
        #expect(clip.text == "b.txt\na.txt\nc.txt")
    }

    @Test("a copied path as plain text stays a text clip")
    func pathTextIsUnchanged() async throws {
        let clipboard = FakeClipboard()
        let watcher = PasteboardWatcher(source: clipboard)
        clipboard.write("/Users/someone/report.pdf")

        let clip = try #require(await watcher.newClip(at: noon)?.clip)

        #expect(clip.kind == .filePath)
        #expect(clip.files == nil)
    }

    @Test("every file resolves while all of them are there")
    func allAvailable() throws {
        let made = try makeFiles(["one.txt", "two.txt"])
        defer { try? FileManager.default.removeItem(at: made.folder) }
        let references = made.urls.map(ClipFileReference.init(url:))

        let resolution = ClipFileResolution.resolving(references)

        guard case .available(let urls) = resolution else {
            Issue.record("expected every file to resolve")
            return
        }
        #expect(urls.map(\.lastPathComponent) == ["one.txt", "two.txt"])
    }

    @Test("one deleted file refuses the whole selection and names it")
    func deletedFileRefusesAll() throws {
        let made = try makeFiles(["one.txt", "two.txt"])
        defer { try? FileManager.default.removeItem(at: made.folder) }
        let references = made.urls.map(ClipFileReference.init(url:))
        try FileManager.default.removeItem(at: made.urls[1])

        #expect(ClipFileResolution.resolving(references) == .unavailable(["two.txt"]))
    }

    @Test("a moved file is found again through its bookmark")
    func movedFileIsFollowed() throws {
        let made = try makeFiles(["moving.txt"])
        defer { try? FileManager.default.removeItem(at: made.folder) }
        let reference = ClipFileReference(url: made.urls[0])
        let moved = made.folder.appending(path: "renamed.txt", directoryHint: .notDirectory)
        try FileManager.default.moveItem(at: made.urls[0], to: moved)

        #expect(reference.resolved()?.lastPathComponent == "renamed.txt")
    }

    @Test("a file with no bookmark and no path is unavailable")
    func noBookmarkAndGone() {
        let reference = ClipFileReference(path: "/nonexistent-\(UUID().uuidString)/gone.txt")

        #expect(reference.resolved() == nil)
        #expect(ClipFileResolution.resolving([reference]) == .unavailable(["gone.txt"]))
    }

    @Test("the same files copied twice are one clip, and a text edit does not touch them")
    func dedupeAndEditGuard() async throws {
        let folder = try TemporaryFolder()
        let made = try makeFiles(["same.txt"])
        defer { try? FileManager.default.removeItem(at: made.folder) }
        let files = made.urls.map(ClipFileReference.init(url:))
        let first = Clip(text: "same.txt", kind: .file, copiedAt: Date(), files: files)
        _ = try await folder.store.record(first, keeping: folder.retention)
        _ = try await folder.store.record(
            Clip(text: "same.txt", kind: .file, copiedAt: Date(), files: files), keeping: folder.retention)
        _ = try await folder.store.record(
            Clip(text: "same.txt", kind: .text, copiedAt: Date()), keeping: folder.retention)
        _ = try await folder.store.setText("other", of: first.id, keeping: folder.retention)

        let clips = await folder.store.clips(keeping: folder.retention)
        let fileClips = clips.filter { $0.kind == .file }

        #expect(clips.count == 2, "the text clip with the same words is separate")
        #expect(fileClips.count == 1)
        #expect(fileClips.first?.timesCopied == 2)
        #expect(fileClips.first?.text == "same.txt")
    }

    @Test("a file clip survives a restart with its references")
    func persists() async throws {
        let folder = try TemporaryFolder()
        let reference = ClipFileReference(path: "/tmp/example.txt", bookmark: Data([1, 2, 3]))
        _ = try await folder.store.record(
            Clip(text: "example.txt", kind: .file, copiedAt: Date(), files: [reference]),
            keeping: folder.retention)

        let reopened = ClipboardStore(file: folder.url.appending(path: "clipboard.json"))
        let clips = await reopened.clips(keeping: folder.retention)

        #expect(clips.first?.files == [reference])
        #expect(clips.first?.kind == .file)
    }

    @Test("a plain bookmark from an older build still resolves")
    func plainBookmarkResolves() throws {
        let made = try makeFiles(["old.txt"])
        defer { try? FileManager.default.removeItem(at: made.folder) }
        let plain = try made.urls[0].bookmarkData()
        let moved = made.folder.appending(path: "older.txt", directoryHint: .notDirectory)
        let reference = ClipFileReference(path: made.urls[0].path(percentEncoded: false), bookmark: plain)
        try FileManager.default.moveItem(at: made.urls[0], to: moved)

        #expect(reference.resolved()?.lastPathComponent == "older.txt")
    }

    @Test("only a file clip has a resolution, and the gone files of a list are named per clip")
    func resolutionPerClip() throws {
        let made = try makeFiles(["here.txt", "gone.txt"])
        defer { try? FileManager.default.removeItem(at: made.folder) }
        let references = made.urls.map(ClipFileReference.init(url:))
        let whole = Clip(text: "here.txt\ngone.txt", kind: .file, copiedAt: noon, files: references)
        let intact = Clip(text: "here.txt", kind: .file, copiedAt: noon, files: [references[0]])
        let text = Clip(text: "words", kind: .text, copiedAt: noon)
        try FileManager.default.removeItem(at: made.urls[1])

        #expect(text.fileResolution == nil)
        guard case .available(let urls)? = intact.fileResolution else {
            Issue.record("expected the intact clip to resolve")
            return
        }
        #expect(urls.map(\.lastPathComponent) == ["here.txt"])
        #expect(Clip.missingFiles(among: [whole, intact, text]) == [whole.id: ["gone.txt"]])
    }
}
