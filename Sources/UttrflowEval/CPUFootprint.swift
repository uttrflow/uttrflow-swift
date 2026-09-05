import Darwin
import Foundation

/// Processor seconds, cores held busy, cycles and instructions for one stretch. See Docs/eval-profiling.md.
public struct CPUReading: Sendable, Equatable {
    /// Time this process's threads spent running its own code.
    public let userSeconds: Double
    /// Time the kernel spent on its behalf — page faults, the pasteboard, file reads.
    public let systemSeconds: Double
    /// Processor cycles, from the hardware counters. `nil` when the kernel would not say.
    public let cycles: UInt64?
    /// Instructions retired, from the same counters.
    public let instructions: UInt64?

    public init(
        userSeconds: Double, systemSeconds: Double, cycles: UInt64? = nil,
        instructions: UInt64? = nil
    ) {
        self.userSeconds = userSeconds
        self.systemSeconds = systemSeconds
        self.cycles = cycles
        self.instructions = instructions
    }

    /// Everything the process spent, whoever spent it.
    public var cpuSeconds: Double { userSeconds + systemSeconds }
}

/// The difference between two ``CPUReading``s over a known wall-clock stretch; a lone reading is a total.
public struct CPUCost: Sendable, Equatable {
    public let userSeconds: Double
    public let systemSeconds: Double
    public let wallSeconds: Double
    public let cycles: UInt64?
    public let instructions: UInt64?

    public init(
        userSeconds: Double, systemSeconds: Double, wallSeconds: Double,
        cycles: UInt64? = nil, instructions: UInt64? = nil
    ) {
        self.userSeconds = userSeconds
        self.systemSeconds = systemSeconds
        self.wallSeconds = wallSeconds
        self.cycles = cycles
        self.instructions = instructions
    }

    public var cpuSeconds: Double { userSeconds + systemSeconds }

    /// Cores held busy on average (1.0 is one saturated); `nil` for a stretch of no measurable length.
    public var cores: Double? {
        wallSeconds > 0 ? cpuSeconds / wallSeconds : nil
    }

    /// The kernel's share of the processor time; a process living in syscalls is usually polling.
    public var systemShare: Double? {
        cpuSeconds > 0 ? systemSeconds / cpuSeconds : nil
    }

    /// The clock speed the cycles and times imply, so a reader can check the counters against the chip.
    public var gigahertz: Double? {
        guard let cycles, cpuSeconds > 0 else { return nil }
        return Double(cycles) / cpuSeconds / 1e9
    }

    /// Instructions retired per cycle, a rough measure of compute against waiting on memory.
    public var instructionsPerCycle: Double? {
        guard let cycles, let instructions, cycles > 0 else { return nil }
        return Double(instructions) / Double(cycles)
    }

    /// The cost between two readings; `nil` when either is missing, since that is no measurement.
    public static func between(
        _ before: CPUReading?, _ after: CPUReading?, wallSeconds: Double
    ) -> CPUCost? {
        guard let before, let after else { return nil }
        return CPUCost(
            userSeconds: after.userSeconds - before.userSeconds,
            systemSeconds: after.systemSeconds - before.systemSeconds,
            wallSeconds: wallSeconds,
            cycles: subtract(after.cycles, before.cycles),
            instructions: subtract(after.instructions, before.instructions)
        )
    }

    /// Subtracts rising counters, or `nil` when "after" is smaller and the readings are not one run.
    private static func subtract(_ after: UInt64?, _ before: UInt64?) -> UInt64? {
        guard let after, let before, after >= before else { return nil }
        return after - before
    }

    /// The sum of several costs; a counter absent from any piece makes the total absent.
    public static func total(of costs: [CPUCost]) -> CPUCost? {
        guard !costs.isEmpty else { return nil }
        func sum(_ each: (CPUCost) -> UInt64?) -> UInt64? {
            var running: UInt64 = 0
            for cost in costs {
                guard let value = each(cost) else { return nil }
                running += value
            }
            return running
        }
        return CPUCost(
            userSeconds: costs.reduce(0) { $0 + $1.userSeconds },
            systemSeconds: costs.reduce(0) { $0 + $1.systemSeconds },
            wallSeconds: costs.reduce(0) { $0 + $1.wallSeconds },
            cycles: sum(\.cycles),
            instructions: sum(\.instructions)
        )
    }
}

/// Reads times from `task_info` and counters from `proc_pid_rusage`. See Docs/eval-profiling.md.
public enum CPUFootprint {
    /// Everything from both interfaces; `nil` only when the times are unavailable.
    public static func reading() -> CPUReading? {
        guard let times = threadTimes() else { return nil }
        let counters = hardwareCounters()
        return CPUReading(
            userSeconds: times.user, systemSeconds: times.system,
            cycles: counters?.cycles, instructions: counters?.instructions)
    }

    /// Runs `operation` and returns its cost, `nil` when a reading fails; rethrows with the cost discarded.
    public static func measuring<Success, Failure: Error>(
        read: () -> CPUReading? = CPUFootprint.reading,
        clock: some Clock<Duration> = ContinuousClock(),
        _ operation: () async throws(Failure) -> Success
    ) async throws(Failure) -> (value: Success, cost: CPUCost?) {
        let before = read()
        let start = clock.now
        let value = try await operation()
        let elapsed = start.duration(to: clock.now)
        let after = read()
        return (value, CPUCost.between(before, after, wallSeconds: elapsed.inSeconds))
    }

    // MARK: - The two kernel interfaces

    /// Processor time, live threads included.
    private static func threadTimes() -> (user: Double, system: Double)? {
        var basic = task_basic_info_64_data_t()
        var live = task_thread_times_info_data_t()
        guard MachTask.fill(&basic, flavor: TASK_BASIC_INFO_64),
            MachTask.fill(&live, flavor: TASK_THREAD_TIMES_INFO)
        else { return nil }
        return (
            user: seconds(basic.user_time) + seconds(live.user_time),
            system: seconds(basic.system_time) + seconds(live.system_time)
        )
    }

    private static func seconds(_ value: time_value_t) -> Double {
        Double(value.seconds) + Double(value.microseconds) / 1_000_000
    }

    /// Cycles and instructions only; the struct is passed by rebinding its own address, never a pointer's.
    private static func hardwareCounters() -> (cycles: UInt64, instructions: UInt64)? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        return (cycles: info.ri_cycles, instructions: info.ri_instructions)
    }
}
