// Tests for the Insights page: the calendar, the range switch, the figures, and the wait.
import Foundation
import UttrflowHistory
import UttrflowSettings
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    /// One dictation on each of `days` days in a row, so the page has the week of evidence it waits for.
    static func aWeek(
        words: Int = 10, seconds: Int? = nil, days: Int = 7, from first: Int = 0,
        application: String? = "Slack", measured: Bool = true
    ) -> [HistoryEntry] {
        let changes = measured ? RecordedChanges() : nil
        return (first..<(first + days)).map { day in
            let text = String(repeating: "word ", count: words)
            return seconds.map {
                timed(
                    text, seconds: $0, daysAgo: day, application: application, changes: changes)
            }
                ?? HistoryEntry(
                    id: UUID(), text: text, when: now.addingTimeInterval(Double(-day) * 86_400),
                    applicationName: application, changes: changes)
        }
    }

    /// The fixture's calendar with the week starting on Monday, as the region's own does.
    static var mondayFirst: Calendar {
        var calendar = calendar
        calendar.firstWeekday = 2
        return calendar
    }

    /// Settings keeping history for `days` days.
    static func keeping(_ days: Int) -> Settings {
        var settings = Settings.default
        settings.transcriptRetentionDays = days
        return settings
    }

    /// The Insights page over these inputs, with the fixed clock, a Monday-first week and history kept a week.
    static func insights(
        entries: [HistoryEntry] = [],
        settings: Settings = keeping(7),
        range: InsightsRange? = nil,
        calendar: Calendar = mondayFirst
    ) -> InsightsPresentation {
        InsightsPresenter.page(
            for: InsightsSnapshot(entries: entries, settings: settings, range: range, now: now),
            calendar: calendar, locale: locale)
    }
}

@Suite("The calendar's days")
struct InsightsCalendarBucketingTests {
    @Test("one tile per day of the range, oldest first, ending today")
    func oneTilePerDay() throws {
        let week = try #require(HistoryFixture.insights(entries: HistoryFixture.aWeek()).calendar)
        #expect(week.days.count == 7)
        #expect(week.days.last?.isToday == true)
        #expect(week.days.filter(\.isToday).count == 1)
        #expect(week.days.map(\.date) == week.days.map(\.date).sorted())
        #expect(week.days.last?.number == "15")
        #expect(week.days.first?.id == week.days.first?.date)

        let month = try #require(
            HistoryFixture.insights(
                entries: HistoryFixture.aWeek(), settings: HistoryFixture.keeping(30)
            ).calendar)
        #expect(month.days.count == 30)
        #expect(Set(month.days.map(\.id)).count == 30)
        #expect(month.days.first?.number == "17")
        #expect(month.days.last?.number == "15")

