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
        entries: [DictionaryEntry] = [], draft: DictionaryDraft? = nil, query: String = "",
        filter: String = "", sort: String = "", corrections: [Correction] = []
    ) -> DictionaryPresentation {
        DictionaryPresenter.page(
            for: DictionarySnapshot(
                entries: entries, draft: draft, query: query, filter: filter, sort: sort,
                corrections: corrections, now: now),
            calendar: calendar, locale: locale)
    }
}

@Suite("The words Uttrflow knows")
struct DictionaryPageTests {
    @Test("every word is listed, the newest first")
    func lists() {
        let page = HistoryFixture.dictionary(entries: [
            HistoryFixture.word("pgvector", daysAgo: 5), HistoryFixture.word("Uttrflow"),
        ])
        #expect(page.rows.map(\.word) == ["Uttrflow", "pgvector"])
        #expect(
            page.chrome.caption
                == "Names and terms Uttrflow would otherwise get wrong. · 2 words · 1 given to the recogniser"
        )
        #expect(page.chrome.title == "Dictionary")
    }

    @Test("the caption counts only words still applied")
    func captionExcludesRetiredWords() {
        let page = HistoryFixture.dictionary(entries: [
            HistoryFixture.word("Uttrflow"),
            HistoryFixture.word("Retired", used: 4, reverted: 3),
        ])
        #expect(
            page.chrome.caption
                == "Names and terms Uttrflow would otherwise get wrong. · 1 word · 1 given to the recogniser"
        )
    }

    @Test("each row says whether the recogniser is given it, and the caption counts those")
    func promptStanding() {
        let page = DictionaryPresenter.page(
            for: DictionarySnapshot(
                entries: [
                    // A day apart, so the newest-first list has no tie for identity to break.
                    HistoryFixture.word("Uttrflow", daysAgo: 1, used: 9),
                    HistoryFixture.word("pgvector", pronunciation: nil, daysAgo: 2, used: 2),
                    HistoryFixture.word("Retired", daysAgo: 3, used: 4, reverted: 3),
                ],
                now: HistoryFixture.now, packed: ["Uttrflow"]),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)
        #expect(page.rows.map(\.prompt.text) == ["In prompt · 1", "No room · 2", "Retired"])
        #expect(page.rows.map(\.prompt.isInPrompt) == [true, false, false])
        #expect(page.rows[1].prompt.spoken.contains("no room"))
        #expect(
            page.chrome.caption
                == "Names and terms Uttrflow would otherwise get wrong. · 2 words · 1 given to the recogniser"
        )
    }

    @Test("every standing has its own words")
    func promptChipWording() {
        let chips: [DictionaryPromptChip] = [
            .init(.inPrompt(rank: 1)), .init(.belowLimit(rank: 30, limit: 28)),
            .init(.sharesSound(with: "Nikhil")), .init(.retired), .init(.unusedInferred),
            .init(.tooLong(rank: 4)), .init(nil),
        ]
        #expect(Set(chips.map(\.text)).count == chips.count)
        #expect(Set(chips.map(\.spoken)).count == chips.count)
        #expect(chips[1].text == "Ranked 30 · top 28")
        #expect(chips[2].spoken.contains("Nikhil"))
    }

    @Test("a row says how it sounds, where it came from and how it has fared")
    func row() {
        let page = HistoryFixture.dictionary(entries: [
            HistoryFixture.word("Valkey", pronunciation: "val-key", origin: .learned, used: 22, reverted: 2)
        ])
        let row = page.rows[0]
        #expect(row.pronunciation == "val-key")
        #expect(row.origin == "Learned")
        #expect(row.source == .learned)
        #expect(row.hasBeenUndone)
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

    @Test("a word in good standing offers to be edited or deleted")
    func actions() {
        let entry = HistoryFixture.word()
        let row = HistoryFixture.dictionary(entries: [entry]).rows[0]
        #expect(row.actions.map(\.intent) == [.editWord(entry.id), .forgetWords([entry.id])])
        #expect(!row.actions[0].isDestructive)
        #expect(row.actions[1].isDestructive)
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

    /// Adding is always offered: from the empty page's own button, and from the title bar once there are words.
    @Test("adding a word is always offered")
    func add() {
        #expect(HistoryFixture.dictionary().chrome.addAction == nil)
        #expect(HistoryFixture.dictionary().emptyState?.action?.intent == .addWord)
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
            HistoryFixture.word("Kestrel", used: 10, reverted: 7)
        ]).rows[0]

        #expect(row.isRetired)
        #expect(row.source == .retired)
        #expect(row.source.title == "Retired")
    }

    @Test("a word that has not earned its retirement is not drawn as retired")
    func notRetired() {
        let row = HistoryFixture.dictionary(entries: [
            HistoryFixture.word("Kestrel", used: 15, reverted: 7)
        ]).rows[0]
        #expect(!row.isRetired)
        #expect(row.source == .added)
    }

    /// A way out that is harder to find than the problem is not a way out.
    @Test("a retired word offers to be restored")
    func restore() {
        let entry = HistoryFixture.word(used: 10, reverted: 7)
        let row = HistoryFixture.dictionary(entries: [entry]).rows[0]
        #expect(row.actions.map(\.title) == ["Restore", "Edit", "Delete"])
        #expect(row.actions[0].intent == .restoreWords([entry.id]))
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

    @Test("the footnote always says what the four origins mean")
    func origins() {
        let footnote = HistoryFixture.dictionary(entries: [HistoryFixture.word()]).footnote
        #expect(footnote?.contains("Learned means") == true)
        #expect(footnote?.contains("Seen on screen means") == true)
        #expect(footnote?.contains("Added by you means") == true)
        #expect(footnote?.contains("Shipped with Uttrflow means") == true)
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
        // Three days, because a term seen on screen has to keep coming back.
        for day in 1...3 {
            try await store.learn(
                heard: "try pgvector", wrote: "Try pgvector.",
                seeing: AppContext(documentName: "pgvector — notes"),
                at: .now.addingTimeInterval(Double(day) * 86_400))
        }

        let reached = Set(await store.allEntries().map(\.origin))
        #expect(
            reached == Set(WordOrigin.allCases).subtracting([.shipped]),
            "a dictation produces every origin but the shipped one")

        // The shipped origin is the install's rather than a dictation's, so a fresh dictionary reaches it.
        let fresh = PersonalDictionaryStore(
            file: file.deletingLastPathComponent().appending(path: "fresh.json"))
        try await fresh.seedShippedWords(at: .now)
        #expect(await fresh.allEntries().map(\.origin) == [.shipped])

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
        #expect(page.emptyState?.title == "Your dictionary is empty")
        #expect(page.emptyState?.action?.intent == .addWord)
        #expect(page.emptyState?.action?.title == "Add Word")
        #expect(page.emptyState?.message == "Add names and terms Uttrflow would otherwise get wrong.")
        #expect(page.emptyState?.footnote == nil)
        #expect(page.footnote == nil)
    }

    @Test("offers a word when the last dictionary entry is deleted during search")
    func emptyDuringSearch() {
        let page = HistoryFixture.dictionary(query: "anything")
        #expect(page.emptyState?.title == "Your dictionary is empty")
        #expect(page.emptyState?.action?.intent == .addWord)
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
        #expect(editor.problem == nil)
        #expect(!editor.canSave)
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

    @Test("the editor refuses DBMS with four pronunciation words and says the limit")
    func fourWordPronunciation() throws {
        let editor = try #require(
            HistoryFixture.dictionary(
                draft: DictionaryDraft(word: "DBMS", pronunciation: "dee bee em ess")
            ).editor)
        #expect(editor.problem == "The spelling and pronunciation can each have at most 3 words.")
        #expect(!editor.canSave)
    }

    @Test("the editor refuses a four-word spelling even with a short pronunciation")
    func fourWordSpelling() throws {
        let editor = try #require(
            HistoryFixture.dictionary(
                draft: DictionaryDraft(word: "Bank of New Zealand", pronunciation: "bank")
            ).editor)
        #expect(editor.problem == "The spelling and pronunciation can each have at most 3 words.")
        #expect(!editor.canSave)
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

    @Test("editing a word does not refuse its own spelling, and saves over it keeping its identity")
    func editingKeepsIdentity() throws {
        let held = HistoryFixture.word("Uttrflow", pronunciation: nil, origin: .learned)
        let editor = try #require(
            HistoryFixture.dictionary(
                entries: [held],
                draft: DictionaryDraft(editing: held.id, word: "Uttrflow", pronunciation: "utter flow")
            ).editor)
        #expect(editor.problem == nil)
        #expect(editor.canSave)
        #expect(editor.badge.text == "Editing")
        #expect(editor.replace == nil)
        #expect(
            editor.save.intent == .replaceWord(held.id, word: "Uttrflow", pronunciation: "utter flow"))
    }

    @Test("editing a word into another held word's spelling is still refused")
    func editingIntoAnotherWord() throws {
        let edited = HistoryFixture.word("Nikhil", pronunciation: nil)
        let other = HistoryFixture.word("Uttrflow", pronunciation: nil)
        let editor = try #require(
            HistoryFixture.dictionary(
                entries: [edited, other], draft: DictionaryDraft(editing: edited.id, word: "uttrflow")
            ).editor)
        #expect(editor.problem == "“uttrflow” is already in your dictionary.")
        #expect(!editor.canSave)
    }

    @Test("a respelling of a held word names it and offers to replace it")
    func closedUpDuplicate() throws {
        let held = HistoryFixture.word("OpenAI", pronunciation: nil)
        let editor = try #require(
            HistoryFixture.dictionary(entries: [held], draft: DictionaryDraft(word: "Open AI")).editor)
        let named = "\u{2018}Open AI\u{2019} is already in your dictionary as \u{2018}OpenAI\u{2019}."
        #expect(editor.problem == named)
        #expect(!editor.canSave)
        #expect(editor.replace?.intent == .replaceWord(held.id, word: "Open AI", pronunciation: ""))
    }

    @Test("two spellings of one word are flagged as sounding alike and offered a merge")
    func respellingsAreMergeable() {
        let joined = HistoryFixture.word("OpenAI", pronunciation: nil, daysAgo: 1)
        let spaced = HistoryFixture.word("Open AI", pronunciation: nil, daysAgo: 2)
        let rows = HistoryFixture.dictionary(entries: [joined, spaced]).rows
        #expect(rows.map(\.soundsLike) == [sounds("Open AI"), sounds("OpenAI")])
        let merge = MainIntent.mergeWords(keeping: joined.id, absorbing: spaced.id)
        #expect(rows[0].actions.first?.intent == merge)
    }

    @Test("different words that share a sound are flagged without a merge")
    func soundAlikesAreNotMerged() {
        let british = HistoryFixture.word("Colour", pronunciation: nil, daysAgo: 1)
        let american = HistoryFixture.word("Color", pronunciation: nil, daysAgo: 2)
        let rows = HistoryFixture.dictionary(entries: [british, american]).rows
        #expect(rows.map(\.soundsLike) == [sounds("Color"), sounds("Colour")])
        let titles = rows.flatMap { $0.actions.map(\.title) }
        #expect(!titles.contains("Keep this spelling"))
    }

    /// The chip a row wears when another entry competes for its sound.
    private func sounds(_ word: String) -> String {
        "Sounds like \u{2018}\(word)\u{2019}"
    }

    /// The page refuses exactly what the store refuses: case, spaces and punctuation, so an accented twin is a new word.
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

