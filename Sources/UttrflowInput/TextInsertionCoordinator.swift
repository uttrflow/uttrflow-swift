public import UttrflowCore

/// Gets finished text to the user, one way or another.
///
/// Tries each strategy in order and stops at the first that works. The list must end
/// in one that cannot fail — leaving the text on the clipboard — because §19 is
/// explicit that a user must never lose their words to a failed insertion.
public struct TextInsertionCoordinator: TextInserting {
    private let strategies: [any TextInsertionEngine]

    public init(strategies: [any TextInsertionEngine]) {
        self.strategies = strategies
    }

    /// The strategies that will be tried, in order.
    public var route: [TextInsertionMethod] { strategies.map(\.method) }

    /// Inserts `text`, returning how it got there.
    ///
    /// - Throws: ``TextInsertionError/clipboardUnavailable`` only if every strategy
    ///   failed, which means even the clipboard refused.
    @discardableResult
    public func insert(_ text: String) async throws(TextInsertionError) -> TextInsertionMethod {
        try await insert(text, richText: nil)
    }

    /// E2 — the same insertion, with the formatted form carried alongside where there is
    /// one.
    ///
    /// A formatted clip skips the Accessibility strategy. That strategy writes a plain
    /// string straight into the focused element, which is the best route for words and
    /// the wrong one for a note: it would silently drop every heading and bullet while
    /// reporting success. Going by the pasteboard puts both flavours up and lets the
    /// receiving application take the one it understands — which is the whole reason a
    /// clip keeps both.
    ///
    /// The floor is unchanged: the last strategy cannot fail, so the worst outcome is
    /// still the words sitting on the clipboard rather than nowhere.
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
            // Report the last strategy's reason: it is the most specific, and the
            // earlier ones failing is expected rather than interesting.
            throw errors.compactMap { $0 as? TextInsertionError }.last ?? .clipboardUnavailable
        }
    }
}
