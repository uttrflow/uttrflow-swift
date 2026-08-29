public import struct Foundation.Date

import struct Synchronization.Mutex

/// Why a report did not arrive.
///
/// Deliberately *not* a ``UttrflowFailure``. Everything conforming to that protocol owes
/// the user a sentence and an offer of recovery, and telemetry owes them neither: a report
/// that could not be sent is Uttrflow's problem, not theirs, and an alert about it would be
/// the app interrupting somebody's work to complain about its own analytics. Making it a
/// different kind of error means nobody can wire it into the alert machinery by habit.
///
/// The status is a number rather than the server's message. An error carrying a string
/// from the network would be the one text-shaped thing in this subsystem, and it would end
/// up in a log beside everything else.
public enum TelemetryError: Error, Sendable, Equatable {
    /// No answer. Almost always the aeroplane rather than the outage.
    case unreachable
    /// The server answered and refused. A 400 here means the app and
    /// `migrations/0005_telemetry.sql` have fallen out of step, which is a bug in this
    /// module and not in anybody's connection.
    case refused(status: Int)
}

/// Whatever puts a report on the wire.
///
/// A protocol for the same reason ``AuthenticationService`` is one: the endpoint is a
/// deployment detail, and everything worth testing — what is collected, what is encoded,
/// what happens when it fails — must be testable with no server anywhere near it. The real
/// implementation is a `URLSession` posting ``TelemetryReport/encodedForIngest()`` to
/// `POST /v1/telemetry` and mapping the response code onto ``TelemetryError``; it belongs
/// behind this protocol and not in this repository, because the host it talks to is
/// configuration rather than source.
public protocol TelemetrySending: Sendable {
    func send(_ report: TelemetryReport) async throws(TelemetryError)
}

/// One report that actually left the Mac, and when.
///
/// This is the record the privacy page is drawn from: not a summary of what the app
/// intends to send, but the very value that was encoded and posted. Showing the user a
/// prettier description written separately would be showing them a claim; showing them
/// this is showing them the thing.
public struct TelemetryDispatch: Sendable, Equatable {
    public let report: TelemetryReport
    public let sentAt: Date

    public init(report: TelemetryReport, sentAt: Date) {
        self.report = report
        self.sentAt = sentAt
    }
}

/// A sender that keeps reports instead of sending them.
///
/// Ships in the module rather than in the tests, exactly as
/// ``InMemoryAuthenticationService`` does, and for the same two reasons: the app has to be
/// runnable with no telemetry host configured, and a fake that lives beside the real
/// protocol cannot drift away from it.
public final class RecordingTelemetrySender: TelemetrySending {
    private let state: Mutex<(reports: [TelemetryReport], failure: TelemetryError?)>

    /// - Parameter failure: What to throw instead of accepting anything. `nil` accepts.
    public init(failing failure: TelemetryError? = nil) {
        self.state = Mutex((reports: [], failure: failure))
    }

    /// Everything this sender has been given, oldest first.
    public var reports: [TelemetryReport] { state.withLock { $0.reports } }

    /// Starts or stops refusing, so one test can cover an outage and the recovery after it.
    public func fail(with failure: TelemetryError?) {
        state.withLock { $0.failure = failure }
    }

    public func send(_ report: TelemetryReport) async throws(TelemetryError) {
        let failure = state.withLock { state -> TelemetryError? in
            guard let failure = state.failure else {
                state.reports.append(report)
                return nil
            }
            return failure
        }
        if let failure { throw failure }
    }
}

/// Collecting, sending, and remembering what was sent.
///
/// The three are one type because the rule that ties them together — that nothing is sent
/// which was not collected, and nothing is collected once the user says no — is only
/// enforceable somewhere that can see all three.
public final class TelemetryService: Sendable {
    /// How many reports may wait for a connection.
    ///
    /// Small on purpose. An outbox is the classic place for an offline app to quietly
    /// consume a disk, and the value of a fortnight-old report is close to nothing anyway.
    public static let outboxCapacity = 8

    /// How many dispatches the user can look back over.
    public static let ledgerCapacity = 64

