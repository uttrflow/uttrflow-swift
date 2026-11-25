// Tests that every learned word is held for Undo, said once, and offered in the popover.

import Foundation
import Testing
import UttrflowDictionary
import UttrflowUX

@Suite("Recently learned words")
struct RecentlyLearnedTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("a learned word is said once and gets one popover row with Undo")
    func oneWordOneRowOneLine() {
        var learned = RecentlyLearned()
        let entry = DictionaryEntry(word: "Kubernetes", origin: .learned, firstSeen: now)

        let learnt = learned.record([entry], at: now)
        let rows = MenuBarPresenter.present(MenuBarState(learned: learned.current(at: now))).learned

        #expect(RecentlyLearned.announcement(for: learnt) == "Learned “Kubernetes” from a correction.")
        #expect(rows.count == 1)
        #expect(rows.first?.undo.intent == .undoLearnedWord(id: entry.id))
        #expect(rows.first?.undo.title == "Undo")
    }

    @Test("two words in one dictation give two rows, and a word from the screen says so")
    func everyWordIsOffered() {
        var learned = RecentlyLearned()
        let corrected = DictionaryEntry(word: "Aarav", origin: .learned, firstSeen: now)
        let seen = DictionaryEntry(word: "Grafana", origin: .observed, firstSeen: now)

        let learnt = learned.record([corrected, seen], at: now)
        let rows = MenuBarPresenter.present(MenuBarState(learned: learned.current(at: now))).learned

        #expect(rows.map(\.word) == ["Aarav", "Grafana"])
        #expect(rows.map(\.source) == ["from a correction", "from the screen"])
        #expect(
            RecentlyLearned.announcement(for: learnt)
                == "Learned “Aarav” from a correction. 1 more word in the menu bar.")
    }

    @Test("a word the user added or the build shipped is not news")
    func onlyInferredWordsAreHeld() {
        var learned = RecentlyLearned()
        let added = DictionaryEntry(word: "Mine", origin: .added, firstSeen: now)

        #expect(learned.record([added], at: now).isEmpty)
        #expect(RecentlyLearned.announcement(for: []) == nil)
    }

    @Test("undoing a word drops its row, and a word leaves after the holding period")
    func forgetsAndExpires() {
        var learned = RecentlyLearned()
        let first = DictionaryEntry(word: "Alpha", origin: .learned, firstSeen: now)
        let second = DictionaryEntry(word: "Beta", origin: .observed, firstSeen: now)
        learned.record([first, second], at: now)

        learned.forget(first.id)

        #expect(learned.current(at: now).map(\.id) == [second.id])
        let later = now.addingTimeInterval(RecentlyLearned.holdingPeriod)
        #expect(learned.current(at: later).isEmpty)
    }

    @Test("a dictation in progress greys Undo, which would race it")
    func undoWaitsForDictation() {
        var learned = RecentlyLearned()
        learned.record([DictionaryEntry(word: "Alpha", origin: .learned, firstSeen: now)], at: now)

        let rows = MenuBarPresenter.present(
            MenuBarState(activity: .listening, learned: learned.current(at: now))
        ).learned

        #expect(rows.first?.undo.isEnabled == false)
    }

    @Test("a corrected word keeps what it replaced and where; a word from the screen has no pair")
    func keepsThePair() {
        var learned = RecentlyLearned()
        let corrected = DictionaryEntry(word: "Priya", origin: .learned, firstSeen: now)
        let seen = DictionaryEntry(word: "Grafana", origin: .observed, firstSeen: now)

        learned.record([corrected, seen], at: now, heard: "pree-ya", application: "Notes")

        #expect(learned.words.map(\.heard) == ["pree-ya", nil])
        #expect(learned.words.map(\.application) == ["Notes", "Notes"])
    }

    @Test("the Dictionary page lists each learnt word with an Undo that forgets it")
    func pageListsLearntWords() throws {
        var learned = RecentlyLearned()
        let corrected = DictionaryEntry(word: "Priya", origin: .learned, firstSeen: now)
        let seen = DictionaryEntry(word: "Grafana", origin: .observed, firstSeen: now)
        learned.record([corrected, seen], at: now, heard: "pree-ya", application: "Notes")
        let calendar = Calendar(identifier: .gregorian)

        let page = DictionaryPresenter.page(
            for: DictionarySnapshot(
                entries: [corrected, seen], now: now.addingTimeInterval(600),
                learnt: learned.current(at: now)),
            calendar: calendar, locale: Locale(identifier: "en_US"))

        let section = try #require(page.recentlyLearnt)
        #expect(section.title == "Recently learnt")
        #expect(section.rows.map(\.word) == ["Priya", "Grafana"])
        #expect(section.rows.first?.detail == "heard “pree-ya”, wrote “Priya”")
        #expect(section.rows.last?.detail == "Read off the screen and said")
        #expect(section.rows.first?.place.hasPrefix("Notes · Today ") == true)
        #expect(section.rows.first?.undo.title == "Undo")
        #expect(section.rows.first?.undo.intent == .forgetWords([corrected.id]))
    }

    @Test("a word no longer in the dictionary, a search, or nothing learnt leaves the list out")
    func pageOmitsTheListWhenThereIsNothingToUndo() {
        var learned = RecentlyLearned()
        let entry = DictionaryEntry(word: "Priya", origin: .learned, firstSeen: now)
        learned.record([entry], at: now)
        let calendar = Calendar(identifier: .gregorian)
        let locale = Locale(identifier: "en_US")

        let gone = DictionaryPresenter.page(
            for: DictionarySnapshot(now: now, learnt: learned.current(at: now)), calendar: calendar,
            locale: locale)
        let searching = DictionaryPresenter.page(
            for: DictionarySnapshot(
                entries: [entry], query: "pri", now: now, learnt: learned.current(at: now)),
            calendar: calendar, locale: locale)
        let none = DictionaryPresenter.page(
            for: DictionarySnapshot(entries: [entry], now: now), calendar: calendar, locale: locale)

        #expect(gone.recentlyLearnt == nil)
        #expect(searching.recentlyLearnt == nil)
        #expect(none.recentlyLearnt == nil)
    }
}
