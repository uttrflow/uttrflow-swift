// The History page's time rail: day summaries, row details and actions, lost recordings, and the stat tiles.
import Foundation
import UttrflowCore
import UttrflowHistory
import UttrflowSettings
import Testing

@testable import UttrflowUX

/// A lost recording at the fixed clock.
private func recording(minutesAgo: Int, seconds: Int = 6) -> KeptRecording {
    KeptRecording(
        id: UUID(), when: HistoryFixture.now.addingTimeInterval(Double(-minutesAgo) * 60),
        duration: .seconds(seconds))
}

/// The History page with recordings and playback state as well as entries.
private func page(
    entries: [HistoryEntry], recordings: [KeptRecording] = [], query: String = "",
    retrying: UUID? = nil, playing: UUID? = nil
) -> HistoryPresentation {
    HistoryPresenter.page(
        for: HistorySnapshot(
            entries: entries, query: query, recordings: recordings, retrying: retrying,
            playing: playing, now: HistoryFixture.now),
        calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)
}

@Suite("History's time rail")
struct HistoryRailPresentationTests {
    @Test("a day says how many dictations and words it holds")
    func daySummary() {
        let result = page(entries: [
            HistoryFixture.entry("One two three", minutesAgo: 2),
            HistoryFixture.entry("Four", minutesAgo: 9),
        ])
        #expect(result.days.first?.summary == "2 dictations · 4 words")
    }

    @Test("a single dictation of a single word is not written in the plural")
    func daySummarySingular() {
        let result = page(entries: [HistoryFixture.entry("Hello", minutesAgo: 2)])
        #expect(result.days.first?.summary == "1 dictation · 1 word")
    }

    @Test("a row is stamped on the 24-hour clock and measured in words")
    func rowTimeAndLength() {
        let row = page(entries: [HistoryFixture.entry("Two words", minutesAgo: 0)]).days[0].rows[0]
        #expect(row.time == "15:20")
        #expect(row.length == "2 words")
    }

    @Test("a timed dictation gives its length on a clock before the words")
    func timedLength() {
        let entry = HistoryEntry(
            text: "Hi there", when: HistoryFixture.now, spokenFor: .seconds(9))
        #expect(HistoryPresenter.length(of: entry) == "0:09 · 2 words")
    }

    @Test("an out-of-range stored duration leaves the words visible without a clock")
    func outOfRangeDuration() {
        let duration = Duration.seconds(Int64.max)
        let entry = HistoryEntry(text: "Hi there", when: HistoryFixture.now, spokenFor: duration)
        #expect(HistoryPresenter.clock(duration) == "—")
        #expect(HistoryPresenter.length(of: entry) == "2 words")
    }

    @Test("a clock writes minutes and two-digit seconds")
    func clock() {
        #expect(HistoryPresenter.clock(.seconds(6)) == "0:06")
        #expect(HistoryPresenter.clock(.seconds(760)) == "12:40")
        #expect(HistoryPresenter.clock(.seconds(-3)) == "0:00")
    }

    @Test("only a changed dictation carries a tag")
    func tagOnlyWhenChanged() {
        let changed = RecordedChanges(
            corrections: [
                RecordedCorrection(
                    heard: "tha", wrote: "the", wordRange: 0..<1, entryID: UUID(),
                    reason: .heardAsStrayLetters, heardConfidence: 0.3)
            ])
        let result = page(entries: [
            HistoryFixture.entry("Changed", minutesAgo: 1, changes: changed),
            HistoryFixture.entry("As said", minutesAgo: 2),
            HistoryFixture.entry("Unmeasured", minutesAgo: 3, changes: nil),
        ])
        #expect(result.days[0].rows.map(\.tag) == ["1 change", nil, nil])
    }

    @Test("a row offers copy, copy to paste elsewhere and flag, and report and delete in its menu")
    func rowActions() {
        let entry = HistoryFixture.entry("Hello", isFlagged: true)
        let row = page(entries: [entry]).days[0].rows[0]
        #expect(row.actions.map(\.title) == ["Copy", "Copy to Paste Elsewhere", "Unflag"])
        #expect(row.actions.map(\.intent) == [.copy("Hello"), .copy("Hello"), .flagDictation(entry.id)])
        #expect(row.isFlagged)
        #expect(
            row.more.map(\.intent)
                == FlagReason.allCases.map { .flagDictationAs(entry.id, $0) }
                + [.reportDictation(entry.id), .forgetDictation(entry.id)])
        #expect(row.recording == nil)
    }

    @Test("an unflagged row offers to flag")
    func flagOffer() {
        let row = page(entries: [HistoryFixture.entry()]).days[0].rows[0]
        #expect(row.actions.last?.title == "Flag")
        #expect(!row.isFlagged)
    }
}

