import Foundation
import UttrflowHistory
import UttrflowSettings
import Testing

@testable import UttrflowUX

/// A fixed clock and a fixed region, so a test cannot pass in one time zone and fail in
/// another — or start failing at midnight.
enum HistoryFixture {
    static let locale = Locale(identifier: "en_GB")

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        // The one time zone in which "today" and "yesterday" mean the same thing to every
        // machine that runs the suite.
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// Mid-afternoon on 15 June 2025, chosen so that subtracting hours in a test stays
    /// inside the same day and the day names below are stable.
    static let now = Date(timeIntervalSince1970: 1_750_000_800)

    /// One kept dictation.
    ///
    /// `changes` defaults to an empty record — *measured, and nothing was changed* —
    /// because that is what an ordinary dictation looks like. Pass `nil` for one written
    /// before changes were kept, which is a different fact and must stay out of the
    /// accuracy arithmetic.
    static func entry(
        _ text: String = "Hello there",
        minutesAgo: Int = 0,
        daysAgo: Int = 0,
        application: String? = "Slack",
        applicationIdentifier: String? = nil,
        changes: RecordedChanges? = RecordedChanges(),
        isFlagged: Bool = false
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            text: text,
            when: now.addingTimeInterval(
                Double(-minutesAgo) * 60 + Double(-daysAgo) * 86_400),
            applicationName: application,
            applicationIdentifier: applicationIdentifier,
            changes: changes,
            isFlagged: isFlagged)
    }

    static func snapshot(
        entries: [HistoryEntry],
        query: String = "",
        settings: Settings = .default,
        keepsRecordings: Bool = false
    ) -> HistorySnapshot {
        HistorySnapshot(
            entries: entries, query: query, settings: settings,
            keepsRecordings: keepsRecordings, now: now)
    }

    static func page(
        entries: [HistoryEntry],
        query: String = "",
        settings: Settings = .default,
        keepsRecordings: Bool = false
    ) -> HistoryPresentation {
        HistoryPresenter.page(
            for: snapshot(
                entries: entries, query: query, settings: settings,
                keepsRecordings: keepsRecordings),
            calendar: calendar, locale: locale)
    }
}

@Suite("What the history page shows")
struct HistoryPresentationTests {
    @Test("today's dictations are grouped under Today, newest first")
    func groupsToday() {
        let page = HistoryFixture.page(entries: [
            HistoryFixture.entry("Newest", minutesAgo: 2),
            HistoryFixture.entry("Older", minutesAgo: 40),
        ])

        #expect(page.days.count == 1)
        #expect(page.days[0].title == "Today")
        #expect(page.days[0].rows.map(\.text) == ["Newest", "Older"])
        #expect(page.emptyState == nil)
        #expect(page.days[0].id == "Today")
    }

    @Test("yesterday is named rather than dated")
    func namesYesterday() {
        let page = HistoryFixture.page(entries: [HistoryFixture.entry(daysAgo: 1)])
        #expect(page.days.map(\.title) == ["Yesterday"])
    }

    @Test("anything older is dated")
    func datesOlderDays() {
        let page = HistoryFixture.page(entries: [HistoryFixture.entry(daysAgo: 3)])
        let title = page.days.first?.title
        #expect(title?.contains("June") == true)
    }

    /// The store orders by arrival rather than by timestamp, and this must not undo that.
    /// Merging as days are met is also what stops a clock that moved producing two
    /// sections both called "Today".
    @Test("the order the store gave is kept, and a day appears once")
    func keepsArrivalOrderAndMergesDays() {
        let page = HistoryFixture.page(entries: [
            HistoryFixture.entry("First", minutesAgo: 5),
            HistoryFixture.entry("Yesterday's", daysAgo: 1),
            HistoryFixture.entry("Second", minutesAgo: 90),
        ])

        #expect(page.days.map(\.title) == ["Today", "Yesterday"])
        #expect(page.days[0].rows.map(\.text) == ["First", "Second"])
    }

    @Test("a row says which app the text went into")
    func rowsCarryTheApplication() {
        let page = HistoryFixture.page(entries: [HistoryFixture.entry(application: "slack")])
        let application = page.days.first?.rows.first?.application
        #expect(application?.name == "slack")
        #expect(application?.initial == "S")
    }

    @Test("a row with no app, or a blank one, simply has no tile")
    func rowsWithoutAnApplication() {
        #expect(HistoryPresenter.application(named: "   ") == nil)
        let page = HistoryFixture.page(entries: [HistoryFixture.entry(application: nil)])
        #expect(page.days.first?.rows.first?.application == nil)
    }