@Suite("The dictionary's filter chips")
struct DictionaryFilterTests {
    static let words = [
        HistoryFixture.word("Uttrflow", origin: .added),
        HistoryFixture.word("Valkey", origin: .learned),
        HistoryFixture.word("Kestrel", origin: .observed),
        HistoryFixture.word("Spindle", origin: .shipped),
        HistoryFixture.word("Anand", origin: .learned, used: 10, reverted: 7),
    ]

    @Test("every source a chip names lists only its own words")
    func filters() {
        let chosen = { (id: String) in
            HistoryFixture.dictionary(entries: Self.words, filter: id).rows.map(\.word)
        }
        #expect(chosen("added") == ["Uttrflow"])
        #expect(chosen("learned") == ["Valkey"])
        #expect(chosen("seen") == ["Kestrel"])
        #expect(chosen("retired") == ["Anand"])
    }

    @Test("All, an empty choice and an unknown one list every word")
    func all() {
        for id in ["", "all", "shipped", "nonsense"] {
            #expect(HistoryFixture.dictionary(entries: Self.words, filter: id).rows.count == 5)
        }
    }

    @Test("the chips run All then the four sources, with the chosen one selected")
    func chips() {
        let chips = HistoryFixture.dictionary(entries: Self.words, filter: "learned").filters
        #expect(chips.map(\.title) == ["All", "Added by you", "Learned", "Seen on screen", "Retired"])
        #expect(chips.filter(\.isSelected).map(\.id) == ["learned"])
        #expect(HistoryFixture.dictionary(entries: Self.words).filters.first?.isSelected == true)
    }

