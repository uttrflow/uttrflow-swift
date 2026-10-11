// Tests that a learned word reaches the popover with no window open, and that its Undo refuses it.

import Foundation
import Testing
import UttrflowCore
import UttrflowDictionary
import UttrflowUX

@testable import Uttrflow

@MainActor
@Suite("Learned words in the menu bar", .serialized)
struct LearnedWordWiringTests {
    @Test("with no window open, a learned word is a popover row, and Undo refuses it for good")
    func undoRefusesTheWord() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(
            container: sandbox.root,
            clipboardSource: InMemoryClipboardSource(),
            account: HeldSession(signedIn: true).layer)
        app.drawsWindows = false
        let store = PersonalDictionaryStore(file: PersonalDictionaryStore.defaultFile(in: sandbox.root))
        let context = AppContext(selectedText: "utter flow")
        let learnt = try await store.learn(
            heard: "utter flow", wrote: "Uttrflow", seeing: context, at: .now)
        try #require(learnt.count == 1)

        app.noteLearned(learnt)

        #expect(app.menuBarPresentation.learned.map(\.word) == ["Uttrflow"])
        #expect(app.actionNotice == nil)

        app.carryOut(.undoLearnedWord(id: learnt[0].id))
        await app.intentWork?.value

        #expect(app.menuBarPresentation.learned.isEmpty)
        #expect(await store.allEntries().contains { $0.word == "Uttrflow" } == false)
        // Reopened, since the refusal is the app's store's write and this instance read its ledger before it.
        let reopened = PersonalDictionaryStore(file: PersonalDictionaryStore.defaultFile(in: sandbox.root))
        let again = try await reopened.learn(
            heard: "utter flow", wrote: "Uttrflow", seeing: context, at: .now)
        #expect(again.isEmpty)
    }
}