        let quarter = try #require(
            HistoryFixture.insights(
                entries: HistoryFixture.aWeek(), settings: HistoryFixture.keeping(90), range: .quarter
            ).calendar)
        #expect(quarter.days.count == 90)
        #expect(Set(quarter.days.map(\.id)).count == 90)
        #expect(
            quarter.days.map(\.number).contains { number in
                quarter.days.filter { $0.number == number }.count > 1
            })
    }

    @Test("an oversized saved retention cannot expand the Insights calendar")
    func oversizedSavedRetentionIsCapped() throws {
        let settings = try JSONDecoder().decode(
            Settings.self,
            from: Data(#"{"transcriptRetentionDays": 100000}"#.utf8))
        let page = HistoryFixture.insights(
            entries: HistoryFixture.aWeek(), settings: settings, range: .quarter)
        let calendar = try #require(page.calendar)

        #expect(settings.transcriptRetentionDays == Settings.maximumFiniteRetentionDays)
        #expect(calendar.days.count <= Settings.maximumFiniteRetentionDays)
        #expect(calendar.days.count == InsightsRange.quarter.days)
    }

    /// Fifty dictations in one afternoon are one tile holding all their words.
    @Test("dictations on the same day add up on one tile")
    func sameDaySums() throws {
        let entries =
            HistoryFixture.aWeek(words: 10)
            + [HistoryFixture.entry("one two three", minutesAgo: 60)]
        let calendar = try #require(HistoryFixture.insights(entries: entries).calendar)
        #expect(calendar.days.last?.words == 13)
        #expect(calendar.days.first?.words == 10)
    }

    /// The day is the calendar's, so a minute either side of midnight lands on different tiles.
    @Test("a dictation is counted on the day it was said, by the calendar's midnight")
    func midnight() throws {
        let startOfToday = HistoryFixture.calendar.startOfDay(for: HistoryFixture.now)
        let late = HistoryEntry(
            id: UUID(), text: "late night words", when: startOfToday.addingTimeInterval(-60),
            applicationName: "Slack")
        let early = HistoryEntry(
            id: UUID(), text: "early", when: startOfToday.addingTimeInterval(60),
            applicationName: "Slack")
        let entries = HistoryFixture.aWeek(words: 1, days: 7, from: 2) + [late, early]
        let calendar = try #require(
            HistoryFixture.insights(
                entries: entries, settings: HistoryFixture.keeping(30), range: .week
            ).calendar)

        #expect(calendar.days[6].words == 1, "today holds only the dictation after midnight")
        #expect(calendar.days[5].words == 3, "yesterday holds the one before")
    }

    /// A gap is information; a missing tile would be a mystery.
    @Test("a day nobody spoke on is a bare tile rather than left out")
    func silentDays() throws {
        let calendar = try #require(
            HistoryFixture.insights(
                entries: HistoryFixture.aWeek(), settings: HistoryFixture.keeping(30)
            ).calendar)
        let silent = calendar.days.filter(\.isSilent)

        #expect(silent.count == 23)
        #expect(silent.allSatisfy { $0.shade == 0 && $0.words == 0 && !$0.usesDeepInk })
        #expect(silent.first?.detail.hasPrefix("No dictation · ") == true)
    }

    @Test("dictations older than the range are not on it")
    func outsideTheRange() throws {
        let entries = HistoryFixture.aWeek(words: 10, days: 20)
        let week = try #require(
            HistoryFixture.insights(
                entries: entries, settings: HistoryFixture.keeping(30), range: .week
            ).calendar)
        #expect(week.days.reduce(0) { $0 + $1.words } == 70)
    }

    @Test("a dictation before the first chart day is excluded from the range figures")
    func beforeFirstChartDay() throws {
        let first = InsightsPresenter.firstDay(
            of: .week, now: HistoryFixture.now, calendar: HistoryFixture.mondayFirst)
        let prior = HistoryFixture.entry("outside", when: first.addingTimeInterval(-1))
        let entries = HistoryFixture.aWeek(words: 1, days: 7, from: 0) + [prior]
        let page = HistoryFixture.insights(
            entries: entries, settings: HistoryFixture.keeping(30), range: .week)
        let chart = try #require(page.calendar)

        #expect(chart.days.reduce(0) { $0 + $1.words } == 7)
        #expect(page.figures.first?.value == "7")
        #expect(page.figures.last?.value == "7 days")
    }
}

@Suite("The calendar's shading")
struct InsightsCalendarShadeTests {
    /// The busiest day is fully teal; a quiet day keeps a floor so it still reads as spoken on.
    @Test("each tile is a share of the busiest day, over a floor")
    func shades() throws {
        var entries = HistoryFixture.aWeek(words: 10)
        entries.append(HistoryFixture.entry(String(repeating: "word ", count: 90)))
        let calendar = try #require(HistoryFixture.insights(entries: entries).calendar)
        let today = try #require(calendar.days.last)
        let quiet = try #require(calendar.days.first)

        #expect(today.words == 100)
        #expect(today.fraction == 1)
        #expect(abs(today.shade - 1) < 1e-9)
        #expect(today.usesDeepInk)
        #expect(quiet.fraction == 0.1)
        #expect(abs(quiet.shade - (0.15 + 0.85 * 0.1)) < 1e-9)
        #expect(!quiet.usesDeepInk)
    }

