import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import UttrflowUX
import Testing

@testable import Uttrflow

/// A folder of its own per test, removed with the test.
///
/// Real files rather than substitutes: what is being checked here is that a button
/// reaches the store at all, and a substitute store would prove only that the substitute
/// was called.
struct Sandbox: ~Copyable {
    let root: URL

    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-wiring-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

/// Waits for the change a button set going to reach disk.
///
/// Every store is an actor and every intent hands off to a `Task`, so the write has not
/// happened when `carryOut` returns. Polling rather than sleeping a fixed time: a fixed
/// sleep is either slower than it needs to be or flaky on a loaded machine, and this is
/// both fast when the write lands immediately and patient when it does not.
@MainActor
private func eventually(
    _ condition: () async -> Bool, within limit: Duration = .seconds(2)
) async -> Bool {
    let deadline = ContinuousClock.now + limit
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return await condition()
}

@MainActor
@Suite("What the buttons on the main window actually do")
struct MainIntentWiringTests {

    // MARK: The dictionary

    @Test("saving a word puts it in the dictionary")
    func savesAWord() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))

        app.carryOut(.saveWord(word: "Uttrflow", pronunciation: "utter-flow"))

        let saved = await eventually { await store.allEntries().count == 1 }
        #expect(saved)
        let kept = try #require(await store.allEntries().first)
        #expect(kept.word == "Uttrflow")
        #expect(kept.pronunciation == "utter-flow")
        #expect(kept.origin == .added)
    }

    @Test("deleting a word removes it")
    func forgetsAWord() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))
        let entry = DictionaryEntry(word: "Uttrflow", origin: .added, firstSeen: .now)
        try await store.add(entry)

        app.carryOut(.forgetWord(entry.id))

        let gone = await eventually { await store.allEntries().isEmpty }
        #expect(gone)
    }

    @Test("restoring a retired word lets it be applied again")
    func restoresAWord() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))
        let entry = DictionaryEntry(
            word: "Uttrflow", origin: .learned, firstSeen: .now, timesUsed: 4, timesReverted: 3)
        try await store.add(entry)
        #expect(await store.allEntries().first?.isTrustworthy == false)

        app.carryOut(.restoreWord(entry.id))

        let trusted = await eventually { await store.allEntries().first?.isTrustworthy == true }
        #expect(trusted)
    }

    /// The presenter refuses a blank word before the button is live. Reaching the store
    /// with one means the two disagree — and it must cost the save, not the file.
    @Test("a blank word writes nothing at all")
    func refusesABlankWord() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))

        app.carryOut(.saveWord(word: "   ", pronunciation: "utter-flow"))

        let wrote = await eventually({ !(await store.allEntries().isEmpty) }, within: .milliseconds(200))
        #expect(!wrote)
    }

    // MARK: Snippets

    @Test("saving a snippet keeps it")
    func savesASnippet() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = SnippetStore(file: SnippetStore.defaultFile(in: sandbox.root))

        app.carryOut(.saveSnippet(trigger: "my address", text: "Flat 402", replacing: nil))

        let saved = await eventually { await store.snippets().count == 1 }
        #expect(saved)
        #expect(await store.snippets().first?.trigger == "my address")
    }

    /// The whole reason the store grew a save-from-the-editor call: an edit must not
    /// reset what has been counted about a snippet.
    @Test("editing a snippet keeps what the user did not type")
    func editsASnippet() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = SnippetStore(file: SnippetStore.defaultFile(in: sandbox.root))
        let original = Snippet(
            trigger: "my adress", expansion: "Flat 402", created: .distantPast, timesUsed: 7)
        try await store.save(original)

        app.carryOut(
            .saveSnippet(trigger: "my address", text: "Flat 402", replacing: original.id))

        let edited = await eventually { await store.snippets().first?.trigger == "my address" }
        #expect(edited)
        let kept = try #require(await store.snippets().first)
        #expect(kept.id == original.id)
        #expect(kept.timesUsed == 7)
        #expect(kept.created == original.created)
    }

    /// The window's copy of the list is the last refresh and can be a snippet behind, so
    /// opening the editor from it would find nothing for a row just added.
    ///
    /// Read back off the window rather than by saving with an identity the test supplied
    /// — that earlier version passed with the whole `.editSnippet` case deleted, because
    /// the assertion only ever checked what the test had itself passed in.
    @Test("editing a snippet added since the last redraw opens the editor on that row")
    func editsASnippetTheWindowHasNotSeen() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        app.mainWindow = app.makeMainWindow()
        let store = SnippetStore(file: SnippetStore.defaultFile(in: sandbox.root))
        let snippet = Snippet(trigger: "my address", expansion: "Flat 402", created: .now)
        try await store.save(snippet)

        // No refresh in between, so the app has never seen this snippet.
        app.carryOut(.editSnippet(snippet.id))

        let opened = await eventually { app.mainWindow?.snippetDraft.editing == snippet.id }
        #expect(opened)
        #expect(app.mainWindow?.snippetDraft.trigger == "my address")
        #expect(app.mainWindow?.snippetDraft.text == "Flat 402")
    }

    /// The one decision made from a cached list: whether Save is enabled is decided from
    /// the words the page last drew. That list can now go stale *while the editor is
    /// open*, because a dictation finishing in another app teaches the dictionary. The
    /// store has the current answer and is asked again.
    @Test("a word learnt while the editor was open is not saved over")
    func doesNotOverwriteAWordLearntSinceTheEditorOpened() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        app.mainWindow = app.makeMainWindow()
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))

        app.carryOut(.addWord)
        // A dictation elsewhere teaches it, after the page was drawn.
        try await store.add(
            DictionaryEntry(word: "pgvector", origin: .observed, firstSeen: .now, timesUsed: 6))

        app.carryOut(.saveWord(word: "pgvector", pronunciation: ""))

        // Still the learnt entry, with everything known about it: replacing would have
        // reset the origin to `.added` and the count to zero, and `removeLearned()` would
        // then no longer remove it.
        let settled = await eventually(
            { await store.allEntries().first?.origin != .observed }, within: .milliseconds(300))
        #expect(!settled)
        #expect(await store.allEntries().count == 1)
        #expect(await store.allEntries().first?.timesUsed == 6)
    }

    /// `.addSnippet` opens the editor at once; `.editSnippet` has to read the store
    /// first. Clicking Edit and then New used to give a blank form that filled itself
    /// with the row's text a moment later — and because the draft carried `editing:`,
    /// Save then edited that row instead of creating a snippet.
    @Test("clicking New after Edit gives a new snippet, not the one being edited")
    func newSnippetWinsOverAnEditStillReadingTheDisk() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        app.mainWindow = app.makeMainWindow()
        let store = SnippetStore(file: SnippetStore.defaultFile(in: sandbox.root))
        let snippet = Snippet(trigger: "my address", expansion: "Flat 402", created: .now)
        try await store.save(snippet)

        app.carryOut(.editSnippet(snippet.id))
        app.carryOut(.addSnippet)

        // Long enough for the disk read behind the Edit to have finished and, unguarded,
        // to have written itself over the blank form.
        let filled = await eventually(
            { app.mainWindow?.snippetDraft.editing != nil }, within: .milliseconds(400))
        #expect(!filled)
        #expect(app.mainWindow?.snippetDraft == SnippetDraft())
    }

    /// `saveWord`'s own documentation makes closing-only-once-it-is-in its contract, and
    /// nothing checked it: removing the close from both success paths left every test
    /// passing.
    @Test("a saved word closes the editor, and a refused one leaves it open")
    func closesTheEditorOnlyOnSuccess() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        app.mainWindow = app.makeMainWindow()

        app.carryOut(.addWord)
        // What typing into the field does. Without it the draft is empty before the save
        // as well as after, and "the editor closed" is indistinguishable from "nothing
        // happened" — which is how the first version of this test passed with the close
        // removed.
        app.mainWindow?.editWord(DictionaryDraft(word: "Uttrflow", pronunciation: "utter-flow"))
        #expect(app.mainWindow?.wordDraft.word == "Uttrflow")

        app.carryOut(.saveWord(word: "Uttrflow", pronunciation: "utter-flow"))
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))
        let saved = await eventually { await store.allEntries().count == 1 }
        #expect(saved)
        let closed = await eventually { app.mainWindow?.wordDraft == DictionaryDraft() }
        #expect(closed)
    }

    /// The other half of the contract, and the reason a refusal is worth showing: the
    /// editor stays open holding what was typed rather than closing over a word that was
    /// never saved.
    @Test("a refused word leaves the editor open with the text still in it")
    func keepsTheEditorOpenOnRefusal() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        app.mainWindow = app.makeMainWindow()
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))

        app.carryOut(.addWord)
        app.mainWindow?.editWord(DictionaryDraft(word: "   "))
        app.carryOut(.saveWord(word: "   ", pronunciation: ""))

        let wrote = await eventually(
            { !(await store.allEntries().isEmpty) }, within: .milliseconds(300))
        #expect(!wrote)
        #expect(app.mainWindow?.wordDraft.word == "   ")
    }

    @Test("deleting a snippet removes it")
    func forgetsASnippet() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = SnippetStore(file: SnippetStore.defaultFile(in: sandbox.root))
        let snippet = Snippet(trigger: "my address", expansion: "Flat 402", created: .now)
        try await store.save(snippet)

        app.carryOut(.forgetSnippet(snippet.id))

        let gone = await eventually { await store.snippets().isEmpty }
        #expect(gone)
    }

    // MARK: The history

    @Test("deleting a dictation removes it")
    func forgetsADictation() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = DictationHistoryStore(
            file: DictationHistoryStore.defaultFile(in: sandbox.root))
        let retention = Retention(days: 30, now: .now)
        let record = DictationRecord(text: "Right, the drafting is done.", when: .now)
        try await store.append(record, keeping: retention)

        app.carryOut(.forgetDictation(record.id))

        let gone = await eventually { await store.records(keeping: retention).isEmpty }
        #expect(gone)
    }

    @Test("flagging a dictation is kept, and flagging it again puts it back")
    func flagsADictation() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = DictationHistoryStore(
            file: DictationHistoryStore.defaultFile(in: sandbox.root))
        let retention = Retention(days: 30, now: .now)
        let record = DictationRecord(text: "Right, the drafting is done.", when: .now)
        try await store.append(record, keeping: retention)

        app.carryOut(.flagDictation(record.id))
        let flagged = await eventually {
            await store.records(keeping: retention).first?.isFlagged == true
        }
        #expect(flagged)

        app.carryOut(.flagDictation(record.id))
        let unflagged = await eventually {
            await store.records(keeping: retention).first?.isFlagged == false
        }
        #expect(unflagged)
    }

    /// Undo has to reach *both* stores. Putting the words back without telling the
    /// dictionary its entry was wrong would leave the word to be applied again tomorrow,
    /// which is the whole mechanism by which a bad word retires itself.
    @Test("undoing a correction puts the words back and blames the entry that caused it")
    func undoesACorrection() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let history = DictationHistoryStore(
            file: DictationHistoryStore.defaultFile(in: sandbox.root))
        let dictionary = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))
        let retention = Retention(days: 30, now: .now)

        let entry = DictionaryEntry(word: "SQL", origin: .added, firstSeen: .now)
        try await dictionary.add(entry)
        let correction = try #require(
            RecordedCorrection(
                heard: "s q l", wrote: "SQL", wordRange: 1..<4, entryID: entry.id,
                reason: "heardAsStrayLetters", heardConfidence: 0.4))
        let record = DictationRecord(
            text: "print SQL", when: .now,
            changes: RecordedChanges(corrections: [correction], snippets: []))
        try await history.append(record, keeping: retention)

        app.carryOut(.undoCorrection(correction.id))

        let blamed = await eventually { await dictionary.allEntries().first?.timesReverted == 1 }
        #expect(blamed)

        // The order the comment in `carryOut` claims, made enforceable: undoing again
        // must count nothing, because the history has already put the words back and
        // says so. If the revert were counted first, a second click — or a stale row
        // still on screen — would retire a word that nothing had corrected.
        app.carryOut(.undoCorrection(correction.id))
        let settled = await eventually(
            { await dictionary.allEntries().first?.timesReverted != 1 },
            within: .milliseconds(300))
        #expect(!settled)
        let kept = try #require(await history.records(keeping: retention).first)
        #expect(kept.changes?.corrections.first?.isUndone == true)
        #expect(kept.text == "print s q l")
    }
}