    @Test("there are no chips while there are no words")
    func noChips() {
        #expect(HistoryFixture.dictionary().filters.isEmpty)
        #expect(HistoryFixture.dictionary().chrome.caption == nil)
        let editing = DictionaryPresenter.page(for: DictionarySnapshot(draft: DictionaryDraft(), now: .now))
        #expect(editing.chrome.caption == "Names and terms Uttrflow would otherwise get wrong.")
    }

    @Test("a chip with nothing under it says so and keeps the page")
    func emptyChip() {
        let page = HistoryFixture.dictionary(entries: [HistoryFixture.word()], filter: "retired")
        #expect(page.rows.isEmpty)
        #expect(page.emptyState?.title == "Nothing in this view")
        #expect(page.emptyState?.message.contains("retired") == true)
        #expect(page.filters.count == 5)
    }

    @Test("each source has a name, and an entry takes the one its origin gives")
    func sources() {
        for source in DictionarySource.allCases { #expect(!source.title.isEmpty) }
        #expect(Self.words.map { DictionarySource($0) } == [.added, .learned, .seen, .shipped, .retired])
    }
}

@Suite("Today's fixes on the dictionary page")
struct DictionaryFixesTests {
    @Test("today's standing corrections are cards, newest first, three at most")
    func cards() {
        let corrections = [
            HistoryFixture.correction(heard: "a", wrote: "A", minutesAgo: 40),
            HistoryFixture.correction(heard: "b", wrote: "B", minutesAgo: 10),
            HistoryFixture.correction(heard: "c", wrote: "C", minutesAgo: 30),
            HistoryFixture.correction(heard: "d", wrote: "D", minutesAgo: 20),
        ]
        let page = HistoryFixture.dictionary(entries: [HistoryFixture.word()], corrections: corrections)
        #expect(page.fixes.map(\.wrote) == ["B", "D", "C"])
        #expect(page.fixesLabel == "Fixed today · 4 corrections")
        #expect(page.fixes[0].undo?.intent == .undoCorrection(corrections[1].id))
    }