    /// Between the two inks' limits neither clears 4.5:1 in dark, so a tile steps over that band.
    @Test("no tile is shaded between the page ink's ceiling and the deep ink's floor")
    func deepInk() {
        let day = { (fraction: Double) in
            InsightsCalendarDay(
                date: HistoryFixture.now, number: "1", words: 1, fraction: fraction, isToday: false,
                detail: "")
        }
        let shades = (0...100).map { day(Double($0) / 100) }
        #expect(
            shades.allSatisfy {
                $0.shade <= InsightsCalendarDay.inkCeiling || $0.shade >= InsightsCalendarDay.deepInkFloor
            })
        #expect(shades.allSatisfy { $0.usesDeepInk == ($0.shade >= InsightsCalendarDay.deepInkFloor) })
        #expect(zip(shades, shades.dropFirst()).allSatisfy { $0.shade <= $1.shade })
        #expect(day(0.42).shade == InsightsCalendarDay.inkCeiling)
        #expect(day(0.6).shade == InsightsCalendarDay.deepInkFloor)
        #expect(!day(0.42).usesDeepInk)
        #expect(day(0.6).usesDeepInk)
    }

    @Test("a tile's share and a calendar's blanks are kept in range")
    func clamps() {
        let tile = InsightsCalendarDay(
            date: HistoryFixture.now, number: "1", words: 5, fraction: 3, isToday: false, detail: "")
        #expect(tile.fraction == 1)
        #expect(
            InsightsCalendarDay(
                date: HistoryFixture.now, number: "1", words: 5, fraction: -1, isToday: false,
                detail: ""
            ).fraction == 0)
        #expect(InsightsCalendar(title: "", weekdays: [], leadingBlanks: 9, days: []).leadingBlanks == 6)
        #expect(InsightsCalendar(title: "", weekdays: [], leadingBlanks: -2, days: []).leadingBlanks == 0)
    }

    @Test("the legend steps from less to more")
    func legend() {
        #expect(InsightsCalendar.legend == InsightsCalendar.legend.sorted())
        #expect(InsightsCalendar.legend.count == 4)
    }

    @Test("a tile says how many words, with the thousands grouped")
    func detail() throws {
        let entries =
            HistoryFixture.aWeek(words: 1, from: 1)
            + [HistoryFixture.entry(String(repeating: "word ", count: 1_284))]
        let calendar = try #require(HistoryFixture.insights(entries: entries).calendar)
        #expect(calendar.days.last?.detail.hasPrefix("1,284 words · 15") == true)
        #expect(calendar.days.first?.detail.hasPrefix("1 word · ") == true)
    }
}

@Suite("The calendar's weeks")
struct InsightsCalendarWeekTests {
    /// Sunday 15 June 2025 is today, so a week back starts on Monday 9 June.
    @Test("a week starting on the first weekday needs no blanks")
    func mondayWeek() throws {
        let calendar = try #require(HistoryFixture.insights(entries: HistoryFixture.aWeek()).calendar)
        #expect(calendar.leadingBlanks == 0)
        #expect(calendar.weeks == 1)
        #expect(calendar.weekdays == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(calendar.title == "June")
    }

