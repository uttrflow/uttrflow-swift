// Tests memory readings and the peak poller.
import Synchronization
import Testing

@testable import UttrflowEval
@testable import UttrflowTestSupport

/// Hands out prepared readings in order, then repeats the last one, since real figures move on their own.
private final class ScriptedReadings: Sendable {
    /// The reading count, kept apart from the script position so thirty readings are not capped at three.
    private struct Progress {
        var next = 0
        var calls = 0
    }

    private let script: [MemoryReading?]
    private let progress = Mutex(Progress())

    init(_ footprints: [Int64?]) {
        script = footprints.map {
            $0.map { MemoryReading(footprintBytes: $0, residentBytes: $0 * 2) }
        }
    }

    var read: @Sendable () -> MemoryReading? {
        // `self` rather than a capture list: `Mutex` is non-copyable, and the class is `Sendable`.
        {
            self.progress.withLock { progress in
                progress.calls += 1
                defer { progress.next = min(progress.next + 1, self.script.count - 1) }
                return self.script.isEmpty
                    ? nil : self.script[min(progress.next, self.script.count - 1)]
            }
        }
    }

    var callCount: Int { progress.withLock { $0.calls } }
}

/// A clock whose sleep never ends, even when cancelled, standing in for a poller a busy machine never schedules again.
private final class StalledClock: Clock, Sendable {
    let now = ContinuousClock.Instant.now
    var minimumResolution: Duration { .nanoseconds(1) }
    /// Kept rather than dropped, so the parked sleeps are never reported as leaked.
    private let parked = Mutex<[CheckedContinuation<Void, Never>]>([])

    func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {
        await withCheckedContinuation { continuation in parked.withLock { $0.append(continuation) } }
    }

    /// Ends every parked sleep, so a test that timed out waiting on one does not hang the run.
    func release() {
        let sleepers = parked.withLock { parked in
            defer { parked = [] }
            return parked
        }
        for sleeper in sleepers { sleeper.resume() }
    }
}

@Suite("Reading this process's memory")
struct MemoryReadingTests {
    @Test("reports both figures for this running process")
    func readsTheRealProcess() {
        let reading = MemoryFootprint.reading()
        #expect(reading != nil)
        #expect((reading?.footprintBytes ?? 0) > 1_000_000, "a running process uses over a megabyte")
        #expect((reading?.residentBytes ?? 0) > 1_000_000)
    }

    /// The one-number form ``EvaluationRunner`` uses has to go on meaning the footprint.
    @Test("the one-number form is the footprint")
    func currentIsTheFootprint() {
        #expect(MemoryFootprint.current() != nil)
        #expect((MemoryFootprint.current() ?? 0) > 1_000_000)
    }

    @Test("a sample carries the moment it describes")
    func samplesAreLabelled() {
        let readings = ScriptedReadings([1_000])
        let sample = MemoryFootprint.sample("idle", read: readings.read)
        #expect(sample?.label == "idle")
        #expect(sample?.reading.footprintBytes == 1_000)
        #expect(sample?.reading.residentBytes == 2_000)
    }

    /// An unavailable reading is not zero bytes, and a row that said zero would be read as a measurement.
    @Test("a failed reading produces no sample at all")
    func failedReadingIsNotZero() {
        #expect(MemoryFootprint.sample("idle", read: { nil }) == nil)
    }
}

@Suite("Watching for a peak")
struct PeakMemoryTests {
    @Test("keeps the highest figure seen while the work ran")
    func catchesTheSpike() async {
        let readings = ScriptedReadings([100, 900, 400, 400])
        let clock = ManualClock()
        let (value, peak) = await PeakMemory.observed(
            interval: .milliseconds(1), read: readings.read, clock: clock
        ) {
            // Advances only once the poller is actually asleep, so the count of polls is exact.
            for _ in 0..<3 { await clock.advanceWhenSomethingIsWaiting(by: .milliseconds(1)) }
            // Asleep again only once it has read after the last advance, so that reading is never cancelled away.
            await clock.waitUntilSomethingIsWaiting()
            return "done"
        }
        #expect(value == "done")
        #expect(peak?.footprintBytes == 900)
        #expect(peak?.residentBytes == 1_800)
        // One before the work, three while it runs, one after: the middle three are the point of polling.
        #expect(readings.callCount == 5)
    }

    /// A spike in the last few milliseconds falls between polls; the reading after the work catches it.
    @Test("reads once more after the work finishes")
    func readsAfterTheWork() async {
        let readings = ScriptedReadings([100, 500])
        let (_, peak) = await PeakMemory.observed(
            interval: .seconds(60), read: readings.read, clock: ManualClock()
        ) {
            0
        }
        #expect(peak?.footprintBytes == 500)
    }

    @Test("no peak at all when every reading fails")
    func noReadingsMeansNoPeak() async {
        let (value, peak) = await PeakMemory.observed(
            interval: .seconds(60), read: { nil }, clock: ManualClock()
        ) { 7 }
        #expect(value == 7)
        #expect(peak == nil)
    }

    /// A failed journey's peak describes something that did not happen.
    @Test("rethrows what the work threw")
    func rethrowsTheOperationsError() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await PeakMemory.observed(interval: .seconds(60), read: { nil }, clock: ManualClock()) {
                throw Boom()
            }
        }
    }

    /// Waiting for the poller would put every watch behind whatever else holds the machine's threads.
    @Test(
        "returns once the work is done, without waiting for the poller to run again",
        .timeLimit(.minutes(1)))
    func neverWaitsForThePoller() async {
        let readings = ScriptedReadings([100, 500])
        let clock = StalledClock()
        let (value, peak) = await withTaskCancellationHandler {
            await PeakMemory.observed(interval: .milliseconds(1), read: readings.read, clock: clock) { 7 }
        } onCancel: {
            clock.release()
        }
        #expect(value == 7)
        #expect(peak?.footprintBytes == 500)
    }

    /// A poller still waiting for a thread when the work starts leaves a test on the injected clock waiting on the scheduler.
    @Test("the poller is asleep on the clock before the work starts")
    func pollerSleepsBeforeTheWork() async {
        let clock = ManualClock()
        let asleep = await PeakMemory.observed(interval: .seconds(60), read: { nil }, clock: clock) {
            clock.advanceIfSomethingIsWaiting(exactly: .seconds(60))
        }.value
        #expect(asleep)
    }

    /// A sleep of no time never suspends, so a poller started on the caller would loop there and the work never run.
    @Test("a zero interval reads only before and after the work")
    func zeroIntervalNeverPolls() async {
        let readings = ScriptedReadings([100, 200])
        let (value, peak) = await PeakMemory.observed(
            interval: .zero, read: readings.read, clock: ManualClock()
        ) { 7 }
        #expect(value == 7)
        #expect(peak?.footprintBytes == 200)
        #expect(readings.callCount == 2)
    }

    /// The poller must never spin: on a clock that never advances, cancelling it must not need a second reading.
    @Test("never polls again once the clock stops moving")
    func neverSpinsOnAStalledClock() async {
        let readings = ScriptedReadings([100])
        let clock = ManualClock()
        _ = await PeakMemory.observed(interval: .milliseconds(1), read: readings.read, clock: clock) {
            await clock.waitUntilSomethingIsWaiting()
        }
        // Before the work, and once more after: nothing in between, since the clock never advanced.
        #expect(readings.callCount == 2)
    }
}
