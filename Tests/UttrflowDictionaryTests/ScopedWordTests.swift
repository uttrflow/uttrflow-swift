// A word the person confined to chosen applications: offered there and nowhere else.

import Foundation
import Testing
import UttrflowCore

@testable import UttrflowDictionary

@Suite("A word confined to chosen applications")
struct ScopedWordTests {
    private static let editor = "com.example.Editor"

    private static func scoped(_ spelling: String) -> DictionaryEntry {
        DictionaryEntry(word: spelling, origin: .added, firstSeen: epoch, applications: [editor])
    }

    @Test("the index offers a scoped word only in its application; unscoped words everywhere")
    func indexOffersOnlyThere() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(Self.scoped("Zentrova"))
        try await store.add(word("Uttrflow", from: .added))

        #expect(
            await store.index(in: Self.editor).candidates(soundingLike: "zen trova").map(\.word) == [
                "Zentrova"
            ])
        #expect(await store.index(in: "com.example.Chat").candidates(soundingLike: "zen trova").isEmpty)
        #expect(await store.index(in: nil).candidates(soundingLike: "zen trova").isEmpty)
        #expect(await store.index(in: nil).candidates(soundingLike: "utter flow").map(\.word) == ["Uttrflow"])
        #expect(await store.index().candidates(soundingLike: "zen trova").map(\.word) == ["Zentrova"])
    }

    @Test("with no word confined, every application gets the whole index")
    func unscopedDictionaryIsTheWholeIndex() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        try await store.add(word("Uttrflow", from: .added))
        #expect(await store.index(in: "com.example.Chat") == store.index())
    }

    @Test("the recogniser's word list leaves out a word confined elsewhere")
    func workingSetLeavesOutOtherApplications() {
        let entries = [Self.scoped("Zentrova"), word("Uttrflow", from: .added)]
        let elsewhere = AppContext(bundleIdentifier: "com.example.Chat")
        let there = AppContext(bundleIdentifier: Self.editor)
        #expect(WorkingSet.words(from: entries, now: epoch, favouring: elsewhere) == ["Uttrflow"])
        #expect(
            Set(WorkingSet.words(from: entries, now: epoch, favouring: there)) == ["Zentrova", "Uttrflow"])
    }

    @Test("typing a word in the editor keeps its applications, and a respelling keeps the new ones")
    func editorKeepsApplications() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(file: sandbox.file)
        let added = try await store.add(
            word: "Zentrova", pronunciation: "", at: epoch, applications: [Self.editor])
        let id = try #require(added.first?.id)
        #expect(sandbox.onDisk()?.first?.applications == [Self.editor])
        let respelt = try await store.replace(
            id, word: "Zentrova", pronunciation: "zen trova", applications: [])
        #expect(respelt.first?.applications == [])
    }

    @Test("an entry from before scopes is offered everywhere, and an unscoped one writes no key")
    func oldEntryDecodesUnscoped() throws {
        let old = try rawDictionaryEntryJSON(word: "Zentrova", timesUsed: 1, timesReverted: 0)
        let entry = try JSONDecoder().decode(DictionaryEntry.self, from: old)
        #expect(entry.applications.isEmpty)
        #expect(entry.applies(in: "com.example.Chat"))
        #expect(!String(decoding: try JSONEncoder().encode(entry), as: UTF8.self).contains("applications"))
        let scoped = Self.scoped("Zentrova")
        #expect(try JSONDecoder().decode(DictionaryEntry.self, from: JSONEncoder().encode(scoped)) == scoped)
        #expect(scoped.inLatinScript.applications == [Self.editor])
    }
}
