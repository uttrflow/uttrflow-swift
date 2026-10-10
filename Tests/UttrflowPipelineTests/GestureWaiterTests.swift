// Tests that a gesture the controller will never handle still answers the caller waiting on it.
import Testing

@testable import UttrflowPipeline

private typealias Gesture = DictationController<ContinuousClock>.Gesture

@Suite("Orphaned gesture waiters")
struct GestureWaiterTests {
    @Test("A control command nobody will handle answers that nothing is recording")
    func controlIsAnswered() async {
        let outcome = await withCheckedContinuation { handled in
            Gesture.control(.stop, handled).releaseWaiter()
        }
        #expect(outcome == .nothingRecording)
    }

    @Test("Every gesture that carries a waiter resumes it")
    func everyWaiterResumes() async {
        let waiters: [(CheckedContinuation<Void, Never>) -> Gesture] = [
            { .drained($0) }, { .reached($0) }, { .activation(.holdToTalk, $0) },
            { .handsFree(true, $0) }, { .sessionEnding($0) },
        ]
        for makeGesture in waiters {
            await withCheckedContinuation { handled in makeGesture(handled).releaseWaiter() }
        }
    }

    @Test("A gesture that carries no waiter is left alone")
    func plainGesturesAreIgnored() {
        Gesture.settled(1).releaseWaiter()
        Gesture.limitReached(1).releaseWaiter()
        Gesture.silenceReached(1).releaseWaiter()
    }
}
