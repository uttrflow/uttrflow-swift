// Tests for the Snippets page: rows, search, the inline editor, and the empty page.
import Foundation
import UttrflowCore
import UttrflowDictionary
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    /// One snippet, used a dozen times, last used today by default.
    static func snippet(
        _ trigger: String = "my address",
        text: String = "Flat 402, Example Residences, Bengaluru",
        used: Int = 12,
        lastUsedDaysAgo: Int? = 0,
        createdDaysAgo: Int = 10
    ) -> Snippet {
        Snippet(
            trigger: trigger, expansion: text,
            created: now.addingTimeInterval(Double(-createdDaysAgo) * 86_400),
            timesUsed: used,
            lastUsed: lastUsedDaysAgo.map { now.addingTimeInterval(Double(-$0) * 86_400) })
    }

    /// The Snippets page over these inputs.
    static func snippets(
        _ snippets: [Snippet] = [], draft: SnippetDraft? = nil, query: String = "", sort: String = "",
        arrival: SnippetArrival? = nil
    ) -> SnippetsPresentation {
        SnippetsPresenter.page(
            for: SnippetsSnapshot(
                snippets: snippets, draft: draft, query: query, sort: sort, now: now, arrival: arrival),
            calendar: calendar, locale: locale)
    }
}

@Suite("Snippets: a phrase you say for a block of text")
struct SnippetsPageTests {
    @Test("every snippet is listed, the newest first")
    func lists() {
        let page = HistoryFixture.snippets([
            HistoryFixture.snippet("sign off", used: 64, createdDaysAgo: 20),
            HistoryFixture.snippet("my address"),
        ])
        #expect(page.rows.map(\.trigger.text) == ["my address", "sign off"])
        #expect(page.chrome.caption == "Say a short phrase; Uttrflow types the whole thing. · 2 snippets")
        #expect(page.chrome.title == "Snippets")
        #expect(page.emptyState == nil)
    }

    @Test("a stored snippet whose trigger says a spoken command is listed with a warning")
    func collidingRowWarns() {
        let page = HistoryFixture.snippets([
            HistoryFixture.snippet("new line please", createdDaysAgo: 20),
            HistoryFixture.snippet("my address"),
        ])
        let warnings = Dictionary(uniqueKeysWithValues: page.rows.map { ($0.trigger.text, $0.warning) })
        #expect(
            warnings["new line please"]
                == "Says the spoken command “new line”, so the command runs and this snippet never does.")
        #expect(warnings["my address"] == .some(nil))
    }

    @Test("a row says what it types, how often and when it last did")
    func row() {
        let snippet = HistoryFixture.snippet(used: 48, lastUsedDaysAgo: 0)
        let row = HistoryFixture.snippets([snippet]).rows[0]
        #expect(row.text == snippet.expansion)
        #expect(row.timesUsed == "48")
        #expect(row.lastUsed == "Today")
        #expect(row.trigger.tone == .accent)
        #expect(row.id == snippet.id)
        #expect(row.actions.map(\.intent) == [.editSnippet(snippet.id), .forgetSnippet(snippet.id)])
    }

    /// A snippet nobody has used is worth spotting, so it says so rather than leaving the cell blank.
    @Test("a snippet that has never fired says never")
    func neverUsed() {
        let row = HistoryFixture.snippets([HistoryFixture.snippet(lastUsedDaysAgo: nil)]).rows[0]
        #expect(row.lastUsed == "Never")
    }

    /// Spoken triggers arrive with any spacing, so comparing them raw would make one snippet look like two.
    @Test("a trigger is matched on its words, not its spacing")
    func matchKey() {
        #expect(
            Snippet(trigger: "  My   Address ", expansion: "x", created: .distantPast)
                .triggerWords == ["my", "address"],
            "spacing and case are the user's, the words are the trigger")
    }

    @Test("searching matches the trigger and what it types")
    func searching() {
        let snippets = [
            HistoryFixture.snippet("my address", text: "Flat 402, Bengaluru"),
            HistoryFixture.snippet("sign off", text: "Thanks, Avery"),
        ]
        #expect(HistoryFixture.snippets(snippets, query: "address").rows.count == 1)
        #expect(HistoryFixture.snippets(snippets, query: "Avery").rows.count == 1)
        #expect(HistoryFixture.snippets(snippets, query: "  ").rows.count == 2)
    }

    @Test("the search field appears only when there is something to search")
    func search() {
        #expect(HistoryFixture.snippets().chrome.search == nil)
        #expect(HistoryFixture.snippets([HistoryFixture.snippet()]).chrome.search != nil)
    }

    @Test("a new snippet can always be started, from the empty page's own button when there are none")
    func add() {
        #expect(HistoryFixture.snippets().chrome.addAction == nil)
        #expect(HistoryFixture.snippets().emptyState?.action?.intent == .addSnippet)
        #expect(HistoryFixture.snippets([HistoryFixture.snippet()]).chrome.addAction?.intent == .addSnippet)
    }

    @Test("the footnote explains how a trigger is matched")
    func footnote() {
        #expect(
            HistoryFixture.snippets([HistoryFixture.snippet()]).footnote?
                .contains("matched on what you said") == true)
        #expect(HistoryFixture.snippets().footnote == nil)
    }
}

