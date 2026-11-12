// Each selection check keeps or withdraws the armed offer from one read, and a stale or busy check reads nothing.

import Foundation
import Testing
import UttrflowContext

@testable import Uttrflow

@MainActor
@Suite struct SuggestionSelectionPollingTests {
    private static let caret = NSRange(location: 12, length: 0)
    private static let here = FocusedFieldSelection(processIdentifier: 41, elementHash: 900, range: caret)

    private let polling = SuggestionSelectionPolling()

    init() {
        polling.guardrail = ArmedSelectionGuard(expectedRange: Self.caret)
    }

    /// Runs one check with the given read, counting how many reads it made.
    private func check(
        _ answer: FocusedFieldSelectionRead, generation: Int? = nil, isArmed: Bool = true,
        isInserting: Bool = false, isAllowed: Bool = true
    ) async -> (SuggestionSelectionPolling.Verdict, reads: Int) {
        var reads = 0
        let verdict = await polling.check(
            generation: generation ?? polling.generation, isArmed: isArmed, isInserting: isInserting,
            isAllowed: { isAllowed },
            read: {
                reads += 1
                return answer
            })
        return (verdict, reads)
    }

    @Test("the caret where the offer expects it keeps the offer")
    func unchangedCaretKeeps() async {
        let (verdict, reads) = await check(.selection(Self.here))

        #expect(verdict == .keep)
        #expect(reads == 1)
        #expect(!polling.isReadInFlight)
    }

    @Test("a moved caret withdraws the offer")
    func movedCaretWithdraws() async {
        let moved = FocusedFieldSelection(
            processIdentifier: 41, elementHash: 900, range: NSRange(location: 28, length: 0))

        #expect(await check(.selection(moved)).0 == .withdraw)
    }

    @Test("a selection Accessibility cannot name withdraws, and one that timed out keeps")
    func unavailableWithdrawsTimeoutKeeps() async {
        #expect(await check(.unavailable).0 == .withdraw)
        #expect(await check(.timedOut).0 == .keep)
        #expect(!polling.isReadInFlight)
    }

    @Test("a field where suggestions are no longer allowed withdraws without a read")
    func disallowedWithdrawsUnread() async {
        let (verdict, reads) = await check(.selection(Self.here), isAllowed: false)

        #expect(verdict == .withdraw)
        #expect(reads == 0)
    }

    @Test("nothing armed, an insertion under way, or no guard reads nothing")
    func idleChecksReadNothing() async {
        #expect(await check(.unavailable, isArmed: false) == (.keep, 0))
        #expect(await check(.unavailable, isInserting: true) == (.keep, 0))
        polling.guardrail = nil
        #expect(await check(.unavailable) == (.keep, 0))
    }

    @Test("a check from an earlier generation reads nothing")
    func staleGenerationReadsNothing() async {
        let stale = polling.generation
        polling.stop {}
        polling.guardrail = ArmedSelectionGuard(expectedRange: Self.caret)

        #expect(await check(.unavailable, generation: stale) == (.keep, 0))
    }

    @Test("a stop while the read is out voids its answer")
    func stopDuringReadVoidsAnswer() async {
        var reads = 0
        let verdict = await polling.check(
            generation: polling.generation, isArmed: true, isInserting: false, isAllowed: { true },
            read: {
                reads += 1
                polling.stop {}
                return .unavailable
            })

        #expect(verdict == .keep)
        #expect(reads == 1)
        #expect(!polling.isReadInFlight)
    }

    @Test("a check already reading turns the next one away")
    func inFlightReadTurnsAwayAnother() async {
        polling.isReadInFlight = true

        #expect(await check(.unavailable) == (.keep, 0))
    }
}