    private let collector: TelemetryCollector
    private let sender: any TelemetrySending
    private let outbox: Mutex<Outbox>

    public init(collector: TelemetryCollector, sender: any TelemetrySending) {
        self.collector = collector
        self.sender = sender
        self.outbox = Mutex(Outbox())
    }

    /// What the dictation path writes to. Synchronous, and therefore incapable of making a
    /// dictation wait — see ``TelemetryCollector``.
    public var recorder: TelemetryCollector { collector }

    /// Whether anything is being collected or sent.
    public var isEnabled: Bool { collector.isEnabled }

    /// Turns telemetry on or off.
    ///
    /// Switching off empties the outbox as well as the counters. Reports waiting for a
    /// connection have not left the Mac yet, and a user who has just opted out has said
    /// something about those too — sending them anyway on the next flight home would be
    /// keeping the letter of the setting and breaking all of it that matters.
    public func setEnabled(_ enabled: Bool, at moment: Date) {
        collector.setEnabled(enabled, at: moment)
        if !enabled { outbox.withLock { $0.pending.removeAll() } }
    }

    /// Every report that has actually been sent, oldest first.
    ///
    /// The whole point of item 5: the app can show the user exactly what left their
    /// machine, because this is exactly what left their machine.
    public var sentReports: [TelemetryDispatch] { outbox.withLock { $0.sent } }

    /// Reports still waiting for a connection.
    public var pendingReports: [TelemetryReport] { outbox.withLock { $0.pending } }

    /// Closes the current window and tries to deliver everything owed.
    ///
    /// Cannot throw and cannot report a problem, which is the design rather than an
    /// oversight: there is no caller who should do anything differently because telemetry
    /// failed, and a version of this that threw would eventually be `try`-ed somewhere that
    /// mattered. An unreachable server leaves the reports in the outbox and the app
    /// entirely unaffected.
    ///
    /// - Parameter moment: Now. The window ends here and the next one starts here.
    public func flush(at moment: Date) async {
        // One flush at a time. Two overlapping ones would each see the same report at the
        // front of the queue and send it twice, which the server would faithfully count.
        guard outbox.withLock({ $0.beginFlushing() }) else { return }
        defer { outbox.withLock { $0.isFlushing = false } }

        guard collector.isEnabled else {
            // Belt and braces: somebody may have switched the collector off directly.
            outbox.withLock { $0.pending.removeAll() }
            return
        }
        if let report = collector.takeReport(endedAt: moment) {
            outbox.withLock { $0.enqueue(report) }
        }

        while let next = outbox.withLock({ $0.pending.first }) {
            do {
                try await sender.send(next)
            } catch {
                // Silent, and everything stays queued for the next attempt.
                return
            }
            outbox.withLock { $0.accept(next, at: moment) }
        }
    }
}

extension TelemetryService {
    /// Reports owed, and reports delivered.
    private struct Outbox: Sendable {
        var pending: [TelemetryReport] = []
        var sent: [TelemetryDispatch] = []
        var isFlushing = false

        /// Claims the right to flush, or reports that somebody else already holds it.
        mutating func beginFlushing() -> Bool {
            guard !isFlushing else { return false }
            isFlushing = true
            return true
        }

        /// Adds a report, discarding the oldest if that would overflow.
        ///
        /// The oldest rather than the newest, because a report describes a window that has
        /// already closed: the recent ones say what Uttrflow is like now, and the ancient
        /// one at the front of the queue is the least worth the space it is holding.
        mutating func enqueue(_ report: TelemetryReport) {
            pending.append(report)
            if pending.count > TelemetryService.outboxCapacity { pending.removeFirst() }
        }

        /// Moves a delivered report out of the queue and into the record.
        ///
        /// Found by value rather than assumed to still be at the front: opting out empties
        /// the queue, and it can do so while a send is in flight.
        mutating func accept(_ report: TelemetryReport, at moment: Date) {
            if let index = pending.firstIndex(of: report) { pending.remove(at: index) }
            sent.append(TelemetryDispatch(report: report, sentAt: moment))
            if sent.count > TelemetryService.ledgerCapacity { sent.removeFirst() }
        }
    }
}
