import Synchronization
import Testing

@testable import UttrflowEval

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

/// A wait the test controls, so the poll count is exact rather than a claim about the scheduler.
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
            // Counted before the reading it precedes, so the nth call is the one that produces the nth poll.
            let count = self.polls.withLock { count in
                count += 1
                return count
            }
            guard count > self.target else { return true }
            self.announce.finish()
            // Stopping rather than parking: a gate that never returned would leak the polling task and crash.
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
        // One before the work, three while it runs, one after: the middle three are the point of polling.
        #expect(readings.callCount == 5)
    }

    /// A spike in the last few milliseconds falls between polls; the reading after the work catches it.
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

    /// A failed journey's peak describes something that did not happen.
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