@Suite("Writing a snippet")
struct SnippetsEditorTests {
    @Test("a new snippet opens an empty editor")
    func newSnippet() {
        let page = HistoryFixture.snippets([], draft: SnippetDraft())
        #expect(page.editor?.problem == nil)
        #expect(page.editor?.canSave == false)
        #expect(page.editor?.editing == nil)
        #expect(page.editor?.badge.text == "New")
        #expect(page.editor?.title == "New snippet")
        #expect(page.editor?.triggerLabel == "When I say")
        #expect(page.editor?.textLabel == "Type this")
        #expect(page.editor?.cancel.intent == .cancelSnippetEdit)
    }

    @Test("editing an existing snippet says so")
    func editing() {
        let snippet = HistoryFixture.snippet()
        let page = HistoryFixture.snippets(
            [snippet],
            draft: SnippetDraft(editing: snippet.id, trigger: snippet.trigger, text: "New text"))

        #expect(page.editor?.badge.text == "Editing")
        #expect(page.editor?.title == "Edit snippet")
        #expect(page.editor?.canSave == true)
        #expect(
            page.editor?.save.intent
                == .saveSnippet(
                    trigger: snippet.trigger, text: "New text", applications: [], replacing: snippet.id))
    }

    @Test("a snippet needs both halves before it can be saved")
    func bothHalves() {
        #expect(
            HistoryFixture.snippets([], draft: SnippetDraft(trigger: " ", text: "x")).editor?
                .problem == "A snippet needs something to say.")
        #expect(
            HistoryFixture.snippets([], draft: SnippetDraft(trigger: "x", text: " ")).editor?
                .problem == "A snippet needs something to type.")
    }

    /// Two snippets answering to one phrase means one silently never fires, with no way to tell which.
    @Test("a trigger somebody already has is refused before it is saved")
    func duplicate() {
        let existing = HistoryFixture.snippet("my address")
        let editor = HistoryFixture.snippets(
            [existing], draft: SnippetDraft(trigger: "My  Address", text: "Somewhere else")
        ).editor

        #expect(editor?.canSave == false)
        #expect(editor?.problem == "You already have a snippet for “My  Address”.")
    }

    @Test("a one-word trigger is saved but warned about, since it fires on that word everywhere")
    func oneWordTriggerCaution() {
        let editor = HistoryFixture.snippets(
            draft: SnippetDraft(trigger: " address ", text: "x")
        ).editor

        #expect(editor?.canSave == true)
        #expect(
            editor?.caution == """
                Uttrflow swaps in this text every time you say “address”, in any sentence. \
                A phrase you would not say otherwise, such as “my home address”, is safer.
                """)
    }

    @Test("a trigger of two or more words, or one that cannot be saved, carries no warning")
    func noCaution() {
        #expect(
            HistoryFixture.snippets(draft: SnippetDraft(trigger: "my address", text: "x")).editor?
                .caution == nil)
        #expect(
            HistoryFixture.snippets(draft: SnippetDraft(trigger: "address", text: " ")).editor?
                .caution == nil)
    }

    @Test("a trigger dictation rewrites says how it arrives and offers to save that form")
    func arrivalDiffers() {
        let editor = HistoryFixture.snippets(
            draft: SnippetDraft(trigger: "email one", text: "x"),
            arrival: SnippetArrival(trigger: "email one", arrives: "Email 1.")
        ).editor

        #expect(editor?.arrival == "Said aloud, this arrives as “Email 1.”.")
        #expect(
            editor?.saveArrived?.intent
                == .saveSnippet(trigger: "Email 1.", text: "x", applications: [], replacing: nil))
    }

    @Test("a trigger word that is a Dictionary entry's sounds-like says what dictation writes instead")
    func dictionarySoundsLike() {
        let entry = DictionaryEntry(
            word: "Quillon", pronunciation: "quill on", origin: .added, firstSeen: HistoryFixture.now)
        let note = SnippetsPresenter.dictionaryNote(for: "send quill on invoice", in: [entry])
        #expect(note == "Dictation may write “quill on” as “Quillon”, from your Dictionary.")
    }

    @Test("a trigger word that is a Dictionary spelling is named")
    func dictionarySpelling() {
        let entry = DictionaryEntry(word: "Example Corp", origin: .added, firstSeen: HistoryFixture.now)
        let note = SnippetsPresenter.dictionaryNote(for: "sign off example corp", in: [entry])
        #expect(note == "“Example Corp” is a Dictionary word, so dictation may change how it arrives.")
    }

    @Test("a trigger with no Dictionary word, or only part of a phrase, shows no Dictionary note")
    func dictionaryNone() {
        let entries = [
            DictionaryEntry(word: "Example Corp", origin: .added, firstSeen: HistoryFixture.now),
            DictionaryEntry(
                word: "Quillon", pronunciation: "quill on", origin: .added, firstSeen: HistoryFixture.now),
        ]
        #expect(SnippetsPresenter.dictionaryNote(for: "my example address", in: entries) == nil)
        #expect(SnippetsPresenter.dictionaryNote(for: "quill", in: entries) == nil)
        #expect(SnippetsPresenter.dictionaryNote(for: "", in: entries) == nil)
    }

    @Test("the editor carries the Dictionary note from the snapshot's dictionary")
    func dictionaryNoteInEditor() {
        let entry = DictionaryEntry(
            word: "Quillon", pronunciation: "quill on", origin: .added, firstSeen: HistoryFixture.now)
        let editor = SnippetsPresenter.page(
            for: SnippetsSnapshot(
                draft: SnippetDraft(trigger: "quill on", text: "x"), now: HistoryFixture.now,
                dictionary: [entry])
        ).editor
        #expect(
            editor?.dictionaryNote == "Dictation may write “quill on” as “Quillon”, from your Dictionary.")
    }

    @Test("a trigger that arrives as the same words shows no note")
    func arrivalSame() {
        let editor = HistoryFixture.snippets(
            draft: SnippetDraft(trigger: "my address", text: "x"),
            arrival: SnippetArrival(trigger: "my address", arrives: "My address.")
        ).editor
        #expect(editor?.arrival == nil)
        #expect(editor?.saveArrived == nil)
    }

    @Test("an arrival measured for an older trigger is not shown")
    func arrivalStale() {
        let editor = HistoryFixture.snippets(
            draft: SnippetDraft(trigger: "email two", text: "x"),
            arrival: SnippetArrival(trigger: "email one", arrives: "Email 1.")
        ).editor
        #expect(editor?.arrival == nil)
    }

    @Test("a draft that cannot be saved is not offered the arrived form")
    func arrivalBlockedByProblem() {
        let editor = HistoryFixture.snippets(
            draft: SnippetDraft(trigger: "email one", text: " "),
            arrival: SnippetArrival(trigger: "email one", arrives: "Email 1.")
        ).editor
        #expect(editor?.arrival != nil)
        #expect(editor?.saveArrived == nil)
    }

    @Test("a snippet does not clash with itself")
    func editingItsOwnTrigger() {
        let existing = HistoryFixture.snippet("my address")
        let editor = HistoryFixture.snippets(
            [existing],
            draft: SnippetDraft(editing: existing.id, trigger: "my address", text: "Updated")
        ).editor
        #expect(editor?.canSave == true)
    }

    /// An empty state under an open editor would be telling the user off for the thing they are doing.
    @Test("an open editor replaces the empty state")
    func editorInsteadOfEmpty() {
        let page = HistoryFixture.snippets([], draft: SnippetDraft())
        #expect(page.emptyState == nil)
        #expect(page.editor != nil)
    }
}

