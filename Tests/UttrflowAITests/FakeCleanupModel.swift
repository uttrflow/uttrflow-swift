import Synchronization

@testable import UttrflowAI
@testable import UttrflowCore

/// A language model that returns whatever a test scripts.
final class FakeCleanupModel: CleanupModel {
    struct Call: Sendable, Equatable {
        let text: String
        let instructions: String
        let kind: TransformerKind
    }

    private struct State {
        var availability: TransformerAvailability = .available
        var rewrite: @Sendable (String) -> String = { _ in "rewritten" }
        var error: TransformationError?
        var calls: [Call] = []
        var languagesAsked: [LanguageCode?] = []
    }

    private let state = Mutex(State())

    init(
        availability: TransformerAvailability = .available,
        rewrite: @escaping @Sendable (String) -> String = { _ in "rewritten" }
    ) {
        state.withLock {
            $0.availability = availability
            $0.rewrite = rewrite
        }
    }

    func availability(for language: LanguageCode?) async -> TransformerAvailability {
        state.withLock { state in
            state.languagesAsked.append(language)
            return state.availability
        }
    }

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

    func fail(with error: TransformationError) { state.withLock { $0.error = error } }
    var calls: [Call] { state.withLock(\.calls) }
    var languagesAsked: [LanguageCode?] { state.withLock(\.languagesAsked) }
}

/// A transformer that records what it was asked and returns a fixed answer.
final class StubTransformer: TextTransformationEngine {
    let kind: TransformerKind
    private let state: Mutex<(availability: TransformerAvailability, error: TransformationError?, count: Int)>

    init(
        kind: TransformerKind,
        availability: TransformerAvailability = .available,
        error: TransformationError? = nil
    ) {
        self.kind = kind
        self.state = Mutex((availability, error, 0))
    }

    func availability(for request: TransformationRequest) async -> TransformerAvailability {
        state.withLock(\.availability)
    }

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
