// Tests for vetoing a provisional word the user replaced by hand after it landed.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowDictionary

private let applied = EditAway.Applied(entryID: UUID(), word: "Uttrflwo")

@Suite("A learned word replaced by hand after it landed")
struct EditAwayTests {
    @Test("A word replaced with its neighbours kept is edited away")
    func replacementKeepsNeighbours() {
        #expect(
            EditAway.editedAway([applied], inserted: "ship Uttrflwo today.", fieldNow: "Ship Uttrflow today")
                == [applied.entryID])
    }

    @Test("A word at either end of the insertion counts with the one neighbour it has")
    func wordAtAnEdge() {
        #expect(
            EditAway.editedAway([applied], inserted: "Uttrflwo ships", fieldNow: "Uttrflow ships") == [
                applied.entryID
            ])
        #expect(
            EditAway.editedAway([applied], inserted: "ship Uttrflwo", fieldNow: "ship it") == [
                applied.entryID
            ])
    }

    @Test("A word still in the field, a cleared field or a rewritten one vetoes nothing")
    func nothingToVeto() {
        #expect(
            EditAway.editedAway([applied], inserted: "ship Uttrflwo today", fieldNow: "ship Uttrflwo, today")
                .isEmpty)
        #expect(EditAway.editedAway([applied], inserted: "ship Uttrflwo today", fieldNow: "").isEmpty)
        #expect(
            EditAway.editedAway([applied], inserted: "ship Uttrflwo today", fieldNow: "today ship").isEmpty)
        #expect(
            EditAway.editedAway([applied], inserted: "ship Uttrflwo today", fieldNow: "send it today").isEmpty
        )
        #expect(EditAway.editedAway([applied], inserted: "Uttrflwo", fieldNow: "Uttrflow").isEmpty)
        #expect(EditAway.editedAway([applied], inserted: "ship it today", fieldNow: "ship today").isEmpty)
        #expect(
            EditAway.editedAway(
                [EditAway.Applied(entryID: UUID(), word: "...")], inserted: "a ... b", fieldNow: "a b"
            ).isEmpty)
    }

    /// The acceptance replay: learned once from a misspelt edit, edited away once, then gone and refused.
    @Test("A misspelt learned word edited away once is removed and refused")
    func editedAwayIsGoneAndRefused() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let learnt = try await store.learn(
            heard: "Uttrflwo", wrote: "Uttrflwo",
            seeing: AppContext(applicationName: "Xcode", documentName: "notes", selectedText: "utter flow"),
            at: epoch)
        let entry = try #require(learnt.first)
        #expect(entry.isProvisional)

        let vetoed = EditAway.editedAway(
            [EditAway.Applied(entryID: entry.id, word: entry.word)],
            inserted: "ship Uttrflwo today", fieldNow: "ship Uttrflow today")
        for id in vetoed { try await store.recordRevert(of: id) }

        #expect(await store.allEntries().isEmpty)
        #expect(await store.refusedWords() == ["Uttrflwo"])
        #expect(
            try await store.learn(
                heard: "Uttrflwo", wrote: "Uttrflwo",
                seeing: AppContext(
                    applicationName: "Xcode", documentName: "notes", selectedText: "utter flow"),
                at: epoch.addingTimeInterval(86_400)
            ).isEmpty)
    }
}
