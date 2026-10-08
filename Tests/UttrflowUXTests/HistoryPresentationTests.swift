// The shared history fixture, and tests for the History page: grouping, retention, search, empties.
import Foundation
import UttrflowHistory
import UttrflowSettings
import Testing

@testable import UttrflowUX

/// A fixed clock and a fixed region, so a test cannot pass in one time zone and fail in another.
enum HistoryFixture {
    /// A fixed region.
    static let locale = Locale(identifier: "en_GB")

    /// A Gregorian calendar pinned to GMT.
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        // The one time zone in which "today" and "yesterday" mean the same thing on every machine.
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    /// Mid-afternoon on 15 June 2025, so subtracting hours stays inside the same day.
    static let now = Date(timeIntervalSince1970: 1_750_000_800)

    /// A date at noon in the fixture's fixed calendar.
    static func date(year: Int, month: Int, day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    /// One kept dictation; `changes` defaults to measured-and-unchanged, and `nil` means never measured.
    static func entry(
        _ text: String = "Hello there",
        minutesAgo: Int = 0,
        daysAgo: Int = 0,
        when: Date? = nil,
        application: String? = "Slack",
        applicationIdentifier: String? = nil,
        changes: RecordedChanges? = RecordedChanges(),
        isFlagged: Bool = false,
        arrival: RecordedArrival? = nil
    ) -> HistoryEntry {
        HistoryEntry(
            id: UUID(),
            text: text,
            when: when
                ?? now.addingTimeInterval(
                    Double(-minutesAgo) * 60 + Double(-daysAgo) * 86_400),
            applicationName: application,
            applicationIdentifier: applicationIdentifier,
            changes: changes,
            isFlagged: isFlagged,
            arrival: arrival)
    }

    /// A snapshot over these entries at the fixed clock.
    static func snapshot(
        entries: [HistoryEntry],
        query: String = "",
        settings: Settings = .default,
        keepsRecordings: Bool = false,
        now: Date = HistoryFixture.now
    ) -> HistorySnapshot {
        HistorySnapshot(
            entries: entries, query: query, settings: settings,
            keepsRecordings: keepsRecordings, now: now)
    }

    /// The History page over these entries.
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

    @Test("same month and day in different years have distinct headings")
    func distinguishesYearsForSameMonthAndDay() throws {
        let snapshot = HistoryFixture.snapshot(
            entries: [
                HistoryFixture.entry(
                    "Last year", when: try HistoryFixture.date(year: 2025, month: 9, day: 28)),
                HistoryFixture.entry(
                    "This year", when: try HistoryFixture.date(year: 2026, month: 9, day: 28)),
            ], now: try HistoryFixture.date(year: 2026, month: 9, day: 30))

        let page = HistoryPresenter.page(
            for: snapshot, calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)

        #expect(page.days.map(\.title) == ["28 September 2025", "28 September"])
    }

    @Test("a date from this year keeps its existing heading")
    func currentYearHeadingStaysUnchanged() throws {
        let snapshot = HistoryFixture.snapshot(
            entries: [
                HistoryFixture.entry(
                    "This year", when: try HistoryFixture.date(year: 2026, month: 9, day: 28))
            ], now: try HistoryFixture.date(year: 2026, month: 9, day: 30))

        let page = HistoryPresenter.page(
            for: snapshot, calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)

        #expect(page.days.map(\.title) == ["28 September"])
    }

    @Test("an older heading formats its year in the selected locale")
    func olderHeadingUsesLocaleFormatting() throws {
        let snapshot = HistoryFixture.snapshot(
            entries: [
                HistoryFixture.entry(
                    "Last year", when: try HistoryFixture.date(year: 2025, month: 9, day: 28))
            ], now: try HistoryFixture.date(year: 2026, month: 9, day: 30))
        let locale = Locale(identifier: "en_US")

        let page = HistoryPresenter.page(for: snapshot, calendar: HistoryFixture.calendar, locale: locale)

        #expect(page.days.map(\.title) == ["September 28, 2025"])
    }

    /// The store orders by arrival, and merging days as met stops a moved clock making two "Today"s.
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

    /// Measured against the snapshot's clock, or the row would disagree with retention.
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

    @Test("a row shows the clock time alongside how long ago")
    func rowsCarryTheClockTime() {
        let page = HistoryFixture.page(entries: [HistoryFixture.entry(minutesAgo: 2)])
        let row = page.days.first?.rows.first
        #expect(row?.time.isEmpty == false)
        #expect(row?.time != row?.when)
    }

    @Test("a row whose words never reached a field says so; a delivered row stays quiet")
    func rowsCarryTheArrival() {
        let arrivals: [RecordedArrival?] = [.notInserted, .unconfirmed, .confirmed, .notReported, nil]
        let labels = arrivals.map {
            HistoryPresenter.row(
                for: HistoryFixture.entry(arrival: $0), relativeTo: HistoryFixture.now,
                locale: HistoryFixture.locale
            ).arrival
        }
        #expect(labels == ["Not inserted", "Unconfirmed", nil, nil, nil])
    }
}

@Suite("History row actions")
struct HistoryRowActionsTests {
    @Test("offers copy, copy to paste elsewhere, and flag, in that order")
    func offersTheSameThreeActions() {
        let entry = HistoryFixture.entry("Hello there")
        let row = HistoryPresenter.row(
            for: entry, relativeTo: HistoryFixture.now, locale: HistoryFixture.locale)

        #expect(row.actions.map(\.title) == ["Copy", "Copy to Paste Elsewhere", "Flag"])
        #expect(row.actions[0].intent == .copy("Hello there"))
        #expect(row.actions[1].intent == .copy("Hello there"))
        #expect(row.actions[2].intent == .flagDictation(entry.id))
    }