    @Test("an undone correction and one from another day are not today's fixes")
    func onlyToday() {
        let page = HistoryFixture.dictionary(
            entries: [HistoryFixture.word()],
            corrections: [
                HistoryFixture.correction(isUndone: true),
                HistoryFixture.correction(daysAgo: 2),
            ])
        #expect(page.fixes.isEmpty)
        #expect(page.fixesLabel == nil)
    }

    @Test("one fix is counted in the singular")
    func singular() {
        let page = HistoryFixture.dictionary(
            entries: [HistoryFixture.word()], corrections: [HistoryFixture.correction()])
        #expect(page.fixesLabel == "Fixed today · 1 correction")
    }
}

@Suite("What the pronunciation will do")
struct PronunciationNoteTests {
    private func editor(_ word: String, _ said: String) throws -> DictionaryEditor {
        try #require(
            HistoryFixture.dictionary(draft: DictionaryDraft(word: word, pronunciation: said)).editor)
    }

    @Test(
        "the spelling again adds nothing, and says so",
        arguments: [
            ("PayPal", "pay pal"), ("Uttrflow", "uttrflow"), ("iOS", "i o s"),
            ("Kubectl", "kubectl"), ("GitHub", "git-hub"), ("Zorvex", "ZORVEX"),
        ])
    func addsNothing(word: String, said: String) throws {
        let editor = try editor(word, said)
        #expect(editor.pronunciationNote == "This is the spelling again, so it adds nothing. Leave it blank.")
        #expect(editor.canSave)
    }

