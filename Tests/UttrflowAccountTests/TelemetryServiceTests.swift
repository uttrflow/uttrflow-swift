// Tests for TelemetryService: sending, the outbox, the ledger, the opt-out, and the recording sender.

import Foundation
import Synchronization
import Testing

@testable import UttrflowAccount

/// Sending, not sending, and remembering which of the two happened.
@Suite("Sending telemetry")
struct TelemetryServiceTests {
    /// Records one completed dictation on the service's collector.
    private func dictate(_ service: TelemetryService, characters: Int = 10) {
        service.recorder.recordDictation(.completed, language: .english, charactersInserted: characters)
    }

    @Test("sends the window's report and keeps a record of having sent it")
    func sendsAndRecords() async throws {
        let (service, sender) = Telemetry.service()
        dictate(service)

        await service.flush(at: Telemetry.anHourLater)

        #expect(sender.reports.count == 1)
        #expect(service.pendingReports.isEmpty)

        let dispatch = try #require(service.sentReports.first)
        #expect(dispatch.sentAt == Telemetry.anHourLater)
        // The record is the report itself, so the settings page shows the very value uploaded.
        #expect(dispatch.report == sender.reports[0])
        #expect(dispatch.report.charactersInserted == 10)
    }

    @Test("says nothing when there is nothing to say")
    func silentWhenIdle() async {
        let (service, sender) = Telemetry.service()
        await service.flush(at: Telemetry.anHourLater)

        #expect(sender.reports.isEmpty)
        #expect(service.sentReports.isEmpty)
    }

    // MARK: - Failure

    /// A telemetry failure is Uttrflow's problem: `flush` does not throw, so it cannot even report one.
    @Test("an unreachable server costs the app nothing and is never reported")
    func failureIsSilent() async throws {
        let (service, sender) = Telemetry.service(sender: RecordingTelemetrySender(failing: .unreachable))
        dictate(service)

        await service.flush(at: Telemetry.anHourLater)

        #expect(sender.reports.isEmpty)
        #expect(service.sentReports.isEmpty)
        // Not lost, either — it waits for a connection.
        #expect(service.pendingReports.count == 1)
    }

    @Test("delivers what it could not send once the connection comes back")
    func recoversAfterAnOutage() async throws {
        let sender = RecordingTelemetrySender(failing: .refused(status: 503))
        let (service, _) = Telemetry.service(sender: sender)

        dictate(service, characters: 1)
        await service.flush(at: Telemetry.anHourLater)
        dictate(service, characters: 2)
        await service.flush(at: Telemetry.anHourLater.addingTimeInterval(3600))
        #expect(service.pendingReports.count == 2)

        sender.fail(with: nil)
        await service.flush(at: Telemetry.anHourLater.addingTimeInterval(7200))

        #expect(sender.reports.map(\.charactersInserted) == [1, 2])
        #expect(service.pendingReports.isEmpty)
        #expect(service.sentReports.count == 2)
    }

