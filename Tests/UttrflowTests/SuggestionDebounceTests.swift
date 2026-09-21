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
}
