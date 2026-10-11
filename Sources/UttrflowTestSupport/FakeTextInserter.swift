// A TextInserting that answers as scripted and records every string it is handed.
public import UttrflowCore
private import Synchronization

/// A ``TextInserting`` that records each string, answers as scripted, and takes the scripted time.
public final class FakeTextInserter: TextInserting, Sendable {
    private struct State: Sendable {
        var outcomes: ScriptedSequence<InsertionAttempt, TextInsertionError>
        var received: [String] = []
        var placedCarets: [Int] = []
    }

    private let state: Mutex<State>
    private let takes: ScriptedDuration

    /// An inserter that answers each insertion with the next of `outcomes`, by default landing by Accessibility.
    public init(
        answering outcomes: ScriptedSequence<InsertionAttempt, TextInsertionError> = ScriptedSequence(
            .success(InsertionAttempt(.accessibility))),
        takes: ScriptedDuration = .instant
    ) {
        state = Mutex(State(outcomes: outcomes))
        self.takes = takes
    }

    /// An inserter that answers every insertion with `outcome`.
    public convenience init(
        _ outcome: ScriptedOutcome<InsertionAttempt, TextInsertionError>, takes: ScriptedDuration = .instant
    ) {
        self.init(answering: ScriptedSequence(outcome), takes: takes)
    }

    public func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        let outcome = state.withLock { state in
            state.received.append(text)
            return state.outcomes.next()
        }
        await takes.elapse()
        return try outcome.resolve()
    }

    /// Records how far back the caret was asked to move, and moves it.
    public func placeCaret(back units: Int) async -> Bool {
        state.withLock { $0.placedCarets.append(units) }
        return true
    }

    /// Every caret move the pipeline asked for, in UTF-16 units back from the end, in order.
    public var placedCarets: [Int] { state.withLock { $0.placedCarets } }

    /// Every string the pipeline asked to have inserted, in order.
    public var received: [String] { state.withLock { $0.received } }
}
