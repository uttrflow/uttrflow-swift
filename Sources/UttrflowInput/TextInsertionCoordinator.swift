public import UttrflowCore

/// Gets finished text to the user by trying each strategy, ending in one that cannot fail.
public struct TextInsertionCoordinator: TextInserting {
    private let strategies: [any TextInsertionEngine]

    public init(strategies: [any TextInsertionEngine]) {
        self.strategies = strategies
    }

    /// The strategies that will be tried, in order.
    public var route: [TextInsertionMethod] { strategies.map(\.method) }

    /// Inserts `text` and reports how it got there, throwing only when every strategy refused.
    @discardableResult
    public func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        try await insert(text, richText: nil)
    }

    /// The same insertion carrying the formatted form, which skips Accessibility so no heading is dropped.
    @discardableResult
    public func insert(
        _ text: String, richText: String?
    ) async throws(TextInsertionError) -> TextInsertionMethod {
        let usable =
            richText == nil ? strategies : strategies.filter { $0.method != .accessibility }
        let outcome = await FallbackRunner.firstSuccess(among: usable) { strategy in
            guard await strategy.canInsert() else { throw TextInsertionError.noFocusedTextField }
            try await strategy.insert(text, richText: richText)
            return strategy.method
        }

        switch outcome {
        case .succeeded(let method):
            return method
        case .exhausted(let errors):
            // The last strategy's reason is the most specific; the earlier refusals are expected.
            throw errors.compactMap { $0 as? TextInsertionError }.last ?? .clipboardUnavailable
        }
    }
}