    @Test(
        "one ordinary word is noted as a word every doubt about it will offer",
        arguments: ["time", "people", "year", "look", "good", "work"])
    func ordinaryWord(said: String) throws {
        let editor = try editor("Zorvex", said)
        #expect(
            editor.pronunciationNote
                == "Uttrflow will offer \u{201C}Zorvex\u{201D} whenever it doubts \u{201C}\(said)\u{201D}; the screen or your own earlier words must back it."
        )
        #expect(editor.canSave)
    }

    @Test(
        "one function word is refused, since swapping it changes the meaning",
        arguments: ["the", "and", "of", "is", "would", "because"])
    func functionWord(said: String) throws {
        let editor = try editor("Zorvex", said)
        #expect(
            editor.problem
                == "\u{201C}\(said)\u{201D} is too common a small word to stand for \u{201C}Zorvex\u{201D}; swapping it would change what was said."
        )
        #expect(editor.pronunciationNote == nil)
        #expect(!editor.canSave)
    }

    @Test(
        "digits or symbols are noted as matched as written",
        arguments: ["r2d2", "c#", "k8s", "dot.net", "x+y", "zor_vex"])
    func literal(said: String) throws {
        let editor = try editor("Zorvex", said)
        #expect(
            editor.pronunciationNote
                == "Digits and symbols have no sound to match, so this is matched as written.")
        #expect(editor.canSave)
    }

    @Test(
        "a blank or a sounded-out phrase gets no note",
        arguments: [
            ("Kubectl", "cube control"), ("Uttrflow", "utter-flow"), ("Zorvex", ""),
            ("Nikhil", "nikkel"), ("Zorvex", "zore vecks"), ("Zorvex", "   "),
        ])
    func silent(word: String, said: String) throws {
        let editor = try editor(word, said)
        #expect(editor.pronunciationNote == nil)
        #expect(editor.problem == nil)
    }
}

@Suite("The words Uttrflow will not learn")
struct DictionaryNotLearningTests {
    /// The page the store's refusals draw, through the presenter as the app calls it.
    private func page(entries: [DictionaryEntry] = [], refused: [String]) -> DictionaryPresentation {
        DictionaryPresenter.page(
            for: DictionarySnapshot(entries: entries, now: HistoryFixture.now, refused: refused),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)
    }

    @Test("lists each refused spelling in the store's order, each with Allow again")
    func listsRefusals() throws {
        let section = try #require(page(refused: ["pgvector", "Docker"]).notLearning)
        #expect(section.title == "Not learning · 2 words")
        #expect(section.rows.map(\.word) == ["pgvector", "Docker"])
        #expect(section.rows.map(\.allow.intent) == [.allowWord("pgvector"), .allowWord("Docker")])
        #expect(section.rows.allSatisfy { $0.allow.title == "Allow again" })
        #expect(section.note.contains("\(PersonalDictionaryStore.maximumRefusedWords)"))
    }

    @Test("draws no disclosure when nothing is refused")
    func absentWhenNothingIsRefused() {
        #expect(page(entries: [HistoryFixture.word()], refused: []).notLearning == nil)
    }
}

