public import UttrflowCore

/// Gets finished text to the user by trying each strategy, ending in one that cannot fail.
public struct TextInsertionCoordinator: TextInserting {
    private let strategies: [any TextInsertionEngine]
    /// Asked where the words went the moment they are written, since the recording's answer may be stale.
    private let focus: (any AccessibilityFocus)?
    /// Where confirmed writes are remembered for a later command, or `nil` where nothing asks.
    private let ledger: InsertionLedger?

    public init(
        strategies: [any TextInsertionEngine], focus: (any AccessibilityFocus)? = nil,
        ledger: InsertionLedger? = nil
    ) {
        self.strategies = strategies
        self.focus = focus
        self.ledger = ledger
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
        do {
            let attempt = try await write(text, richText: richText, targeting: destination)
            await remember(attempt, text: text)
            return attempt
        } catch {
            ledger?.clear()
            throw error
        }
    }

    /// Moves the caret back into the newest confirmed write, verified against the ledger; `false` leaves it at the end.
    public func placeCaret(back units: Int) async -> Bool {
        guard units > 0 else { return true }
        guard let ledger, let focus else { return false }
        return await AccessibilityThread.run(orElse: false) {
            guard let place = focus.focusedFieldPlace(), let record = ledger.records(in: place.field).last,
                let field = focus.focusedTextField()
            else { return false }
            let target = EditTarget(
                record: record, focused: place.field, isSecure: focus.focusedFieldIsSecure())
            do {
                try field.placeCaret(in: target, back: units)
                return true
            } catch {
                return false
            }
        }
    }

    /// Reads the caret after the write, so the ledger holds the span the words occupy now.
    private func remember(_ attempt: InsertionAttempt, text: String) async {
        guard let ledger else { return }
        let focus = focus
        let place = await AccessibilityThread.run(orElse: FieldPlace?.none) { focus?.focusedFieldPlace() }
        ledger.note(attempt, text: text, endingAt: place)
    }

    private func write(
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
                strategy.method, arrival: arrival, destination: landed ?? focus?.focusedApplication(),
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
            // Lost trust hides every field and refuses every keystroke, so it outranks whatever each strategy reported.
            let trusted = await AccessibilityThread.run(orElse: true) { focus?.isTrusted() ?? true }
            guard trusted else { throw .accessibilityDenied }
            // The last strategy's reason is the most specific; the earlier refusals are expected.
            let failure = errors.compactMap { $0 as? TextInsertionError }.last ?? .clipboardUnavailable
            let keepsClipboard = strategies.contains { $0.method == .clipboard }
            let canType = strategies.contains { $0.method == .typed }
            if canType, !keepsClipboard {
                switch failure {
                case .clipboardChanged, .insertionUnconfirmed, .insertionTargetChanged, .insertionFieldClosed,
                    .insertionInterrupted:
                    throw failure
                default: throw .insertionNeedsCopy(description: failure.userMessage)
                }
            }
            throw failure
        }
    }
}