@Suite("Snippets with nothing in them")
struct SnippetsEmptyTests {
    @Test("an empty page explains the idea and offers to start one")
    func empty() {
        let page = HistoryFixture.snippets()
        #expect(page.emptyState?.title == "No snippets yet")
        #expect(page.emptyState?.action?.intent == .addSnippet)
    }

    @Test("offers a new snippet when the last one is deleted during search")
    func emptyDuringSearch() {
        let page = HistoryFixture.snippets(query: "anything")
        #expect(page.emptyState?.title == "No snippets yet")
        #expect(page.emptyState?.action?.intent == .addSnippet)
    }

    @Test("the empty page says the idea in one line")
    func oneLine() {
        let page = HistoryFixture.snippets()
        #expect(page.emptyState?.message == "Say a short phrase, and Uttrflow types the whole thing.")
    }

    @Test("a search that matched nothing says what it was looking for")
    func noMatches() {
        let page = HistoryFixture.snippets([HistoryFixture.snippet()], query: "invoice")
        #expect(page.emptyState?.title == "No matches")
        #expect(page.emptyState?.message.contains("“invoice”") == true)
    }
}

@Suite("An editor that has just opened")
struct UntouchedEditorTests {
    /// #156: both editors opened already showing a refusal, before anything had been typed.
    @Test("says nothing about a snippet nobody has typed into yet")
    func snippetStaysQuiet() {
        #expect(SnippetsPresenter.problem(with: SnippetDraft(), in: SnippetsSnapshot(now: .now)) == nil)
    }