    @Test("the grid starts on the calendar's own first weekday")
    func sundayFirst() throws {
        var sundayFirst = HistoryFixture.calendar
        sundayFirst.firstWeekday = 1
        let calendar = try #require(
            HistoryFixture.insights(entries: HistoryFixture.aWeek(), calendar: sundayFirst).calendar)
        #expect(calendar.weekdays.first == "S")
        #expect(calendar.leadingBlanks == 1)
        #expect(calendar.weeks == 2)
    }

    /// Thirty days back from 15 June is Saturday 17 May, five cells into a Monday-first week.
    @Test("a month lines its first day up under its weekday and names both months")
    func month() throws {
        let calendar = try #require(
            HistoryFixture.insights(
                entries: HistoryFixture.aWeek(), settings: HistoryFixture.keeping(30)
            ).calendar)
        #expect(calendar.leadingBlanks == 5)
        #expect(calendar.days.first?.number == "17")
        #expect(calendar.weeks == 5)
        #expect(calendar.title == "May – June")
        #expect(
            HistoryFixture.insights(
                entries: HistoryFixture.aWeek(), settings: HistoryFixture.keeping(30)
            ).chartCaption == "70 words · 17 May – 15 June")
    }

    @Test("the chart span keeps its short same-month form")
    func sameMonth() throws {
        let first = try HistoryFixture.date(year: 2025, month: 6, day: 2)
        let last = try HistoryFixture.date(year: 2025, month: 6, day: 15)
        #expect(
            InsightsPresenter.caption(
                words: 70, from: first, to: last, calendar: HistoryFixture.calendar,
                locale: HistoryFixture.locale) == "70 words · 2 – 15 June")
    }

    @Test("the chart span names both months in the fixture locale")
    func crossMonth() throws {
        let first = try HistoryFixture.date(year: 2025, month: 5, day: 17)
        let last = try HistoryFixture.date(year: 2025, month: 6, day: 15)
        #expect(
            InsightsPresenter.caption(
                words: 70, from: first, to: last, calendar: HistoryFixture.calendar,
                locale: HistoryFixture.locale) == "70 words · 17 May – 15 June")
    }

    @Test("the chart span includes the year at both ends across New Year")
    func crossYear() throws {
        let first = try HistoryFixture.date(year: 2024, month: 12, day: 17)
        let last = try HistoryFixture.date(year: 2025, month: 1, day: 15)
        #expect(
            InsightsPresenter.caption(
                words: 70, from: first, to: last, calendar: HistoryFixture.calendar,
                locale: HistoryFixture.locale) == "70 words · 17 December 2024 – 15 January 2025")
    }

    @Test("the chart span follows the requested locale's date order")
    func localeAware() throws {
        let first = try HistoryFixture.date(year: 2025, month: 5, day: 17)
        let last = try HistoryFixture.date(year: 2025, month: 6, day: 15)
        #expect(
            InsightsPresenter.caption(
                words: 70, from: first, to: last, calendar: HistoryFixture.calendar,
                locale: Locale(identifier: "en_US")) == "70 words · May 17 – June 15")
    }

    @Test("a quarter names its first and last months and runs to thirteen weeks")
    func quarter() throws {
        let calendar = try #require(
            HistoryFixture.insights(
                entries: HistoryFixture.aWeek(), settings: HistoryFixture.keeping(90), range: .quarter
            ).calendar)
        #expect(calendar.title == "March – June")
        #expect(calendar.leadingBlanks == 1, "18 March is a Tuesday")
        #expect(calendar.weeks == 13)
    }
}

@Suite("The range switch")
struct InsightsRangeTests {
    @Test("three ranges, in order, each named by its days")
    func ranges() {
        #expect(InsightsRange.allCases.map(\.days) == [7, 30, 90])
        #expect(InsightsRange.allCases.map(\.title) == ["7 days", "30 days", "90 days"])
        #expect(InsightsRange.allCases.map(\.id) == ["7", "30", "90"])
        #expect(InsightsRange(rawValue: "") == nil)
    }

    @Test("a month is shown by default where history reaches that far")
    func defaultIsAMonth() {
        let page = HistoryFixture.insights(
            entries: HistoryFixture.aWeek(), settings: HistoryFixture.keeping(90))
        #expect(page.ranges.filter(\.isSelected).map(\.range) == [.month])
        #expect(page.ranges.allSatisfy { $0.isAvailable })
        #expect(page.ranges.map(\.id) == ["7", "30", "90"])
        #expect(page.ranges.map(\.title) == ["7 days", "30 days", "90 days"])
    }

    @Test("history kept always can show every range")
    func keptAlways() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek(), settings: .default)
        #expect(page.ranges.map(\.isAvailable) == [true, true, true])
    }

    /// History kept for a week has nothing to show further back, so the switch says so.
    @Test("a range beyond what is kept cannot be picked, and says why")
    func beyondRetention() throws {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek(), range: .month)
        #expect(page.ranges.filter(\.isSelected).map(\.range) == [.week])
        #expect(page.ranges.map(\.isAvailable) == [true, false, false])
        let reason = try #require(page.ranges[1].unavailableReason)
        #expect(reason.contains("History is kept for 7 days"))
        #expect(reason.contains("30 days"))
        #expect(page.calendar?.days.count == 7)
    }

    @Test("the picked range is shown when it is in reach")
    func picked() {
        let page = HistoryFixture.insights(
            entries: HistoryFixture.aWeek(), settings: HistoryFixture.keeping(30), range: .week)
        #expect(page.ranges.filter(\.isSelected).map(\.range) == [.week])
        #expect(page.ranges.map(\.isAvailable) == [true, true, false])
    }

    /// A week is always offered, even to history kept for a day, so the switch is never empty.
    @Test("a week is in reach however short the retention")
    func weekAlwaysOffered() {
        for days in [1, 3, 7] {
            #expect(InsightsPresenter.reaches(.week, retention: days))
            #expect(InsightsPresenter.chosen(nil, retention: days) == .week)
        }
        #expect(InsightsPresenter.chosen(.quarter, retention: 30) == .month)
        #expect(InsightsPresenter.chosen(.quarter, retention: 90) == .quarter)
    }
}

