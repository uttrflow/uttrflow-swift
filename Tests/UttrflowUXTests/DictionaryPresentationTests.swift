// Tests for the Dictionary page: rows, search, retirement, the empty page, and the inline editor.
import Foundation
import UttrflowCore
import UttrflowDictionary
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    /// One dictionary entry, added and in good standing by default.
    static func word(
        _ word: String = "Uttrflow",
        pronunciation: String? = "utter-flow",
        origin: WordOrigin = .added,
        daysAgo: Int = 3,
        used: Int = 4,
        reverted: Int = 0
    ) -> DictionaryEntry {
        DictionaryEntry(
            word: word, pronunciation: pronunciation, origin: origin,
            firstSeen: now.addingTimeInterval(Double(-daysAgo) * 86_400), timesUsed: used,
            timesReverted: reverted)
    }

    /// The Dictionary page over these inputs.
    static func dictionary(
        entries: [DictionaryEntry] = [], draft: DictionaryDraft? = nil, query: String = ""
    ) -> DictionaryPresentation {
        DictionaryPresenter.page(
            for: DictionarySnapshot(entries: entries, draft: draft, query: query, now: now),
            calendar: calendar, locale: locale)
    }
}

@Suite("The words Uttrflow knows")
struct DictionaryPageTests {
    @Test("every word is listed in the order the store keeps it")
    func lists() {
        let page = HistoryFixture.dictionary(entries: [
            HistoryFixture.word("Uttrflow"), HistoryFixture.word("pgvector"),
        ])
        #expect(page.rows.map(\.word) == ["Uttrflow", "pgvector"])
        #expect(page.caption == "2 words Uttrflow knows and a general model does not")
        #expect(page.chrome.title == "Dictionary")
    }

    @Test("a row says how it sounds, where it came from and how it has fared")
    func row() {
        let page = HistoryFixture.dictionary(entries: [
            HistoryFixture.word("Valkey", pronunciation: "val-key", origin: .learned, used: 22, reverted: 2)
        ])
        let row = page.rows[0]
        #expect(row.pronunciation == "val-key")
        #expect(row.origin == "Learned")
        #expect(row.timesUsed == "22")
        #expect(row.timesUndone == "2")
        #expect(!row.added.isEmpty)
    }

    /// An empty cell in a table reads as missing data rather than as "nothing to say".
    @Test("a word whose spelling is a fair guide gets an em dash")
    func noPronunciation() {
        let page = HistoryFixture.dictionary(entries: [
            HistoryFixture.word("Hinglish", pronunciation: nil)
        ])
        #expect(page.rows[0].pronunciation == "—")
    }

    /// "Observed" is the mechanism's name, and the mechanism is not the user's problem.
    @Test("each origin is written in the user's words")
    func origins() {
        #expect(DictionaryPresenter.title(for: .learned) == "Learned")
        #expect(DictionaryPresenter.title(for: .added) == "Added by you")
        #expect(DictionaryPresenter.title(for: .observed) == "Seen on screen")
        for origin in WordOrigin.allCases {
            #expect(!DictionaryPresenter.title(for: origin).isEmpty)
        }
    }