@Suite("Trying a dictionary word from the page")
struct DictionaryTrialTests {
    private func page(
        entries: [DictionaryEntry] = [], draft: DictionaryDraft? = nil, trial: DictionaryTrial?
    ) -> DictionaryPresentation {
        DictionaryPresenter.page(
            for: DictionarySnapshot(entries: entries, draft: draft, now: HistoryFixture.now, trial: trial),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)
    }

    @Test("every row offers Try it, and only the tried row shows the result")
    func rowsOfferTryIt() throws {
        let tried = HistoryFixture.word("Quillon")
        let other = HistoryFixture.word("Nikkel", daysAgo: 5)
        let rows = page(
            entries: [tried, other],
            trial: DictionaryTrial(
                subject: .word(tried.id), phase: .result(line: "Recognised from the start", offer: nil))
        ).rows
        #expect(rows.allSatisfy { $0.tryIt?.title == "Try it" })
        #expect(rows.first { $0.id == tried.id }?.tryIt?.intent == .tryWord(tried.id))
        let line = try #require(rows.first { $0.id == tried.id }?.trial)
        #expect(line == DictionaryTrialLine(text: "Recognised from the start", isBusy: false, offer: nil))
        #expect(rows.first { $0.id == other.id }?.trial == nil)
    }

    @Test("the editor offers Try it once there is a spelling, carrying what is typed")
    func editorOffersTryIt() {
        #expect(page(draft: DictionaryDraft(), trial: nil).editor?.tryIt == nil)
        let editor = page(draft: DictionaryDraft(word: "Quillon", pronunciation: "quill on"), trial: nil)
            .editor
        #expect(editor?.tryIt?.intent == .tryDraft(word: "Quillon", pronunciation: "quill on"))
        #expect(editor?.trial == nil)
    }

    @Test("a running try says so, and a draft's try does not show on a row")
    func busy() {
        let word = HistoryFixture.word("Quillon")
        let listening = page(
            entries: [word], draft: DictionaryDraft(word: "Quillon"),
            trial: DictionaryTrial(subject: .draft, phase: .listening))
        #expect(listening.editor?.trial?.isBusy == true)
        #expect(listening.rows.allSatisfy { $0.trial == nil })
        let checking = page(
            draft: DictionaryDraft(word: "Quillon"), trial: DictionaryTrial(subject: .draft, phase: .checking)
        )
        #expect(checking.editor?.trial?.isBusy == true)
        let failed = page(
            draft: DictionaryDraft(word: "Quillon"),
            trial: DictionaryTrial(subject: .draft, phase: .failed("No microphone")))
        #expect(failed.editor?.trial == DictionaryTrialLine(text: "No microphone", isBusy: false, offer: nil))
    }

    @Test("a miss offers Say it like, for the editor or for the tried word")
    func missOffersSayItLike() {
        let miss = DictionaryTrial.Phase.result(line: "Heard as “nikkel”", offer: "nikkel")
        let editor = page(
            draft: DictionaryDraft(word: "Nickel"), trial: DictionaryTrial(subject: .draft, phase: miss))
        #expect(editor.editor?.trial?.offer?.title == "Say it like ‘nikkel’")
        #expect(editor.editor?.trial?.offer?.intent == .useSayItLike(nil, heard: "nikkel"))
        let word = HistoryFixture.word("Nickel")
        let row = page(entries: [word], trial: DictionaryTrial(subject: .word(word.id), phase: miss)).rows
            .first
        #expect(row?.trial?.offer?.intent == .useSayItLike(word.id, heard: "nikkel"))
    }

    @Test("taking the offer adds the heard words after any already typed")
    func offering() {
        #expect(
            DictionaryPresenter.offering("nikkel", to: DictionaryDraft(word: "Nickel")).pronunciation
                == "nikkel")
        let both = DictionaryPresenter.offering(
            "nikkel", to: DictionaryDraft(word: "Nickel", pronunciation: "nick el"))
        #expect(DictionaryEntry.pronunciations(inField: both.pronunciation) == ["nick el", "nikkel"])
        #expect(both.word == "Nickel")
    }
}