    /// Measured against the snapshot's clock, not the machine's, or the row would
    /// disagree with the retention the rest of the page is reasoned from.
    @Test("how long ago is measured against the snapshot's clock")
    func relativeTimeUsesTheSnapshotClock() {
        let page = HistoryFixture.page(entries: [HistoryFixture.entry(minutesAgo: 2)])
        #expect(page.days.first?.rows.first?.when == "2 minutes ago")
    }

    @Test("a row is identified by the dictation it shows")
    func rowIdentity() {
        let entry = HistoryFixture.entry()
        let row = HistoryPresenter.row(
            for: entry, relativeTo: HistoryFixture.now, locale: HistoryFixture.locale)
        #expect(row.id == entry.id)
    }
}

@Suite("History keeps the promise about retention")
struct HistoryRetentionTests {
    /// The promise is that a dictation older than the window is gone. A page that would
    /// happily draw one can break the promise on the store's behalf.
    @Test("anything older than the window is not shown")
    func dropsExpiredEntries() {
        let page = HistoryFixture.page(entries: [
            HistoryFixture.entry("Kept", daysAgo: 6),
            HistoryFixture.entry("Gone", daysAgo: 9),
        ])

        #expect(page.days.flatMap(\.rows).map(\.text) == ["Kept"])
    }

    @Test("a shorter window drops more")
    func honoursTheConfiguredWindow() {
        var settings = Settings.default
        settings.transcriptRetentionDays = 1
        let page = HistoryFixture.page(
            entries: [HistoryFixture.entry(daysAgo: 3)], settings: settings)

        #expect(page.days.isEmpty)
        #expect(page.emptyState?.title == "Nothing left to show")
    }

    @Test("the notice says how long the text lasts, and that no audio is kept")
    func noticeWhenNothingIsRecorded() {
        let page = HistoryFixture.page(entries: [])
        #expect(
            page.retentionNotice.sentence
                == "Kept on this Mac for 7 days, then deleted. Recordings are never saved.")
        #expect(page.retentionNotice.link.intent == .go(.settings(.privacy)))
    }

    /// The app keeps a recording only until its words land, and the notice says exactly that.
    @Test("the notice says a recording stays only until its words land")
    func noticeWhenAudioIsKept() {
        let page = HistoryFixture.page(entries: [], keepsRecordings: true)
        #expect(
            page.retentionNotice.sentence
                == "Kept on this Mac for 7 days, then deleted. A recording stays only until its words land.")
    }

    /// Somebody checking what the app holds about them should not have to dictate
    /// something first in order to find out.
    @Test("the notice is there even when the list is empty")
    func noticeSurvivesAnEmptyList() {
        #expect(!HistoryFixture.page(entries: []).retentionNotice.sentence.isEmpty)
    }

    /// The boundary itself, because "seven days" has to mean something exact to a user
    /// who reads it as a promise.
    ///
    /// Exactly seven days old is **gone**: its seven days are up. The page used to keep
    /// it — an inclusive comparison here against the store's exclusive one — so a record
    /// the store had already deleted was still being drawn. Where the two could differ,
    /// the promise decides: erring towards deleting keeps a claim the user was shown,
    /// and erring towards keeping breaks it.
    @Test("a dictation whose days are up is gone, on the boundary and past it")
    func retentionBoundary() {
        let entries = [
            HistoryFixture.entry("Still inside", daysAgo: 6),
            HistoryFixture.entry("Exactly seven days", daysAgo: 7),
            HistoryFixture.entry("Past it", daysAgo: 8),
        ]
        let kept = HistoryPresenter.retained(entries, days: 7, now: HistoryFixture.now)

        #expect(kept.map(\.text) == ["Still inside"])
    }

    /// The page and the store must not be able to drift apart again: this asserts they
    /// give the same answer, rather than asserting the page's answer in isolation.
    @Test("the page agrees with the store about what has been deleted")
    func retentionAgreesWithTheStore() {
        for daysAgo in [0, 1, 6, 7, 8, 30] {
            let entry = HistoryFixture.entry("x", daysAgo: daysAgo)
            let onThePage = !HistoryPresenter.retained(
                [entry], days: 7, now: HistoryFixture.now
            ).isEmpty
            let inTheStore = entry.survives(days: 7, now: HistoryFixture.now)
            #expect(onThePage == inTheStore, "disagreed at \(daysAgo) days old")
        }
    }
}

