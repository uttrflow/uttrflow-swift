// Tests for kept recordings on the Dictation page.
import Foundation
import UttrflowCore
import Testing

@testable import UttrflowUX

/// A recording whose words were lost sits in today's list until it is retried or deleted.
@Suite("Dictation page: kept recordings")
struct MainDictationRecordingTests {
    private let recording = KeptRecording(
        id: UUID(), when: HistoryFixture.now.addingTimeInterval(-300), duration: .seconds(14))

    private func page(
        recordings: [KeptRecording], retrying: UUID? = nil, query: String = "",
        permissions: [PermissionKind: PermissionStatus] = [.microphone: .granted, .accessibility: .granted]
    ) -> DictationPresentation {
        DictationPresenter.page(
            for: DictationSnapshot(
                permissions: permissions,
                entries: [HistoryFixture.timed("Hello there.", seconds: 3, minutesAgo: 60)],
                query: query, shortcut: "⌥Space", recordings: recordings, retrying: retrying,
                now: HistoryFixture.now),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)
    }

    @Test("a waiting recording is the first row, with Retry in full and Delete in the menu")
    func waitingRecordingIsARow() throws {
        let rows = page(recordings: [recording]).rows
        #expect(rows.count == 2)
        let row = try #require(rows.first)
        #expect(row.id == recording.id)
        #expect(row.status == .waiting)
        #expect(row.text == "Couldn’t turn this into text")
        #expect(row.detail == "14s")
        #expect(row.application == nil)
        #expect(row.actions.isEmpty)
        #expect(row.prominent?.intent == .retryRecording(recording.id))
        #expect(row.more.map(\.intent) == [.forgetRecording(recording.id)])
        #expect(row.more.first?.isDestructive == true)
        #expect(rows.last?.status == nil)
    }

    @Test("the recording being retried says so and offers nothing until it is done")
    func retryingRecordingSaysSo() throws {
        let row = try #require(page(recordings: [recording], retrying: recording.id).rows.first)
        #expect(row.status == .retrying)
        #expect(row.text == "Transcribing…")
        #expect(row.prominent == nil)
        #expect(row.more.isEmpty)
    }

    @Test("a recording alone is enough to fill the page")
    func recordingAlonePreventsTheEmptyState() {
        let page = DictationPresenter.page(
            for: DictationSnapshot(
                permissions: [.microphone: .granted, .accessibility: .granted],
                shortcut: "⌥Space", recordings: [recording], now: HistoryFixture.now),
            calendar: HistoryFixture.calendar, locale: HistoryFixture.locale)
        #expect(page.emptyState == nil)
        #expect(page.rows.map(\.id) == [recording.id])
    }

    @Test("a search is a search of words, so recordings drop out of it")
    func searchHidesRecordings() {
        #expect(page(recordings: [recording], query: "Hello").rows.allSatisfy { $0.status == nil })
    }

    @Test("a blocked page lists nothing, recordings included")
    func blockedHidesRecordings() {
        let page = page(recordings: [recording], permissions: [.microphone: .denied])
        #expect(page.blocked != nil)
        #expect(page.rows.isEmpty)
    }

    @Test("the badge names each state in words a user would use")
    func statusWording() {
        #expect(DictationRowStatus.waiting.rawValue == "Not transcribed")
        #expect(DictationRowStatus.retrying.rawValue == "Retrying…")
    }

    @Test("the recovery that points at the list reads as a retry everywhere it is drawn")
    func retryFromRecordingIsARetry() {
        #expect(FailurePresenter.symbolName(for: .retryFromRecording) == "arrow.clockwise")
        #expect(FailurePresenter.title(for: .retryFromRecording) == "Retry")
        #expect(MainPresenter.title(for: .retryFromRecording) == "Retry")
        #expect(
            MenuBarPresenter.menuTitle(for: FailureAction(title: "Retry", recovery: .retryFromRecording))
                == "Retry")
    }
}
