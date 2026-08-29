import Foundation
import UttrflowSettings
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    static func correction(
        in dictation: UUID = UUID(),
        heard: String = "utter flow",
        wrote: String = "Uttrflow",
        reason: CorrectionReason = .seenOnScreen,
        minutesAgo: Int = 0,
        daysAgo: Int = 0,
        application: String? = "Slack",
        isUndone: Bool = false
    ) -> Correction {
        Correction(
            dictation: dictation, heard: heard, wrote: wrote, reason: reason,
            when: now.addingTimeInterval(Double(-minutesAgo) * 60 + Double(-daysAgo) * 86_400),
            applicationName: application, isUndone: isUndone)
    }

    static func corrections(
        _ corrections: [Correction] = [],
        dictations: [HistoryEntry] = [],
        query: String = "",
        scope: CorrectionsScope = .all
    ) -> CorrectionsPresentation {
        CorrectionsPresenter.page(
            for: CorrectionsSnapshot(
                corrections: corrections, dictations: dictations, query: query, scope: scope,
                settings: .default, now: now),
            calendar: calendar, locale: locale)
    }
}

@Suite("Corrections: what was changed, and why")
struct CorrectionsPageTests {
    /// The page the whole product is accountable through, so the sentence that says so
    /// is on the page and not in a release note.
    @Test("the page says why it exists")
    func callout() {
        let page = HistoryFixture.corrections()
        #expect(page.callout.message.contains("owes you this page"))
        #expect(page.callout.symbolName == "arrow.left.arrow.right")
        #expect(page.chrome.title == "Corrections")
    }

    @Test("every change made today is listed")
    func lists() {
        let page = HistoryFixture.corrections([
            HistoryFixture.correction(heard: "utter flow", wrote: "Uttrflow"),
            HistoryFixture.correction(heard: "postgress", wrote: "Postgres", reason: .heardAsSeveralWords),
        ])
        #expect(page.rows.map(\.wrote) == ["Uttrflow", "Postgres"])
        #expect(page.emptyState == nil)
    }

    @Test("a row carries what was heard, what was written and the reason")
    func row() {
        let page = HistoryFixture.corrections([
            HistoryFixture.correction(heard: "a sink p g", wrote: "asyncpg", reason: .seenOnScreen)
        ])
        let row = page.rows[0]
        #expect(row.heard == "a sink p g")
        #expect(row.wrote == "asyncpg")
        #expect(row.reason.text == "Seen on screen")
        #expect(row.application?.name == "Slack")
        #expect(!row.when.isEmpty)
    }

    @Test("a change that still applies can be undone")
    func undo() {
        let correction = HistoryFixture.correction()
        let row = HistoryFixture.corrections([correction]).rows[0]
        #expect(row.undo?.intent == .undoCorrection(correction.id))
        #expect(!row.isUndone)
    }

    /// Drawing an undone change as though it still applied would make this page lie
    /// about the exact thing it exists to be honest about.
    @Test("a change already put back is struck through and offers no second undo")
    func alreadyUndone() {
        let row = HistoryFixture.corrections([HistoryFixture.correction(isUndone: true)]).rows[0]
        #expect(row.isUndone)
        #expect(row.undo == nil)
    }

    /// The reasons are the correction engine's own, not a second list written for the
    /// artboard: the page can only be honest about why a word changed if the words it
    /// shows come from whatever decided to change it.
    @Test("the reason on a row is the one the engine gave")
    func everyReasonIsNamed() {
        for reason in CorrectionReason.allCases {
            let row = HistoryFixture.corrections([HistoryFixture.correction(reason: reason)]).rows[0]
            #expect(row.reason.text == reason.title)
            #expect(!reason.title.isEmpty)
        }
    }

    /// The number of changes alone is unreadable without knowing how much was said.
    @Test("the caption counts the changes and the sentences they are spread across")
    func caption() {
        let page = HistoryFixture.corrections(
            [HistoryFixture.correction(), HistoryFixture.correction()],
            dictations: [HistoryFixture.entry(), HistoryFixture.entry(), HistoryFixture.entry()])
        #expect(page.caption == "Today · 2 changes across 3 dictations")
    }

    @Test("yesterday's changes belong to yesterday")
    func todayOnly() {
        let page = HistoryFixture.corrections([
            HistoryFixture.correction(wrote: "Today"),
            HistoryFixture.correction(wrote: "Yesterday", daysAgo: 1),
        ])
        #expect(page.rows.map(\.wrote) == ["Today"])
    }

    /// The artboard says "undo it three times"; the rule in ``DictionaryEntry`` is a
    /// ratio, not a count, and the footnote follows the code rather than the drawing.
    @Test("the footnote describes the retirement rule the dictionary actually applies")
    func footnote() {
        let page = HistoryFixture.corrections([HistoryFixture.correction()])
        #expect(page.footnote?.contains("more often than you keep it") == true)
    }
}

@Suite("Narrowing what Corrections lists")
struct CorrectionsScopeTests {
    @Test("the scope pop-up offers every view of the list")
    func options() {
        let scope = HistoryFixture.corrections([HistoryFixture.correction()]).chrome.scope
        #expect(scope?.options.map(\.id) == ["all", "applied", "undone"])
        #expect(scope?.title == "All changes")
        #expect(scope?.options.filter(\.isSelected).map(\.id) == ["all"])
    }

