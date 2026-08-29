import Foundation
import UttrflowCore
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    static func snippet(
        _ trigger: String = "my address",
        text: String = "Flat 402, Example Residences, Bengaluru",
        used: Int = 12,
        lastUsedDaysAgo: Int? = 0
    ) -> Snippet {
        Snippet(
            trigger: trigger, expansion: text, created: now.addingTimeInterval(-864_000),
            timesUsed: used,
            lastUsed: lastUsedDaysAgo.map { now.addingTimeInterval(Double(-$0) * 86_400) })
    }

    static func snippets(
        _ snippets: [Snippet] = [], draft: SnippetDraft? = nil, query: String = ""
    ) -> SnippetsPresentation {
        SnippetsPresenter.page(
            for: SnippetsSnapshot(snippets: snippets, draft: draft, query: query, now: now),
            calendar: calendar, locale: locale)
    }
}

@Suite("Snippets: a phrase you say for a block of text")
struct SnippetsPageTests {
    @Test("every snippet is listed")
    func lists() {
        let page = HistoryFixture.snippets([
            HistoryFixture.snippet("my address"), HistoryFixture.snippet("sign off", used: 64),
        ])
        #expect(page.rows.map(\.trigger.text) == ["my address", "sign off"])
        #expect(page.caption == "2 snippets")
        #expect(page.chrome.title == "Snippets")
        #expect(page.emptyState == nil)
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

    /// A snippet nobody has used is worth spotting, so it says so rather than leaving
    /// the cell blank.
    @Test("a snippet that has never fired says never")
    func neverUsed() {
        let row = HistoryFixture.snippets([HistoryFixture.snippet(lastUsedDaysAgo: nil)]).rows[0]
        #expect(row.lastUsed == "Never")
    }

    /// Spoken triggers arrive with whatever spacing the recogniser felt like, so
    /// comparing them raw would make one snippet look like two.
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
            HistoryFixture.snippet("sign off", text: "Thanks, Naveen"),
        ]
        #expect(HistoryFixture.snippets(snippets, query: "address").rows.count == 1)
        #expect(HistoryFixture.snippets(snippets, query: "Naveen").rows.count == 1)
        #expect(HistoryFixture.snippets(snippets, query: "  ").rows.count == 2)
    }

    @Test("the search field appears only when there is something to search")
    func search() {
        #expect(HistoryFixture.snippets().chrome.search == nil)
        #expect(HistoryFixture.snippets([HistoryFixture.snippet()]).chrome.search != nil)
    }

    @Test("a new snippet can always be started")
    func add() {
        #expect(HistoryFixture.snippets().chrome.addAction?.intent == .addSnippet)
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
        #expect(page.editor?.editing == nil)
        #expect(page.editor?.badge.text == "New")
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
        #expect(page.editor?.canSave == true)
        #expect(
            page.editor?.save.intent
                == .saveSnippet(trigger: snippet.trigger, text: "New text", replacing: snippet.id))
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

    /// Two snippets answering to one phrase means one of them silently never fires, and
    /// the user has no way to find out which.
    @Test("a trigger somebody already has is refused before it is saved")
    func duplicate() {
        let existing = HistoryFixture.snippet("my address")
        let editor = HistoryFixture.snippets(
            [existing], draft: SnippetDraft(trigger: "My  Address", text: "Somewhere else")
        ).editor

        #expect(editor?.canSave == false)
        #expect(editor?.problem == "You already have a snippet for “My  Address”.")
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

    /// An empty state under an open editor would be telling the user off for the thing
    /// they are doing.
    @Test("an open editor replaces the empty state")
    func editorInsteadOfEmpty() {
        let page = HistoryFixture.snippets([], draft: SnippetDraft())
        #expect(page.emptyState == nil)
        #expect(page.example == nil)
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

    /// The idea lands before the form does.
    @Test("the empty page shows one worked example")
    func example() {
        let page = HistoryFixture.snippets()
        #expect(page.example?.heading == "For example")
        #expect(page.example?.trigger.text == "my address")
        #expect(page.example?.trigger.tone == .accent)
        #expect(page.example?.text.contains("Example Residences") == true)
    }

    @Test("a search that matched nothing says what it was looking for")
    func noMatches() {
        let page = HistoryFixture.snippets([HistoryFixture.snippet()], query: "invoice")
        #expect(page.emptyState?.title == "No matches")
        #expect(page.emptyState?.message.contains("“invoice”") == true)
        // The example belongs to somebody with no snippets, not to a failed search.
        #expect(page.example == nil)
    }
}