@Suite("Searching what was said")
struct HistorySearchTests {
    @Test("an empty query matches everything")
    func emptyQueryMatchesEverything() {
        let entries = [HistoryFixture.entry("One"), HistoryFixture.entry("Two")]
        #expect(
            HistoryPresenter.matches(entries, query: "  ", locale: HistoryFixture.locale).count == 2
        )
    }

    @Test("the text and the app name are both searched, whatever the case")
    func searchesTextAndApplication() {
        let page = HistoryFixture.page(
            entries: [
                HistoryFixture.entry("Deployment is running", application: "Slack"),
                HistoryFixture.entry("Lunch plans", application: "Mail"),
            ],
            query: "MAIL")

        #expect(page.days.flatMap(\.rows).map(\.text) == ["Lunch plans"])
    }

    /// Dictation produces accented words the user will type unaccented when looking for
    /// them again.
    /// An entry that never reached an app has no name to search, and must not stop the
    /// search reaching the entries that do.
    @Test("an entry with no app name is searched for its text alone")
    func searchesEntriesWithoutAnApplication() {
        let page = HistoryFixture.page(
            entries: [
                HistoryFixture.entry("Deployment notes", application: nil),
                HistoryFixture.entry("Lunch plans", application: nil),
            ],
            query: "deployment")

        #expect(page.days.flatMap(\.rows).map(\.text) == ["Deployment notes"])
    }

    @Test("accents are ignored")
    func ignoresAccents() {
        let page = HistoryFixture.page(
            entries: [HistoryFixture.entry("Café at three")], query: "cafe")
        #expect(page.days.flatMap(\.rows).count == 1)
    }

    @Test("a query that matches nothing says so, and quotes the query back")
    func noMatches() {
        let page = HistoryFixture.page(entries: [HistoryFixture.entry("Hello")], query: "zebra")
        #expect(page.days.isEmpty)
        #expect(page.emptyState?.title == "No matches")
        #expect(page.emptyState?.message.contains("zebra") == true)
        #expect(page.emptyState?.action == nil)
    }

    /// A search field over nothing is furniture.
    @Test("the field is only offered when there is something to search")
    func hidesTheFieldWhenThereIsNothingToSearch() {
        #expect(HistoryFixture.page(entries: []).showsSearch == false)
        #expect(HistoryFixture.page(entries: [HistoryFixture.entry()]).showsSearch)
    }

    /// Searching does not make the list stop existing, so the field stays.
    @Test("the field stays while a search is matching nothing")
    func fieldSurvivesAFruitlessSearch() {
        let page = HistoryFixture.page(entries: [HistoryFixture.entry()], query: "zebra")
        #expect(page.showsSearch)
    }
}

@Suite("History with nothing in it")
struct HistoryEmptyTests {
    /// Three different nothings, told apart, because the answer to each is different.
    @Test("never dictated is not the same as everything expired")
    func distinguishesTheEmptinesses() {
        let never = HistoryFixture.page(entries: [])
        #expect(never.emptyState?.title == "Nothing yet")
        #expect(never.emptyState?.message.contains("never leaves this Mac") == true)

        let expired = HistoryFixture.page(entries: [HistoryFixture.entry(daysAgo: 30)])
        #expect(expired.emptyState?.title == "Nothing left to show")
        #expect(expired.emptyState?.message.contains("7 days") == true)
    }

    @Test("an empty page still has no false day sections")
    func noPhantomSections() {
        #expect(HistoryFixture.page(entries: []).days.isEmpty)
    }
}

@Suite("Which app a dictation went to")
struct HistoryApplicationTests {
    /// The name is what the row is labelled with; the identifier is what its icon is
    /// looked up by, and only the identifier cannot answer with the wrong app.
    @Test("carries the identifier the dictation recorded")
    func carriesTheIdentifier() throws {
        let entry = HistoryFixture.entry(
            application: "Claude", applicationIdentifier: "com.anthropic.claudefordesktop")
        let application = try #require(HistoryPresenter.application(for: entry))

        #expect(application.name == "Claude")
        #expect(application.initial == "C")
        #expect(application.identifier == "com.anthropic.claudefordesktop")
    }

    /// Every dictation recorded before identifiers were kept. The row still knows where
    /// it went; the icon lookup falls back to the name.
    @Test("has no identifier for a dictation recorded before they were kept")
    func withoutAnIdentifier() throws {
        let application = try #require(
            HistoryPresenter.application(for: HistoryFixture.entry(application: "Slack")))

        #expect(application.identifier == nil)
    }

    /// Blank rather than absent is the shape a hand-edited history file takes. An empty
    /// string would be asked of LaunchServices on every redraw and answer nothing.
    @Test("treats a blank identifier as none")
    func blankIdentifier() throws {
        let entry = HistoryFixture.entry(application: "Mail", applicationIdentifier: "   ")
        let application = try #require(HistoryPresenter.application(for: entry))

        #expect(application.identifier == nil)
    }

    @Test("has no application at all when the dictation recorded no name")
    func withoutAName() {
        #expect(HistoryPresenter.application(for: HistoryFixture.entry(application: nil)) == nil)
        #expect(HistoryPresenter.application(for: HistoryFixture.entry(application: " ")) == nil)
    }
}
