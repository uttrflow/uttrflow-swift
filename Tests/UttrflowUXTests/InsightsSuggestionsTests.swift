import Foundation
import Testing

@testable import UttrflowUX

@Suite("Suggestion counts in Insights")
struct InsightsSuggestionsTests {
    @Test("the suggestions group presents each stored corpus count")
    func presentsCounts() {
        let counts = SuggestionCounts(entries: 23, uses: 41, accepted: 12, rejected: 9, selfSourced: 7)
        let page = InsightsPresenter.page(
            for: InsightsSnapshot(
                entries: HistoryFixture.aWeek(), settings: HistoryFixture.keeping(30),
                now: HistoryFixture.now, suggestionCounts: counts),
            calendar: HistoryFixture.mondayFirst, locale: HistoryFixture.locale)

        #expect(
            page.suggestionFigures?.map(\.caption) == [
                "Stored lines", "Recorded uses", "Accepted", "Typed past", "Self-sourced",
            ])
        #expect(page.suggestionFigures?.map(\.value) == ["23", "41", "12", "9", "7"])
    }

    @Test("suggestion counts remain visible before the dictation chart has a week")
    func appearsWithoutChart() {
        let page = InsightsPresenter.page(
            for: InsightsSnapshot(
                entries: [], settings: HistoryFixture.keeping(30), now: HistoryFixture.now,
                suggestionCounts: SuggestionCounts(
                    entries: 2, uses: 3, accepted: 1, rejected: 1, selfSourced: 1)),
            calendar: HistoryFixture.mondayFirst, locale: HistoryFixture.locale)

        #expect(page.calendar == nil)
        #expect(page.emptyState != nil)
        #expect(page.suggestionFigures?.count == 5)
    }

    @Test("the suggestions group is absent when suggestions are off")
    func hiddenWhenOff() {
        let page = InsightsPresenter.page(
            for: InsightsSnapshot(
                entries: HistoryFixture.aWeek(), settings: HistoryFixture.keeping(30),
                now: HistoryFixture.now),
            calendar: HistoryFixture.mondayFirst, locale: HistoryFixture.locale)

        #expect(page.suggestionFigures == nil)
    }
}
