import UttrflowCore

/// Waits for pasted words to reach the caret, so a paste is confirmed rather than assumed. See `Docs/insertion.md`.
public struct PasteConfirmation: Sendable {
    /// What waiting for the words found out.
    public enum Outcome: Sendable, Equatable {
        /// The words were behind the caret this long after the paste was posted.
        case landed(Duration)
        /// The field will not say what it holds, so nothing was proved either way.
        case notReported
        /// The budget ran out with no sign of them.
        case gaveUp(Duration)
        /// The task waiting was cancelled, so it stopped looking; nothing was proved either way.
        case cancelled(Duration)
    }

    /// How long to wait before giving up, generous enough that a busy app is not called a failure.
    public static let budget = Duration.milliseconds(1600)

    /// How often the caret is read, which is a synchronous call into another application.
    public static let interval = Duration.milliseconds(40)

    /// How much of the pasted text has to match, enough to be this dictation rather than the last one.
    static let tailLength = 24

    /// How much is read back, more than is compared, so collapsing whitespace cannot shorten it past the match.
    static let readLength = 96

    private let focus: any AccessibilityFocus
    private let clock: any Clock<Duration>
    private let budget: Duration
    private let interval: Duration

    public init(
        focus: any AccessibilityFocus,
        clock: any Clock<Duration> = ContinuousClock(),
        budget: Duration = PasteConfirmation.budget,
        interval: Duration = PasteConfirmation.interval
    ) {
        self.focus = focus
        self.clock = clock
        self.budget = budget
        self.interval = interval
    }

    /// Watches the caret until `text` sits behind it; `before` is the pre-paste tail, so an unchanged match does not count.
    public func waitFor(_ text: String, before: FieldTail? = nil) async -> Outcome {
        let elapsed = UttrflowCore.stopwatch(from: clock)
        guard !Task.isCancelled else { return .cancelled(.zero) }
        let wanted = Self.wanted(from: text)
        // A field that will not answer now will not answer in a second either, so nothing is waited for.
        guard !wanted.isEmpty, focus.tail(upTo: Self.readLength) != .unreadable else { return .notReported }
        let priorText = Self.priorText(matching: wanted, before: before)
        // Set once the caret has read as anything but the pre-paste text, so a later match is trusted even if it settles back on it.
        var hasChangedSincePaste = priorText == nil

        var waited = Duration.zero
        while waited < budget {
            // A cancelled sleep returns at once, so without this the loop reads the field as fast as it can.
            do { try await clock.sleep(for: interval) } catch { return .cancelled(elapsed()) }
            guard !Task.isCancelled else { return .cancelled(elapsed()) }
            guard case .text(let seen) = focus.tail(upTo: Self.readLength) else { return .notReported }
            // Read from the clock rather than tallied from the sleeps, so each read is charged to the budget.
            waited = elapsed()
            if seen != priorText { hasChangedSincePaste = true }
            // A caret unchanged since before the paste proves nothing, however well it matches.
            if Self.collapsed(seen).hasSuffix(wanted), hasChangedSincePaste { return .landed(waited) }
        }
        return .gaveUp(waited)
    }

    /// The pre-paste tail, kept only when it already carried the words this call is waiting for.
    private static func priorText(matching wanted: String, before: FieldTail?) -> String? {
        guard case .text(let seen) = before, collapsed(seen).hasSuffix(wanted) else { return nil }
        return seen
    }

    /// The end of what was pasted, which is what sits against the caret once the application takes it.
    static func wanted(from text: String) -> String {
        String(collapsed(text).suffix(tailLength))
    }

    /// One space for any run of whitespace, so wrapping and indenting on the way in cannot fail a match.
    static func collapsed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
