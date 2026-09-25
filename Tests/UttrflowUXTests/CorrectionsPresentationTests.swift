// Tests for the Corrections page: dictionary-backed rows, scope, search, and empty states.
import Foundation
import UttrflowSettings
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    /// One dictionary-backed correction, seen on screen and in Slack by default.
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

    /// The Corrections page over these inputs.
    static func corrections(
        _ corrections: [Correction] = [],
        dictations: [HistoryEntry] = [],
        query: String = "",
        scope: CorrectionsScope = .all,
        settings: Settings = .default
    ) -> CorrectionsPresentation {
        CorrectionsPresenter.page(
            for: CorrectionsSnapshot(
                corrections: corrections, dictations: dictations, query: query, scope: scope,
                settings: settings, now: now),
            calendar: calendar, locale: locale)
    }
}

@Suite("Corrections: dictionary-backed substitutions")
struct CorrectionsPageTests {
    /// The page the product is accountable through, so the contract is on the page.
    @Test("the page says why it exists")
    func callout() {
        let page = HistoryFixture.corrections()
        #expect(page.callout.message.contains("Dictionary-backed word substitutions"))
        #expect(page.callout.message.contains("what it wrote from your Dictionary"))
        #expect(page.callout.symbolName == "arrow.left.arrow.right")
        #expect(page.chrome.title == "Corrections")
        #expect(page.chrome.caption?.contains("Dictionary-backed substitutions") == true)
    }

    /// A wrong page would lie about why it shows up; the copy must not mention "today" once we keep older corrections.
    @Test("the callout is not scoped to today")
    func calloutNotToday() {
        let page = HistoryFixture.corrections()
        #expect(!page.callout.message.contains("today"))
    }

    @Test("every dictionary correction made today is listed")
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

    @Test("a correction that still applies can be undone")
    func undo() {
        let correction = HistoryFixture.correction()
        let row = HistoryFixture.corrections([correction]).rows[0]
        #expect(row.undo?.intent == .undoCorrection(correction.id))
        #expect(!row.isUndone)
    }

    /// Drawing an undone correction as still applied would make this page lie about its own subject.
    @Test("a correction already put back is struck through and offers no second undo")
    func alreadyUndone() {
        let row = HistoryFixture.corrections([HistoryFixture.correction(isUndone: true)]).rows[0]
        #expect(row.isUndone)
        #expect(row.undo == nil)
    }

    /// The reasons are the engine's own, not a second list, so the page can be honest about why.
    @Test("the reason on a row is the one the engine gave")
    func everyReasonIsNamed() {
        for reason in CorrectionReason.allCases {
            let row = HistoryFixture.corrections([HistoryFixture.correction(reason: reason)]).rows[0]
            #expect(row.reason.text == reason.title)
            #expect(!reason.title.isEmpty)
        }
    }

    /// The number of corrections alone is unreadable without knowing how much was said.
    @Test("the caption counts the corrections and the sentences they are spread across")
    func caption() {
        let page = HistoryFixture.corrections(
            [HistoryFixture.correction(), HistoryFixture.correction()],
            dictations: [HistoryFixture.entry(), HistoryFixture.entry(), HistoryFixture.entry()])
        #expect(page.caption == "2 corrections across 3 dictations")
    }

    /// A correction noticed the next morning is still here, because its dictation is. The page hides nothing.
    @Test("a correction from yesterday is listed alongside today's")
    func yesterdayIsListed() {
        let page = HistoryFixture.corrections([
            HistoryFixture.correction(wrote: "Today"),
            HistoryFixture.correction(wrote: "Yesterday", daysAgo: 1),
        ])
        #expect(page.rows.map(\.wrote) == ["Today", "Yesterday"])
    }

    /// The retention window is what the privacy setting promises; older corrections fall off with their dictation.
    @Test("a correction older than retention is dropped to match the dictation")
    func olderThanRetention() {
        var settings = Settings.default
        settings.transcriptRetentionDays = 7
        let page = HistoryFixture.corrections(
            [
                HistoryFixture.correction(wrote: "Kept"),
                HistoryFixture.correction(wrote: "Beyond the window", daysAgo: 8),
            ],
            settings: settings)
        #expect(page.rows.map(\.wrote) == ["Kept"])
    }

