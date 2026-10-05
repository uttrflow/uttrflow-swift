import Foundation
import Testing

@testable import UttrflowCore

@Suite("What this build keeps on this Mac")
struct LocalStoreInventoryTests {
    private let identifier = LocalStore.productionIdentifier

    private func container() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "inventory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ bytes: Int, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: bytes).write(to: url)
    }

    @Test("Each entry has its own name on disk.")
    func namesAreDistinct() {
        let names = LocalStoreEntry.allCases.flatMap(\.claimedNames)
        #expect(Set(names).count == names.count)
    }

    @Test("Reported bytes and file counts equal what is on disk, folders included.")
    func usageMatchesDisk() throws {
        let root = try container()
        defer { try? FileManager.default.removeItem(at: root) }
        try write(120, to: LocalStoreEntry.dictationHistory.location(in: root, for: identifier))
        let recordings = LocalStoreEntry.recordings.location(in: root, for: identifier)
        try write(300, to: recordings.appending(path: "a.caf"))
        try write(45, to: recordings.appending(path: "day/b.caf"))
        try write(7, to: LocalStore.file(LocalStoreEntry.predict.name + "-wal", in: root, for: identifier))

        let usage = Dictionary(
            uniqueKeysWithValues: LocalStoreInventory.usage(in: root, for: identifier).map { ($0.entry, $0) })
        #expect(usage[.dictationHistory]?.bytes == 120)
        #expect(usage[.recordings]?.bytes == 345)
        #expect(usage[.recordings]?.files == 2)
        #expect(usage[.predict]?.bytes == 7)
        #expect(usage[.snippets]?.files == 0)
        #expect(usage[.snippets]?.oldest == nil)
        #expect(usage[.dictationHistory]?.oldest != nil)
    }

    @Test("A file no entry claims is reported, so a new store cannot ship unlisted.")
    func strayFileIsUnlisted() throws {
        let root = try container()
        defer { try? FileManager.default.removeItem(at: root) }
        for entry in LocalStoreEntry.allCases {
            try write(
                1,
                to: entry.isDirectory
                    ? entry.location(in: root, for: identifier).appending(path: "x")
                    : entry.location(in: root, for: identifier))
        }
        #expect(LocalStoreInventory.unlisted(in: root, for: identifier).isEmpty)

        try write(1, to: LocalStore.file("stray.v1.json", in: root, for: identifier))
        #expect(LocalStoreInventory.unlisted(in: root, for: identifier) == ["stray.v1.json"])
    }

    @Test("Removing an entry's files brings its usage to zero.")
    func deletedEntryShowsZero() throws {
        let root = try container()
        defer { try? FileManager.default.removeItem(at: root) }
        let snippets = LocalStoreEntry.snippets.location(in: root, for: identifier)
        try write(10, to: snippets)
        try FileManager.default.removeItem(at: snippets)
        let row = LocalStoreInventory.usage(in: root, for: identifier).first { $0.entry == .snippets }
        #expect(row?.bytes == 0)
        #expect(row?.files == 0)
    }

    @Test("The files the clipboard and dictionary stores keep beside their own are claimed, not stray.")
    func companionFilesAreClaimed() throws {
        let root = try container()
        defer { try? FileManager.default.removeItem(at: root) }
        let history = LocalStoreEntry.clipboard.location(in: root, for: identifier)
        let images = history.deletingLastPathComponent().appending(path: "Images")
        try write(5, to: images.appending(path: "picture.png"))
        try write(1, to: LocalStore.file("saved.v1.json", in: root, for: identifier))
        try write(1, to: LocalStore.file("dictionary.v1.seeded.json", in: root, for: identifier))
        try write(1, to: LocalStore.file("dictionary.v1.refused.json", in: root, for: identifier))
        #expect(LocalStoreInventory.unlisted(in: root, for: identifier).isEmpty)
        let row = LocalStoreInventory.usage(in: root, for: identifier).first { $0.entry == .clipboardImages }
        #expect(row?.bytes == 5)
    }
}
