public import UttrflowCore

/// Gets finished text to the user by trying each strategy, ending in one that cannot fail.
public struct TextInsertionCoordinator: TextInserting {
    private let strategies: [any TextInsertionEngine]
    /// Asked where the words went the moment they are written, since the recording's answer may be stale.
    private let focus: (any AccessibilityFocus)?

    public init(strategies: [any TextInsertionEngine], focus: (any AccessibilityFocus)? = nil) {
        self.strategies = strategies
        self.focus = focus
    }

    /// The strategies that will be tried, in order.
    public var route: [TextInsertionMethod] { strategies.map(\.method) }

    /// Inserts `text` and reports how it got there, throwing only when every strategy refused.
    @discardableResult
    public func insert(_ text: String) async throws(TextInsertionError) -> InsertionAttempt {
        try await insert(text, richText: nil, targeting: nil)
    }

    @discardableResult
    public func insert(
        _ text: String, targeting destination: InsertionDestination
    ) async throws(TextInsertionError) -> InsertionAttempt {
        try await insert(text, richText: nil, targeting: destination)
    }

    @discardableResult
    public func insert(
        _ text: String, richText: String?, targeting destination: InsertionDestination
    ) async throws(TextInsertionError) -> InsertionAttempt {
        try await insert(text, richText: richText, targeting: Optional(destination))
    }

    /// The same insertion carrying the formatted form, which skips Accessibility so no heading is dropped.
    @discardableResult
    public func insert(
        _ text: String, richText: String?
    ) async throws(TextInsertionError) -> InsertionAttempt {
        try await insert(text, richText: richText, targeting: nil)
    }

    private func insert(
        _ text: String, richText: String?, targeting destination: InsertionDestination?
    ) async throws(TextInsertionError) -> InsertionAttempt {
        let usable =
            richText == nil ? strategies : strategies.filter { $0.method != .accessibility }
        // Asked before the write, since the field that takes the words is the one to judge.
        let focus = focus
        let secure = await AccessibilityThread.run(orElse: true) { focus?.focusedFieldIsSecure() ?? false }
        let outcome = await FallbackRunner.firstSuccess(
            among: usable, stopAfterFailure: { ($0 as? TextInsertionError)?.stopsFallback == true }
        ) { strategy in
            guard await strategy.canInsert() else { throw TextInsertionError.noFocusedTextField }
            // Passed through rather than dropped, so what the strategy found out survives the fallback.
            let arrival: InsertionArrival
            if let destination {
                if let richText {
                    arrival = try await strategy.insert(text, richText: richText, targeting: destination)
                } else {
                    arrival = try await strategy.insert(text, targeting: destination)
                }
            } else {
                arrival = try await strategy.insert(text, richText: richText)
            }
            // The strategy's own reading at the moment of sending wins; otherwise read the app after the write.
            let landed = await strategy.destinationAtLanding()
            return InsertionAttempt(
                strategy.method, arrival: arrival, destination: landed ?? focus?.frontmostApplication(),
                intoSecureField: secure)
        }

        switch outcome {
        case .succeeded(let attempt, _):
            // Asked again once the words are written, so a switch into a secure field during the fallback counts.
            guard !attempt.intoSecureField else { return attempt }
            let nowSecure = await AccessibilityThread.run(orElse: true) {
                focus?.focusedFieldIsSecure() == true
            }
            guard nowSecure else { return attempt }
            return InsertionAttempt(
                attempt.method, arrival: attempt.arrival, destination: attempt.destination,
                intoSecureField: true)
        case .exhausted(let errors):
            // The last strategy's reason is the most specific; the earlier refusals are expected.
            throw errors.compactMap { $0 as? TextInsertionError }.last ?? .clipboardUnavailable
        }
    }
}