@Suite("The figures beside the calendar")
struct InsightsFiguresTests {
    @Test("words, a day, words per minute and the longest streak, in that order")
    func order() {
        let page = HistoryFixture.insights(
            entries: HistoryFixture.aWeek(words: 10, seconds: 10), range: .week)
        #expect(page.figures.map(\.caption) == ["words", "a day", "words / min", "longest streak"])
        #expect(page.figures.map(\.value) == ["70", "10", "60", "7 days"])
    }

    @Test("the words and the daily average are the range's, grouped by thousands")
    func withinTheRange() {
        let entries = HistoryFixture.aWeek(words: 500, days: 20)
        let week = HistoryFixture.insights(
            entries: entries, settings: HistoryFixture.keeping(30), range: .week)
        let month = HistoryFixture.insights(
            entries: entries, settings: HistoryFixture.keeping(30), range: .month)
        #expect(week.figures.prefix(2).map(\.value) == ["3,500", "500"])
        #expect(month.figures.prefix(2).map(\.value) == ["10,000", "333"])
    }

    /// Silent days count, so the average is what a day in the range came to, not a busy day.
    @Test("the daily average divides by every day of the range, to the nearest word")
    func dailyAverage() {
        let entries = HistoryFixture.aWeek(words: 1_000, days: 3)
        #expect(InsightsPresenter.dailyAverage(of: entries.totalWords, over: .week) == 429)
        #expect(InsightsPresenter.dailyAverage(of: entries.totalWords, over: .month) == 100)
        #expect(InsightsPresenter.dailyAverage(of: 0, over: .quarter) == 0)
    }

    /// Words per minute is a dash until something is timed.
    @Test("words per minute is a dash until something is timed")
    func untimedPace() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek())
        #expect(page.figures.first { $0.caption == "words / min" }?.value == "—")
    }

    /// Two runs with a gap between them: the longer, older one is the streak, not the current one.
    @Test("the longest streak is the longest run in the range, not the one that ends today")
    func longestStreak() {
        let entries = HistoryFixture.aWeek(days: 7, from: 1) + HistoryFixture.aWeek(days: 21, from: 20)
        let quarter = HistoryFixture.insights(
            entries: entries, settings: HistoryFixture.keeping(90), range: .quarter)
        #expect(quarter.figures.last?.value == "21 days")
        let month = HistoryFixture.insights(
            entries: entries, settings: HistoryFixture.keeping(90), range: .month)
        #expect(month.figures.last?.value == "10 days", "the older run is cut by the month")
    }

    @Test("several dictations on one day are one day of a streak, and none is no streak")
    func streakCountsDays() {
        let calendar = HistoryFixture.mondayFirst
        let twice = HistoryFixture.aWeek(days: 2) + HistoryFixture.aWeek(days: 2)
        #expect(InsightsPresenter.longestStreak(in: twice, calendar: calendar) == 2)
        #expect(InsightsPresenter.longestStreak(in: [], calendar: calendar) == 0)
    }

    @Test("the header names the page and where its figures come from")
    func chrome() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek())
        #expect(page.chrome.title == "Insights")
        #expect(page.chrome.caption?.hasSuffix("Measured on this Mac.") == true)
        #expect(page.chrome.scope == nil)
        #expect(page.emptyState == nil)
    }
}

@Suite("Insights before there is enough to show")
struct InsightsWaitingTests {
    @Test("before the history is read, there is no empty state and no range switch")
    func beforeTheFirstReading() {
        let page = InsightsPresenter.page(
            for: InsightsSnapshot(now: HistoryFixture.now, hasReadHistory: false))
        #expect(page.emptyState == nil)
        #expect(page.ranges.isEmpty && page.calendar == nil && page.figures.isEmpty)
        #expect(page.chrome.title == "Insights")
    }

