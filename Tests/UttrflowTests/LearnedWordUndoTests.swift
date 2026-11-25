// Tests that what a learnt word carries reaches the app, and that an undone one stays undone.

import Foundation
import UttrflowCore
import UttrflowDictionary
import Testing

@testable import Uttrflow

struct LearnedWordUndoTests {
    @Test("the app and the replaced text reach the learning callback")
    func passesTheContextOn() async throws {
        actor Recorder {
            private(set) var context: AppContext?
            func record(_ context: AppContext) { self.context = context }
        }
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))
        let recorder = Recorder()
        let vocabulary = LearnedVocabulary(dictionary: store) { _, context in
            await recorder.record(context)
        }

        try await vocabulary.learn(
            heard: "utter flow", wrote: "Uttrflow",
            seeing: AppContext(applicationName: "Notes", selectedText: "utter flow"))

        #expect(await recorder.context?.applicationName == "Notes")
        #expect(await recorder.context?.selectedText == "utter flow")
    }

    @Test("a word taken back with the Dictionary's delete is not learnt again")
    func anUndoneWordNeverReturns() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))
        let vocabulary = LearnedVocabulary(dictionary: store)
        let context = AppContext(applicationName: "Notes", selectedText: "utter flow")

        try await vocabulary.learn(heard: "utter flow", wrote: "Uttrflow", seeing: context)
        let learnt = try #require(await store.allEntries().first)
        try await store.remove([learnt.id])
        try await vocabulary.learn(heard: "utter flow", wrote: "Uttrflow", seeing: context)

        #expect(await store.allEntries().filter(\.isTrustworthy).isEmpty)
    }
}
