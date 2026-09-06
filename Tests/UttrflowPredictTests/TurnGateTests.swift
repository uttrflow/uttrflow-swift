import Foundation
import Testing

@testable import UttrflowPredict

private let start = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("One turn at a time, and never a dead loop")
struct TurnGateTests {
    @Test("One turn runs, the next waits, and once the first ends the next is admitted.")
    func oneAtATime() {
        var gate = TurnGate()
        #expect(gate.begin(at: start) == .free(1))
        #expect(gate.isRunning)
        #expect(gate.begin(at: start.addingTimeInterval(1)) == .busy)
        let ended = gate.end(1)
        #expect(ended)
        #expect(!gate.isRunning)
        #expect(gate.begin(at: start.addingTimeInterval(2)) == .free(2))
    }

    @Test("A turn that has not come back in time is left behind, and a new one runs in its place.")
    func aStalledTurnIsLeftBehind() {
        var gate = TurnGate()
        #expect(gate.begin(at: start) == .free(1))
        let late = start.addingTimeInterval(TurnGate.stallSeconds)
        #expect(gate.begin(at: late) == .stalled(2))
        #expect(gate.isRunning)
        // The stalled turn ending later changes nothing about the one that replaced it.
        let staleEnded = gate.end(1)
        #expect(!staleEnded)
        #expect(gate.isRunning)
        let currentEnded = gate.end(2)
        #expect(currentEnded)
        #expect(!gate.isRunning)
    }

    @Test("A turn left behind is no longer current, so it can ask before it touches anything.")
    func aStalledTurnIsNotCurrent() {
        var gate = TurnGate()
        _ = gate.begin(at: start)
        #expect(gate.isCurrent(1))
        _ = gate.begin(at: start.addingTimeInterval(TurnGate.stallSeconds))
        #expect(!gate.isCurrent(1))
        #expect(gate.isCurrent(2))
        _ = gate.end(2)
        #expect(!gate.isCurrent(2))
    }

    @Test("Just short of the stall time a running turn is still waited for.")
    func theStallTimeIsHonoured() {
        var gate = TurnGate()
        _ = gate.begin(at: start)
        #expect(gate.begin(at: start.addingTimeInterval(TurnGate.stallSeconds - 0.001)) == .busy)
    }

    @Test("Ending a turn that is not running, or ending twice, is a no-op that says so.")
    func endingTheWrongTurnDoesNothing() {
        var gate = TurnGate()
        let nothingRunning = gate.end(1)
        #expect(!nothingRunning)
        _ = gate.begin(at: start)
        let first = gate.end(1)
        let second = gate.end(1)
        #expect(first)
        #expect(!second)
    }
}
