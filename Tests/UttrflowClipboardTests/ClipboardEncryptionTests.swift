// Clipboard text indexes and picture files use the shared authenticated local-store envelope.

import CryptoKit
import Foundation
import Security
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowClipboard

@Suite("Encrypted clipboard files")
struct ClipboardEncryptionTests {
    private struct Keys: StoreKeyProviding {
        let value: SymmetricKey
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    private func encryptedStore() -> EncryptedStore {
        EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
    }

    private struct UnavailableKeys: StoreKeyProviding {
        func key(createIfMissing: Bool) throws -> SymmetricKey {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private struct MissingKeys: StoreKeyProviding {
        func key(createIfMissing: Bool) throws -> SymmetricKey {
            throw StoreKeyError.unavailable(Int32(errSecItemNotFound))
        }
    }

    private final class RecoverableKeys: StoreKeyProviding, Sendable {
        private let value: SymmetricKey
        private let unavailable = Mutex(false)

        init(value: SymmetricKey) { self.value = value }

        func key(createIfMissing: Bool) throws -> SymmetricKey {
            guard !unavailable.withLock({ $0 }) else {
                throw StoreKeyError.unavailable(Int32(errSecInteractionNotAllowed))
            }
            return value
        }

        func setUnavailable(_ value: Bool) { unavailable.withLock { $0 = value } }
    }

    @Test("clipboard indexes and picture bytes are sealed and survive a relaunch")
    func filesAreSealed() async throws {
        let folder = try TemporaryFolder()
        let crypto = encryptedStore()
        let file = folder.url.appending(path: "clipboard.json")
        let store = ClipboardStore(file: file, encryptedStore: crypto)
        let original = Data(repeating: 0x89, count: 4096)
        let noticed = NoticedClip(
            clip: Clip(text: "private clipboard phrase", kind: .image, copiedAt: Date()),
            picture: (original, 32, 32))
        _ = try await store.record(noticed, keeping: folder.retention)

        let index = try Data(contentsOf: file)
        #expect(EncryptedStore.isSealed(index))
        #expect(!String(decoding: index, as: UTF8.self).contains("private clipboard phrase"))
        let clip = try #require(await store.clips(keeping: folder.retention).first)
        let image = try #require(clip.image)
        let pictureURL = await store.imagesFolder.appending(path: image.file)
        let picture = try Data(contentsOf: pictureURL)
        #expect(EncryptedStore.isSealed(picture))
        #expect(picture != original)

        let reopened = ClipboardStore(file: file, encryptedStore: crypto)
        let restored = try #require(await reopened.clips(keeping: folder.retention).first)
        #expect(restored.text == "private clipboard phrase")
        #expect(await reopened.imageData(for: try #require(restored.image)) == original)
    }

    @Test("legacy clipboard JSON and picture files migrate on first read")
    func legacyFilesMigrate() async throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appending(path: "clipboard.json")
        let name = "legacy.png"
        let original = ClipImageTests.bytes
        let clip = Clip(
            text: "legacy private phrase", kind: .image, copiedAt: Date(),
            image: ClipImage(file: name, width: 1, height: 1, bytes: original.count))
        try JSONEncoder().encode([clip]).write(to: file)
        let images = folder.url.appending(path: "Images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try original.write(to: images.appending(path: name))

        let store = ClipboardStore(file: file, encryptedStore: encryptedStore())
        let migrated = try #require(await store.clips(keeping: folder.retention).first)
        await store.waitForLegacyPictureMigration()
        #expect(EncryptedStore.isSealed(try Data(contentsOf: file)))
        #expect(await store.imageData(for: try #require(migrated.image)) == original)
        #expect(EncryptedStore.isSealed(try Data(contentsOf: images.appending(path: name))))
    }

    @Test("loading seals every legacy PNG and removes an unreferenced picture")
    func legacyPicturesMigrateOnLoad() async throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appending(path: "clipboard.json")
        let name = "legacy.png"
        let original = ClipImageTests.bytes
        let clip = Clip(
            text: "legacy private phrase", kind: .image, copiedAt: Date(),
            image: ClipImage(file: name, width: 1, height: 1, bytes: original.count))
        try JSONEncoder().encode([clip]).write(to: file)
        let images = folder.url.appending(path: "Images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try original.write(to: images.appending(path: name))
        try original.write(to: images.appending(path: "orphan.png"))

        let crypto = encryptedStore()
        let store = ClipboardStore(file: file, encryptedStore: crypto)
        _ = await store.clips(keeping: folder.retention)
        await store.waitForLegacyPictureMigration()

        let sealed = try Data(contentsOf: images.appending(path: name))
        #expect(EncryptedStore.isSealed(sealed))
        #expect(try crypto.open(sealed, for: name) == original)
        #expect(!FileManager.default.fileExists(atPath: images.appending(path: "orphan.png").path))
    }

    @Test("loading seals pictures even when their index is kept unreadable")
    func legacyPicturesMigrateBesideUnreadableIndex() async throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appending(path: "clipboard.json")
        let damagedIndex = Data("{ damaged legacy index".utf8)
        try damagedIndex.write(to: file)
        let name = "legacy.png"
        let original = ClipImageTests.bytes
        let images = folder.url.appending(path: "Images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try original.write(to: images.appending(path: name))

        let crypto = encryptedStore()
        let store = ClipboardStore(file: file, encryptedStore: crypto)
        _ = await store.clips(keeping: folder.retention)
        await store.waitForLegacyPictureMigration()

        let sealed = try Data(contentsOf: images.appending(path: name))
        #expect(EncryptedStore.isSealed(sealed))
        #expect(try crypto.open(sealed, for: name) == original)
        #expect(try setAsideIndex(in: folder.url) == damagedIndex)
    }

    @Test("zero-length, short and truncated plaintext indexes are preserved and recover")
    func damagedPlaintextIndexesRecover() async throws {
        let damagedIndexes = [Data(), Data([0x7b, 0x22, 0x76]), Data("[{\"id\":".utf8)]
        for damagedIndex in damagedIndexes {
            let folder = try TemporaryFolder()
            let file = folder.url.appending(path: "clipboard.json")
            try damagedIndex.write(to: file)
            let crypto = encryptedStore()
            let store = ClipboardStore(file: file, encryptedStore: crypto)

            #expect(await store.clips(keeping: folder.retention).isEmpty)
            let copies = await store.takeUnreadableIndexSetAsides()
            #expect(copies.count == 1)
            let copy = try #require(copies.first)
            #expect(try Data(contentsOf: copy) == damagedIndex)
            #expect(await store.takeUnreadableIndexSetAsides().isEmpty)

            let later = Clip(text: "a later copy", kind: .text, copiedAt: Date())
            try await store.record(later, keeping: folder.retention)
            let reopened = ClipboardStore(file: file, encryptedStore: crypto)
            #expect(await reopened.clips(keeping: folder.retention).map(\.text) == [later.text])
            #expect(EncryptedStore.isSealed(try Data(contentsOf: file)))
        }
    }

    @Test("a failed picture migration preserves plaintext and retries on the next launch")
    func legacyPictureMigrationRetriesAfterKeyFailure() async throws {
        let folder = try TemporaryFolder()
        let file = folder.url.appending(path: "clipboard.json")
        let name = "legacy.png"
        let original = ClipImageTests.bytes
        let clip = Clip(
            text: "legacy private phrase", kind: .image, copiedAt: Date(),
            image: ClipImage(file: name, width: 1, height: 1, bytes: original.count))
        let index = try JSONEncoder().encode([clip])
        try index.write(to: file)
        let images = folder.url.appending(path: "Images", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        let imageURL = images.appending(path: name)
        try original.write(to: imageURL)

        let unavailable = EncryptedStore(keys: UnavailableKeys())
        let unavailableStore = ClipboardStore(file: file, encryptedStore: unavailable)
        _ = await unavailableStore.clips(keeping: folder.retention)
        await unavailableStore.waitForLegacyPictureMigration()
        #expect(try Data(contentsOf: file) == index)
        #expect(try Data(contentsOf: imageURL) == original)

        let crypto = encryptedStore()
        let availableStore = ClipboardStore(file: file, encryptedStore: crypto)
        _ = await availableStore.clips(keeping: folder.retention)
        await availableStore.waitForLegacyPictureMigration()
        let sealed = try Data(contentsOf: imageURL)
        #expect(EncryptedStore.isSealed(try Data(contentsOf: file)))
        #expect(EncryptedStore.isSealed(sealed))
        #expect(try crypto.open(sealed, for: name) == original)
    }

    @Test("a temporarily unavailable picture key leaves the sealed file for a later retry")
    func lockedPictureKeyRetries() async throws {
        let folder = try TemporaryFolder()
        let keys = RecoverableKeys(value: SymmetricKey(size: .bits256))
        let file = folder.url.appending(path: "clipboard.json")
        let writer = ClipboardStore(file: file, encryptedStore: EncryptedStore(keys: keys))
        let image = try await writer.keep(ClipImageTests.bytes, forClip: UUID(), width: 1, height: 1)
        let url = await writer.imagesFolder.appending(path: image.file)
        let sealed = try Data(contentsOf: url)
        #expect(EncryptedStore.isSealed(sealed))

        // A store holds the first key it reads, so the lock must be in place before this one's first lookup.
        keys.setUnavailable(true)
        let store = ClipboardStore(file: file, encryptedStore: EncryptedStore(keys: keys))
        #expect(await store.imageData(for: image) == nil)
        #expect(try Data(contentsOf: url) == sealed)
        #expect(await store.hasImage(for: image))
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) == [
                image.file
            ])

        keys.setUnavailable(false)
        #expect(await store.imageData(for: image) == ClipImageTests.bytes)
        #expect(try Data(contentsOf: url) == sealed)
    }

