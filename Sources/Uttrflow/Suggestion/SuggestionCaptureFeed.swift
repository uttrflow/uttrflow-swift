import Foundation
import UttrflowContext
import UttrflowPredictCapture

/// Tells capture what happened in the focused field between reads, in order, so a line is learned in the field that received it.
@MainActor
final class SuggestionCaptureFeed {
    let capture: CaptureSession
    /// The accepted lines still being written to the corpus, which capture hears of before the next read.
    private let acceptances: AcceptanceQueue
    /// Printable keyboard input not yet checked against the next accessibility read.
    private let pendingTyping = CaptureTypingRouter()
    /// Set when a paste or a dictation put text in the field that capture has not yet been told was never typed.
    private var insertionPending = false
    /// The field the last turn read, which a later read in another field finishes.
    var lastReading: FieldReading?
    /// The line capture was last handed as a keystroke, and its field, so a Return can catch up what it displaced.
    var handed: (line: String, reading: FieldReading)?

    init(capture: CaptureSession, acceptances: AcceptanceQueue) {
        self.capture = capture
        self.acceptances = acceptances
    }

    /// Holds one key until the next read says which field received it; nil is a key that typed no text.
    func queue(_ key: String?) {
        pendingTyping.append(key)
    }

    /// Notes that text reached the field without being typed, so the line holding it is never learned as typing.
    func noteInsertion() {
        insertionPending = true
    }

    /// Drops every queued key and a pending insertion, for a turn that read no field capture may hear of.
    func discard() {
        pendingTyping.discard()
        insertionPending = false
    }

    /// Waits until the field left last has been finished in capture.
    func waitForPreviousField() async {
        await pendingTyping.waitForPreviousField()
    }

    /// Finishes the field being left as its application stops being one suggestions run in.
    func leaveApplication(at moment: Date) {
        let typed = pendingTyping.drain(markingInsertion: insertionPending)
        insertionPending = false
        if let leaving = lastReading {
            pendingTyping.finishPreviousField(
                leaving, using: capture, typed: typed, at: moment, because: .applicationChanged,
                handed: handed)
        }
        lastReading = nil
        handed = nil
    }

    /// Finishes the field being left for a password field without learning the keys queued for either.
    func finishBeforeSecureRead(_ reading: FieldReading, at moment: Date) async {
        let discardedTyping = pendingTyping.discard() || insertionPending
        insertionPending = false
        await pendingTyping.waitForPreviousField()
        if let leaving = lastReading, leaving != reading {
            await pendingTyping.finish(
                leaving, using: capture,
                typed: CaptureTypingRouter.Batch(keys: [], overflowed: discardedTyping),
                at: moment, because: .tick, handed: handed)
        }
        lastReading = nil
        handed = nil
    }

    /// Tells capture about a read and the keys queued before it, once earlier acceptances and field ends are written.
    func remember(
        _ snapshot: FocusedFieldSnapshot, as reading: FieldReading, because reason: SuggestionReason,
        at moment: Date
    ) async {
        await pendingTyping.waitForPreviousField()
        await acceptances.drained()
        let typed = pendingTyping.drain(markingInsertion: insertionPending)
        if reason != .tick { insertionPending = false }
        await rememberAfterReadsDrained(
            snapshot, as: reading, because: reason, at: moment, leaving: lastReading, pendingTyping: typed)
    }

    /// Delivers a read and its queued keys after acceptance writes, with a prior reading when focus moved.
    func rememberAfterReadsDrained(
        _ snapshot: FocusedFieldSnapshot, as reading: FieldReading, because reason: SuggestionReason,
        at moment: Date, leaving: FieldReading?, typed pendingTyping: [String?]
    ) async {
        await rememberAfterReadsDrained(
            snapshot, as: reading, because: reason, at: moment, leaving: leaving,
            pendingTyping: CaptureTypingRouter.Batch(keys: pendingTyping, overflowed: false))
    }

    private func rememberAfterReadsDrained(
        _ snapshot: FocusedFieldSnapshot, as reading: FieldReading, because reason: SuggestionReason,
        at moment: Date, leaving: FieldReading?, pendingTyping pending: CaptureTypingRouter.Batch
    ) async {
        var typed = pending.keys
        let switchedField = leaving.map { $0 != reading } ?? false
        if switchedField, let leaving {
            await pendingTyping.finish(
                leaving, using: capture,
                typed: CaptureTypingRouter.Batch(keys: pending.keys, overflowed: pending.overflowed),
                at: moment, because: reason, handed: handed)
            typed = []
        }
        if pending.overflowed, !switchedField, (!pending.inserted || reason == .tick) {
            _ = try? await capture.handle(.inserted(at: moment), in: reading)
        }
        let line = snapshot.learnableLine
        var events: [CaptureEvent]
        if case .returnPressed = reason {
            let prior = handed.flatMap { $0.reading == reading ? $0.line : nil } ?? ""
            events = ReturnCatchUp.events(read: line, handed: prior, at: moment)
            handed = nil
        } else {
            events = [reason.event(holding: line, at: moment)]
            if case .keystroke = events[0] { handed = (line, reading) }
        }
        events.insert(contentsOf: typed.map { .typed($0, at: moment) }, at: 0)
        // Only a turn that read the line can tell capture the line holds inserted text.
        if pending.inserted, reason != .tick {
            events = CaptureEvent.marking(events, insertedAt: moment)
        }
        for event in events { _ = try? await capture.handle(event, in: reading) }
    }
}
