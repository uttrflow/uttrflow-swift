import Synchronization
import Testing
import UttrflowCore
import UttrflowTestSupport

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
    private let said = Mutex<[CaptureInterruption]>([])

    var count: Int { said.withLock(\.count) }
    var first: CaptureInterruption? { said.withLock(\.first) }

    /// The error of the first ending reported, which is what a caller acts on.
    var firstError: AudioCaptureError? {
        said.withLock { said in
            said.compactMap { if case .ended(let error) = $0 { error } else { nil } }.first
        }
    }

    func record(_ interruption: CaptureInterruption) {
        said.withLock { $0.append(interruption) }
    }
}

/// A device whose numbered opens can run a step first, so a stop can land while one is in progress.
private final class ScriptedDevice: InputDevice, Sendable {
    struct Log {
        var opens = 0
        var shuts = 0
        var isOpen = false
    }

    let log = Mutex(Log())
    private let steps = Mutex<[Int: @Sendable () -> Bool]>([:])

    /// Runs `step` inside the open with this number, before it finishes; a false return refuses the open.
    func during(open number: Int, _ step: @escaping @Sendable () -> Bool) {
        steps.withLock { $0[number] = step }
    }

    var opens: Int { log.withLock(\.opens) }
    var shuts: Int { log.withLock(\.shuts) }
    var isOpen: Bool { log.withLock(\.isOpen) }

    func open() throws(AudioCaptureError) {
        let number = log.withLock { log -> Int in
            log.opens += 1
            return log.opens
        }
        let step = steps.withLock { $0.removeValue(forKey: number) }
        guard step?() ?? true else { throw .noInputDevice }
        log.withLock { $0.isOpen = true }
    }

    func close() {
        log.withLock { log in
            if log.isOpen { log.shuts += 1 }
            log.isOpen = false
        }
    }
}

/// A pause that holds each reopen attempt until the test lets it go.
private final class Gate: Sendable {
    private let released: AsyncStream<Void>
    private let release: AsyncStream<Void>.Continuation

    init() {
        (released, release) = AsyncStream.makeStream()
    }

    func pause() async {
        for await _ in released { return }
    }

    func letGo() {
        release.yield()
    }
}

/// The device outliving one failed reopen is the whole point: see Docs/microphone.md.
@Suite("An input device session", .timeLimit(.minutes(1)))
struct InputDeviceSessionTests {
    /// No real waiting, so the schedule is exercised without the test taking its three seconds.
    private func session(_ device: FlakyDevice, delays: Int = 5) -> (InputDeviceSession, Reports) {
        let schedule = ReopenSchedule(delays: Array(repeating: .zero, count: delays))
        return (InputDeviceSession(device: device, schedule: schedule, pause: { _ in }), Reports())
    }

    /// A session whose attempts each wait at the gate until the test lets them go.
    private func gated(_ device: any InputDevice, _ gate: Gate, attempts: Int = 1) -> InputDeviceSession {
        InputDeviceSession(
            device: device, schedule: ReopenSchedule(delays: Array(repeating: .zero, count: attempts)),
            pause: { _ in await gate.pause() })
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
        await session.deviceChanged()?.value

        #expect(session.health == .live)
        // One for the first open, three refused, one that took.
        #expect(device.log.withLock(\.opens) == 5)
        // Said even though it worked: the recording now has a hole where the device was away.
        #expect(reported.count == 1)
        #expect(reported.first == .began)
    }

    /// The silence this closes: a reopen that works still costs the words spoken while it was away.
    @Test("says the recording has a hole the moment the device goes")
    func reportsAGapWhenTheDeviceReturns() async throws {
        let device = FlakyDevice(failing: 0)
        let (session, reported) = session(device)
        try session.open { interruption in reported.record(interruption) }

        device.log.withLock { $0.failuresLeft = 1 }
        await session.deviceChanged()?.value

        #expect(session.health == .live)
        #expect(reported.first == .began)
        #expect(reported.firstError == nil, "going away is not yet a failure")
    }

    /// The failure this exists to stop: one refusal used to end the recording with nobody told.
    @Test("says so once when the device never comes back, instead of going quiet")
    func reportsWhenTheDeviceIsGone() async throws {
        let device = FlakyDevice(failing: 0)
        let (session, reported) = session(device, delays: 4)
        try session.open { error in reported.record(error) }

        device.log.withLock { $0.failuresLeft = 99 }
        await session.deviceChanged()?.value

        #expect(session.health == .gone)
        // The hole as it opened, then the ending when nothing filled it.
        #expect(reported.count == 2)
        #expect(reported.first == .began)
        #expect(reported.firstError?.recovery == .retry)
        // Every delay in the schedule is tried before giving up.
        #expect(device.log.withLock(\.opens) == 5)
    }

