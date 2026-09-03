public import UttrflowCore

/// Puts an accepted completion in, taking back the characters it replaces first.
public protocol CompletionWriting: Sendable {
    /// How the text got there, so a caller can prove the clipboard is not among the strategies.
    var method: TextInsertionMethod { get }

    /// Whether this strategy can write into what is currently focused.
    func canWrite() async -> Bool

    /// Writes `text` at the caret, having first taken back the `replaced` characters already there.
    func write(_ text: String, replacing replaced: String) async throws(TextInsertionError)
}

/// Tries each completion strategy in order and ends in nothing, never in the clipboard. See `Docs/predict-accept.md`.
public struct CompletionRoute: Sendable {
    private let strategies: [any CompletionWriting]

    public init(strategies: [any CompletionWriting]) {
        self.strategies = strategies
    }

    /// The strategies that will be tried, in order.
    public var route: [TextInsertionMethod] { strategies.map(\.method) }

    /// Writes the completion, returning how it got there.
    @discardableResult
    public func write(
        _ text: String, replacing replaced: String
    ) async throws(TextInsertionError) -> TextInsertionMethod {
        let outcome = await FallbackRunner.firstSuccess(among: strategies) { strategy in
            guard await strategy.canWrite() else { throw TextInsertionError.noFocusedTextField }
            try await strategy.write(text, replacing: replaced)
            return strategy.method
        }

        switch outcome {
        case .succeeded(let method):
            return method
        case .exhausted(let errors):
            // The last strategy's reason is the most specific; the earlier refusals are expected.
            throw errors.compactMap { $0 as? TextInsertionError }.last ?? .noFocusedTextField
        }
    }
}