/// The one place the two halves of the learning seam meet.
///
/// `UttrflowPipelineTests` proves the pipeline offers the raw transcript, the inserted text
/// and the screen reading; `UttrflowDictionaryTests` proves what the store does with them.
/// Neither target can see the other, so `LearnedVocabulary` is the only untested hop —
/// and a swap of `heard` and `wrote` in it would compile, and would teach the dictionary
/// exactly the words the user was getting rid of.
@Suite("Teaching the dictionary from a finished dictation")
struct LearnedVocabularyTests {
    /// The correction path, end to end through the adapter: the user selected the wrong
    /// spelling, said the word again, and the spelling they kept is learnt at once.
    @Test("a dictation over a selection that sounds the same teaches the new spelling")
    func learnsACorrection() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))

        try await LearnedVocabulary(dictionary: store).learn(
            heard: "utter flow", wrote: "Uttrflow",
            seeing: AppContext(applicationName: "Notes", selectedText: "utter flow"))

        let learnt = try #require(await store.allEntries().first)
        #expect(learnt.word == "Uttrflow")
        #expect(learnt.origin == .learned)
    }

    /// The argument order, checked directly, because it is the failure this whole test
    /// exists for: swapped, the adapter would learn "utter flow" — the spelling the user had
    /// just deleted — and every later dictation of "Uttrflow" would be corrected back to it.
    @Test("the words the user got rid of are never what is learnt")
    func doesNotLearnWhatWasReplaced() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))

        try await LearnedVocabulary(dictionary: store).learn(
            heard: "utter flow", wrote: "Uttrflow",
            seeing: AppContext(applicationName: "Notes", selectedText: "utter flow"))

        #expect(await store.allEntries().map(\.word) == ["Uttrflow"])
    }

    /// Nothing on screen, nothing to learn from — and no write either, because an empty
    /// dictionary file is a different thing from one that was never touched.
    @Test("a dictation with nothing on screen teaches nothing")
    func learnsNothingWithoutContext() async throws {
        let sandbox = Sandbox()
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))

        try await LearnedVocabulary(dictionary: store).learn(
            heard: "Uttrflow", wrote: "Uttrflow", seeing: .unknown)

        #expect(await store.allEntries().isEmpty)
    }
}
