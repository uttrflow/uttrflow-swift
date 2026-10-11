// Tests for learning a fix that does not sound like the word it replaced, with the misheard form as its sound.

import CryptoKit
import Foundation
import Testing
import UttrflowCore

@testable import UttrflowDictionary

private struct Keys: StoreKeyProviding {
    let value = SymmetricKey(size: .bits256)
    func key(createIfMissing: Bool) throws -> SymmetricKey { value }
}

private func day(_ number: Int) -> Date { Date(timeIntervalSince1970: Double(number) * 86_400 + 3_600) }

@Suite("The misheard form is kept with the corrected word")
struct MisheardFormTests {
    @Test("An edit that recurs on separate days becomes one entry that says it like the heard words")
    func recurringEditIsLearnt() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        var learnt: [DictionaryEntry] = []
        for number in [10, 10, 11] {
            learnt += try await store.learnEdit(heard: "cooper nettys", wrote: "Kubernetes", at: day(number))
        }
        #expect(learnt.map(\.word) == ["Kubernetes"])
        #expect(learnt.first?.pronunciation == "cooper nettys")
        #expect(learnt.first?.origin == .learned)
        #expect(sandbox.onDisk()?.map(\.word) == ["Kubernetes"])
    }

    @Test("A fix into one word from two heard words is learnt the same way")
    func shortFix() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        var learnt: [DictionaryEntry] = []
        for number in [20, 21, 22] {
            learnt += try await store.learnEdit(heard: "pie torch", wrote: "PyTorch", at: day(number))
        }
        #expect(learnt.map(\.word) == ["PyTorch"])
        #expect(learnt.first?.pronunciation == "pie torch")
    }

    @Test("A replacement the recogniser already spells is refused, as for every other route")
    func recogniserWord() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        var learnt: [DictionaryEntry] = []
        for number in [10, 11, 12] {
            learnt += try await store.learnEdit(heard: "gate", wrote: "git", at: day(number))
        }
        #expect(GeneralVocabulary.isOrdinary("git"))
        #expect(learnt.isEmpty)
    }

    @Test("A one-off edit learns nothing")
    func oneOff() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let learnt = try await store.learnEdit(heard: "cooper nettys", wrote: "Kubernetes", at: day(10))
        #expect(learnt.isEmpty)
        #expect(sandbox.onDisk() == nil)
    }

    @Test("A burst of edits on one day learns nothing")
    func oneDay() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        var learnt: [DictionaryEntry] = []
        for _ in 0..<5 {
            learnt += try await store.learnEdit(heard: "cooper nettys", wrote: "Kubernetes", at: day(10))
        }
        #expect(learnt.isEmpty)
    }

    @Test("An ordinary word as the replacement is refused however often it recurs")
    func ordinaryReplacement() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        var learnt: [DictionaryEntry] = []
        for number in [10, 11, 12] {
            learnt += try await store.learnEdit(heard: "the end", wrote: "there", at: day(number))
        }
        #expect(learnt.isEmpty)
    }

    @Test("A replacement the user deleted before is refused")
    func refusedWord() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let added = try await store.add(DictionaryEntry(word: "Kubernetes", origin: .added, firstSeen: epoch))
        try await store.remove(added[0].id)
        var learnt: [DictionaryEntry] = []
        for number in [10, 11, 12] {
            learnt += try await store.learnEdit(heard: "cooper nettys", wrote: "Kubernetes", at: day(number))
        }
        #expect(learnt.isEmpty)
    }

    @Test("A rewrite longer than three words learns nothing")
    func rewrite() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        var learnt: [DictionaryEntry] = []
        for number in [10, 11, 12] {
            learnt += try await store.learnEdit(
                heard: "please send it over now", wrote: "Zorvik", at: day(number))
        }
        #expect(learnt.isEmpty)
    }

    @Test("Counts outlive a relaunch as keyed hashes, so the third sighting after a quit still learns")
    func survivesRelaunch() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "uttrflow-misheard-\(UUID().uuidString)")
        let encrypted = EncryptedStore(keys: Keys())
        func store() -> PersonalDictionaryStore {
            let ledger = EvidenceLedgerStore(
                file: folder.appending(path: "evidence.json"), encryptedStore: encrypted)
            let memory = SightingMemory(ledger: ledger, encryptedStore: encrypted) {
                RetentionWindow(days: RetentionWindow.keepAlwaysDays, now: $0)
            }
            return PersonalDictionaryStore(
                file: folder.appending(path: "dictionary.v1.json"), encryptedStore: encrypted,
                sightings: memory)
        }
        #expect(try await store().learnEdit(heard: "cooper nettys", wrote: "Kubernetes", at: day(10)).isEmpty)
        #expect(try await store().learnEdit(heard: "cooper nettys", wrote: "Kubernetes", at: day(11)).isEmpty)
        let learnt = try await store().learnEdit(heard: "cooper nettys", wrote: "Kubernetes", at: day(12))
        #expect(learnt.map(\.word) == ["Kubernetes"])
    }
}