    @Test("a flagged dictation offers Unflag instead of Flag")
    func offersUnflagWhenAlreadyFlagged() {
        let entry = HistoryFixture.entry(isFlagged: true)
        let row = HistoryPresenter.row(
            for: entry, relativeTo: HistoryFixture.now, locale: HistoryFixture.locale)

        #expect(row.actions.last?.title == "Unflag")
    }

    @Test("the overflow menu offers delete, which forgets this dictation")
    func offersDelete() {
        let entry = HistoryFixture.entry()
        let row = HistoryPresenter.row(
            for: entry, relativeTo: HistoryFixture.now, locale: HistoryFixture.locale)

        #expect(
            row.more.map(\.title) == [
                "Flag: Wrong Words", "Flag: Formatting", "Flag: Spacing", "Report This Dictation", "Delete",
            ])
        #expect(row.more.last?.intent == .forgetDictation(entry.id))
        #expect(row.more.last?.isDestructive == true)
    }

    @Test("the overflow menu flags a dictation with each error class, in the taxonomy's order")
    func offersFlagReasons() {
        let entry = HistoryFixture.entry()
        let row = HistoryPresenter.row(
            for: entry, relativeTo: HistoryFixture.now, locale: HistoryFixture.locale)

        #expect(
            row.more.prefix(3).map(\.intent)
                == FlagReason.allCases.map { .flagDictationAs(entry.id, $0) })
        #expect(row.more.prefix(3).allSatisfy { !$0.isDestructive })
    }

    @Test("the overflow menu offers a report of this dictation, which sends nothing by itself")
    func offersReport() {
        let entry = HistoryFixture.entry()
        let row = HistoryPresenter.row(
            for: entry, relativeTo: HistoryFixture.now, locale: HistoryFixture.locale)
        let report = row.more.first { $0.title == "Report This Dictation" }

        #expect(report?.intent == .reportDictation(entry.id))
        #expect(report?.isDestructive == false)
    }

    @Test("offers Keep as clip only when clipboard capture is enabled")
    func offersKeepAsClipWhenEnabled() {
        let entry = HistoryFixture.entry("Hello there")
        let page = HistoryPresenter.page(
            for: HistorySnapshot(
                entries: [entry], canKeepAsClip: true, now: HistoryFixture.now),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)
        let row = page.days.first?.rows.first

        #expect(
            row?.more.map(\.title) == [
                "Flag: Wrong Words", "Flag: Formatting", "Flag: Spacing", "Report This Dictation",
                "Keep as clip", "Delete",
            ])
        #expect(row?.more.dropLast().last?.intent == .keepDictationAsClip(entry.id))
    }

}