    @Test("and starts saying it as soon as there is something to say it about")
    func snippetSpeaksOnceTouched() {
        let touched = SnippetDraft(trigger: "", text: "an address")
        #expect(SnippetsPresenter.problem(with: touched, in: SnippetsSnapshot(now: .now)) != nil)
    }

    @Test("says nothing about a word nobody has typed into yet")
    func wordStaysQuiet() {
        #expect(
            DictionaryPresenter.problem(with: DictionaryDraft(), in: DictionarySnapshot(now: .now)) == nil)
    }

    @Test("and starts saying it as soon as there is something to say it about")
    func wordSpeaksOnceTouched() {
        let touched = DictionaryDraft(word: "", pronunciation: "nik-hil")
        #expect(DictionaryPresenter.problem(with: touched, in: DictionarySnapshot(now: .now)) != nil)
    }
}

@Suite("Snippet pill tints")
struct SnippetTintTests {
    @Test("each snippet keeps the tint of its place in the store, cycling through four")
    func cycles() {
        // Each a day older than the last, so the newest-first list is the store's order and no tie is broken by identity.
        let snippets = (0..<6).map {
            HistoryFixture.snippet("trigger \($0)", text: "text \($0)", createdDaysAgo: 10 + $0)
        }
        #expect(HistoryFixture.snippets(snippets).rows.map(\.tint) == [0, 1, 2, 3, 0, 1])
    }

    @Test("a search does not repaint the snippets it leaves")
    func stableUnderSearch() {
        let snippets = (0..<3).map { HistoryFixture.snippet("trigger \($0)", text: "text \($0)") }
        #expect(HistoryFixture.snippets(snippets, query: "trigger 2").rows.map(\.tint) == [2])
    }

    @Test("an empty page is its title alone, and an open editor brings the caption back without a count")
    func emptyCaption() {
        #expect(HistoryFixture.snippets().chrome.caption == nil)
        let editing = SnippetsPresenter.page(for: SnippetsSnapshot(draft: SnippetDraft(), now: .now))
        #expect(editing.chrome.caption == "Say a short phrase; Uttrflow types the whole thing.")
        #expect(editing.chrome.addAction?.intent == .addSnippet)
    }
}
