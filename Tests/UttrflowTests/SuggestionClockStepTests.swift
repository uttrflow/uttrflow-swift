import Foundation
import Testing

@testable import Uttrflow

@Suite("Suggestion intervals after a backwards clock step")
struct SuggestionClockStepTests {
    private let beforeStep = Date(timeIntervalSince1970: 1_800_000_000)
    private let futureKeystroke = Date(timeIntervalSince1970: 1_800_003_600)

    @Test("a backwards step withdraws an armed offer")
    func aBackwardsStepWithdrawsAnArmedOffer() {
        #expect(
            SuggestionCoordinator.accessibilityValueChangeAction(
                hasArmedOffer: true, lastKeystroke: futureKeystroke, at: beforeStep)
                == .withdrawAndWake)
    }

    @Test("a backwards step marks an accessibility change as unkeyed")
    func aBackwardsStepMarksAnAccessibilityChangeUnkeyed() {
        #expect(
            SuggestionCoordinator.isUnkeyedAccessibilityChange(
                lastKeyDown: futureKeystroke, at: beforeStep))
    }

    @Test("a backwards step gives prediction a nonnegative elapsed interval")
    func aBackwardsStepClampsPredictionInterval() {
        #expect(
            SuggestionCoordinator.elapsedMilliseconds(since: futureKeystroke, at: beforeStep) == 0)
    }
}