    /// Below the retirement threshold, so a word going wrong is seen while there is still a choice.
    @Test("an undo tally worth looking at is marked before the word retires")
    func concerning() {
        #expect(
            !HistoryFixture.dictionary(entries: [HistoryFixture.word(used: 40, reverted: 2)])
                .rows[0].undoneIsConcerning)
        #expect(
            HistoryFixture.dictionary(entries: [HistoryFixture.word(used: 40, reverted: 3)])
                .rows[0].undoneIsConcerning)
    }

    @Test("a word in good standing offers only to be deleted")
    func actions() {
        let entry = HistoryFixture.word()
        let row = HistoryFixture.dictionary(entries: [entry]).rows[0]
        #expect(row.actions.map(\.intent) == [.forgetWord(entry.id)])
        #expect(row.actions[0].isDestructive)
        #expect(row.id == entry.id)
    }

    /// The pronunciation is searchable because it is how the user thinks of a word they cannot spell.
    @Test("searching matches the spelling and how it sounds")
    func searching() {
        let entries = [
            HistoryFixture.word("asyncpg", pronunciation: "a-sync-p-g"),
            HistoryFixture.word("Nikhil", pronunciation: "nick-hill"),
        ]
        #expect(
            HistoryFixture.dictionary(entries: entries, query: "asyncpg").rows.map(\.word)
                == ["asyncpg"])
        // Found by how it sounds, which is nowhere in how it is spelt.
        #expect(
            HistoryFixture.dictionary(entries: entries, query: "nick-hill").rows.map(\.word)
                == ["Nikhil"])
        #expect(HistoryFixture.dictionary(entries: entries, query: " ").rows.count == 2)
    }

    /// A word heard with an accent must still be found when the user types it without one.
    @Test("searching ignores case and accents")
    func searchingIsForgiving() {
        let entries = [HistoryFixture.word("Café", pronunciation: nil)]
        #expect(HistoryFixture.dictionary(entries: entries, query: "cafe").rows.count == 1)
    }

    @Test("the search field appears only when there is something to search")
    func search() {
        #expect(HistoryFixture.dictionary().chrome.search == nil)
        #expect(HistoryFixture.dictionary(entries: [HistoryFixture.word()]).chrome.search != nil)
    }

    /// Adding is always offered, including from the empty page: a dictionary you cannot start is none.
    @Test("adding a word is always offered")
    func add() {
        #expect(HistoryFixture.dictionary().chrome.addAction?.intent == .addWord)
        #expect(
            HistoryFixture.dictionary(entries: [HistoryFixture.word()]).chrome.addAction?.intent
                == .addWord)
    }
}

@Suite("A word that retired itself")
struct DictionaryRetirementTests {
    /// Inverted from ``DictionaryEntry/isTrustworthy``, so the page cannot disagree with the recogniser.
    @Test("a word undone more often than it is kept is drawn as retired")
    func retired() {
        let row = HistoryFixture.dictionary(entries: [
            HistoryFixture.word("Zaprise", used: 10, reverted: 7)
        ]).rows[0]

        #expect(row.isRetired)
        #expect(row.badge?.text == "Retired")
        #expect(row.badge?.tone == .warning)
    }

    @Test("a word that has not earned its retirement is not drawn as retired")
    func notRetired() {
        let row = HistoryFixture.dictionary(entries: [
            HistoryFixture.word("Zaprise", used: 15, reverted: 7)
        ]).rows[0]
        #expect(!row.isRetired)
        #expect(row.badge == nil)
    }

    /// A way out that is harder to find than the problem is not a way out.
    @Test("a retired word offers to be restored")
    func restore() {
        let entry = HistoryFixture.word(used: 10, reverted: 7)
        let row = HistoryFixture.dictionary(entries: [entry]).rows[0]
        #expect(row.actions.map(\.title) == ["Restore", "Delete"])
        #expect(row.actions[0].intent == .restoreWord(entry.id))
        #expect(!row.actions[0].isDestructive)
    }

    /// Explaining a state nothing is in teaches the user to skip the small print.
    @Test("retirement is explained only when something has retired")
    func footnote() {
        #expect(
            HistoryFixture.dictionary(entries: [HistoryFixture.word()]).footnote?
                .contains("retires itself") == false)
        #expect(
            HistoryFixture.dictionary(entries: [HistoryFixture.word(used: 10, reverted: 7)])
                .footnote?.contains("retires itself") == true)
    }

    @Test("the footnote always says what the three origins mean")
    func origins() {
        let footnote = HistoryFixture.dictionary(entries: [HistoryFixture.word()]).footnote
        #expect(footnote?.contains("Learned means") == true)
        #expect(footnote?.contains("Seen on screen means") == true)
        #expect(footnote?.contains("Added by you means") == true)
    }

    /// Drives the real store like a dictation so every origin the page explains is one it can reach.
    @Test("every origin the page explains is one a dictation can actually produce")
    func everyOriginIsReachable() async throws {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "uttrflow-origins-\(UUID().uuidString)/dictionary.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = PersonalDictionaryStore(file: file)

        try await store.add(word: "kubectl", pronunciation: "", at: .now)
        try await store.learn(
            heard: "Uttrflow", wrote: "Uttrflow",
            seeing: AppContext(documentName: "notes", selectedText: "utter flow"), at: .now)
        // Three dictations, because a term seen on screen has to keep coming back.
        for _ in 1...3 {
            try await store.learn(
                heard: "try pgvector", wrote: "Try pgvector.",
                seeing: AppContext(documentName: "pgvector — notes"), at: .now)
        }

        let reached = Set(await store.allEntries().map(\.origin))
        #expect(reached == Set(WordOrigin.allCases))
        // And the page has a word for each of them.
        for origin in WordOrigin.allCases {
            #expect(!DictionaryPresenter.title(for: origin).isEmpty)
        }
    }
}

