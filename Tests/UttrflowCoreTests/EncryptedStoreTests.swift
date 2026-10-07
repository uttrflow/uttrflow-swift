// Tests for authenticated local-store files and legacy migration.

import CryptoKit
import Foundation
import Security
import Synchronization
import Testing

@testable import UttrflowCore

@Suite("Encrypted local stores")
struct EncryptedStoreTests {
    private struct Keys: StoreKeyProviding {
        let value: SymmetricKey
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    @Test("a keyed digest matches equal input, differs by key and purpose, and is never the input")
    func keyedDigestIsKeyed() throws {
        let store = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        let other = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        let line = Data("git commit -m example".utf8)

        let digest = try store.keyedDigest(of: line, purpose: "one")

        #expect(digest.count == 32)
        #expect(try store.keyedDigest(of: line, purpose: "one") == digest)
        #expect(try store.keyedDigest(of: line, purpose: "two") != digest)
        #expect(try other.keyedDigest(of: line, purpose: "one") != digest)
        #expect(Data(SHA256.hash(data: line)) != digest)
    }

    private struct MissingKey: StoreKeyProviding {
        func key(createIfMissing: Bool) throws -> SymmetricKey {
            throw StoreKeyError.unavailable(Int32(errSecItemNotFound))
        }
    }

    private struct LockedKey: StoreKeyProviding {
        func key(createIfMissing: Bool) throws -> SymmetricKey {
            throw StoreKeyError.unavailable(Int32(errSecInteractionNotAllowed))
        }
    }

    private final class UnlockingKeys: StoreKeyProviding, Sendable {
        let value = SymmetricKey(size: .bits256)
        let locked = Mutex(true)
        let lookups = Mutex(0)
        func key(createIfMissing: Bool) throws -> SymmetricKey {
            lookups.withLock { $0 += 1 }
            if locked.withLock({ $0 }) { throw StoreKeyError.unavailable(Int32(errSecInteractionNotAllowed)) }
            return value
        }
    }

    private final class RevocableKeys: StoreKeyProviding, StoreKeyRevoking, Sendable {
        private let stored = Mutex<SymmetricKey?>(nil)

        func key(createIfMissing: Bool) throws -> SymmetricKey {
            try stored.withLock { current in
                if let current { return current }
                guard createIfMissing else {
                    throw StoreKeyError.unavailable(Int32(errSecItemNotFound))
                }
                let generated = SymmetricKey(size: .bits256)
                current = generated
                return generated
            }
        }

        func revokeKey() throws { stored.withLock { $0 = nil } }
    }

    private func folder() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "uttrflow-encrypted-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("writes a filename-bound envelope and reads it back")
    func roundTrip() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let store = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        try store.write(["private"], to: file)

        #expect(try Data(contentsOf: file).starts(with: Data("UTTFLOWE".utf8)))
        #expect(store.read([String].self, from: file).value == ["private"])
    }

    @Test("recovers a truncated write from the previous sealed generation")
    func recoversTruncatedWrite() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let key = SymmetricKey(size: .bits256)
        let store = EncryptedStore(keys: Keys(value: key))
        try store.write(["previous"], to: file)
        let previous = try Data(contentsOf: file)
        let faultingWriter = EncryptedStore(keys: Keys(value: key)) { data, url in
            try PrivateFile.write(Data(data.prefix(10)), to: url)
        }

        try faultingWriter.write(["replacement"], to: file, preservingPreviousGeneration: true)
        let recovered = store.read(
            [String].self, from: file, recoveringPreviousGeneration: true)

        #expect(recovered.value == ["previous"])
        #expect(try Data(contentsOf: file) == previous)
        #expect(try Data(contentsOf: PrivateFile.backupURL(for: file)) == previous)
        #expect(LocalStore.hasSetAside(file))

