// Tests for the Insights page: the chart, the figures, the places, the wait, and the average line.
import Foundation
import UttrflowHistory
import UttrflowSettings
import Testing

@testable import UttrflowUX

extension HistoryFixture {
    /// One dictation on each of the last `days` days, so the page has the week of evidence it waits for.
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

    /// The Insights page over these inputs, with the fixed clock and region.
    static func insights(
        entries: [HistoryEntry] = [],
        settings: Settings = .default
    ) -> InsightsPresentation {
        // The page reads only the entries.
        InsightsPresenter.page(
            for: InsightsSnapshot(entries: entries, settings: settings, now: now),
            calendar: calendar, locale: locale)
    }
}

@Suite("Insights once there is a week to compare")
struct InsightsChartTests {
    @Test("one bar per day of the window, oldest first")
    func bars() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek())
        #expect(page.days.count == Settings.defaultRetentionDays)
        #expect(page.days.last?.isToday == true)
        #expect(page.emptyState == nil)
        #expect(page.chartTitle == "Words dictated")
        #expect(page.chartCaption.hasPrefix("70 words · "))
    }

    /// A gap in a bar chart is information; a missing bar is a mystery.
    @Test("a day nobody spoke on is drawn as a silent day rather than left out")
    func silentDays() {
        // A fortnight's window with only the last week spoken on, so half the chart is silent days.
        var settings = Settings.default
        settings.transcriptRetentionDays = 14
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek(), settings: settings)

        #expect(page.days.count == 14)
        #expect(page.days.filter(\.isSilent).count == 7)
        #expect(page.days.prefix(7).filter(\.isSilent).count == 7)
        #expect(page.days.filter(\.isSilent).map(\.words) == Array(repeating: 0, count: 7))
    }

    @Test("each bar is a share of the busiest day")
    func fractions() {
        var entries = HistoryFixture.aWeek(words: 10)
        entries.append(
            HistoryEntry(
                id: UUID(), text: String(repeating: "word ", count: 90),
                when: HistoryFixture.now, applicationName: "Slack"))

        let page = HistoryFixture.insights(entries: entries)
        #expect(page.days.last?.fraction == 1)
        #expect(page.days.allSatisfy { $0.fraction >= 0 && $0.fraction <= 1 })
        #expect(page.days.last?.words == 100)
        #expect(page.days.first?.id == page.days.first?.label)
    }

    /// The window is the user's own retention setting, not this page's to widen, so the control names it.
    @Test("the scope names the window and offers nothing to pick")
    func scope() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek())
        #expect(page.chrome.scope?.title == "Last 7 days")
        #expect(page.chrome.scope?.isSelectable == false)
    }

    @Test("a shorter retention shortens the window")
    func retention() {
        var settings = Settings.default
        settings.transcriptRetentionDays = 30
        let page = HistoryFixture.insights(
            entries: HistoryFixture.aWeek(days: 20), settings: settings)
        #expect(page.days.count == 30)
        #expect(page.chrome.scope?.title == "Last 30 days")
    }
}

@Suite("The figures Insights can vouch for")
struct InsightsFiguresTests {
    /// The "languages you spoke" card and "time saved" tile have no source, so both are absent.
    @Test("nothing is charted that has not been measured")
    func nothingInvented() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek(measured: false))
        #expect(page.figures.isEmpty)
        #expect(page.footnote?.contains("no “time saved” figure") == true)
    }

    @Test("pace appears once something has been timed")
    func pace() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek(words: 10, seconds: 10))
        let figure = page.figures.first { $0.caption == "Words per minute" }
        #expect(figure?.value == "60")
        #expect(figure?.comment == "Days you did not dictate are skipped.")
    }

    /// A line that dives to the floor because nobody spoke would read as the user getting worse.
    @Test("the pace trend has a point per day that had one, oldest first")
    func trend() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek(seconds: 10))
        #expect(page.paceTrend.count == 7)
        #expect(HistoryFixture.insights(entries: HistoryFixture.aWeek()).paceTrend.isEmpty)
    }

    @Test("accuracy appears once something records what was changed")
    func accuracy() {
        let page = HistoryFixture.insights(
            entries: (0..<7).map { day in
                HistoryFixture.measured(
                    "Word word word", spokenWords: 4,
                    changes: [HistoryFixture.change("word", "Word", over: 0..<1)], daysAgo: day)
            })

        let figure = page.figures.first { $0.caption == "Accuracy" }
        #expect(figure?.value == "75.0%")
        #expect(figure?.meters.map(\.label) == ["Now"])
        // The page borrows the Dictation page's wording, so one arithmetic is described one way.
        #expect(figure?.comment == DictationPresenter.accuracyCaption)
    }

    @Test("no record of changes means no accuracy figure")
    func accuracyNeedsARecord() {
        let page = HistoryFixture.insights(
            entries: HistoryFixture.aWeek(seconds: 10, measured: false))
        #expect(!page.figures.contains { $0.caption == "Accuracy" })
    }
}