    @Test("each scope is named")
    func titles() {
        #expect(CorrectionsScope.all.title == "All changes")
        #expect(CorrectionsScope.applied.title == "Still applied")
        #expect(CorrectionsScope.undone.title == "Undone")
    }

    @Test("still applied hides what has been put back")
    func applied() {
        let page = HistoryFixture.corrections(
            [
                HistoryFixture.correction(wrote: "Kept"),
                HistoryFixture.correction(wrote: "Reverted", isUndone: true),
            ], scope: .applied)
        #expect(page.rows.map(\.wrote) == ["Kept"])
    }

    @Test("undone shows only what has been put back")
    func undone() {
        let page = HistoryFixture.corrections(
            [
                HistoryFixture.correction(wrote: "Kept"),
                HistoryFixture.correction(wrote: "Reverted", isUndone: true),
            ], scope: .undone)
        #expect(page.rows.map(\.wrote) == ["Reverted"])
    }

    /// Three filters over an empty list are three ways to reach the same nothing.
    @Test("the controls appear only once there is something to narrow")
    func noControlsWhenEmpty() {
        let page = HistoryFixture.corrections()
        #expect(page.chrome.scope == nil)
        #expect(page.chrome.search == nil)
    }

    @Test("searching matches what was heard, what was written and the reason")
    func searching() {
        let corrections = [
            HistoryFixture.correction(heard: "utter flow", wrote: "Uttrflow"),
            HistoryFixture.correction(heard: "um, so", wrote: "so", reason: .heardAsStrayLetters),
        ]
        #expect(HistoryFixture.corrections(corrections, query: "uttr").rows.count == 1)
        #expect(HistoryFixture.corrections(corrections, query: "Uttrflow").rows.count == 1)
        #expect(HistoryFixture.corrections(corrections, query: "stray").rows.count == 1)
        #expect(HistoryFixture.corrections(corrections, query: "  ").rows.count == 2)
    }
}

@Suite("Corrections with nothing to show")
struct CorrectionsEmptyTests {
    /// An empty page here is the good outcome, not a missing feature — and it says so.
    @Test("changing nothing is reported as the good outcome")
    func changedNothing() {
        let empty = HistoryFixture.corrections(dictations: [HistoryFixture.entry()]).emptyState
        #expect(empty?.title == "Uttrflow changed nothing you said today")
        #expect(empty?.chips.map(\.caption) == ["dictation today", "words changed"])
        #expect(empty?.chips.first?.value == "1")
        #expect(empty?.footnote?.contains("good outcome") == true)
    }

    @Test("more than one dictation is counted in the plural")
    func plural() {
        let empty = HistoryFixture.corrections(
            dictations: [HistoryFixture.entry(), HistoryFixture.entry()]
        ).emptyState
        #expect(empty?.chips.first?.caption == "dictations today")
    }

    /// The chip says "today". It counted the whole retained history, so a user with three
    /// months of dictations was told they had made ninety-nine today while the Dictation
    /// page beside it said they had made none. Two pages disagreeing about the same fact
    /// is worse than either being silent.
    @Test("the chip counts today and not everything ever kept")
    func countsOnlyToday() {
        let empty = HistoryFixture.corrections(
            dictations: [
                HistoryFixture.entry("today"),
                HistoryFixture.entry("last week", daysAgo: 7),
                HistoryFixture.entry("last month", daysAgo: 30),
            ]
        ).emptyState
        #expect(empty?.chips.first?.value == "1")
        #expect(empty?.chips.first?.caption == "dictation today")
    }

    /// The caption and the chip are two sentences about one number, and they used to be
    /// computed two different ways.
    @Test("the caption and the chip agree about how many were said today")
    func captionAndChipAgree() {
        let page = HistoryFixture.corrections(
            dictations: [HistoryFixture.entry("today"), HistoryFixture.entry("older", daysAgo: 4)])
        #expect(page.caption.contains("1 dictation"))
        #expect(page.emptyState?.chips.first?.value == "1")
    }

    /// The difference between "it changed nothing" and "your filter hid everything" is
    /// the difference between reassurance and confusion.
    @Test("a scope that hid everything says so rather than claiming nothing changed")
    func scopeHidEverything() {
        let empty = HistoryFixture.corrections(
            [HistoryFixture.correction()], scope: .undone
        ).emptyState
        #expect(empty?.title == "Nothing in this view")
        #expect(empty?.message == "1 change today, and none of them is undone.")
    }

    @Test("a search that matched nothing says what it was looking for")
    func noMatches() {
        let empty = HistoryFixture.corrections(
            [HistoryFixture.correction()], query: "invoice"
        ).emptyState
        #expect(empty?.title == "No matches")
        #expect(empty?.message.contains("“invoice”") == true)
    }

    /// Two pieces of small print under one sentence is clutter; the empty state carries
    /// its own closing line.
    @Test("an empty pane drops the list's footnote")
    func noFootnote() {
        #expect(HistoryFixture.corrections().footnote == nil)
    }
}