@Suite("History keeps the promise about retention")
struct HistoryRetentionTests {
    /// A page that would draw a dictation older than the window can break the promise for the store.
    @Test("anything older than the window is not shown")
    func dropsExpiredEntries() {
        let page = HistoryFixture.page(
            entries: [
                HistoryFixture.entry("Kept", daysAgo: 6),
                HistoryFixture.entry("Gone", daysAgo: 9),
            ],
            settings: Settings(transcriptRetentionDays: 7))

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
        let page = HistoryFixture.page(entries: [], settings: Settings(transcriptRetentionDays: 7))
        #expect(
            page.retentionNotice.sentence
                == "Kept on this Mac for 7 days, then deleted. Recordings are never saved.")
        #expect(page.retentionNotice.link.intent == .go(.settings(.privacy)))
    }

    @Test("the notice says text kept always stays until it is deleted")
    func noticeWhenKeptAlways() {
        let page = HistoryFixture.page(entries: [])
        #expect(
            page.retentionNotice.sentence
                == "Kept on this Mac until you delete it. Recordings are never saved.")
    }

    /// The app keeps a recording only until its words land, and the notice says exactly that.
    @Test("the notice says a recording stays only until its words land")
    func noticeWhenAudioIsKept() {
        let page = HistoryFixture.page(
            entries: [], settings: Settings(transcriptRetentionDays: 7), keepsRecordings: true)
        #expect(
            page.retentionNotice.sentence
                == "Kept on this Mac for 7 days, then deleted. A recording stays only until its words land.")
    }

    /// Somebody checking what the app holds should not have to dictate first to find out.
    @Test("the notice is there even when the list is empty")
    func noticeSurvivesAnEmptyList() {
        #expect(!HistoryFixture.page(entries: []).retentionNotice.sentence.isEmpty)
    }

    /// Exactly seven days old is gone: where page and store could differ, the promise decides.
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

    /// The page and the store must give the same answer, so this asserts agreement, not the page alone.
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

    /// An entry that never reached an app has no name to search, and must not block the others.
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
        #expect(never.emptyState?.title == "Nothing dictated yet")
        #expect(never.emptyState?.message == "Every dictation lands here, kept on this Mac.")
        #expect(never.emptyState?.action?.intent == .dictate)

        let expired = HistoryFixture.page(
            entries: [HistoryFixture.entry(daysAgo: 30)], settings: Settings(transcriptRetentionDays: 7))
        #expect(expired.emptyState?.title == "Nothing left to show")
        #expect(expired.emptyState?.message.contains("7 days") == true)
    }

    @Test("before the history is read, the page claims nothing about it")
    func beforeTheFirstReading() {
        let page = HistoryPresenter.page(
            for: HistorySnapshot(entries: [], now: HistoryFixture.now, hasReadHistory: false))
        #expect(page.isReading)
        #expect(page.emptyState == nil)
        #expect(page.days.isEmpty && page.tiles.isEmpty && !page.showsSearch)
        #expect(!HistoryFixture.page(entries: []).isReading)
    }

    @Test("an empty page still has no false day sections")
    func noPhantomSections() {
        #expect(HistoryFixture.page(entries: []).days.isEmpty)
    }
}

@Suite("Which app a dictation went to")
struct HistoryApplicationTests {
    /// The name labels the row; the identifier looks up the icon, and only it cannot answer wrongly.
    @Test("carries the identifier the dictation recorded")
    func carriesTheIdentifier() throws {
        let entry = HistoryFixture.entry(
            application: "Claude", applicationIdentifier: "com.anthropic.claudefordesktop")
        let application = try #require(HistoryPresenter.application(for: entry))

        #expect(application.name == "Claude")
        #expect(application.initial == "C")
        #expect(application.identifier == "com.anthropic.claudefordesktop")
    }

    /// A dictation recorded without an identifier still knows where it went; the icon uses the name.
    @Test("has no identifier for a dictation recorded before they were kept")
    func withoutAnIdentifier() throws {
        let application = try #require(
            HistoryPresenter.application(for: HistoryFixture.entry(application: "Slack")))

        #expect(application.identifier == nil)
    }

    /// Blank is the shape a hand-edited file takes, and an empty string would be asked of LaunchServices.
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

@Suite("Counting a dictation's words")
struct HistoryWordCountTests {
    @Test("counts the same runs a whitespace split does, across every kind of space")
    func matchesSplit() {
        let texts = [
            "", " ", "one", " one  two ", "one\r\ntwo", "tab\tand\u{00A0}nbsp", "ideographic\u{3000}space",
            "e\u{0301}clair and café", "emoji 👩‍👩‍👧 family", "line\u{2028}separator", "trailing\n",
        ]
        for text in texts {
            #expect(
                MainFormatting.words(in: text) == text.split(whereSeparator: \.isWhitespace).count, "\(text)")
        }
    }

    @Test("a day's summary and each row's length agree on the words")
    func summaryAgreesWithRows() {
        let entries = [
            HistoryFixture.entry("one two three", minutesAgo: 1),
            HistoryFixture.entry("four  five", minutesAgo: 2),
        ]
        let day = HistoryFixture.page(entries: entries).days.first
        #expect(day?.summary == "2 dictations · 5 words")
        #expect(day?.rows.map(\.length) == ["3 words", "2 words"])
    }

    @Test("each distinct written word offers a fix carrying that spelling, and the row text is untouched")
    func offersAFixPerWrittenWord() {
        let text = "Ask Nickel, then Nickel's team: Nickel."
        let row = HistoryFixture.page(entries: [HistoryFixture.entry(text)]).days.first?.rows.first

        #expect(row?.text == text)
        #expect(
            row?.fixes.map(\.intent) == [
                .fixWord("Ask"), .fixWord("Nickel"), .fixWord("then"), .fixWord("Nickel's"), .fixWord("team"),
            ])
        #expect(row?.fixes.first?.title == "Fix “Ask”")
    }

    @Test("a token with no letters offers no fix")
    func skipsTokensWithoutLetters() {
        #expect(HistoryPresenter.fixes(for: "42 — 7%").isEmpty)
    }
}