@Suite("Where the words went")
struct InsightsPlacesTests {
    @Test("the apps are listed busiest first, as shares of what is known")
    func places() {
        let entries =
            HistoryFixture.aWeek(days: 6, from: 0, application: "Slack")
            + HistoryFixture.aWeek(days: 2, from: 5, application: "Code")
        let page = HistoryFixture.insights(entries: entries)

        #expect(page.places.map(\.application.name) == ["Slack", "Code"])
        #expect(page.places.first?.percentage == "75%")
        #expect(page.places.map(\.share).reduce(0, +) == 1)
        #expect(page.places.first?.id == "Slack")
    }

    /// Left out of the total as well as the list, so the shares are of what is actually known.
    @Test("a dictation that went nowhere known is not counted")
    func unknownDestination() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek(application: nil))
        #expect(page.places.isEmpty)
    }

    @Test("a blank application name is no name at all")
    func blankName() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek(application: "   "))
        #expect(page.places.isEmpty)
    }
}

@Suite("Insights before there is enough to chart")
struct InsightsWaitingTests {
    /// A baseline drawn from three days is noise wearing a number's clothes, so the page waits.
    @Test("fewer than seven days of speaking means the charts wait")
    func waits() {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek(days: 2))
        #expect(page.days.isEmpty)
        #expect(page.figures.isEmpty)
        #expect(page.places.isEmpty)
        #expect(page.chartCaption.isEmpty)
        #expect(page.footnote == nil)
        #expect(page.emptyState?.title == "Not enough to chart yet")
    }

    @Test("the wait is measured in days spoken on, not dictations")
    func daysNotDictations() {
        let manyInOneDay = (0..<50).map { _ in HistoryFixture.entry() }
        #expect(HistoryFixture.insights(entries: manyInOneDay).emptyState != nil)
    }

    @Test("the progress bar says how far along it is and when it finishes")
    func progress() {
        let empty = HistoryFixture.insights(entries: HistoryFixture.aWeek(days: 2)).emptyState
        #expect(empty?.progress?.leading == "2 of 7 days")
        #expect(empty?.progress?.trailing.hasPrefix("Charts appear on ") == true)
        #expect(empty?.progress?.fraction == 2.0 / 7.0)
        #expect(empty?.message.contains("Uttrflow has 2.") == true)
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

    @Test("the closing line says the rest is waiting rather than missing")
    func footnote() {
        #expect(
            HistoryFixture.insights().emptyState?.footnote?.contains("rather than guessing")
                == true)
    }
}

@Suite("The line a bar means something against")
struct InsightsAverageTests {
    /// A column of bars answers "which day was biggest"; the average turns each bar into a statement.
    @Test("averages the words across every charted day")
    func averagesTheWindow() throws {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek())
        let average = try #require(page.average)
        let total = page.days.reduce(0) { $0 + $1.words }

        #expect(average.words == Int((Double(total) / Double(page.days.count)).rounded()))
        #expect(average.label.hasSuffix("a day"))
    }

    /// Silent days count; dropping them would flatter the figure into "your average dictating day".
    @Test("counts the silent days in the average")
    func silentDaysCount() throws {
        // A month with one week of dictating in it, since the chart needs seven spoken days to appear.
        var settings = Settings.default
        settings.transcriptRetentionDays = 30
        let page = HistoryFixture.insights(
            entries: HistoryFixture.aWeek(words: 20, days: 7), settings: settings)
        let average = try #require(page.average)
        let spoken = page.days.filter { !$0.isSilent }
        let acrossSpokenOnly = spoken.reduce(0) { $0 + $1.words } / max(spoken.count, 1)

        #expect(spoken.count == 7)
        #expect(page.days.count == 30, "the window is the retention setting")
        #expect(acrossSpokenOnly == 20, "each day spoken on had twenty words")
        // The whole window averages far lower than the week inside it: a quiet month reads as quiet.
        #expect(average.words < acrossSpokenOnly)
        #expect(average.words == Int((20.0 * 7 / 30).rounded()))
    }

    /// The tallest bar is `fraction == 1`, so the line is measured against that day, not an invented scale.
    @Test("sits on the same scale as the bars")
    func sharesTheBarsScale() throws {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek())
        let average = try #require(page.average)

        #expect(average.fraction > 0 && average.fraction <= 1)
        #expect(page.days.contains { $0.fraction >= average.fraction })
    }

    @Test("there is no line before there is a chart")
    func noneBeforeTheChart() {
        #expect(HistoryFixture.insights().average == nil)
    }
}

@Suite("How much was said where")
struct InsightsPlaceWordsTests {
    /// The share says how the day was divided; the count says how much of it there was.
    @Test("each place carries the words said in it, not only its share")
    func placesCarryWords() throws {
        let page = HistoryFixture.insights(entries: HistoryFixture.aWeek())
        let place = try #require(page.places.first)

        #expect(place.words.hasSuffix("words") || place.words.hasSuffix("word"))
        #expect(place.words.first?.isNumber == true)
    }
}
