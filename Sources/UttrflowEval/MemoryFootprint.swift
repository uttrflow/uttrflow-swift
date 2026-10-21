// Reads and polls this process's memory use.
import Foundation
import Synchronization

/// Footprint and resident size together; only the second shows mapped weights. See Docs/eval-profiling.md.
public struct MemoryReading: Sendable, Equatable {
    /// `phys_footprint`: dirty and compressed pages, what Activity Monitor calls Memory and limits act on.
    public let footprintBytes: Int64
    /// `resident_size`: every page in RAM including mapped model weights, so it overstates the cost.
    public let residentBytes: Int64

    public init(footprintBytes: Int64, residentBytes: Int64) {
        self.footprintBytes = footprintBytes
        self.residentBytes = residentBytes
    }
}

/// What the process weighed at one named moment, with the label travelling beside the numbers.
public struct MemorySample: Sendable, Equatable {
    public let label: String
    public let reading: MemoryReading

    public init(label: String, reading: MemoryReading) {
        self.label = label
        self.reading = reading
    }
}

/// Reads how much memory this process is using, reported per model because 16 GB Macs are a target.
public enum MemoryFootprint {
    /// The footprint alone, for callers that only ever wanted the one number.
    public static func current() -> Int64? { reading()?.footprintBytes }

    /// Both figures from a single `task_info` call, so they describe the same instant.
    public static func reading() -> MemoryReading? {
        var info = task_vm_info_data_t()
        guard MachTask.fill(&info, flavor: TASK_VM_INFO) else { return nil }
        return MemoryReading(
            footprintBytes: Int64(info.phys_footprint), residentBytes: Int64(info.resident_size))
    }

    /// Reads memory now under `label`, through an injectable `read`; `nil` when the reading fails.
    public static func sample(
        _ label: String, read: () -> MemoryReading? = MemoryFootprint.reading
    ) -> MemorySample? {
        read().map { MemorySample(label: label, reading: $0) }
    }
}

/// The `task_info` calls this process makes about itself.
enum MachTask {
    /// Fills `info` with one flavour of the kernel's view of this task, answering whether it agreed to.
    static func fill<Info>(_ info: inout Info, flavor: Int32) -> Bool {
        var count = mach_msg_type_number_t(MemoryLayout<Info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(flavor), $0, &count)
            }
        }
        return result == KERN_SUCCESS
    }
}

/// Polls memory while something slow runs, so a spike that settles before the end is still seen.
public enum PeakMemory {
    /// How often memory is read: fast enough to catch a model materialising, slow enough not to be the cost.
    public static let defaultInterval = Duration.milliseconds(20)

    /// Runs `operation` sampling memory throughout; `clock` is injectable so a test controls the reading count.
    public static func observed<Success, Failure: Error>(
        interval: Duration = defaultInterval,
        read: @escaping @Sendable () -> MemoryReading? = MemoryFootprint.reading,
        clock: some Clock<Duration> = ContinuousClock(),
        during operation: () async throws(Failure) -> Success
    ) async throws(Failure) -> (value: Success, peak: MemoryReading?) {
        let recorder = Recorder(read: read)
        recorder.observe()
        let poller = Task {
            while (try? await clock.sleep(for: interval)) != nil {
                // Checked after the sleep too: a reading after cancellation belongs to the caller's next work.
                guard !Task.isCancelled else { break }
                recorder.observe()
            }
        }
        // Stopped by a flag the poller's reads honour, never by awaiting it, which would queue behind other work.
        let value: Success
        do {
            value = try await operation()
        } catch {
            poller.cancel()
            recorder.stop()
            throw error
        }
        poller.cancel()

        // One last reading after the work, so a peak in the final milliseconds does not fall between polls.
        recorder.observe()
        return (value, recorder.stop())
    }
}

/// Keeps the highest of each figure seen; locked because the poller and the caller both write.
private final class Recorder: Sendable {
    private struct State {
        var peak: MemoryReading?
        var stopped = false
    }

    private let read: @Sendable () -> MemoryReading?
    private let state = Mutex(State())

    init(read: @escaping @Sendable () -> MemoryReading?) {
        self.read = read
    }

    func observe() {
        state.withLock { state in
            guard !state.stopped, let now = read() else { return }
            guard let highest = state.peak else {
                state.peak = now
                return
            }
            state.peak = MemoryReading(
                footprintBytes: max(highest.footprintBytes, now.footprintBytes),
                residentBytes: max(highest.residentBytes, now.residentBytes)
            )
        }
    }

    /// Ends observation for good and returns the highest figures seen.
    @discardableResult
    func stop() -> MemoryReading? {
        state.withLock { state in
            state.stopped = true
            return state.peak
        }
    }
}
