// Tests for pending title sightings kept across quits as keyed hashes in the evidence ledger.

import CryptoKit
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowDictionary

private struct Keys: StoreKeyProviding {
    let value = SymmetricKey(size: .bits256)
    func key(createIfMissing: Bool) throws -> SymmetricKey { value }
}

/// A dictionary and its evidence ledger in one temporary folder, sharing one installation key.
private struct Rig {
    let folder = FileManager.default.temporaryDirectory.appending(
        path: "uttrflow-sightings-\(UUID().uuidString)")
    let encrypted = EncryptedStore(keys: Keys())
    var ledgerFile: URL { folder.appending(path: "evidence.json") }
    var ledger: EvidenceLedgerStore { EvidenceLedgerStore(file: ledgerFile, encryptedStore: encrypted) }

    /// A fresh store over the same files, as a relaunch would open it.
    func store() -> PersonalDictionaryStore {
        let memory = SightingMemory(ledger: ledger, encryptedStore: encrypted) {
            RetentionWindow(days: RetentionWindow.keepAlwaysDays, now: $0)
        }
        return PersonalDictionaryStore(
            file: folder.appending(path: "dictionary.v1.json"), encryptedStore: encrypted, sightings: memory)
    }

    func rows() async -> [UttrflowCore.EvidenceRow] {
        await ledger.rows(keeping: RetentionWindow(days: RetentionWindow.keepAlwaysDays, now: .now))
    }
}

private let title = AppContext(applicationName: "Notes", documentName: "Zorvik rollout plan")

private func sighting(_ store: PersonalDictionaryStore, onDay day: Int) async throws -> [String] {
    try await store.learn(
        heard: "check the zorvick rollout", wrote: "Check the zorvick rollout.", seeing: title,
        at: Date(timeIntervalSince1970: Double(day) * 86_400 + 3_600)
    ).map(\.word)
}

@Suite("Pending sightings kept as keyed hashes")
struct SightingMemoryTests {
    @Test("three dictations on one day learn nothing")
    func oneDayLearnsNothing() async throws {
        let rig = Rig()
        let store = rig.store()
        for _ in 1...3 { #expect(try await sighting(store, onDay: 20_000).isEmpty) }
    }

    @Test("three days learn the term, across a relaunch each day")
    func threeDaysAcrossRelaunches() async throws {
        let rig = Rig()
        #expect(try await sighting(rig.store(), onDay: 20_000).isEmpty)
        #expect(try await sighting(rig.store(), onDay: 20_001).isEmpty)
        #expect(try await sighting(rig.store(), onDay: 20_002) == ["Zorvik"])
    }

    @Test("no pending record holds the term's text")
    func noTextOnDisk() async throws {
        let rig = Rig()
        _ = try await sighting(rig.store(), onDay: 20_000)
        let rows = await rig.rows()
        #expect(rows.count == 1)
        #expect(rows.allSatisfy { !$0.subject.lowercased().contains("zorvik") })
        let bytes = try Data(contentsOf: rig.ledgerFile)
        #expect(!String(decoding: bytes, as: UTF8.self).lowercased().contains("zorvik"))
    }

    @Test("removing learnt words cancels the pending days")
    func resetCancels() async throws {
        let rig = Rig()
        _ = try await sighting(rig.store(), onDay: 20_000)
        _ = try await sighting(rig.store(), onDay: 20_001)
        try await rig.store().removeLearned()
        #expect(try await sighting(rig.store(), onDay: 20_002).isEmpty)
        #expect(SightingLedger(remembering: await rig.rows()).pendingCount == 1)
    }

    @Test("the same text hashes alike under one key and purpose, and apart under another")
    func digestIsKeyed() throws {
        let store = EncryptedStore(keys: Keys())
        let first = try store.digest(of: "zorvik", for: SightingMemory.purpose)
        #expect(first == (try store.digest(of: "zorvik", for: SightingMemory.purpose)))
        #expect(first != (try store.digest(of: "zorvik", for: "another")))
        #expect(first != (try EncryptedStore(keys: Keys()).digest(of: "zorvik", for: SightingMemory.purpose)))
        #expect(!first.contains("zorvik"))
    }
}
