// Named against pinned, through every sequence, across real store instances, files and the real key provider.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowClipboard

@Suite("A named clip against a pinned one, across relaunches")
struct NamedClipRelaunchTests {
    enum Mark: String, CaseIterable, Sendable { case name, pin }
    private static let password = "Vb4nM7xQ2p-invented"
    private static var now: ClipRetention { ClipRetention(days: 7, now: Date()) }

    private struct Disk {
        let folder = FileManager.default.temporaryDirectory.appending(path: "named-\(UUID().uuidString)")
        var sealing: EncryptedStore {
            EncryptedStore(keys: KeychainStoreKeyProvider(fileURL: folder.appending(path: "key")))
        }
        func launch() -> ClipboardStore {
            ClipboardStore(file: folder.appending(path: "clipboard.v1.json"), encryptedStore: sealing)
        }
    }

    private static func disk() throws -> Disk {
        let disk = Disk()
        try FileManager.default.createDirectory(at: disk.folder, withIntermediateDirectories: true)
        return disk
    }

    private static func copy(_ kind: ClipKind) -> Clip {
        Clip(text: password, kind: kind, copiedAt: Date(), source: "Example")
    }

    private static func keep(
        _ id: UUID, by mark: Mark, as label: String, in store: ClipboardStore
    ) async throws {
        switch mark {
        case .name: try await store.setAlias(label, of: id, keeping: now)
        case .pin: try await store.setPinned(true, of: id, keeping: now)
        }
    }

    @Test(
        "copy then keep, then a relaunch each time for five rounds", arguments: Mark.allCases,
        [ClipKind.secret, .text])
    func repeatedRelaunches(mark: Mark, kind: ClipKind) async throws {
        let disk = try Self.disk()
        let clip = Self.copy(kind)
        let store = disk.launch()
        try await store.record(clip, keeping: Self.now)
        try await Self.keep(clip.id, by: mark, as: "first", in: store)

        for round in 0..<5 {
            let reopened = disk.launch()
            let listed = await reopened.clips(keeping: Self.now)
            #expect(listed.map(\.id) == [clip.id], "round \(round)")
            await reopened.waitForClassifierMigrations()
        }
    }

    @Test("rename repeatedly, relaunching between renames", arguments: [ClipKind.secret, .text])
    func repeatedRenames(kind: ClipKind) async throws {
        let disk = try Self.disk()
        let clip = Self.copy(kind)
        try await disk.launch().record(clip, keeping: Self.now)
        let first = disk.launch()
        if await first.clips(keeping: Self.now).isEmpty { try await first.record(clip, keeping: Self.now) }
        try await first.setAlias("a", of: clip.id, keeping: Self.now)

        for name in ["b", "c", "b", "d"] {
            let store = disk.launch()
            try await store.setAlias(name, of: clip.id, keeping: Self.now)
            let listed = await disk.launch().clips(keeping: Self.now)
            #expect(listed.map(\.alias) == [name])
        }
    }

    @Test(
        "copying again between renames and relaunches leaves one named clip",
        arguments: [ClipKind.secret, .text])
    func copyThenRename(kind: ClipKind) async throws {
        let disk = try Self.disk()
        let clip = Self.copy(kind)
        let store = disk.launch()
        try await store.record(clip, keeping: Self.now)
        try await store.setAlias("a", of: clip.id, keeping: Self.now)

        for name in ["b", "c"] {
            let next = disk.launch()
            let after = try await next.record(Self.copy(kind), keeping: Self.now)
            #expect(after.count == 1)
            try await next.setAlias(name, of: clip.id, keeping: Self.now)
            #expect(await disk.launch().clips(keeping: Self.now).map(\.alias) == [name])
        }
    }

    @Test("many other copies and a passed window leave the named clip", arguments: Mark.allCases)
    func otherCopiesAndTime(mark: Mark) async throws {
        let disk = try Self.disk()
        let clip = Self.copy(.secret)
        let store = disk.launch()
        try await store.record(clip, keeping: Self.now)
        try await Self.keep(clip.id, by: mark, as: "name", in: store)
        for index in 0..<510 {
            try await store.record(
                Clip(text: "note \(index)", kind: .text, copiedAt: Date()), keeping: Self.now)
        }
        let later = ClipRetention(days: 7, now: Date(timeIntervalSinceNow: 86_400 * 60))

        #expect(await disk.launch().clips(keeping: later).map(\.id) == [clip.id])
    }

    @Test("undo of a deleted named clip brings it back after a relaunch")
    func undo() async throws {
        let disk = try Self.disk()
        let clip = Self.copy(.secret)
        let store = disk.launch()
        try await store.record(clip, keeping: Self.now)
        try await store.setAlias("name", of: clip.id, keeping: Self.now)
        let held = try #require(await store.clips(keeping: Self.now).first)
        try await store.delete(clip.id, keeping: Self.now)
        try await store.restore(held, keeping: Self.now)

        #expect(await disk.launch().clips(keeping: Self.now).map(\.alias) == ["name"])
    }

    @Test("emptying the name is what lets a secret go, and it goes unnamed only then")
    func emptiedName() async throws {
        let disk = try Self.disk()
        let clip = Self.copy(.secret)
        let store = disk.launch()
        try await store.record(clip, keeping: Self.now)
        try await store.setAlias("name", of: clip.id, keeping: Self.now)
        try await store.setAlias(nil, of: clip.id, keeping: Self.now)

        #expect(await store.clips(keeping: Self.now).count == 1)
        #expect(await disk.launch().clips(keeping: Self.now).isEmpty)
    }
}
