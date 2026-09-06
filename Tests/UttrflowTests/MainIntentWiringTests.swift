// Tests that the main window's buttons reach the stores.

import Foundation
import UttrflowAI
import UttrflowCore
import UttrflowDictionary
import UttrflowHistory
import UttrflowUX
import Testing

@testable import Uttrflow

/// A folder of its own per test, with real files, because a substitute store proves only itself.
struct Sandbox: ~Copyable {
    let root: URL

    init() {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-wiring-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }
}

/// Polls until the change a button set going reaches disk; a fixed sleep is slow or flaky.
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

    /// The presenter refuses a blank word first; one reaching the store must cost the save, not the file.
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

    /// An edit must not reset what has been counted about a snippet.
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

    /// The window's list can be a snippet behind, so the editor reads back off the window, not the test.
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

    /// The words the page last drew can go stale while the editor is open; the store is asked again.
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

        // Still the learnt entry; replacing would reset the origin and count.
        let settled = await eventually(
            { await store.allEntries().first?.origin != .observed }, within: .milliseconds(300))
        #expect(!settled)
        #expect(await store.allEntries().count == 1)
        #expect(await store.allEntries().first?.timesUsed == 6)
    }

    /// `.addSnippet` opens the editor at once; `.editSnippet` reads the store first and must not win late.
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

        // Long enough for the disk read behind Edit to have finished.
        let filled = await eventually(
            { app.mainWindow?.snippetDraft.editing != nil }, within: .milliseconds(400))
        #expect(!filled)
        #expect(app.mainWindow?.snippetDraft == SnippetDraft())
    }

    /// `saveWord` closes the editor only once the word is in.
    @Test("a saved word closes the editor, and a refused one leaves it open")
    func closesTheEditorOnlyOnSuccess() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        app.mainWindow = app.makeMainWindow()

        app.carryOut(.addWord)
        // What typing into the field does; without it a closed editor looks like nothing happened.
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

    /// A refusal leaves the editor open holding what was typed.
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

    /// Undo reaches both stores, or the word is applied again tomorrow.
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

        // Undoing again counts nothing, because the history already put the words back.
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

/// The one place the two halves of the learning seam meet; a swap of `heard` and `wrote` would compile.
@Suite("Teaching the dictionary from a finished dictation")
struct LearnedVocabularyTests {
    /// The correction path end to end through the adapter.
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

    /// The argument order checked directly, because swapped it would learn the spelling the user deleted.
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

    /// Nothing on screen, nothing to learn from, and no write either.
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
