// A clip the user kept crosses a launch whatever its kind, sealed, and goes only when they delete it.

import CryptoKit
import Foundation
import Testing

@testable import UttrflowClipboard
@testable import UttrflowCore

@Suite("A kept clip survives until the user deletes it")
struct KeptClipSurvivalTests {
    private struct Keys: StoreKeyProviding {
        let value: SymmetricKey
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    /// Invented: the shape of a personal access token, never issued by anyone.
    private static let token = "ghp_Zx9kLmQ2rT7pQ3vB8nW4sY6uC0eH5jD1aF3g"
    private static let retention = ClipRetention(days: 7, now: Date())

    private let folder: URL
    private let sealing = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "kept-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// A store over the same folder and key, which is what a relaunch or an update is.
    private func launch() -> ClipboardStore {
        ClipboardStore(file: folder.appending(path: "clipboard.v1.json"), encryptedStore: sealing)
    }

    private func secret(_ text: String = Self.token) -> Clip {
        Clip(text: text, kind: .secret, copiedAt: Date(), source: nil)
    }

    private func bytesOnDisk() throws -> Data {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        return try names.reduce(into: Data()) { all, name in
            var isFolder: ObjCBool = false
            let path = folder.appending(path: name).path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), !isFolder.boolValue
            else { return }
            all.append(try Data(contentsOf: URL(filePath: path)))
        }
    }

    @Test(
        "named, tagged, pinned or filed, a secret survives a relaunch sealed and still masked",
        arguments: ["name", "tag", "pin", "file"])
    func keptSecretSurvives(how: String) async throws {
        let store = launch()
        let clip = secret()
        try await store.record(clip, keeping: Self.retention)
        switch how {
        case "name": try await store.setAlias("Deploy token", of: clip.id, keeping: Self.retention)
        case "tag":
            try await store.setLabels(alias: nil, tags: ["work"], of: clip.id, keeping: Self.retention)
        case "pin": try await store.setPinned(true, of: clip.id, keeping: Self.retention)
        default: try await store.setCategory("Keys", of: clip.id, keeping: Self.retention)
        }

        let reopened = await launch().clips(keeping: Self.retention)

        #expect(reopened.map(\.id) == [clip.id])
        #expect(reopened.first?.text == Self.token)
        #expect(reopened.first?.kind == .secret)
        let onDisk = try bytesOnDisk()
        #expect(!onDisk.isEmpty)
        #expect(onDisk.range(of: Data(Self.token.utf8)) == nil, "the value is sealed at rest")
    }

    @Test("a secret nobody kept is still not written")
    func unkeptSecretStaysInMemory() async throws {
        let store = launch()
        try await store.record(secret(), keeping: Self.retention)

        #expect(await store.clips(keeping: Self.retention).count == 1)
        #expect(await launch().clips(keeping: Self.retention).isEmpty)
    }

    @Test("a store with no sealing key never writes a kept secret in plaintext")
    func noPlaintextWithoutSealing() async throws {
        let store = ClipboardStore(file: folder.appending(path: "clipboard.v1.json"))
        let clip = secret()
        try await store.record(clip, keeping: Self.retention)
        try await store.setPinned(true, of: clip.id, keeping: Self.retention)

        let onDisk = try bytesOnDisk()
        #expect(onDisk.range(of: Data(Self.token.utf8)) == nil)
    }

    @Test("the same text copied again leaves a kept secret kept and on disk")
    func repeatCopy() async throws {
        let store = launch()
        let clip = secret()
        try await store.record(clip, keeping: Self.retention)
        try await store.setAlias("Deploy token", of: clip.id, keeping: Self.retention)
        try await store.record(secret(), keeping: Self.retention)

        let reopened = await launch().clips(keeping: Self.retention)

        #expect(reopened.map(\.alias) == ["Deploy token"])
        #expect(reopened.first?.kind == .secret)
    }

    @Test("a clip the user marked secret stays masked when the detector disagrees after a relaunch")
    func markedSecretHoldsAcrossALaunch() async throws {
        let store = launch()
        let clip = Clip(text: "blue-horse", kind: .text, copiedAt: Date(), source: nil)
        try await store.record(clip, keeping: Self.retention)
        try await store.setPinned(true, of: clip.id, keeping: Self.retention)
        try await store.setSecret(true, of: clip.id, keeping: Self.retention)

        let relaunched = launch()
        let plainCopy = Clip(text: "blue-horse", kind: .text, copiedAt: Date(), source: nil)
        let after = try await relaunched.record(plainCopy, keeping: Self.retention)

        #expect(after.map(\.kind) == [.secret])
        let pinned = Clip(text: "blue-horse", kind: .secret, copiedAt: Date(), source: nil, isPinned: true)
        let merged = ClipReclassification.merge(
            [pinned.reclassified(as: ClipClassification(kind: .text, language: nil))],
            from: [pinned], into: [pinned])
        #expect(merged.clips.map(\.kind) == [.secret])
    }

    @Test("window, count cap and memory quota remove no kept clip")
    func evictionSparesKept() async throws {
        let store = ClipboardStore(
            file: folder.appending(path: "clipboard.v1.json"),
            budget: ClipboardBudget(
                ceiling: 3, copied: ClipboardTier(bytes: 1, items: 1),
                dictation: ClipboardTier(bytes: 1, items: 1),
                images: ClipboardTier(bytes: 1, items: 1, days: 1), largestClip: 10_000,
                largestPicture: 1, pictureEdge: 1, disk: 1),
            encryptedStore: sealing)
        let old = Clip(
            text: "an old note", kind: .text, copiedAt: Date(timeIntervalSinceNow: -86_400 * 400), source: nil,
            isPinned: true)
        try await store.record(old, keeping: Self.retention)
        for index in 0..<5 {
            try await store.record(
                Clip(text: "filler \(index)", kind: .text, copiedAt: Date(), source: nil),
                keeping: Self.retention)
        }

        #expect(await store.clips(keeping: Self.retention).contains { $0.id == old.id })
    }

    @Test("a name lost to a duplicate leaves the clip kept")
    func duplicateAliasStaysKept() {
        let first = Clip(text: "one", kind: .text, copiedAt: Date(), source: nil, alias: "Same")
        let second = Clip(text: "two", kind: .text, copiedAt: Date(), source: nil, alias: "Same")

        let unique = ClipOrdering.uniqueAliases(in: [first, second])

        #expect(unique.map(\.alias) == ["Same", nil])
        #expect(unique.map(\.isKept) == [true, true])
    }

    @Test("an explicit delete does remove a kept secret, from the disk too")
    func explicitDelete() async throws {
        let store = launch()
        let clip = secret()
        try await store.record(clip, keeping: Self.retention)
        try await store.setPinned(true, of: clip.id, keeping: Self.retention)
        try await store.delete(clip.id, keeping: Self.retention)

        #expect(await launch().clips(keeping: Self.retention).isEmpty)
    }

    @Test("reset removes a kept secret; clearing the history spares it")
    func resetAndClear() async throws {
        let store = launch()
        let clip = secret()
        try await store.record(clip, keeping: Self.retention)
        try await store.setPinned(true, of: clip.id, keeping: Self.retention)

        try await store.deleteEverything(keeping: Self.retention)
        #expect(await launch().clips(keeping: Self.retention).map(\.id) == [clip.id])

        try await launch().forgetEverything()
        #expect(await launch().clips(keeping: Self.retention).isEmpty)
    }
}
