// Tests for the encrypted, versioned, resettable evidence ledger.

import CryptoKit
import Foundation
import Testing

@testable import UttrflowCore

@Suite("Evidence ledger store")
struct EvidenceLedgerStoreTests {
    private struct Keys: StoreKeyProviding {
        let value = SymmetricKey(size: .bits256)
        func key(createIfMissing: Bool) throws -> SymmetricKey { value }
    }

    private func sandbox() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("ledger.json")
    }

    private let row = EvidenceRow(kind: .use, subject: "entry-1", day: 20_000, provenance: .dictation)

    @Test("appended rows round-trip and the file on disk is sealed, not plain JSON")
    func roundTripsEncrypted() async throws {
        let file = try sandbox()
        let encrypted = EncryptedStore(keys: Keys())
        let store = EvidenceLedgerStore(file: file, encryptedStore: encrypted)
        let revert = EvidenceRow(kind: .revert, subject: "entry-1", weight: 2, day: 20_001, provenance: .undo)
        try await store.append([row])
        try await store.append([revert])
        #expect(await store.rows() == [row, revert])
        let bytes = try Data(contentsOf: file)
        #expect(EncryptedStore.isSealed(bytes))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("entry-1"))
        #expect(await EvidenceLedgerStore(file: file, encryptedStore: encrypted).rows() == [row, revert])
    }

    @Test("reset deletes every row and resetting an absent ledger succeeds")
    func resetDeletesRows() async throws {
        let file = try sandbox()
        let store = EvidenceLedgerStore(file: file, encryptedStore: EncryptedStore(keys: Keys()))
        try await store.append([row])
        try await store.reset()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await store.rows().isEmpty)
        try await store.reset()
    }

    @Test("a file from a newer build is read as empty and never overwritten")
    func newerVersionIsLeftAlone() async throws {
        let file = try sandbox()
        let encrypted = EncryptedStore(keys: Keys())
        try encrypted.write(
            EvidenceLedgerFile(schemaVersion: EvidenceLedgerFile.currentVersion + 1, rows: [row]), to: file)
        let before = try Data(contentsOf: file)
        let store = EvidenceLedgerStore(file: file, encryptedStore: encrypted)
        #expect(await store.rows().isEmpty)
        await #expect(throws: EvidenceLedgerError.newerVersion(EvidenceLedgerFile.currentVersion + 1)) {
            try await store.append([row])
        }
        #expect(try Data(contentsOf: file) == before)
    }
}
