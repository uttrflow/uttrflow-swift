// Tests for the words this build ships knowing, and for seeding them exactly once.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowDictionary

@Suite("The words Uttrflow ships knowing")
struct ShippedWordsTests {
    @Test("ships the product's own name, which is the word a user writing about it will say")
    func shipsTheProductName() {
        #expect(ShippedWords.spellings.map(\.word).contains("Uttrflow"))
        #expect(ShippedWords.entries(at: epoch).allSatisfy { $0.origin == .shipped })
        #expect(ShippedWords.entries(at: epoch).allSatisfy { $0.firstSeen == epoch })
    }

    /// A shipped word claims nothing about this Mac, so it is neither learned nor added.
    @Test("writes the shipped words into an empty dictionary, marked as shipped")
    func seedsAnEmptyDictionary() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)

        let seeded = try await store.seedShippedWords(at: epoch)

        #expect(seeded.map(\.word) == ["Uttrflow"])
        #expect(await store.allEntries().map(\.origin) == [.shipped])
        #expect(sandbox.onDisk()?.map(\.word) == ["Uttrflow"])
    }

    @Test("seeds once, however many times it is asked")
    func seedsOnlyOnce() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.seedShippedWords(at: epoch)

        #expect(try await store.seedShippedWords(at: epoch).isEmpty)
        #expect(await store.allEntries().count == 1)
        // A later launch is a new store over the same files, which is the case that has to hold.
        let relaunched = PersonalDictionaryStore(file: sandbox.file)
        #expect(try await relaunched.seedShippedWords(at: epoch).isEmpty)
        #expect(await relaunched.allEntries().count == 1)
    }

    @Test("a full reset offers shipped words again on the next launch", arguments: [false, true])
    func fullResetRestoresSeeding(deleteFirst: Bool) async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let seeded = try await store.seedShippedWords(at: epoch)
        if deleteFirst {
            let entry = try #require(seeded.first)
            try await store.remove(entry.id)
        }

        try await store.removeEverything()
        #expect(await store.allEntries().isEmpty)
        let record = sandbox.folder.appending(path: "dictionary.v1.seeded.json")
        #expect(!FileManager.default.fileExists(atPath: record.path(percentEncoded: false)))

        let relaunched = PersonalDictionaryStore(file: sandbox.file)
        let restored = try await relaunched.seedShippedWords(at: epoch)
        #expect(restored.map(\.word) == ShippedWords.entries(at: epoch).map(\.word))
        #expect(try await relaunched.seedShippedWords(at: epoch).isEmpty)
        #expect(sandbox.onDisk()?.map(\.word) == restored.map(\.word))
    }

    @Test("forgetting learned words keeps the deletion of a shipped word across launches")
    func learnedResetKeepsSeedingRecord() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let seeded = try await store.seedShippedWords(at: epoch)
        let entry = try #require(seeded.first)
        try await store.remove(entry.id)
        try await store.removeLearned()

        let relaunched = PersonalDictionaryStore(file: sandbox.file)
        #expect(try await relaunched.seedShippedWords(at: epoch).isEmpty)
        #expect(await relaunched.allEntries().isEmpty)
    }

    @Test("a full reset reports a seed record it cannot remove")
    func fullResetReportsSeedRecordFailure() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.seedShippedWords(at: epoch)
        let record = sandbox.folder.appending(path: "dictionary.v1.seeded.json")
        try setImmutable(record, true)
        defer { try? setImmutable(record, false) }

        await #expect(throws: DictionaryStoreError.couldNotWrite) {
            try await store.removeEverything()
        }
    }

    /// The user's deletion is the whole point of the record beside the file.
    @Test("does not bring back a shipped word the user deleted")
    func doesNotResurrectADeletedWord() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.seedShippedWords(at: epoch)
        let seeded = try #require(await store.allEntries().first)
        try await store.remove(seeded.id)

        let relaunched = PersonalDictionaryStore(file: sandbox.file)
        try await relaunched.seedShippedWords(at: epoch)

        #expect(await relaunched.allEntries().isEmpty)
    }

    @Test("does not restore a deleted shipped word when its seed record is damaged")
    func damagedRecordDoesNotResurrectADeletedWord() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.seedShippedWords(at: epoch)
        let seeded = try #require(await store.allEntries().first)
        try await store.remove(seeded.id)
        let record = sandbox.folder.appending(path: "dictionary.v1.seeded.json")
        let damaged = Data("not JSON".utf8)
        try damaged.write(to: record)

        // The unreadable record is set aside, so every later launch must still refuse rather than reseed.
        for _ in 0..<2 {
            let relaunched = PersonalDictionaryStore(file: sandbox.file)
            await #expect(throws: DictionaryStoreError.couldNotReadSeedRecord) {
                try await relaunched.seedShippedWords(at: epoch)
            }
            #expect(await relaunched.allEntries().isEmpty)
        }
        #expect(LocalStore.hasSetAside(record))
    }

    @Test("keeps a deleted shipped word deleted when a later build ships another")
    func laterListDoesNotResurrectADeletedWord() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.seedShippedWords(at: epoch)
        let seeded = try #require(await store.allEntries().first)
        try await store.remove(seeded.id)
        let later = ShippedWords.entries(at: epoch) + [word("Zyphrel", from: .shipped)]

        let relaunched = PersonalDictionaryStore(file: sandbox.file)
        let added = try await relaunched.seed(later)

        #expect(added.map(\.word) == ["Zyphrel"])
        #expect(await relaunched.allEntries().map(\.word) == ["Zyphrel"])
        #expect(try await PersonalDictionaryStore(file: sandbox.file).seed(later).isEmpty)
    }

    @Test("treats a record naming only version 1 as having offered that version's words")
    func versionOnlyRecordCountsAsOffered() async throws {
        let sandbox = Sandbox()
        let record = sandbox.folder.appending(path: "dictionary.v1.seeded.json")
        try PrivateFile.write(Data(#"{"version":1}"#.utf8), to: record)
        let later = ShippedWords.entries(at: epoch) + [word("Zyphrel", from: .shipped)]

        let added = try await PersonalDictionaryStore(file: sandbox.file).seed(later)

        #expect(added.map(\.word) == ["Zyphrel"])
    }

    @Test("leaves a word the user added under their own name alone")
    func doesNotDuplicateAWordAlreadyKnown() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word: "Uttrflow", pronunciation: "", at: epoch)

        #expect(try await store.seedShippedWords(at: epoch).isEmpty)
        #expect(await store.allEntries().map(\.origin) == [.added])
    }

    /// "Forget what Uttrflow learned" is about this Mac; a shipped word was inferred from nothing.
    @Test("keeps a shipped word when the learned ones are forgotten")
    func survivesForgettingWhatWasLearned() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.seedShippedWords(at: epoch)
        try await store.add(word("kubectl", from: .observed))

        let kept = try await store.removeLearned()

        #expect(kept.map(\.word) == ["Uttrflow"])
    }

    /// Matching is by sound, which is what makes one entry cover the family of mishearings.
    @Test(
        "is found by the way the name sounds, not only by its spelling",
        arguments: ["utter flow", "utterflow", "otter flow", "udder flow"])
    func isFoundBySound(heard: String) async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.seedShippedWords(at: epoch)

        let found = await store.index()
            .candidates(for: Utterance(heard: heard, confidence: 0.4))

        #expect(found.map(\.word) == ["Uttrflow"])
    }

    /// Two dictionaries in one folder must not share a record, or the second is never seeded.
    @Test("records the seeding against the dictionary it seeded")
    func recordsAgainstItsOwnFile() async throws {
        let sandbox = Sandbox()
        let first = PersonalDictionaryStore(file: sandbox.file)
        let second = PersonalDictionaryStore(
            file: sandbox.folder.appending(path: "dictionary.other.json"))
        try await first.seedShippedWords(at: epoch)

        #expect(try await second.seedShippedWords(at: epoch).map(\.word) == ["Uttrflow"])
    }

    /// A dictionary that cannot be written to seeds nothing, and must not be marked as seeded.
    @Test("seeds on the next launch when the words could not be written the first time")
    func retriesAfterTheWordsFailToWrite() async throws {
        let sandbox = Sandbox()
        try sandbox.seed([DictionaryEntry]())
        try setImmutable(sandbox.file, true)
        let store = PersonalDictionaryStore(file: sandbox.file)

        await #expect(throws: DictionaryStoreError.couldNotWrite) {
            try await store.seedShippedWords(at: epoch)
        }
        try setImmutable(sandbox.file, false)

        let relaunched = PersonalDictionaryStore(file: sandbox.file)
        #expect(try await relaunched.seedShippedWords(at: epoch).map(\.word) == ["Uttrflow"])
        #expect(await relaunched.allEntries().map(\.word) == ["Uttrflow"])
    }

    /// The words landed and only the record failed, so the next launch writes the record and no second copy.
    @Test("installs the words exactly once when only the record could not be written")
    func retriesAfterTheRecordFailsToWrite() async throws {
        let sandbox = Sandbox()
        let record = sandbox.folder.appending(path: "dictionary.v1.seeded.json")
        try PrivateFile.write(Data(#"{"version":0}"#.utf8), to: record)
        try setImmutable(record, true)
        let store = PersonalDictionaryStore(file: sandbox.file)

        await #expect(throws: DictionaryStoreError.couldNotWrite) {
            try await store.seedShippedWords(at: epoch)
        }
        try setImmutable(record, false)

        let relaunched = PersonalDictionaryStore(file: sandbox.file)
        #expect(try await relaunched.seedShippedWords(at: epoch).isEmpty)
        #expect(await relaunched.allEntries().map(\.word) == ["Uttrflow"])

        // Recorded now, so a word deleted from here on stays deleted.
        let seeded = try #require(await relaunched.allEntries().first)
        try await relaunched.remove(seeded.id)
        try await PersonalDictionaryStore(file: sandbox.file).seedShippedWords(at: epoch)
        #expect(await PersonalDictionaryStore(file: sandbox.file).allEntries().isEmpty)
    }

    /// Locks or unlocks a file against every write, the way a failing disk refuses one.
    private func setImmutable(_ file: URL, _ locked: Bool) throws {
        try FileManager.default.setAttributes(
            [.immutable: locked], ofItemAtPath: file.path(percentEncoded: false))
    }
}