    @Test("a second change while one reopen is in flight does not start another")
    func oneReopenAtATime() async throws {
        let device = FlakyDevice(failing: 0)
        let gate = Gate()
        let session = gated(device, gate, attempts: 5)
        try session.open { _ in }

        device.log.withLock { $0.failuresLeft = 2 }
        let retry = session.deviceChanged()
        #expect(session.deviceChanged() == nil)
        for _ in 0..<3 { gate.letGo() }
        await retry?.value

        #expect(session.health == .live)
        #expect(device.log.withLock(\.opens) == 4)
    }

    /// A stop landing mid-reopen used to report nothing, so the truncated recording read as whole.
    @Test("keeps the hole reported when the recording stops mid-reopen", .timeLimit(.minutes(1)))
    func closingStopsTheRetry() async throws {
        let device = ScriptedDevice()
        let gate = Gate()
        let session = gated(device, gate)
        let reported = Reports()
        try session.open { reported.record($0) }

        let retry = session.deviceChanged()
        // The gate stays shut, so only the cancellation the close sends can end the pause.
        session.close()
        await retry?.value

        #expect(retry != nil)
        #expect(session.health == .gone)
        // Said before the retry began, so the close cancelling it costs the caller nothing.
        #expect(reported.count == 1)
        #expect(reported.first == .began)
        #expect(device.opens == 1, "a cancelled retry never reaches the device")
    }

    /// The stop lands before the retry is recorded, so only the health check after the pause can catch it.
    @Test("abandons the reopen when the recording stops as the hole is reported")
    func stopAsTheHoleIsReported() async throws {
        let device = ScriptedDevice()
        let session = InputDeviceSession(
            device: device, schedule: ReopenSchedule(delays: [.zero]), pause: { _ in })
        try session.open { if $0 == .began { session.close() } }

        let retry = session.deviceChanged()
        await retry?.value

        #expect(retry != nil)
        #expect(session.health == .gone)
        #expect(device.opens == 1, "nothing reopens a device the recording has let go of")
        #expect(!device.isOpen)
    }

    /// A device opened after the recording stopped is one nothing else would ever shut: see #171.
    @Test("closes a device it opened after the close, rather than stranding it open")
    func neverStrandsADeviceOpen() async throws {
        let device = ScriptedDevice()
        let gate = Gate()
        let session = gated(device, gate)
        try session.open { _ in }
        device.during(open: 2) {
            session.close()
            return true
        }

        let retry = session.deviceChanged()
        gate.letGo()
        await retry?.value

        #expect(session.health == .gone)
        #expect(device.opens == 2)
        // Every open is answered by a close, including the one that finished after the stop.
        #expect(device.shuts == device.opens)
        #expect(!device.isOpen, "the microphone is left open after the recording stopped")
    }

    @Test("reports no ending when the recording stops while the last retry is failing")
    func stopDuringAFailingRetry() async throws {
        let device = ScriptedDevice()
        let gate = Gate()
        let session = gated(device, gate)
        let reported = Reports()
        try session.open { reported.record($0) }
        device.during(open: 2) {
            session.close()
            return false
        }

        let retry = session.deviceChanged()
        gate.letGo()
        await retry?.value

        #expect(session.health == .gone)
        #expect(reported.count == 1)
        #expect(reported.firstError == nil, "a stop is not the device failing")
    }

    /// A retry that gives up after a stop must not end the recording that started since.
    @Test("leaves the next recording alone when a stale retry gives up")
    func staleRetryLeavesTheNextRecording() async throws {
        let device = ScriptedDevice()
        let gate = Gate()
        let session = gated(device, gate)
        try session.open { _ in }
        let next = Reports()
        device.during(open: 2) {
            session.close()
            try? session.open { next.record($0) }
            return false
        }

        let retry = session.deviceChanged()
        gate.letGo()
        await retry?.value

        #expect(session.health == .live)
        #expect(next.count == 0, "the next recording is told it ended")
        #expect(device.isOpen)
    }

    /// Waits for the reopen task, which runs off this one.
    private func untilSettled(_ session: InputDeviceSession) async throws {
        try await eventually { session.health != .reopening }
    }
}