        try store.remove(file)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: PrivateFile.backupURL(for: file).path))

        let ordinaryFile = directory.appending(path: "ordinary.v1.json")
        try store.write(["previous"], to: ordinaryFile)
        let ordinaryPrevious = try Data(contentsOf: ordinaryFile)
        try PrivateFile.preserveSealedGeneration(ordinaryPrevious, from: ordinaryFile)
        try Data(ordinaryPrevious.prefix(10)).write(to: ordinaryFile)
        let ordinaryRead = store.read([String].self, from: ordinaryFile)
        #expect(ordinaryRead.value == nil)

        let missingFile = directory.appending(path: "missing.v1.json")
        try store.write(["restore missing index"], to: missingFile)
        let missingGeneration = try Data(contentsOf: missingFile)
        try PrivateFile.preserveSealedGeneration(missingGeneration, from: missingFile)
        try FileManager.default.removeItem(at: missingFile)
        let missingRead = store.read(
            [String].self, from: missingFile, recoveringPreviousGeneration: true)
        #expect(missingRead.value == nil)
        #expect(!missingRead.isUnreadable)
        #expect(!FileManager.default.fileExists(atPath: missingFile.path))
        #expect(FileManager.default.fileExists(atPath: PrivateFile.backupURL(for: missingFile).path))
        try store.write(["new generation"], to: missingFile, preservingPreviousGeneration: true)
        #expect(!FileManager.default.fileExists(atPath: PrivateFile.backupURL(for: missingFile).path))
        let newGeneration = try Data(contentsOf: missingFile)
        try store.write(["newer generation"], to: missingFile, preservingPreviousGeneration: true)
        try Data(try Data(contentsOf: missingFile).prefix(10)).write(to: missingFile)
        let afterNewWrite = store.read(
            [String].self, from: missingFile, recoveringPreviousGeneration: true)
        #expect(afterNewWrite.value == ["new generation"])
        #expect(try Data(contentsOf: PrivateFile.backupURL(for: missingFile)) == newGeneration)
    }

    @Test("reset removes the backup before the primary so interruption cannot revive it")
    func resetRemovesBackupBeforePrimary() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "clipboard.v1.json")
        let key = SymmetricKey(size: .bits256)
        let store = EncryptedStore(keys: Keys(value: key))
        try store.write(["previous"], to: file)
        try store.write(["current"], to: file, preservingPreviousGeneration: true)
        let interruptedReset = EncryptedStore(
            keys: Keys(value: key),
            writeFile: { data, url in try PrivateFile.write(data, to: url) },
            removeFile: { target in
                guard target != file else { throw CocoaError(.fileWriteUnknown) }
                try FileManager.default.removeItem(at: target)
            })

        #expect(throws: (any Error).self) { try interruptedReset.remove(file) }
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: PrivateFile.backupURL(for: file).path))
        #expect(
            store.read([String].self, from: file, recoveringPreviousGeneration: true).value == ["current"])
    }

    @Test("file fallback keeps one key across provider instances and removes it on reset")
    func fileKeyFallbackPersistsAndRevokes() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyFile = directory.appending(path: "key.v1")
        let first = KeychainStoreKeyProvider(fileURL: keyFile)
        let key = try first.resolveKeychainResult(
            status: errSecItemNotFound,
            data: nil,
            createIfMissing: true
        ) { _ in errSecMissingEntitlement }
        #expect(try Data(contentsOf: keyFile).count == 32)
        #expect(
            try first.resolveKeychainResult(
                status: errSecItemNotFound,
                data: nil,
                createIfMissing: false
            ) { _ in
                Issue.record("Must reuse the existing fallback without adding a Keychain item");
                return errSecSuccess
            }
            .withUnsafeBytes { Data($0) }
                == key.withUnsafeBytes { Data($0) })

        try first.revokeKey()
        #expect(!FileManager.default.fileExists(atPath: keyFile.path))
        #expect(throws: (any Error).self) {
            try first.resolveKeychainResult(
                status: errSecItemNotFound,
                data: nil,
                createIfMissing: false
            ) { _ in
                Issue.record("Must not add while reading a missing key"); return errSecSuccess
            }
        }
    }

    @Test("does not use the file fallback for unrelated Keychain failures")
    func keychainFailuresStayFailClosed() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let provider = KeychainStoreKeyProvider(fileURL: directory.appending(path: "key.v1"))

        #expect(throws: (any Error).self) {
            try provider.resolveKeychainResult(
                status: errSecInteractionNotAllowed,
                data: nil,
                createIfMissing: true
            ) { _ in
                Issue.record("Must not try to add after a locked-keychain response"); return errSecSuccess
            }
        }
    }

    @Test("rejects a different key and leaves the source bytes set aside")
    func wrongKey() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let writer = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        try writer.write(["private"], to: file)
        let reader = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        let stored = reader.read([String].self, from: file)

        #expect(stored.isUnreadable)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(LocalStore.hasSetAside(file))
    }

    @Test("migrates valid legacy JSON and preserves its decoded value")
    func migratesLegacy() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        try Data("[\"private\"]".utf8).write(to: file)
        let store = EncryptedStore(keys: RevocableKeys())

        #expect(store.read([String].self, from: file).value == ["private"])
        #expect(try Data(contentsOf: file).starts(with: Data("UTTFLOWE".utf8)))
    }

    @Test("keeps migrating every legacy file in the launch whose first seal created the key")
    func migrationLaunchStaysOpen() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "history.v1.json")
        let second = directory.appending(path: "snippets.v1.json")
        try Data("[\"one\"]".utf8).write(to: first)
        try Data("[\"two\"]".utf8).write(to: second)
        let store = EncryptedStore(keys: RevocableKeys())

        try store.write(["new"], to: directory.appending(path: "settings.v1.json"))

        #expect(store.read([String].self, from: first).value == ["one"])
        #expect(store.read([String].self, from: second).value == ["two"])
    }

    @Test("refuses and sets aside a plaintext file written once the installation key exists")
    func plaintextAfterKeyIsRefused() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "clipboard.v1.json")
        let keys = RevocableKeys()
        let writer = EncryptedStore(keys: keys)
        try writer.write(["mine"], to: file)
        let planted = Data("[\"planted\"]".utf8)
        try planted.write(to: file)

        let reader = EncryptedStore(keys: keys)
        let stored = reader.read([String].self, from: file)

        #expect(stored.isUnreadable)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        guard case .unreadable(let moved) = stored else { return }
        let movedData = try Data(contentsOf: try #require(moved))
        #expect(EncryptedStore.isSealed(movedData))
        #expect(try reader.open(movedData, for: moved!.lastPathComponent) == planted)
    }

    @Test("keeps a leftover plaintext file readable while the previous launch's migration marker is missing")
    func plaintextBeforeMarkerIsReadAsLegacy() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "clipboard.v1.json")
        let marker = directory.appending(path: "marker.v1")
        let keys = RevocableKeys()
        try EncryptedStore(keys: keys).write(["mine"], to: file)
        try Data("[\"leftover\"]".utf8).write(to: file)

        let next = EncryptedStore(
            keys: keys,
            writeFile: { data, url in try data.write(to: url) },
            markerURL: marker)
        let result = next.read([String].self, from: file)

        #expect(result.value == ["leftover"])
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("keeps legacy migration open until every lazy store has finished")
    func migrationWindowWaitsForEveryStore() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appending(path: "marker.v1")
        let file = directory.appending(path: "dictionary.v1.refused.json")
        let keys = RevocableKeys()
        let writer = EncryptedStore(
            keys: keys,
            writeFile: { data, url in try data.write(to: url) },
            markerURL: marker)
        try writer.write(["seed"], to: directory.appending(path: "key-creation.v1.json"))
        try Data("[\"refused\"]".utf8).write(to: file)

        try writer.markLegacyMigrationComplete(for: .clipboardPictures)
        let afterOneStore = EncryptedStore(
            keys: keys,
            writeFile: { data, url in try data.write(to: url) },
            markerURL: marker)

        #expect(afterOneStore.read([String].self, from: file).value == ["refused"])

        try writer.markLegacyMigrationComplete(for: .dictionaryRecords)
        try Data("[\"planted\"]".utf8).write(to: file)
        let afterEveryStore = EncryptedStore(
            keys: keys,
            writeFile: { data, url in try data.write(to: url) },
            markerURL: marker)

        #expect(afterEveryStore.read([String].self, from: file).isUnreadable)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("refuses and sets aside leftover plaintext once the previous launch's migration marker is in place")
    func plaintextAfterMarkerIsRefused() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "clipboard.v1.json")
        let marker = directory.appending(path: "marker.v1")
        let keys = RevocableKeys()
        let writer = EncryptedStore(
            keys: keys,
            writeFile: { data, url in try data.write(to: url) },
            markerURL: marker)
        try writer.write(["mine"], to: file)
        try writer.markLegacyMigrationComplete()
        try Data("[\"leftover\"]".utf8).write(to: file)

        let next = EncryptedStore(
            keys: keys,
            writeFile: { data, url in try data.write(to: url) },
            markerURL: marker)
        let stored = next.read([String].self, from: file)

        #expect(stored.isUnreadable)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("leaves a plaintext file in place while the key cannot be looked up")
    func plaintextWithLockedKeyStays() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "clipboard.v1.json")
        try Data("[\"x\"]".utf8).write(to: file)

        #expect(EncryptedStore(keys: LockedKey()).read([String].self, from: file).isLeftInPlace)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("keeps malformed legacy JSON in place when it cannot be encrypted")
    func malformedLegacyStaysWhenSealingFails() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let source = Data("{ malformed".utf8)
        try source.write(to: file)

        let stored = EncryptedStore(keys: MissingKey()).read([String].self, from: file)

        #expect(stored.isUnreadable)
        #expect(stored.isLeftInPlace)
        #expect(try Data(contentsOf: file) == source)
        #expect(!LocalStore.hasSetAside(file))
        let remaining = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(remaining == [file.lastPathComponent])
    }

    @Test("seals a plaintext file it sets aside, so the copy is not readable beside the encrypted store")
    func plaintextSetAsideIsSealed() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let source = Data("[\"private\", ".utf8)
        try source.write(to: file)
        let store = EncryptedStore(
            keys: Keys(value: SymmetricKey(size: .bits256)),
            markerURL: directory.appending(path: "legacy-migration.marker"))

        let stored = store.read([String].self, from: file)

        guard case .unreadable(let moved) = stored else {
            Issue.record("expected the file to be set aside")
            return
        }
        let copy = try #require(moved)
        let sealed = try Data(contentsOf: copy)
        #expect(EncryptedStore.isSealed(sealed))
        #expect(try store.open(sealed, for: copy.lastPathComponent) == source)
    }

    @Test("rejects a renamed store because the logical filename is authenticated")
    func wrongFilename() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let renamed = directory.appending(path: "snippets.v1.json")
        let store = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        try store.write(["private"], to: file)
        try FileManager.default.moveItem(at: file, to: renamed)

        #expect(store.read([String].self, from: renamed).isUnreadable)
        #expect(LocalStore.hasSetAside(renamed))
    }

    @Test("does not quarantine an encrypted file while its keychain is temporarily locked")
    func lockedKeyLeavesFileInPlace() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let writer = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        try writer.write(["private"], to: file)
        let source = try Data(contentsOf: file)
        let reader = EncryptedStore(keys: LockedKey())

        let stored = reader.read([String].self, from: file)

        #expect(stored.isUnreadable)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: file) == source)
        #expect(!LocalStore.hasSetAside(file))
    }

    @Test("quarantines an encrypted file when its key is definitely missing")
    func missingKeyQuarantines() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        try EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256))).write(["private"], to: file)

        let stored = EncryptedStore(keys: MissingKey()).read([String].self, from: file)

        #expect(stored.isUnreadable)
        #expect(LocalStore.hasSetAside(file))
    }

    @Test("does not replace an encrypted file when its key is missing")
    func missingKeyCannotReplaceEncryptedFile() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        try EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256))).write(["private"], to: file)
        let source = try Data(contentsOf: file)

        do {
            try EncryptedStore(keys: MissingKey()).write(["replacement"], to: file)
            Issue.record("Expected a missing key to prevent replacing the encrypted file")
        } catch StoreKeyError.unavailable(let status) {
            #expect(status == Int32(errSecItemNotFound))
        }

        #expect(try Data(contentsOf: file) == source)
    }

    @Test("revoking the installation key makes retained envelopes unreadable")
    func revokeKey() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "history.v1.json")
        let retainedDirectory = directory.appending(path: "retained", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: retainedDirectory, withIntermediateDirectories: true)
        let retainedCopy = retainedDirectory.appending(path: "history.v1.json")
        let keys = RevocableKeys()
        let store = EncryptedStore(keys: keys)
        try store.write(["private"], to: source)
        try Data(contentsOf: source).write(to: retainedCopy)

        try store.revokeKey()

        let unreadable = store.read([String].self, from: retainedCopy)
        #expect(unreadable.value == nil)
        #expect(LocalStore.hasSetAside(retainedCopy))
    }

    @Test("a locked key is read again after unlock and then reused")
    func lockedKeyIsRetriedThenCached() throws {
        let keys = UnlockingKeys()
        let store = EncryptedStore(keys: keys)
        #expect(throws: StoreKeyError.self) { try store.seal(Data([1]), for: "chunk") }
        keys.locked.withLock { $0 = false }
        let sealed = try store.seal(Data([1]), for: "chunk")
        _ = try store.seal(Data([2]), for: "chunk")
        #expect(try store.open(sealed, for: "chunk") == Data([1]))
        #expect(keys.lookups.withLock { $0 } == 2)
    }

    @Test("rejects unsupported, truncated and modified envelopes")
    func malformedEnvelopes() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "history.v1.json")
        let store = EncryptedStore(keys: Keys(value: SymmetricKey(size: .bits256)))
        try store.write(["private"], to: file)
        let valid = try Data(contentsOf: file)
        for (index, invalid) in [
            Data(valid.dropLast(4)),
            Data(valid.enumerated().map { $0.offset == valid.count - 1 ? $0.element ^ 0x01 : $0.element }),
            Data(valid.enumerated().map { $0.offset == 8 ? 0x02 : $0.element }),
        ].enumerated() {
            try invalid.write(to: file)
            #expect(store.read([String].self, from: file).isUnreadable, "invalid envelope \(index)")
            try valid.write(to: file)
        }
    }
}
