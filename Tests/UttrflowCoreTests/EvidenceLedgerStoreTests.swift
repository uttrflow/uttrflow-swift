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

    /// Noon on day 20,001, with a window long enough to keep every row these tests write.
    private let now = Date(timeIntervalSince1970: 20_001 * 86_400 + 43_200)
    private var always: RetentionWindow { RetentionWindow(days: RetentionWindow.keepAlwaysDays, now: now) }

    @Test("appended rows round-trip and the file on disk is sealed, not plain JSON")
    func roundTripsEncrypted() async throws {
        let file = try sandbox()
        let encrypted = EncryptedStore(keys: Keys())
        let store = EvidenceLedgerStore(file: file, encryptedStore: encrypted)
        let revert = EvidenceRow(kind: .revert, subject: "entry-1", weight: 2, day: 20_001, provenance: .undo)
        try await store.append([row], keeping: always)
        try await store.append([revert], keeping: always)
        #expect(await store.rows(keeping: always) == [row, revert])
        let bytes = try Data(contentsOf: file)
        #expect(EncryptedStore.isSealed(bytes))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("entry-1"))
        #expect(
            await EvidenceLedgerStore(file: file, encryptedStore: encrypted).rows(keeping: always) == [
                row, revert,
            ])
    }

    @Test("reset deletes every row and resetting an absent ledger succeeds")
    func resetDeletesRows() async throws {
        let file = try sandbox()
        let store = EvidenceLedgerStore(file: file, encryptedStore: EncryptedStore(keys: Keys()))
        try await store.append([row], keeping: always)
        try await store.reset()
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await store.rows(keeping: always).isEmpty)
        try await store.reset()
    }

    @Test("forgetting one subject's kinds leaves its other kinds and every other subject")
    func forgetRemovesOnlyTheNamedRows() async throws {
        let store = EvidenceLedgerStore(file: try sandbox(), encryptedStore: EncryptedStore(keys: Keys()))
        let other = EvidenceRow(kind: .use, subject: "entry-2", day: 20_000, provenance: .dictation)
        let sighting = EvidenceRow(kind: .sighting, subject: "entry-1", day: 20_000, provenance: .dictation)
        try await store.append([row, other, sighting], keeping: always)
        try await store.forget(subject: "entry-1", kinds: [.use, .revert])
        #expect(await store.rows(keeping: always) == [other, sighting])
        try await store.forget(kinds: [.sighting])
        #expect(await store.rows(keeping: always) == [other])
    }

    @Test("a file from a newer build is read as empty and never overwritten")
    func newerVersionIsLeftAlone() async throws {
        let file = try sandbox()
        let encrypted = EncryptedStore(keys: Keys())
        try encrypted.write(
            EvidenceLedgerFile(schemaVersion: EvidenceLedgerFile.currentVersion + 1, rows: [row]), to: file)
        let before = try Data(contentsOf: file)
        let store = EvidenceLedgerStore(file: file, encryptedStore: encrypted)
        #expect(await store.rows(keeping: always).isEmpty)
        await #expect(throws: EvidenceLedgerError.newerVersion(EvidenceLedgerFile.currentVersion + 1)) {
            try await store.append([row], keeping: always)
        }
        #expect(try Data(contentsOf: file) == before)
    }

    @Test("rows outside the History window are hidden and deleted from disk, and none left removes the file")
    func retentionDeletesExpiredRows() async throws {
        let file = try sandbox()
        let encrypted = EncryptedStore(keys: Keys())
        let store = EvidenceLedgerStore(file: file, encryptedStore: encrypted)
        let today = EvidenceRow(kind: .use, subject: "entry-2", day: 20_001, provenance: .dictation)
        try await store.append([row, today], keeping: always)
        let oneDay = RetentionWindow(days: 1, now: now)
        #expect(await store.rows(keeping: oneDay) == [today])
        #expect(
            await EvidenceLedgerStore(file: file, encryptedStore: encrypted).rows(keeping: always) == [today])
        #expect(await store.rows(keeping: RetentionWindow(days: 0, now: now)).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("an append drops rows the window no longer keeps")
    func appendAppliesRetention() async throws {
        let file = try sandbox()
        let store = EvidenceLedgerStore(file: file, encryptedStore: EncryptedStore(keys: Keys()))
        let today = EvidenceRow(kind: .sighting, subject: "entry-3", day: 20_001, provenance: .dictation)
        try await store.append([row], keeping: always)
        try await store.append([today], keeping: RetentionWindow(days: 1, now: now))
        #expect(await store.rows(keeping: always) == [today])
    }

    @Test("a clock too far ahead to be believed hides expired rows but leaves them on disk")
    func unbelievableClockOnlyHides() async throws {
        let file = try sandbox()
        let store = EvidenceLedgerStore(file: file, encryptedStore: EncryptedStore(keys: Keys()))
        try await store.append([row], keeping: always)
        let farAhead = RetentionWindow(days: 1, now: now.addingTimeInterval(2 * 365 * 86_400))
        #expect(await store.rows(keeping: farAhead).isEmpty)
        #expect(await store.rows(keeping: always) == [row])
    }

    @Test("a day number carries no time of day")
    func dayOfMoment() {
        #expect(EvidenceRow.day(of: now) == 20_001)
        #expect(EvidenceRow.day(of: Date(timeIntervalSince1970: 20_001 * 86_400)) == 20_001)
        #expect(EvidenceRow.day(of: Date(timeIntervalSince1970: -1)) == -1)
    }

    @Test("the ledger is one listed store entry under the support folder")
    func defaultFileIsListed() {
        let root = URL(fileURLWithPath: "/tmp/example")
        #expect(EvidenceLedgerStore.defaultFile(in: root).lastPathComponent == "evidence.v1.json")
        #expect(LocalStoreEntry.evidenceLedger.claimedNames == ["evidence.v1.json"])
    }
}