    /// A baseline drawn from three days is noise wearing a number's clothes, so the page waits.
    @Test("fewer than seven days of speaking means the calendar waits")
    func waits() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek(days: 2))
        #expect(page.calendar == nil)
        #expect(page.ranges.isEmpty)
        #expect(page.figures.isEmpty)
        #expect(page.emptyState?.title == "Not enough to chart yet")
        #expect(page.chrome.title == "Insights")
    }

    @Test("the wait is measured in days spoken on, not dictations")
    func daysNotDictations() {
        let manyInOneDay = (0..<50).map { _ in HistoryFixture.entry() }
        #expect(HistoryFixture.insights(entries: manyInOneDay).emptyState != nil)
    }

    @Test("a day before the chart range does not complete its seven spoken days")
    func priorDayDoesNotCompleteChartingThreshold() {
        let first = InsightsPresenter.firstDay(
            of: .week, now: HistoryFixture.now, calendar: HistoryFixture.mondayFirst)
        let prior = HistoryFixture.entry("outside", when: first.addingTimeInterval(-1))
        let entries = HistoryFixture.aWeek(days: 6) + [prior]
        let page = HistoryFixture.insights(
            entries: entries, settings: HistoryFixture.keeping(30), range: .week)

        #expect(page.calendar == nil)
        #expect(page.emptyState?.progress?.leading == "6 of 7 days")
    }

    @Test("the progress bar says how far along it is and when it finishes")
    func progress() {
        let empty = HistoryFixture.insights(entries: HistoryFixture.aWeek(days: 2)).emptyState
        #expect(empty?.progress?.leading == "2 of 7 days")
        #expect(empty?.progress?.trailing.hasPrefix("Charts appear on ") == true)
        #expect(empty?.progress?.fraction == 2.0 / 7.0)
        #expect(empty?.progress?.steps == 7)
        #expect(empty?.progress?.stepsDone == 2)
        #expect(empty?.message == "Dictate on 7 different days and your charts appear. 2 of 7 days so far.")
    }

    @Test("a whole week ahead is next week's day, not today's name")
    func aWeekAheadSaysNext() {
        let now = HistoryFixture.now
        let calendar = HistoryFixture.calendar
        let locale = HistoryFixture.locale
        let today = now.formatted(.dateTime.weekday(.wide).locale(locale))
        #expect(
            InsightsPresenter.remaining(spoken: 0, now: now, calendar: calendar, locale: locale)
                == "Charts appear next \(today)")
        #expect(
            InsightsPresenter.remaining(spoken: 1, now: now, calendar: calendar, locale: locale)
                .hasPrefix("Charts appear on "))
    }

    @Test("the remaining-day estimate follows the calendar across spring DST")
    func springDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")
        calendar.locale = locale
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let now = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026, month: 3, day: 7, hour: 23, minute: 30)))
        let expectedDate = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        let expectedWeekday = expectedDate.formatted(.dateTime.weekday(.wide).locale(locale))

        #expect(
            InsightsPresenter.remaining(spoken: 6, now: now, calendar: calendar, locale: locale)
                == "Charts appear on \(expectedWeekday)")
    }

    /// The two numbers that are already true are given rather than withheld.
    @Test("the figures that are honest on day two are given")
    func chips() {
        let empty = HistoryFixture.insights(
            entries: HistoryFixture.aWeek(words: 5, days: 2)
        ).emptyState
        #expect(empty?.chips.map(\.caption) == ["dictations so far", "words so far"])
        #expect(empty?.chips.map(\.value) == ["2", "10"])
    }

    @Test("a Mac that has never dictated has no figures to give")
    func nothingAtAll() {
        let empty = HistoryFixture.insights().emptyState
        #expect(empty?.chips.isEmpty == true)
        #expect(empty?.progress?.fraction == 0)
    }

    @Test("the empty page has no closing line under it")
    func noFootnote() {
        #expect(HistoryFixture.insights().emptyState?.footnote == nil)
    }
}