    /// An outbox is the classic way for an offline app to quietly eat a disk.
    @Test("the queue cannot grow without limit while offline")
    func theQueueIsBounded() async throws {
        let sender = RecordingTelemetrySender(failing: .unreachable)
        let (service, _) = Telemetry.service(sender: sender)

        let attempts = TelemetryService.outboxCapacity + 6
        for index in 0..<attempts {
            dictate(service, characters: index + 1)
            await service.flush(at: Telemetry.anHourLater.addingTimeInterval(Double(index) * 3600))
        }

        #expect(service.pendingReports.count == TelemetryService.outboxCapacity)
        // The earliest are dropped: a report describes a closed window, and the earliest is worth the least.
        #expect(
            service.pendingReports.first?.charactersInserted == attempts - TelemetryService.outboxCapacity + 1
        )
        #expect(service.pendingReports.last?.charactersInserted == attempts)
    }

    /// The record the user can look at is bounded for the same reason the queue is.
    @Test("the record of what was sent is bounded too")
    func theRecordIsBounded() async throws {
        let (service, _) = Telemetry.service()
        let attempts = TelemetryService.ledgerCapacity + 3

        for index in 0..<attempts {
            dictate(service, characters: index + 1)
            await service.flush(at: Telemetry.anHourLater.addingTimeInterval(Double(index) * 3600))
        }

        #expect(service.sentReports.count == TelemetryService.ledgerCapacity)
        #expect(service.sentReports.last?.report.charactersInserted == attempts)
    }

    // MARK: - Opt-out

    @Test("sends nothing while switched off")
    func sendsNothingWhenOff() async {
        let (service, sender) = Telemetry.service(isEnabled: false)
        dictate(service)

        await service.flush(at: Telemetry.anHourLater)

        #expect(!service.isEnabled)
        #expect(sender.reports.isEmpty)
        #expect(service.sentReports.isEmpty)
        #expect(service.pendingReports.isEmpty)
    }

    /// Queued reports have not left the Mac, and sending them after an opt-out would break the setting.
    @Test("opting out empties the outbox as well as the counters")
    func optingOutEmptiesTheOutbox() async {
        let sender = RecordingTelemetrySender(failing: .unreachable)
        let (service, _) = Telemetry.service(sender: sender)

        dictate(service)
        await service.flush(at: Telemetry.anHourLater)
        #expect(service.pendingReports.count == 1)

        service.setEnabled(false, at: Telemetry.anHourLater)
        #expect(service.pendingReports.isEmpty)

        sender.fail(with: nil)
        await service.flush(at: Telemetry.anHourLater.addingTimeInterval(3600))
        #expect(sender.reports.isEmpty)
    }

    /// The collector can be switched off directly, and the outbox must still notice.
    @Test("a collector switched off behind the service's back still empties the outbox")
    func flushHonoursTheCollectorDirectly() async {
        let sender = RecordingTelemetrySender(failing: .unreachable)
        let (service, _) = Telemetry.service(sender: sender)

        dictate(service)
        await service.flush(at: Telemetry.anHourLater)
        #expect(service.pendingReports.count == 1)

        service.recorder.setEnabled(false, at: Telemetry.anHourLater)
        sender.fail(with: nil)
        await service.flush(at: Telemetry.anHourLater.addingTimeInterval(3600))

        #expect(sender.reports.isEmpty)
        #expect(service.pendingReports.isEmpty)
    }

    // MARK: - Concurrency

    /// Two overlapping flushes would each send the front report, and the server would count both.
    @Test("a flush that begins while another is running does nothing")
    func flushesDoNotOverlap() async throws {
        let sender = ReentrantSender()
        let service = TelemetryService(collector: Telemetry.collector(), sender: sender)
        sender.reentering(into: service)

        dictate(service)
        await service.flush(at: Telemetry.anHourLater)

        #expect(sender.sendCount == 1)
        #expect(service.sentReports.count == 1)
    }
}

/// A sender that flushes the service again from inside a send, the only deterministic way to overlap two.
private final class ReentrantSender: TelemetrySending {
    /// The service to re-enter, and how many sends so far.
    private let state = Mutex<(service: TelemetryService?, count: Int)>((service: nil, count: 0))

    var sendCount: Int { state.withLock { $0.count } }

    /// Names the service to flush from inside the first send.
    func reentering(into service: TelemetryService) {
        state.withLock { $0.service = service }
    }

    /// Counts the send and, on the first one only, flushes the service again.
    func send(_ report: TelemetryReport) async throws(TelemetryError) {
        let service = state.withLock { state -> TelemetryService? in
            state.count += 1
            return state.count == 1 ? state.service : nil
        }
        await service?.flush(at: Telemetry.anHourLater)
    }
}

/// The fake that ships beside the protocol, checked like anything else that ships.
@Suite("The recording sender")
struct RecordingTelemetrySenderTests {
    @Test("keeps what it is given, in order")
    func keepsWhatItIsGiven() async throws {
        let sender = RecordingTelemetrySender()
        let report = try #require(Telemetry.report(charactersInserted: 3))

        try await sender.send(report)
        #expect(sender.reports == [report])
    }

    @Test("throws instead, and keeps nothing, while it is set to fail")
    func failsOnDemand() async throws {
        let sender = RecordingTelemetrySender(failing: .refused(status: 400))
        let report = try #require(Telemetry.report())

        await #expect(throws: TelemetryError.refused(status: 400)) { try await sender.send(report) }
        #expect(sender.reports.isEmpty)
    }
}
