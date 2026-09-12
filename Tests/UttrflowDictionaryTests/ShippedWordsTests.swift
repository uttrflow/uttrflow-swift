// Tests for the words this build ships knowing, and for seeding them exactly once.

import Foundation
import Testing

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
        let store = PersonalDictionaryStore(file: Sandbox().file)
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
        let store = PersonalDictionaryStore(file: Sandbox().file)
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
}
