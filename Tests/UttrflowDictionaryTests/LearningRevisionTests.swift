// Tests that dictionary counts follow the revision that produced them.

import Foundation
import Testing

@testable import UttrflowDictionary

@Suite("Counts follow the revision that produced them")
struct LearningRevisionTests {
    private let revisionA = LearningRevision(recogniser: "model-a", prompt: "aaaaaa", lexicon: 1)
    private let revisionB = LearningRevision(recogniser: "model-b", prompt: "aaaaaa", lexicon: 1)

    @Test("opens under B with entries and refusals intact, counts restarted, and under A without loss")
    func roundTrip() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let kept = word("kubectl", saying: "cube control", from: .added, used: 9, reverted: 2)
        let doomed = word("zork", from: .learned, used: 1)
        try await store.add(kept)
        try await store.add(doomed)
        try await store.remove(doomed.id)
        #expect(try await store.settle(under: revisionA) == .unchanged)

        #expect(try await store.settle(under: revisionB) == .restarted(entries: 1))
        let underB = await store.allEntries()
        #expect(underB.map(\.word) == ["kubectl"])
        #expect(underB.first?.pronunciation == "cube control")
        #expect(underB.first?.timesUsed == 0)
        #expect(underB.first?.timesReverted == 0)
        #expect(await store.refusedWords() == ["zork"])

        // Counts earned under B stay with B when the older revision returns.
        for _ in 0..<4 { try await store.recordUse(of: kept.id) }
        #expect(try await store.settle(under: revisionA) == .restored(entries: 1))
        #expect(await store.allEntries().first?.timesUsed == 9)
        #expect(await store.allEntries().first?.timesReverted == 2)
        #expect(await store.refusedWords() == ["zork"])

        #expect(try await store.settle(under: revisionB) == .restored(entries: 1))
        #expect(await store.allEntries().first?.timesUsed == 4)
    }

    @Test("the same revision on a later launch changes nothing")
    func sameRevision() async throws {
        let sandbox = Sandbox()
        try await PersonalDictionaryStore(file: sandbox.file).add(word("kubectl", from: .added, used: 5))
        try await PersonalDictionaryStore(file: sandbox.file).settle(under: revisionA)
        let reopened = PersonalDictionaryStore(file: sandbox.file)
        #expect(try await reopened.settle(under: revisionA) == .unchanged)
        #expect(await reopened.allEntries().first?.timesUsed == 5)
    }

    @Test("a change in any one part of the revision counts as a change")
    func eachPart() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word("kubectl", from: .added, used: 5))
        try await store.settle(under: revisionA)
        let prompt = LearningRevision(recogniser: "model-a", prompt: "bbbbbb", lexicon: 1)
        let lexicon = LearningRevision(recogniser: "model-a", prompt: "aaaaaa", lexicon: 2)
        #expect(try await store.settle(under: prompt) == .restarted(entries: 1))
        #expect(try await store.settle(under: lexicon) == .restarted(entries: 1))
    }

    @Test("an unreadable record leaves the counts as they are")
    func unreadableRecord() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word("kubectl", from: .added, used: 5))
        try FileManager.default.createDirectory(at: sandbox.folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: await store.revisionRecord)
        await #expect(throws: (any Error).self) { try await store.settle(under: revisionB) }
        #expect(await store.allEntries().first?.timesUsed == 5)
    }
}