    @Test("a definitely missing picture key sets the sealed file aside")
    func missingPictureKeySetsAside() async throws {
        let folder = try TemporaryFolder()
        let writer = ClipboardStore(
            file: folder.url.appending(path: "clipboard.json"), encryptedStore: encryptedStore())
        let image = try await writer.keep(ClipImageTests.bytes, forClip: UUID(), width: 1, height: 1)
        let url = await writer.imagesFolder.appending(path: image.file)
        let sealed = try Data(contentsOf: url)
        let reader = ClipboardStore(
            file: folder.url.appending(path: "clipboard.json"),
            encryptedStore: EncryptedStore(keys: MissingKeys()))

        #expect(await reader.imageData(for: image) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let aside = try #require(
            FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
                .first { $0.hasPrefix("\(image.file).unreadable-") })
        #expect(try Data(contentsOf: url.deletingLastPathComponent().appending(path: aside)) == sealed)
    }

    /// Reads the damaged history index after its load-time set-aside.
    private func setAsideIndex(in folder: URL) throws -> Data? {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        guard let name = names.first(where: { $0.hasPrefix("clipboard.json.unreadable-") }) else {
            return nil
        }
        return try Data(contentsOf: folder.appending(path: name, directoryHint: .notDirectory))
    }

    @Test("a damaged encrypted picture is preserved in the unreadable set-aside")
    func damagedPictureIsSetAside() async throws {
        let folder = try TemporaryFolder()
        let store = ClipboardStore(
            file: folder.url.appending(path: "clipboard.json"), encryptedStore: encryptedStore())
        let image = try await store.keep(ClipImageTests.bytes, forClip: UUID(), width: 1, height: 1)
        let url = await store.imagesFolder.appending(path: image.file)
        let original = try Data(contentsOf: url)
        var damaged = original
        damaged[damaged.index(before: damaged.endIndex)] ^= 0xff
        try damaged.write(to: url)

        #expect(await store.imageData(for: image) == nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        let asideName = try #require(names.first { $0.hasPrefix("\(image.file).unreadable-") })
        #expect(try Data(contentsOf: url.deletingLastPathComponent().appending(path: asideName)) == damaged)
    }
}
