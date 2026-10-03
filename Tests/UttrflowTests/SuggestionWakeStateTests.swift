// Tests that stopping a suggestion turn discards any wake it queued before stopping.
import Testing

@testable import Uttrflow

@Suite("Suggestion wake state")
struct SuggestionWakeStateTests {
    @Test("stopping mid-turn prevents the queued wake from starting another field read")
    func stopDiscardsQueuedWake() {
        var state = SuggestionWakeState()
        state.start()
        #expect(state.queue(.keystroke))

        state.stop()
        var fieldReads = 0
        if state.takeAfterTurn() != nil { fieldReads += 1 }

        #expect(fieldReads == 0)
        #expect(!state.queue(.tick))
        #expect(state.takeAfterTurn() == nil)
    }

    @Test("a Return stays ahead of a later tick while a turn is running")
    func keepsTheMostUrgentQueuedWake() {
        var state = SuggestionWakeState()
        state.start()
        #expect(state.queue(.returnPressed))
        #expect(state.queue(.tick))
        #expect(state.takeAfterTurn() == .returnPressed)
    }

    @Test("starting the loop clears stopped state and any wake from its previous run")
    func startResetsPendingWake() {
        var state = SuggestionWakeState()
        state.queue(.keystroke)
        state.stop()
        state.start()

        #expect(!state.isStopped)
        #expect(state.takeAfterTurn() == nil)
        #expect(state.queue(.tick))
        #expect(state.takeAfterTurn() == .tick)
    }
}
