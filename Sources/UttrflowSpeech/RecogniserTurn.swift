// A first-come queue for the recogniser, which a caller can leave by being cancelled.
import Synchronization
import UttrflowCore

/// Admits one holder at a time in arrival order; a waiter that is cancelled leaves the queue and throws.
final class RecogniserTurn: Sendable {
    /// Whether the turn is held, and who is waiting for it.
    private struct State {
        var isHeld = false
        var waiting: [(id: Int, continuation: CheckedContinuation<Bool, Never>)] = []
        var nextID = 0
    }

    private let state = Mutex(State())

    /// Waits for the turn, throwing instead when the caller is cancelled before it arrives.
    func take() async throws(SpeechEngineError) {
        let id = state.withLock { state -> Int in
            state.nextID += 1
            return state.nextID
        }
        let admitted = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                let answer = state.withLock { state -> Bool? in
                    // Checked under the lock the handler takes, so a cancel cannot fall between check and queue.
                    if Task.isCancelled { return false }
                    guard state.isHeld else {
                        state.isHeld = true
                        return true
                    }
                    state.waiting.append((id, continuation))
                    return nil
                }
                if let answer { continuation.resume(returning: answer) }
            }
        } onCancel: {
            let leaving = state.withLock { state -> CheckedContinuation<Bool, Never>? in
                guard let index = state.waiting.firstIndex(where: { $0.id == id }) else { return nil }
                return state.waiting.remove(at: index).continuation
            }
            leaving?.resume(returning: false)
        }
        guard admitted else {
            throw .transcriptionFailed(description: "cancelled while an earlier transcription finished")
        }
    }

    /// How many callers are queued for the turn.
    var waitingCount: Int { state.withLock(\.waiting.count) }

    /// Hands the turn to the longest waiter, or frees it when nobody is waiting.
    func release() {
        let next = state.withLock { state -> CheckedContinuation<Bool, Never>? in
            guard !state.waiting.isEmpty else {
                state.isHeld = false
                return nil
            }
            return state.waiting.removeFirst().continuation
        }
        next?.resume(returning: true)
    }
}