    /// The undo is the path that retires a word, and it must reach a change noticed the next morning.
    @Test("a correction from yesterday still offers Undo")
    func yesterdayUndo() {
        let correction = HistoryFixture.correction(wrote: "Stale", daysAgo: 1)
        let row = HistoryFixture.corrections([correction]).rows[0]
        #expect(row.undo?.intent == .undoCorrection(correction.id))
        #expect(!row.isUndone)
    }

    /// The "Today" framing was the bug; the page must keep its own copy honest.
    @Test("the caption does not say 'today' once corrections are kept across days")
    func captionIsNotToday() {
        let page = HistoryFixture.corrections(
            [HistoryFixture.correction()],
            dictations: [HistoryFixture.entry()])
        #expect(!page.caption.contains("Today"))
    }

    /// The rule in ``DictionaryEntry`` is a ratio, not a count, and the footnote follows the code.
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
        #expect(scope?.title == "All corrections")
        #expect(scope?.options.filter(\.isSelected).map(\.id) == ["all"])
    }

    @Test("each scope is named")
    func titles() {
        #expect(CorrectionsScope.all.title == "All corrections")
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
            HistoryFixture.correction(heard: "s q l", wrote: "SQL", reason: .heardAsStrayLetters),
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
    @Test("no dictionary corrections is reported as the good outcome")
    func noDictionaryCorrections() {
        let empty = HistoryFixture.corrections(dictations: [HistoryFixture.entry()]).emptyState
        #expect(empty?.title == "No dictionary corrections")
        #expect(empty?.message.contains("word substitutions backed by your Dictionary") == true)
        #expect(empty?.message.contains("filler removal") == true)
        #expect(empty?.message.contains("does not appear here") == true)
        #expect(empty?.chips.map(\.caption) == ["dictation", "dictionary corrections"])
        #expect(empty?.chips.first?.value == "1")
        #expect(empty?.footnote?.contains("good outcome") == true)
    }

    @Test("more than one dictation is counted in the plural")
    func plural() {
        let empty = HistoryFixture.corrections(
            dictations: [HistoryFixture.entry(), HistoryFixture.entry()]
        ).emptyState
        #expect(empty?.chips.first?.caption == "dictations")
    }

    /// The chip counts what survives the retention window, the same set the caption and History show.
    @Test("the chip counts within the retention window")
    func countsWithinRetention() {
        var settings = Settings.default
        settings.transcriptRetentionDays = 7
        let empty = HistoryFixture.corrections(
            dictations: [
                HistoryFixture.entry("today"),
                HistoryFixture.entry("just inside", daysAgo: 6),
                HistoryFixture.entry("last week", daysAgo: 7),
                HistoryFixture.entry("last month", daysAgo: 30),
            ],
            settings: settings
        ).emptyState
        #expect(empty?.chips.first?.value == "2")
        #expect(empty?.chips.first?.caption == "dictations")
    }

    /// The caption and the chip are two sentences about one number, computed one way.
    @Test("the caption and the chip agree about how many were said")
    func captionAndChipAgree() {
        let page = HistoryFixture.corrections(
            dictations: [HistoryFixture.entry("today"), HistoryFixture.entry("older", daysAgo: 4)])
        #expect(page.caption.contains("2 dictations"))
        #expect(page.emptyState?.chips.first?.value == "2")
    }

    /// "No corrections" and "your filter hid everything" are reassurance and confusion.
    @Test("a scope that hid everything says so rather than claiming nothing changed")
    func scopeHidEverything() {
        let empty = HistoryFixture.corrections(
            [HistoryFixture.correction()], scope: .undone
        ).emptyState
        #expect(empty?.title == "Nothing in this view")
        #expect(empty?.message == "1 correction, and none of them is undone.")
    }

    @Test("a search that matched nothing says what it was looking for")
    func noMatches() {
        let empty = HistoryFixture.corrections(
            [HistoryFixture.correction()], query: "invoice"
        ).emptyState
        #expect(empty?.title == "No matches")
        #expect(empty?.message.contains("“invoice”") == true)
        #expect(empty?.message.contains("dictionary correction") == true)
    }

    /// Two pieces of small print under one sentence is clutter; the empty state has its own closing line.
    @Test("an empty pane drops the list's footnote")
    func noFootnote() {
        #expect(HistoryFixture.corrections().footnote == nil)
    }
}
