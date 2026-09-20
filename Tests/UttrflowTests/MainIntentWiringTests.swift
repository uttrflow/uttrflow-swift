// Tests that the main window's buttons reach the stores.

import Foundation
import Synchronization
import UttrflowAI
import UttrflowAccount
import UttrflowClipboard
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

        await app.intentWork?.value
        #expect(await store.allEntries().count == 1)
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

        await app.intentWork?.value
        #expect(await store.allEntries().isEmpty)
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

        await app.intentWork?.value
        #expect(await store.allEntries().first?.isTrustworthy == true)
    }

    /// The presenter refuses a blank word first; one reaching the store must cost the save, not the file.
    @Test("a blank word writes nothing at all")
    func refusesABlankWord() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = PersonalDictionaryStore(
            file: PersonalDictionaryStore.defaultFile(in: sandbox.root))

        app.carryOut(.saveWord(word: "   ", pronunciation: "utter-flow"))

        // The save has run to its end, so an empty store is a refusal rather than a write still on its way.
        await app.intentWork?.value
        #expect(await store.allEntries().isEmpty)
    }

    // MARK: Snippets

    @Test("saving a snippet keeps it")
    func savesASnippet() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let store = SnippetStore(file: SnippetStore.defaultFile(in: sandbox.root))

        app.carryOut(.saveSnippet(trigger: "my address", text: "Flat 402", replacing: nil))

        await app.intentWork?.value
        #expect(await store.snippets().count == 1)
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

        await app.intentWork?.value
        let edited = await store.snippets().first?.trigger == "my address"
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

        // Waited for rather than polled for: the read is off the disk, and a deadline is a guess.
        await app.openingEditor?.value

        #expect(app.mainWindow?.snippetDraft.editing == snippet.id)
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

        // Still the learnt entry once the save has finished; replacing would reset the origin and count.
        await app.intentWork?.value
        #expect(await store.allEntries().first?.origin == .observed)
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

        // The disk read behind Edit has finished, so it had its chance to win late.
        await app.openingEditor?.value
        #expect(app.mainWindow?.snippetDraft.editing == nil)
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
        await app.intentWork?.value
        #expect(await store.allEntries().count == 1)
        #expect(app.mainWindow?.wordDraft == DictionaryDraft())
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

        await app.intentWork?.value
        #expect(await store.allEntries().isEmpty)
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

        await app.intentWork?.value
        #expect(await store.snippets().isEmpty)
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

        await app.intentWork?.value
        #expect(await store.records(keeping: retention).isEmpty)
    }

    /// Deleting a dictation takes its clipboard copy, found by identifier once the texts have drifted apart.
    @Test("deleting a dictation deletes its clipboard copy after an undo and after a panel edit")
    func forgetsTheDictationsClip() async throws {
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root)
        let history = DictationHistoryStore(
            file: DictationHistoryStore.defaultFile(in: sandbox.root))
        let clipboard = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        let retention = Retention(days: 30, now: .now)
        let window = ClipRetention(days: 30, now: .now)
        let correction = try #require(
            RecordedCorrection(
                heard: "s q l", wrote: "SQL", wordRange: 1..<4, entryID: UUID(),
                reason: "heardAsStrayLetters", heardConfidence: 0.4))
        let undone = DictationRecord(
            text: "print SQL", when: .now,
            changes: RecordedChanges(corrections: [correction], snippets: []))
        let edited = DictationRecord(text: "Right, the drafting is done.", when: .now)
        try await history.append(undone, keeping: retention)
        try await history.append(edited, keeping: retention)
        for record in [undone, edited] {
            try await clipboard.record(
                Clip(
                    text: record.text, kind: .text, copiedAt: .now,
                    source: ClipOrigin.dictationSource, origin: .uttrflow,
                    dictations: [record.id]), keeping: window)
        }
        let editedClip = try #require(
            await clipboard.clips(keeping: window).first { $0.dictations == [edited.id] })
        try await clipboard.setText("Right, drafting done.", of: editedClip.id, keeping: window)
        app.carryOut(.undoCorrection(correction.id))
        await app.intentWork?.value
        let afterUndo = await history.records(keeping: retention).first { $0.id == undone.id }
        #expect(afterUndo?.text == "print s q l")

        app.carryOut(.forgetDictation(undone.id))
        await app.intentWork?.value
        app.carryOut(.forgetDictation(edited.id))
        await app.intentWork?.value

        #expect(await history.records(keeping: retention).isEmpty)
        // Read afresh, since each store keeps what it last read in memory.
        let reread = ClipboardStore(file: ClipboardStore.defaultFile(in: sandbox.root))
        #expect(await reread.clips(keeping: window).isEmpty)
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
        await app.intentWork?.value
        #expect(await store.records(keeping: retention).first?.isFlagged == true)

        app.carryOut(.flagDictation(record.id))
        await app.intentWork?.value
        #expect(await store.records(keeping: retention).first?.isFlagged == false)
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

        await app.intentWork?.value
        #expect(await dictionary.allEntries().first?.timesReverted == 1)

        // Undoing again counts nothing, because the history already put the words back.
        app.carryOut(.undoCorrection(correction.id))
        await app.intentWork?.value
        #expect(await dictionary.allEntries().first?.timesReverted == 1)
        let kept = try #require(await history.records(keeping: retention).first)
        #expect(kept.changes?.corrections.first?.isUndone == true)
        #expect(kept.text == "print s q l")
    }

    // MARK: The account

    @Test("signing out clears the profile before the server is told, and still tells it")
    func signOutClearsFirst() async throws {
        let signedIn = try await SignedInAccount()
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, account: signedIn.layer)

        app.carryOut(.signOut)

        #expect(signedIn.profiles.load() == nil)
        await app.intentWork?.value
        #expect(signedIn.authentication.signOuts == [.profileAlreadyCleared])
    }

    @Test("the Account page stops naming the account as soon as it signs out")
    func accountPageAfterSignOut() async throws {
        let signedIn = try await SignedInAccount()
        let sandbox = Sandbox()
        let app = AppDelegate(container: sandbox.root, account: signedIn.layer)
        app.readAccount()
        #expect(app.accountPage(at: .now).identity?.name == "Development User")

        app.carryOut(.signOut)

        let page = app.accountPage(at: .now)
        #expect(page.identity == nil)
        #expect(page.emptyState?.action?.intent == .signIn)
    }
}