@Suite("History's lost recordings")
struct HistoryRecordingRowTests {
    @Test("a recording sits among the day's dictations by its time, and counts as one")
    func interleaved() {
        let lost = recording(minutesAgo: 5)
        let result = page(
            entries: [
                HistoryFixture.entry("Newer", minutesAgo: 1),
                HistoryFixture.entry("Older", minutesAgo: 10),
            ],
            recordings: [lost])
        #expect(result.days[0].rows.map(\.id)[1] == lost.id)
        #expect(result.days[0].summary == "3 dictations · 2 words")
    }

    @Test("a recording older than every dictation goes last")
    func appendedWhenOldest() {
        let lost = recording(minutesAgo: 50)
        let result = page(entries: [HistoryFixture.entry(minutesAgo: 1)], recordings: [lost])
        #expect(result.days[0].rows.last?.id == lost.id)
    }

    @Test("a recording alone still makes a day, and no empty state")
    func recordingAlone() {
        let result = page(entries: [], recordings: [recording(minutesAgo: 3)])
        #expect(result.days.count == 1)
        #expect(result.emptyState == nil)
        #expect(result.tiles.isEmpty)
    }

    @Test("a waiting recording offers play and retry, and delete in its menu")
    func waiting() throws {
        let lost = recording(minutesAgo: 3)
        let row = page(entries: [], recordings: [lost]).days[0].rows[0]
        let parts = try #require(row.recording)
        #expect(parts.duration == "0:06")
        #expect(parts.message == "Couldn’t turn this into text")
        #expect(parts.play.intent == .playRecording(lost.id))
        #expect(parts.play.title == "Play Recording")
        #expect(!parts.isPlaying)
        #expect(parts.retry?.intent == .retryRecording(lost.id))
        #expect(row.more.map(\.intent) == [.forgetRecording(lost.id)])
        #expect(row.application == nil)
        #expect(row.actions.isEmpty)
    }

    @Test("a recording being retried says so and offers nothing to press again")
    func retrying() throws {
        let lost = recording(minutesAgo: 3)
        let row = page(entries: [], recordings: [lost], retrying: lost.id).days[0].rows[0]
        let parts = try #require(row.recording)
        #expect(parts.message == "Transcribing…")
        #expect(parts.retry == nil)
        #expect(row.more.isEmpty)
    }

    @Test("a playing recording offers to stop")
    func playing() throws {
        let lost = recording(minutesAgo: 3)
        let row = page(entries: [], recordings: [lost], playing: lost.id).days[0].rows[0]
        let parts = try #require(row.recording)
        #expect(parts.isPlaying)
        #expect(parts.play.title == "Stop")
        #expect(parts.play.intent == .playRecording(lost.id))
    }

    @Test("a search leaves recordings out, since they have no words to match")
    func searchSkipsRecordings() {
        let result = page(
            entries: [HistoryFixture.entry("Lunch plans", minutesAgo: 1)],
            recordings: [recording(minutesAgo: 3)], query: "lunch")
        #expect(result.days[0].rows.map(\.text) == ["Lunch plans"])
    }
}

@Suite("History's header")
struct HistoryHeaderTests {
    @Test("the stat tiles are home's four, drawn once anything is kept")
    func tiles() {
        let result = page(entries: [HistoryFixture.entry("Hello there")])
        #expect(result.tiles.map(\.kind) == [.wordsToday, .streak, .pace, .leftAsDictated])
        #expect(result.tiles.first?.value == "2")
        #expect(page(entries: []).tiles.isEmpty)
    }

    @Test("the caption's phrase says how long dictations are kept")
    func phrase() {
        var settings = Settings.default
        settings.transcriptRetentionDays = 30
        let result = HistoryFixture.page(entries: [], settings: settings)
        #expect(result.retentionNotice.phrase == "kept for 30 days")
        #expect(result.retentionNotice.link.intent == .go(.settings(.privacy)))
    }

    @Test("the caption's phrase says dictations kept always stay until deleted")
    func phraseWhenKeptAlways() {
        let result = HistoryFixture.page(entries: [])
        #expect(result.retentionNotice.phrase == "kept until you delete it")
    }
}