@Suite("A dictionary with nothing in it")
struct DictionaryEmptyTests {
    @Test("an empty dictionary explains what would fill it")
    func empty() {
        let page = HistoryFixture.dictionary()
        #expect(page.emptyState?.title == "No words of your own yet")
        #expect(page.emptyState?.action?.intent == .addWord)
        #expect(page.emptyState?.footnote?.contains("Nothing is pre-loaded") == true)
        #expect(page.footnote == nil)
    }

    @Test("a search that matched nothing says what it was looking for")
    func noMatches() {
        let empty = HistoryFixture.dictionary(
            entries: [HistoryFixture.word()], query: "invoice"
        ).emptyState
        #expect(empty?.title == "No matches")
        #expect(empty?.message.contains("“invoice”") == true)
    }
}

@Suite("Adding a word")
struct DictionaryEditorTests {
    @Test("there is no editor until one is asked for")
    func closed() {
        #expect(HistoryFixture.dictionary(entries: [HistoryFixture.word()]).editor == nil)
    }

    @Test("the editor asks for the spelling and how it sounds, and says which is which")
    func open() throws {
        let editor = try #require(
            HistoryFixture.dictionary(draft: DictionaryDraft()).editor)
        #expect(editor.wordLabel == "Write it as")
        #expect(editor.pronunciationLabel == "Say it like")
        #expect(editor.pronunciationHint.contains("Leave this blank"))
        #expect(editor.badge.text == "New")
        #expect(editor.cancel.intent == .cancelWordEdit)
    }

    /// The empty state invites the user to do the thing they are already doing, so it goes.
    @Test("an open editor replaces the empty state rather than sitting under it")
    func hidesTheEmptyState() {
        let page = HistoryFixture.dictionary(draft: DictionaryDraft(word: "Claude"))
        #expect(page.editor != nil)
        #expect(page.emptyState == nil)
    }

    @Test("a word with a spelling can be saved, and carries both fields with it")
    func saveable() throws {
        let editor = try #require(
            HistoryFixture.dictionary(
                draft: DictionaryDraft(word: "Uttrflow", pronunciation: "utter-flow")
            ).editor)
        #expect(editor.canSave)
        #expect(editor.problem == nil)
        #expect(editor.save.intent == .saveWord(word: "Uttrflow", pronunciation: "utter-flow"))
    }

    /// The second field is genuinely optional — most words are spelt as they sound.
    @Test("a word with no pronunciation is fine")
    func pronunciationIsOptional() throws {
        let editor = try #require(
            HistoryFixture.dictionary(draft: DictionaryDraft(word: "Uttrflow")).editor)
        #expect(editor.canSave)
    }

    @Test("a blank word says what is missing rather than only refusing")
    func blank() throws {
        let editor = try #require(
            HistoryFixture.dictionary(draft: DictionaryDraft(word: "   ")).editor)
        #expect(editor.problem == "A word needs a spelling.")
        #expect(!editor.canSave)
    }

    /// A re-add replaces the entry with its counters at zero, so refusing keeps what the app learned.
    @Test("a word already in the dictionary is refused rather than saved over the top")
    func duplicate() throws {
        let editor = try #require(
            HistoryFixture.dictionary(
                entries: [HistoryFixture.word("Uttrflow")],
                draft: DictionaryDraft(word: "uttrflow")
            ).editor)
        #expect(editor.problem == "“uttrflow” is already in your dictionary.")
        #expect(!editor.canSave)
    }

    /// The page refuses exactly what the store refuses: case only, so an accented twin is a new word.
    @Test("a word that differs only by an accent is a different word")
    func accentsAreNotDuplicates() throws {
        let editor = try #require(
            HistoryFixture.dictionary(
                entries: [HistoryFixture.word("Renee")],
                draft: DictionaryDraft(word: "Renée")
            ).editor)
        #expect(editor.canSave)
    }

    @Test("surrounding space does not make a duplicate look new")
    func duplicateIgnoringSpace() throws {
        let editor = try #require(
            HistoryFixture.dictionary(
                entries: [HistoryFixture.word("Uttrflow")],
                draft: DictionaryDraft(word: "  Uttrflow ")
            ).editor)
        #expect(!editor.canSave)
    }
}
