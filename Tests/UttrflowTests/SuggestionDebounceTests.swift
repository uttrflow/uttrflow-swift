// Tests that the model debounce counts from the keystroke, not from the work before the pass (#878).

import Foundation
import Testing

@testable import Uttrflow

@Suite("The quiet before a model pass")
struct SuggestionDebounceTests {
    static let key = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a key just pressed waits the whole debounce")
    func freshKeystrokeWaitsInFull() {
        let waiting = SuggestionCoordinator.remainingDebounce(sinceKeystroke: Self.key, now: Self.key)
        #expect(waiting == .milliseconds(SuggestionCoordinator.generationDebounceInMilliseconds))
    }

    @Test("work done since the key comes off the wait")
    func workSinceTheKeyCounts() {
        let now = Self.key.addingTimeInterval(0.05)
        let waiting = SuggestionCoordinator.remainingDebounce(sinceKeystroke: Self.key, now: now)
        #expect(waiting < .milliseconds(SuggestionCoordinator.generationDebounceInMilliseconds))
        #expect(waiting > .zero)
    }

    @Test("a pause already longer than the debounce waits no second time")
    func aLongPauseDoesNotWaitAgain() {
        let now = Self.key.addingTimeInterval(5)
        #expect(SuggestionCoordinator.remainingDebounce(sinceKeystroke: Self.key, now: now) == .zero)
    }

    @Test("a future keystroke waits no longer than a fresh keystroke")
    func futureKeystrokeWaitsNoLongerThanFreshKey() {
        let future = Self.key.addingTimeInterval(3_600)
        #expect(
            SuggestionCoordinator.remainingDebounce(sinceKeystroke: future, now: Self.key)
                == .milliseconds(SuggestionCoordinator.generationDebounceInMilliseconds))
    }

    @Test("A steady typing burst leaves one field snapshot within the three-message-per-key budget")
    func countsMessagesAcrossTypingBurst() {
        var reader = CountingAccessibilityFake()
        let interval = 0.1
        let keys = (0..<8).map { Self.key.addingTimeInterval(Double($0) * interval) }
        var pendingRead: Date?

        for key in keys {
            if let pendingRead,
                SuggestionCoordinator.remainingFieldReadDebounce(sinceKeystroke: pendingRead, now: key) == 0
            {
                reader.readSnapshot()
            }
            pendingRead = key
        }
        if let pendingRead {
            let afterPause = pendingRead.addingTimeInterval(
                Double(SuggestionCoordinator.fieldReadDebounceInMilliseconds) / 1000)
            if SuggestionCoordinator.remainingFieldReadDebounce(sinceKeystroke: pendingRead, now: afterPause)
                == 0
            {
                reader.readSnapshot()
            }
        }

        #expect(reader.snapshots == 1)
        #expect(reader.messages == 24)
        #expect(reader.messages <= keys.count * 3)
    }
}

/// Counts the ordinary field snapshot's bounded Accessibility message allowance without contacting another app.
private struct CountingAccessibilityFake {
    private(set) var messages = 0
    private(set) var snapshots = 0

    mutating func readSnapshot() {
        snapshots += 1
        for _ in 0..<3 { copyAttributeValue() }
        copyMultipleAttributeValues()
        for _ in 0..<8 { copyAttributeValue() }
        for _ in 0..<12 { copyParameterizedAttributeValue() }
    }

    private mutating func copyAttributeValue() { messages += 1 }
    private mutating func copyMultipleAttributeValues() { messages += 1 }
    private mutating func copyParameterizedAttributeValue() { messages += 1 }
}

@Suite("The quiet before a field snapshot")
struct FieldSnapshotDebounceTests {
    static let key = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("The snapshot waits longer than the generation debounce")
    func waitsForTypingToPause() {
        #expect(
            SuggestionCoordinator.fieldReadDebounceInMilliseconds
                > SuggestionCoordinator.generationDebounceInMilliseconds)
        #expect(
            SuggestionCoordinator.remainingFieldReadDebounce(sinceKeystroke: Self.key, now: Self.key)
                == SuggestionCoordinator.fieldReadDebounceInMilliseconds)
    }

    @Test("The last key replaces the older snapshot deadline")
    func latestKeySetsTheDeadline() {
        let key = Self.key.addingTimeInterval(0.1)
        let now = Self.key.addingTimeInterval(0.15)
        #expect(
            SuggestionCoordinator.remainingFieldReadDebounce(sinceKeystroke: key, now: now) == 130)
    }

    @Test("The snapshot is due at the full quiet interval, never early")
    func doesNotReadEarly() {
        let before = Self.key.addingTimeInterval(0.179)
        let due = Self.key.addingTimeInterval(0.180)
        #expect(SuggestionCoordinator.remainingFieldReadDebounce(sinceKeystroke: Self.key, now: before) == 1)
        #expect(SuggestionCoordinator.remainingFieldReadDebounce(sinceKeystroke: Self.key, now: due) == 0)
    }

    @Test("a future keystroke waits only the field-read debounce")
    func futureKeystrokeWaitsOnlyTheFieldReadDebounce() {
        let future = Self.key.addingTimeInterval(3_600)
        #expect(
            SuggestionCoordinator.remainingFieldReadDebounce(sinceKeystroke: future, now: Self.key)
                == SuggestionCoordinator.fieldReadDebounceInMilliseconds)
    }
}

@Suite("The wake-up after a prose pause")
struct SuggestionHesitationWakeTests {
    static let key = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a turn settling right at the last key waits the whole pause")
    func settlingAtTheKeyWaitsTheWholePause() {
        #expect(SuggestionCoordinator.hesitationWake(sinceKeystroke: Self.key, now: Self.key) == 420)
    }

    @Test("a turn started before a later key still wakes 400ms after that key (#1623)")
    func aLaterKeyDoesNotPushTheWakeLater() {
        let now = Self.key.addingTimeInterval(0.1)
        #expect(SuggestionCoordinator.hesitationWake(sinceKeystroke: Self.key, now: now) == 320)
    }

    @Test("a pause already long enough wakes at once")
    func aLongPauseWakesAtOnce() {
        let now = Self.key.addingTimeInterval(2)
        #expect(SuggestionCoordinator.hesitationWake(sinceKeystroke: Self.key, now: now) == 20)
    }

    @Test("a future keystroke gets the normal prose-pause wake")
    func futureKeystrokeGetsNormalProsePauseWake() {
        let future = Self.key.addingTimeInterval(3_600)
        #expect(SuggestionCoordinator.hesitationWake(sinceKeystroke: future, now: Self.key) == 420)
    }
}