// MARK: - A development account held in memory

/// Bytes in memory, so no profile reaches the test runner's defaults.
private final class MemoryStorage: SessionStorage {
    private let contents = Mutex<[String: Data]>([:])

    func data(forKey key: String) -> Data? { contents.withLock { $0[key] } }

    func set(_ data: Data?, forKey key: String) { contents.withLock { $0[key] = data } }
}

/// The in-memory backend, noting whether the profile was already gone each time it is told of a sign-out.
private final class RecordingAuthentication: AuthenticationService {
    /// What the profile cache held at one sign-out.
    enum SignOut: Equatable {
        case profileAlreadyCleared
        case profileStillThere
    }

    let backend = InMemoryAuthenticationService()
    private let recorded = Mutex<[SignOut]>([])
    /// Set once the cache exists, which is after the backend that signs for it.
    let profiles = Mutex<(any ProfileCache)?>(nil)

    var signOuts: [SignOut] { recorded.withLock { $0 } }

    func beginSignIn(with provider: SignInProvider) async throws(AccountError) -> SignInChallenge {
        try await backend.beginSignIn(with: provider)
    }

    func completeSignIn(_ challenge: SignInChallenge) async throws(AccountError) -> Profile {
        try await backend.completeSignIn(challenge)
    }

    func currentProfile(ifChangedFrom cached: Profile?) async throws(AccountError) -> ProfileRefresh {
        try await backend.currentProfile(ifChangedFrom: cached)
    }

    func avatar(at path: String) async -> Data? { await backend.avatar(at: path) }

    func signOut() async {
        let cleared = profiles.withLock { $0?.load() == nil }
        recorded.withLock { $0.append(cleared ? .profileAlreadyCleared : .profileStillThere) }
        await backend.signOut()
    }
}

/// A development account layer, signed in, with nothing on disk and nothing on the network.
private struct SignedInAccount {
    let authentication = RecordingAuthentication()
    let profiles: UserDefaultsProfileCache
    let layer: OnboardingAccountLayer

    init() async throws {
        profiles = UserDefaultsProfileCache(
            storage: MemoryStorage(), verifier: authentication.backend.verifier)
        layer = OnboardingAccountLayer(
            authentication: authentication, profiles: profiles,
            local: UserDefaultsLocalAccountStore(storage: MemoryStorage()))
        authentication.profiles.withLock { [profiles] in $0 = profiles }
        let challenge = try await authentication.beginSignIn(with: .google)
        try profiles.save(await authentication.completeSignIn(challenge))
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
