// Sends telemetry reports and remembers exactly what left the Mac.
public import struct Foundation.Date

import struct Synchronization.Mutex

/// Why a report did not arrive; not a ``UttrflowFailure``, so nothing wires it into an alert by habit.
public enum TelemetryError: Error, Sendable, Equatable {
    /// No answer. Almost always the aeroplane rather than the outage.
    case unreachable
    /// The server answered and refused; a 400 means this module and `migrations/0005_telemetry.sql` disagree.
    case refused(status: Int)
}

/// Whatever puts a report on the wire; the `URLSession` conformance lives outside this repository.
public protocol TelemetrySending: Sendable {
    /// Posts one report, throwing only a ``TelemetryError``.
    func send(_ report: TelemetryReport) async throws(TelemetryError)
}

/// One report that left the Mac, and when; the privacy page draws from this exact value.
public struct TelemetryDispatch: Sendable, Equatable {
    /// The value that was encoded and posted.
    public let report: TelemetryReport
    /// When it left.
    public let sentAt: Date

    /// Pairs a report with the moment it left.
    public init(report: TelemetryReport, sentAt: Date) {
        self.report = report
        self.sentAt = sentAt
    }
}

/// A sender that keeps reports instead of sending them; in the module so the app runs with no telemetry host.
public final class RecordingTelemetrySender: TelemetrySending {
    /// What has been given, and what to throw instead of accepting.
    private let state: Mutex<(reports: [TelemetryReport], failure: TelemetryError?)>

    /// `failure` is thrown instead of accepting anything; `nil` accepts.
    public init(failing failure: TelemetryError? = nil) {
        self.state = Mutex((reports: [], failure: failure))
    }

    /// Everything this sender has been given, oldest first.
    public var reports: [TelemetryReport] { state.withLock { $0.reports } }

    /// Starts or stops refusing, so one test can cover an outage and the recovery after it.
    public func fail(with failure: TelemetryError?) {
        state.withLock { $0.failure = failure }
    }

    /// Keeps the report, or throws the configured failure.
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

/// Collecting, sending and remembering what was sent, in one type so the opt-out rule can see all three.
public final class TelemetryService: Sendable {
    /// How many reports may wait for a connection; small, so an offline app cannot quietly consume a disk.
    public static let outboxCapacity = 8

    /// How many dispatches the user can look back over.
    public static let ledgerCapacity = 64

    /// The counters the dictation path writes to.
    private let collector: TelemetryCollector
    /// Puts a report on the wire.
    private let sender: any TelemetrySending
    /// Reports owed and delivered, behind one lock.
    private let outbox: Mutex<Outbox>

    /// Wires the collector to the sender with an empty outbox.
    public init(collector: TelemetryCollector, sender: any TelemetrySending) {
        self.collector = collector
        self.sender = sender
        self.outbox = Mutex(Outbox())
    }

    /// What the dictation path writes to; synchronous, so it cannot make a dictation wait.
    public var recorder: TelemetryCollector { collector }

    /// Whether anything is being collected or sent.
    public var isEnabled: Bool { collector.isEnabled }

    /// Turns telemetry on or off; switching off empties the outbox as well as the counters.
    public func setEnabled(_ enabled: Bool, at moment: Date) {
        collector.setEnabled(enabled, at: moment)
        if !enabled { outbox.withLock { $0.pending.removeAll() } }
    }

    /// Every report that has been sent, oldest first; exactly what left the machine.
    public var sentReports: [TelemetryDispatch] { outbox.withLock { $0.sent } }

    /// Reports still waiting for a connection.
    public var pendingReports: [TelemetryReport] { outbox.withLock { $0.pending } }

    /// Closes the window and sends everything owed; cannot fail, and an unreachable server leaves the queue.
    public func flush(at moment: Date) async {
        // One flush at a time, so two overlapping ones cannot both send the report at the front of the queue.
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
        /// Reports waiting for a connection, oldest first.
        var pending: [TelemetryReport] = []
        /// Reports delivered, oldest first.
        var sent: [TelemetryDispatch] = []
        /// Whether a flush holds the queue.
        var isFlushing = false

        /// Claims the right to flush, or reports that somebody else already holds it.
        mutating func beginFlushing() -> Bool {
            guard !isFlushing else { return false }
            isFlushing = true
            return true
        }

        /// Adds a report, dropping the earliest when that overflows: a recent window says the most.
        mutating func enqueue(_ report: TelemetryReport) {
            pending.append(report)
            if pending.count > TelemetryService.outboxCapacity { pending.removeFirst() }
        }

        /// Records a delivered report, finding it by value because opting out can empty the queue mid-send.
        mutating func accept(_ report: TelemetryReport, at moment: Date) {
            if let index = pending.firstIndex(of: report) { pending.remove(at: index) }
            sent.append(TelemetryDispatch(report: report, sentAt: moment))
            if sent.count > TelemetryService.ledgerCapacity { sent.removeFirst() }
        }
    }
}
