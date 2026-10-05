// Tests that stopping a suggestion turn discards any wake it queued before stopping.
import Testing

@testable import Uttrflow

@Suite("Suggestion wake state")
struct SuggestionWakeStateTests {
    @Test("stopping mid-turn prevents the queued wake from starting another field read")
    func stopDiscardsQueuedWake() {
        var state = SuggestionWakeState()
        state.start()
        let queued1 = state.queue(.keystroke)
        #expect(queued1)

        state.stop()
        var fieldReads = 0
        if state.takeAfterTurn() != nil { fieldReads += 1 }

        #expect(fieldReads == 0)
        let queued2 = state.queue(.tick)
        #expect(!queued2)
        #expect(state.takeAfterTurn() == nil)
    }

    @Test("a Return stays ahead of a later tick while a turn is running")
    func keepsTheMostUrgentQueuedWake() {
        var state = SuggestionWakeState()
        state.start()
        let queued3 = state.queue(.returnPressed)
        #expect(queued3)
        let queued4 = state.queue(.tick)
        #expect(queued4)
        #expect(state.takeAfterTurn() == .returnPressed)
    }

    @Test("starting the loop clears stopped state and any wake from its previous run")
    func startResetsPendingWake() {
        var state = SuggestionWakeState()
        _ = state.queue(.keystroke)
        state.stop()
        state.start()

        #expect(!state.isStopped)
        #expect(state.takeAfterTurn() == nil)
        let queued5 = state.queue(.tick)
        #expect(queued5)
        #expect(state.takeAfterTurn() == .tick)
    }
}
