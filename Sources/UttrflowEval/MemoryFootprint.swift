import Foundation

/// Two ways of saying how much memory this process is using, read together.
///
/// They differ, and the gap is the whole story for a product that memory-maps a 646 MB
/// CoreML model: the mapped weights are clean, file-backed pages, so they show in the
/// resident size and not in the footprint.
public struct MemoryReading: Sendable, Equatable {
    /// `phys_footprint` — what Activity Monitor calls Memory, and what a memory limit is
    /// enforced against. Dirty and compressed pages, not clean file-backed ones. The
    /// number that decides whether a Mac starts swapping.
    public let footprintBytes: Int64
    /// `resident_size` — every page currently in physical RAM, mapped model weights
    /// included. Larger, and evictable under pressure, so it overstates the cost; but a
    /// report that showed only the footprint would look as though 300 MB of model had
    /// gone missing.
    public let residentBytes: Int64

    public init(footprintBytes: Int64, residentBytes: Int64) {
        self.footprintBytes = footprintBytes
        self.residentBytes = residentBytes
    }
}

/// What the process weighed at one named moment in its life.
///
/// The label travels with the numbers because a column of bytes with the moments implied
/// by row order is exactly the table someone mis-reads a year later.
public struct MemorySample: Sendable, Equatable {
    public let label: String
    public let reading: MemoryReading

    public init(label: String, reading: MemoryReading) {
        self.label = label
        self.reading = reading
    }
}

/// Reads how much memory this process is actually using.
///
/// Reported per model because a laptop with 16 GB is a target, and a model that wins
/// on quality but needs 12 GB has not won.
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

    /// Reads memory now and names the moment.
    ///
    /// - Parameters:
    ///   - label: What the process had just done.
    ///   - read: Where the numbers come from. Injectable so a profile can be driven
    ///     through a test with figures the test chose.
    /// - Returns: `nil` when the reading failed, which is the same distinction
    ///   ``reading()`` draws — an unavailable number is not zero bytes.
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

/// Watches memory while something slow runs, so a spike that settles again is still seen.
///
/// Readings taken before and after a transcription say nothing about the middle, and the
/// middle is where a 16 GB Mac is pushed into swap. The only way to catch that from
/// inside the process is to keep asking.
public enum PeakMemory {
    /// How often memory is read while `operation` runs.
    ///
    /// Fast enough to catch a CoreML model materialising its weights, slow enough that
    /// the polling itself is not part of what is being measured.
    public static let defaultInterval = Duration.milliseconds(20)

    /// Runs `operation`, sampling memory throughout.
    ///
    /// - Parameters:
    ///   - interval: How often to read. Injectable so a test does not have to wait.
    ///   - read: Where the readings come from. Injectable for the same reason: the real
    ///     figures move on their own, and a test that asserted on them would assert on
    ///     the machine rather than on this code.
    ///   - wait: Pauses between readings, and says whether to take another. Injectable
    ///     for a sharper reason than convenience: the default waits on the wall clock, so
    ///     a test asserting that polling actually happened would really be asserting that
    ///     the machine was not busy — and on a loaded Mac it fails. A test supplies a wait
    ///     it controls and gets an exact number of readings. A `Clock` would not do:
    ///     every manual clock in this codebase returns from `sleep` immediately, which
    ///     turns the poller into a spin and makes the count *less* predictable, not more.
    ///     Returning `false` is how the default reports cancellation, and how a test says
    ///     it has seen enough — either way the poller finishes rather than being left
    ///     suspended inside somebody else's closure.
    ///   - operation: The work to watch. Non-escaping, so it runs on the caller's
    ///     context exactly as it would without the watching.
    /// - Returns: Whatever `operation` returned, and the highest of each figure seen —
    ///   `nil` only when every reading failed. Each field is its own maximum and the two
    ///   may come from different instants, which is what "peak" has to mean when the
    ///   process is only sampled.
    /// - Throws: Rethrows whatever `operation` threw, with the peak discarded. A failed
    ///   operation's peak describes a journey that did not finish.
    public static func observed<Success, Failure: Error>(
        interval: Duration = defaultInterval,
        read: @escaping @Sendable () -> MemoryReading? = MemoryFootprint.reading,
        wait: @escaping @Sendable (Duration) async -> Bool = PeakMemory.sleeping,
        during operation: () async throws(Failure) -> Success
    ) async throws(Failure) -> (value: Success, peak: MemoryReading?) {
        let recorder = Recorder(read: read)
        await recorder.observe()
        let poller = Task {
            while await wait(interval) {
                // Checked after the wait as well: cancellation can land while a reading
                // is being taken, and a reading taken then belongs to whatever the caller
                // does next, not to this work.
                guard !Task.isCancelled else { break }
                await recorder.observe()
            }
        }
        // Cancelled *and waited for*, on both paths, rather than abandoned in a `defer`.
        // An abandoned poller outlives the call that started it: it can take one more
        // reading and attribute it to work that has already finished, and the process it
        // belongs to may tear its stack down underneath it. Waiting costs one scheduler
        // hop and makes the function say exactly what it did.
        let value: Success
        do {
            value = try await operation()
        } catch {
            await stop(poller)
            throw error
        }
        await stop(poller)

        // One last reading after the work finishes: a peak reached in the final
        // milliseconds would otherwise fall between polls and go unreported.
        await recorder.observe()
        return (value, await recorder.peak)
    }

    /// The default wait: sleep, and carry on unless this task has been cancelled.
    ///
    /// A named function rather than a closure literal in the default argument. A default
    /// argument is compiled at the call site, so an `async` closure written there has its
    /// frame allocated by whichever task evaluates it — and when that is not the task
    /// that later awaits it, the runtime's allocator is entitled to object.
    public static func sleeping(for interval: Duration) async -> Bool {
        do { try await Task.sleep(for: interval) } catch { return false }
        return true
    }

    private static func stop(_ poller: Task<Void, Never>) async {
        poller.cancel()
        await poller.value
    }
}

/// Keeps the highest of each figure seen. An actor because the poller and the caller
/// both write to it.
private actor Recorder {
    private let read: @Sendable () -> MemoryReading?
    private(set) var peak: MemoryReading?

    init(read: @escaping @Sendable () -> MemoryReading?) {
        self.read = read
    }

    func observe() {
        guard let now = read() else { return }
        guard let highest = peak else {
            peak = now
            return
        }
        peak = MemoryReading(
            footprintBytes: max(highest.footprintBytes, now.footprintBytes),
            residentBytes: max(highest.residentBytes, now.residentBytes)
        )
    }
}
