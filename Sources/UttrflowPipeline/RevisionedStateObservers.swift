// Delivers pipeline state with ordering for observers that must discard pre-boundary events.
import Foundation
private import Synchronization

/// A pipeline state transition and the generation it belongs to.
public typealias DictationStateSnapshot = (revision: UInt64, state: DictationState, generation: Int)

/// Keeps ordinary and revisioned observers on the same transition sequence.
final class RevisionedStateObservers: Sendable {
    private let latest = Mutex((revision: UInt64(0), state: DictationState.idle, generation: 0))
    private let states = StateObservers<DictationState>()
    private let revisionedStates = StateObservers<DictationStateSnapshot>()

    /// The latest emitted state and its revision, read atomically.
    var currentSnapshot: DictationStateSnapshot { latest.withLock { $0 } }

    /// A stream of states beginning with the pipeline's current state.
    func states(startingWith state: DictationState) -> AsyncStream<DictationState> {
        states.makeStream(startingWith: state)
    }

    /// A stream of state revisions beginning with the latest emitted snapshot.
    func statesWithRevisions() -> AsyncStream<DictationStateSnapshot> {
        revisionedStates.makeStream(startingWith: currentSnapshot)
    }

    /// Reserves a generation before work can emit a measurement or await a state transition.
    func updateGeneration(_ generation: Int) {
        latest.withLock { $0.generation = generation }
    }

    /// Publishes one state to both observer streams with a shared revision.
    func send(_ state: DictationState, generation: Int) {
        let snapshot = latest.withLock { current -> DictationStateSnapshot in
            let next = (revision: current.revision + 1, state: state, generation: generation)
            current = next
            return next
        }
        states.send(state)
        revisionedStates.send(snapshot)
    }
}

extension DictationPipeline {
    /// The latest state and revision, read atomically by consumers establishing a boundary.
    nonisolated public var currentStateSnapshot: DictationStateSnapshot { observers.currentSnapshot }

    /// Every state with its revision, so a consumer can discard events emitted before a boundary.
    public func statesWithRevisions() -> AsyncStream<DictationStateSnapshot> {
        observers.statesWithRevisions()
    }
}
