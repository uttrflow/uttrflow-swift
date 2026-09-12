import Synchronization
import Testing
import UttrflowCore

@testable import UttrflowAudio

/// A device that fails a set number of opens before it comes back, standing in for a re-enumerating one.
private final class FlakyDevice: InputDevice, @unchecked Sendable {
    struct Log {
        var opens = 0
        var closes = 0
        var failuresLeft = 0
    }

    let log = Mutex(Log())

    init(failing: Int) {
        log.withLock { $0.failuresLeft = failing }
    }

    func open() throws(AudioCaptureError) {
        let refuse = log.withLock { log -> Bool in
            log.opens += 1
            guard log.failuresLeft > 0 else { return false }
            log.failuresLeft -= 1
            return true
        }
        if refuse { throw .noInputDevice }
    }

    func close() {
        log.withLock { $0.closes += 1 }
    }
}

/// Collects what the session said, since a Mutex cannot itself be handed back in a tuple.
private final class Reports: Sendable {
    private let errors = Mutex<[AudioCaptureError]>([])

    var count: Int { errors.withLock(\.count) }
    var first: AudioCaptureError? { errors.withLock(\.first) }

    func record(_ error: AudioCaptureError) {
        errors.withLock { $0.append(error) }
    }
}

/// The device outliving one failed reopen is the whole point: see Docs/microphone.md.
@Suite("An input device session")
struct InputDeviceSessionTests {
    /// No real waiting, so the schedule is exercised without the test taking its three seconds.
    private func session(_ device: FlakyDevice, delays: Int = 5) -> (InputDeviceSession, Reports) {
        let schedule = ReopenSchedule(delays: Array(repeating: .zero, count: delays))
        return (InputDeviceSession(device: device, schedule: schedule, pause: { _ in }), Reports())
    }

    @Test("opens once and reports nothing when the device is there")
    func opensCleanly() throws {
        let device = FlakyDevice(failing: 0)
        let (session, reported) = session(device)

        try session.open { error in reported.record(error) }

        #expect(session.health == .live)
        #expect(device.log.withLock(\.opens) == 1)
        #expect(reported.count == 0)
    }

    @Test("hands a first failure to the caller rather than retrying it")
    func firstOpenIsNotRetried() {
        let device = FlakyDevice(failing: 1)
        let (session, _) = session(device)

        #expect(throws: AudioCaptureError.noInputDevice) {
            try session.open { _ in }
        }
        #expect(device.log.withLock(\.opens) == 1)
        #expect(session.health == .gone)
    }

    @Test("reopens a device that comes back after several refusals")
    func retriesUntilTheDeviceReturns() async throws {
        let device = FlakyDevice(failing: 0)
        let (session, reported) = session(device)
        try session.open { error in reported.record(error) }

        device.log.withLock { $0.failuresLeft = 3 }
        session.deviceChanged()
        try await untilSettled(session)

        #expect(session.health == .live)
        // One for the first open, three refused, one that took.
        #expect(device.log.withLock(\.opens) == 5)
        #expect(reported.count == 0)
    }

    /// The failure this exists to stop: one refusal used to end the recording with nobody told.
    @Test("says so once when the device never comes back, instead of going quiet")
    func reportsWhenTheDeviceIsGone() async throws {
        let device = FlakyDevice(failing: 0)
        let (session, reported) = session(device, delays: 4)
        try session.open { error in reported.record(error) }

        device.log.withLock { $0.failuresLeft = 99 }
        session.deviceChanged()
        try await untilSettled(session)

        #expect(session.health == .gone)
        #expect(reported.count == 1)
        #expect(reported.first?.recovery == .retry)
        // Every delay in the schedule is tried before giving up.
        #expect(device.log.withLock(\.opens) == 5)
    }

    @Test("a second change while one reopen is in flight does not start another")
    func oneReopenAtATime() async throws {
        let device = FlakyDevice(failing: 0)
        let (session, _) = session(device)
        try session.open { _ in }

        device.log.withLock { $0.failuresLeft = 2 }
        session.deviceChanged()
        session.deviceChanged()
        try await untilSettled(session)

        #expect(session.health == .live)
        #expect(device.log.withLock(\.opens) == 4)
    }

    @Test("closing abandons a reopen rather than letting it reopen a stopped recording")
    func closingStopsTheRetry() async throws {
        let device = FlakyDevice(failing: 0)
        let (session, reported) = session(device)
        try session.open { error in reported.record(error) }

        device.log.withLock { $0.failuresLeft = 99 }
        session.deviceChanged()
        session.close()
        try await untilSettled(session)

        #expect(session.health == .gone)
        #expect(reported.count == 0)
    }

    /// A device opened after the recording stopped is one nothing else would ever shut: see #171.
    @Test("closes a device it opened after the close, rather than stranding it open")
    func neverStrandsADeviceOpen() async throws {
        // Opens succeed, so every attempt leaves a device that something has to close.
        let device = FlakyDevice(failing: 0)
        let (session, _) = session(device)
        try session.open { _ in }

        session.deviceChanged()
        session.close()
        try await untilSettled(session)

        #expect(session.health == .gone)
        // Every open is answered by a close, whichever side of the race the reopen landed.
        #expect(device.log.withLock(\.closes) >= device.log.withLock(\.opens))
    }

    /// Waits for the reopen task, which runs off this one.
    private func untilSettled(_ session: InputDeviceSession) async throws {
        for _ in 0..<200 where session.health == .reopening {
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
