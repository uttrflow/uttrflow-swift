import Foundation
import UttrflowContext
import UttrflowPredictCapture

/// Tells capture, through the ordered write queue, what happened in the focused field between reads, so a turn never waits on a corpus write.
@MainActor
final class SuggestionCaptureFeed {
    let capture: CaptureSession
    /// The ordered corpus writes, which capture events join behind the accepted lines queued before them.
    private let acceptances: AcceptanceQueue
    /// Printable keyboard input not yet checked against the next accessibility read.
    private let pendingTyping = CaptureTypingRouter()
    /// Set when a paste or a dictation put text in the field that capture has not yet been told was never typed.
    private var insertionPending = false
    /// The field the last turn read, which a later read in another field finishes.
    var lastReading: FieldReading?
    /// The line capture was last handed as a keystroke, and its field, so a Return can catch up what it displaced.
    var handed: (line: String, reading: FieldReading)?
    /// Printable keys typed since a read last showed them, so a slow field's late echo is not taken for an insertion.
    private var unechoedTyping = ""
    /// The line the last read showed and its field, which the unechoed keys are expected to extend.
    private var echoBase: (line: String, reading: FieldReading)?

    /// Whether keys typed in the field may still be echoing into it, however late the echo arrives.
    var awaitsTypedEcho: Bool { !unechoedTyping.isEmpty }

    init(capture: CaptureSession, acceptances: AcceptanceQueue) {
        self.capture = capture
        self.acceptances = acceptances
    }

    /// Holds one key until the next read says which field received it; nil is a key that typed no text.
    func queue(_ key: String?) {
        pendingTyping.append(key)
        // A key that typed no text makes the echo unpredictable, so the next change is judged as before.
        if let key { unechoedTyping += key } else { unechoedTyping = "" }
    }

    /// Notes that text reached the field without being typed, so the line holding it is never learned as typing.
    func noteInsertion() {
        insertionPending = true
    }

    /// Drops every queued key and a pending insertion, for a turn that read no field capture may hear of.
    func discard() {
        pendingTyping.discard()
        insertionPending = false
        forgetEcho()
    }

    private func forgetEcho() {
        unechoedTyping = ""
        echoBase = nil
    }

    /// Keeps only the typed suffix a read has not shown yet, or nothing when the read is not a prefix of the typing.
    private func noteEcho(of line: String, in reading: FieldReading, because reason: SuggestionReason) {
        if case .returnPressed = reason {
            forgetEcho()
            return
        }
        if let base = echoBase, base.reading == reading {
            unechoedTyping = Self.unechoed(after: base.line, typed: unechoedTyping, read: line) ?? ""
        } else {
            unechoedTyping = ""
        }
        echoBase = (line, reading)
    }

    /// The typed keys a read of `read` has not shown yet, or nil when the read is not `base` plus a prefix of them.
    nonisolated static func unechoed(after base: String, typed: String, read: String) -> String? {
        let expected = base + typed
        guard expected.hasPrefix(read), read.hasPrefix(base) else { return nil }
        return String(expected.dropFirst(read.count))
    }

    /// Waits until every capture event and accepted line queued so far has been written.
    func waitForPreviousField() async {
        await acceptances.drained()
    }

    /// Finishes the field being left as its application stops being one suggestions run in.
    func leaveApplication(at moment: Date) {
        let typed = pendingTyping.drain(markingInsertion: insertionPending)
        insertionPending = false
        if let leaving = lastReading {
            enqueue(
                pendingTyping.finishEvents(
                    leaving, typed: typed, at: moment, because: .applicationChanged, handed: handed),
                in: leaving)
        }
        lastReading = nil
        handed = nil
        forgetEcho()
    }

    /// Finishes the field being left for a password field without learning the keys queued for either.
    func finishBeforeSecureRead(_ reading: FieldReading, at moment: Date) async {
        let discardedTyping = pendingTyping.discard() || insertionPending
        insertionPending = false
        if let leaving = lastReading, leaving != reading {
            enqueue(
                pendingTyping.finishEvents(
                    leaving, typed: CaptureTypingRouter.Batch(keys: [], overflowed: discardedTyping),
                    at: moment, because: .tick, handed: handed),
                in: leaving)
        }
        lastReading = nil
        handed = nil
        forgetEcho()
    }

    /// Queues a read and the keys before it behind earlier acceptances and field ends, without waiting for them.
    func remember(
        _ snapshot: FocusedFieldSnapshot, as reading: FieldReading, because reason: SuggestionReason,
        at moment: Date
    ) async {
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
            enqueue(
                pendingTyping.finishEvents(
                    leaving,
                    typed: CaptureTypingRouter.Batch(keys: pending.keys, overflowed: pending.overflowed),
                    at: moment, because: reason, handed: handed),
                in: leaving)
            typed = []
        }
        if pending.overflowed, !switchedField, (!pending.inserted || reason == .tick) {
            enqueue([.inserted(at: moment)], in: reading)
        }
        let line = snapshot.learnableLine
        noteEcho(of: line, in: reading, because: reason)
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
        enqueue(events, in: reading)
    }

    /// Queues events for one field behind every earlier corpus write.
    private func enqueue(_ events: [CaptureEvent], in reading: FieldReading) {
        guard !events.isEmpty else { return }
        _ = acceptances.enqueueCapture(events, in: reading, using: capture)
    }
}
