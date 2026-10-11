// Tests that the refusal and seed records are sealed whenever the dictionary is.

import CryptoKit
import Foundation
import Security
import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowDictionary

@Suite("Sealing the dictionary's side records")
struct SealedSidecarTests {
    private struct Keys: StoreKeyProviding {
        let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    /// An installation from before encryption: no key until the first seal creates one.
    private final class FreshKeys: StoreKeyProviding, Sendable {
        private let stored = Mutex<SymmetricKey?>(nil)
        func key(createIfMissing: Bool) throws -> SymmetricKey {
            try stored.withLock { current in
                if let current { return current }
                guard createIfMissing else { throw StoreKeyError.unavailable(Int32(errSecItemNotFound)) }
                let generated = SymmetricKey(size: .bits256)
                current = generated
                return generated
            }
        }
    }

    private let deletedWord = "Zorblatt"

    private func sealedStore(
        _ sandbox: borrowing Sandbox, keys: any StoreKeyProviding
    ) -> PersonalDictionaryStore {
        PersonalDictionaryStore(file: sandbox.file, encryptedStore: EncryptedStore(keys: keys))
    }

    /// Every file under the folder, so a new sidecar cannot escape the check by its name.
    private func filesHolding(_ text: String, in folder: URL) throws -> [String] {
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
        return try names.filter { name in
            let data = try Data(contentsOf: folder.appending(path: name))
            return data.range(of: Data(text.utf8)) != nil
        }
    }

    @Test("leaves no file in the folder holding a deleted word in plaintext")
    func deletedWordIsNowhereInPlaintext() async throws {
        let sandbox = Sandbox()
        let store = sealedStore(sandbox, keys: Keys())
        let deleted = word(deletedWord, from: .learned)
        try await store.add(deleted)
        try await store.add(word("Uttrflow", from: .added))
        try await store.remove(deleted.id)
        try await store.seedShippedWords(at: epoch)

        let names = try FileManager.default.contentsOfDirectory(
            atPath: sandbox.folder.path(percentEncoded: false))
        #expect(names.contains("dictionary.v1.refused.json"))
        #expect(names.contains("dictionary.v1.seeded.json"))
        #expect(try filesHolding(deletedWord, in: sandbox.folder).isEmpty)
        #expect(try filesHolding("Uttrflow", in: sandbox.folder).isEmpty)
    }

    @Test("still refuses a deleted word after a relaunch with the records sealed")
    func sealedRefusalSurvivesARelaunch() async throws {
        let sandbox = Sandbox()
        let keys = Keys()
        let deleted = word(deletedWord, from: .learned)
        try await sealedStore(sandbox, keys: keys).add(deleted)
        try await sealedStore(sandbox, keys: keys).remove(deleted.id)

        let reopened = sealedStore(sandbox, keys: keys)
        let relearned = try await reopened.learn(
            heard: "zor blatt", wrote: deletedWord,
            seeing: .fixture(selectedText: "zor blatt"), at: epoch)
        #expect(relearned.isEmpty)
    }

    @Test("migrates plaintext records from an older build in place without losing a refusal")
    func plaintextRecordsMigrateOnFirstRead() async throws {
        let sandbox = Sandbox()
        let keys = FreshKeys()
        try sandbox.seed([word("Uttrflow", from: .added)])
        let refused = sandbox.folder.appending(path: "dictionary.v1.refused.json")
        let seeded = sandbox.folder.appending(path: "dictionary.v1.seeded.json")
        try JSONEncoder().encode([deletedWord]).write(to: refused)
        try Data(#"{"version":1}"#.utf8).write(to: seeded)

        let store = sealedStore(sandbox, keys: keys)
        let relearned = try await store.learn(
            heard: "zor blatt", wrote: deletedWord,
            seeing: .fixture(selectedText: "zor blatt"), at: epoch)
        try await store.seedShippedWords(at: epoch)

        #expect(relearned.isEmpty)
        #expect(EncryptedStore.isSealed(try Data(contentsOf: refused)))
        #expect(EncryptedStore.isSealed(try Data(contentsOf: seeded)))
        #expect(try filesHolding(deletedWord, in: sandbox.folder).isEmpty)
    }

    @Test("removes both sealed records on a full reset")
    func resetRemovesTheRecords() async throws {
        let sandbox = Sandbox()
        let store = sealedStore(sandbox, keys: Keys())
        let deleted = word(deletedWord, from: .learned)
        try await store.add(deleted)
        try await store.remove(deleted.id)
        try await store.seedShippedWords(at: epoch)

        try await store.removeEverything()

        let names = try FileManager.default.contentsOfDirectory(
            atPath: sandbox.folder.path(percentEncoded: false))
        #expect(!names.contains("dictionary.v1.refused.json"))
        #expect(!names.contains("dictionary.v1.seeded.json"))
    }
}
