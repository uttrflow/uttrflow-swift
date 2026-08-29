import Synchronization
import Testing

@testable import UttrflowEval

/// Hands out prepared readings in order, then repeats the last one forever.
///
/// The real figures move on their own, so a test that asserted on them would be
/// asserting on whatever else the machine was doing.
private final class ScriptedReadings: Sendable {
    /// Counted separately from the position in the script, which stops at the last
    /// entry. Folding the two together would cap the count at the script's length and
    /// quietly turn "how many readings were taken" into "how much of the script was
    /// used" — a number that cannot tell three readings from thirty.
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
        // `self` rather than a capture list: `Mutex` is non-copyable and cannot be
        // captured by value, and the class is `Sendable` so capturing it is enough.
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

@Suite("Reading this process's memory")
struct MemoryReadingTests {
    @Test("reports both figures for this running process")
    func readsTheRealProcess() {
        let reading = MemoryFootprint.reading()
        #expect(reading != nil)
        #expect((reading?.footprintBytes ?? 0) > 1_000_000, "a running process uses over a megabyte")
        #expect((reading?.residentBytes ?? 0) > 1_000_000)
    }

    /// The one-number form is what ``EvaluationRunner`` has always used, so it has to go
    /// on meaning the footprint and not quietly become the larger figure.
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

    /// An unavailable reading is not zero bytes, and a table row that said zero would be
    /// read as a measurement.
    @Test("a failed reading produces no sample at all")
    func failedReadingIsNotZero() {
        #expect(MemoryFootprint.sample("idle", read: { nil }) == nil)
    }
}

/// Lets a test say exactly how many times the poller reads memory.
///
/// The previous version of this test slept for sixty milliseconds with a one-millisecond
/// interval and asserted that more than two readings had happened. That is an assertion
/// about the scheduler, not about ``PeakMemory``: under load the polling task simply does
/// not get a turn, and the test fails for a reason that has nothing to do with the code
/// it is testing. A manual clock would not have fixed it either — every `sleep` on one
/// returns immediately, which turns the poller into a spin and makes the count *less*
/// predictable.
///
/// So the wait itself is the thing under the test's control. It returns at once for the
/// first `target` polls, and then says stop — which makes the count exact rather than
/// likely, and pins the operation to finish *after* those polls rather than after a
/// stretch of wall clock.
private final class PollGate: Sendable {
    private let target: Int
    private let polls = Mutex(0)
    private let quotaMet: AsyncStream<Void>
    private let announce: AsyncStream<Void>.Continuation

    init(target: Int) {
        self.target = target
        (quotaMet, announce) = AsyncStream.makeStream()
    }

    var wait: @Sendable (Duration) async -> Bool {
        { _ in
            // Counted before the reading it precedes, so the nth call is the one that
            // would produce the nth poll.
            let count = self.polls.withLock { count in
                count += 1
                return count
            }
            guard count > self.target else { return true }
            self.announce.finish()
            // Stopping rather than parking. A gate that never returned would leave the
            // polling task suspended inside this closure for the rest of the test run,
            // which is both a leak and — Swift's task allocator objects — a crash.
            return false
        }
    }

    /// Returns once the poller has taken exactly `target` readings and no more.
    func untilPolled() async { for await _ in quotaMet {} }
}

@Suite("Watching for a peak")
struct PeakMemoryTests {
    @Test("keeps the highest figure seen while the work ran")
    func catchesTheSpike() async {
        let readings = ScriptedReadings([100, 900, 400, 400])
        let gate = PollGate(target: 3)
        let (value, peak) = await PeakMemory.observed(
            interval: .milliseconds(1), read: readings.read, wait: gate.wait
        ) {
            await gate.untilPolled()
            return "done"
        }
        #expect(value == "done")
        #expect(peak?.footprintBytes == 900)
        #expect(peak?.residentBytes == 1_800)
        // One before the work, three while it ran, one after: the middle three are the
        // whole point of polling, and this says so as a number rather than as a hope.
        #expect(readings.callCount == 5)
    }

    /// A spike in the last few milliseconds falls between polls; the reading taken after
    /// the work finishes is what catches it.
    @Test("reads once more after the work finishes")
    func readsAfterTheWork() async {
        let readings = ScriptedReadings([100, 500])
        let (_, peak) = await PeakMemory.observed(
            interval: .seconds(60), read: readings.read
        ) {
            0
        }
        #expect(peak?.footprintBytes == 500)
    }

    @Test("no peak at all when every reading fails")
    func noReadingsMeansNoPeak() async {
        let (value, peak) = await PeakMemory.observed(interval: .seconds(60), read: { nil }) { 7 }
        #expect(value == 7)
        #expect(peak == nil)
    }

    /// A failed journey's peak describes something that did not happen, so the error
    /// comes back rather than a number.
    @Test("rethrows what the work threw")
    func rethrowsTheOperationsError() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await PeakMemory.observed(interval: .seconds(60), read: { nil }) {
                throw Boom()
            }
        }
    }
}
