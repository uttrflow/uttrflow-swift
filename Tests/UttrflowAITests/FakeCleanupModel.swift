import Synchronization

@testable import UttrflowAI
@testable import UttrflowCore

// A scripted cleanup model and a scripted transformer for the tests in this module.
/// A language model that returns whatever a test scripts.
final class FakeCleanupModel: CleanupModel {
    /// One rewrite request as the model received it.
    struct Call: Sendable, Equatable {
        /// The text to rewrite.
        let text: String
        /// The instructions it came with.
        let instructions: String
        /// The engine asking.
        let kind: TransformerKind
    }

    /// Everything scripted and everything recorded, behind one lock.
    private struct State {
        /// What `availability(for:)` answers.
        var availability: TransformerAvailability = .available
        /// What `rewrite` returns for a text.
        var rewrite: @Sendable (String) -> String = { _ in "rewritten" }
        /// The error every rewrite throws, once set.
        var error: TransformationError?
        /// Every rewrite asked for, in order.
        var calls: [Call] = []
        /// Every language asked about, in order.
        var languagesAsked: [LanguageCode?] = []
        /// Every instruction string warmed with, in order.
        var warmed: [String] = []
    }

    /// The script and the record.
    private let state = Mutex(State())

    /// Scripts the availability and the rewrite.
    init(
        availability: TransformerAvailability = .available,
        rewrite: @escaping @Sendable (String) -> String = { _ in "rewritten" }
    ) {
        state.withLock {
            $0.availability = availability
            $0.rewrite = rewrite
        }
    }

    /// Records the language asked about and answers the scripted availability.
    func availability(for language: LanguageCode?) async -> TransformerAvailability {
        state.withLock { state in
            state.languagesAsked.append(language)
            return state.availability
        }
    }

    /// Records the call, then throws the scripted error or returns the scripted rewrite.
    func rewrite(
        _ text: String, instructions: String, kind: TransformerKind
    ) async throws(TransformationError) -> String {
        let outcome = state.withLock { state -> Result<String, TransformationError> in
            state.calls.append(Call(text: text, instructions: instructions, kind: kind))
            if let error = state.error { return .failure(error) }
            return .success(state.rewrite(text))
        }
        switch outcome {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }

    /// Records the instructions warmed with.
    func warm(instructions: String) async {
        state.withLock { $0.warmed.append(instructions) }
    }

    /// Makes every later rewrite throw `error`.
    func fail(with error: TransformationError) { state.withLock { $0.error = error } }
    var warmed: [String] { state.withLock(\.warmed) }
    var calls: [Call] { state.withLock(\.calls) }
    var languagesAsked: [LanguageCode?] { state.withLock(\.languagesAsked) }
}

/// A transformer that counts how often it is asked and returns a fixed answer.
final class StubTransformer: TextTransformationEngine {
    /// The engine this stands for.
    let kind: TransformerKind
    /// The scripted availability, the scripted error, and how many times `transform` ran.
    private let state: Mutex<(availability: TransformerAvailability, error: TransformationError?, count: Int)>

    /// Scripts the availability and an optional failure.
    init(
        kind: TransformerKind,
        availability: TransformerAvailability = .available,
        error: TransformationError? = nil
    ) {
        self.kind = kind
        self.state = Mutex((availability, error, 0))
    }

    /// The scripted availability.
    func availability(for request: TransformationRequest) async -> TransformerAvailability {
        state.withLock(\.availability)
    }

    /// Counts the call, then throws the scripted error or answers "by <kind>".
    func transform(
        _ request: TransformationRequest
    ) async throws(TransformationError) -> TransformationResult {
        let error = state.withLock { state -> TransformationError? in
            state.count += 1
            return state.error
        }
        if let error { throw error }
        return TransformationResult(text: "by \(kind.rawValue)", producedBy: kind)
    }

    var transformCount: Int { state.withLock(\.count) }
}
