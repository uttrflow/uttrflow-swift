import Darwin
import Foundation

/// How much processor a stretch of work used, and how hard it worked the machine.
///
/// Memory answers "will it fit". This answers the other half of the same question — what
/// it costs to run — and the two are not interchangeable. A dictation that fits in 274 MB
/// but holds four cores busy for ten seconds is a fan spinning up and a battery draining,
/// and nothing in ``MemoryReading`` would ever say so.
///
/// Four figures, because no one of them survives being quoted alone:
///
/// - **processor seconds** — user plus system, summed across every thread. What the Mac
///   actually spent. Ten seconds of it is ten seconds whether one core or eight did it.
/// - **cores** — processor seconds over wall seconds. 1.0 is one core saturated; 4.0 is
///   four. This is the number a person recognises, because it is what Activity Monitor's
///   CPU column shows, and it is the difference between "busy" and "hot".
/// - **cycles** and **instructions** — read from the processor's own counters. Alone
///   among these they do not depend on how fast this particular Mac is, which is what
///   makes them the only figures here that say anything about a Mac that was not
///   measured.
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

/// The difference between two ``CPUReading``s, over a known stretch of wall clock.
///
/// A reading on its own is a running total since launch and means nothing; every figure
/// worth reporting is a difference. Keeping the subtraction in a type rather than at each
/// call site is what stops a report quoting a total where it meant an increment.
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

    /// How many cores were held busy on average. 1.0 is one saturated; below 1.0 the
    /// process spent part of the stretch waiting rather than computing.
    ///
    /// `nil` for a stretch of no measurable length, where the division would report a
    /// number invented by the clock's resolution rather than by the work.
    public var cores: Double? {
        wallSeconds > 0 ? cpuSeconds / wallSeconds : nil
    }

    /// What fraction of the processor time was the kernel's rather than the app's.
    ///
    /// Worth having on its own because the two have different cures. User time is code
    /// this project wrote or linked; system time is syscalls, and a process that spends
    /// its life there is usually polling something.
    public var systemShare: Double? {
        cpuSeconds > 0 ? systemSeconds / cpuSeconds : nil
    }

    /// The clock speed implied by the cycles and the time they took.
    ///
    /// Reported so that a reader can check the arithmetic against a chip they can look
    /// up. A figure far from this Mac's real clock means the counters and the times
    /// disagree, and that the cycle counts below should not be trusted — which is
    /// exactly the sort of thing that goes unnoticed when only the derived number is
    /// printed.
    public var gigahertz: Double? {
        guard let cycles, cpuSeconds > 0 else { return nil }
        return Double(cycles) / cpuSeconds / 1e9
    }

    /// Instructions retired per cycle. A rough measure of whether the work was compute
    /// or waiting on memory.
    public var instructionsPerCycle: Double? {
        guard let cycles, let instructions, cycles > 0 else { return nil }
        return Double(instructions) / Double(cycles)
    }

    /// The cost of the stretch between two readings.
    ///
    /// - Returns: `nil` when either reading is missing, because a cost computed against
    ///   an absent baseline is not a smaller cost — it is no measurement at all.
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

    /// Counters are unsigned and only ever rise, so a smaller "after" means the two
    /// readings did not come from one uninterrupted run. Dropping to `nil` says so;
    /// wrapping round would report an astronomical figure as though it were work.
    private static func subtract(_ after: UInt64?, _ before: UInt64?) -> UInt64? {
        guard let after, let before, after >= before else { return nil }
        return after - before
    }

    /// The sum of several costs, for a phase measured in pieces.
    ///
    /// A counter absent from any one piece makes the total absent, rather than making it
    /// a sum of the pieces that happened to have it — which would read as a complete
    /// figure and be short by however many were missing.
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

/// Reads how much processor this process has used.
///
/// Two kernel interfaces rather than one, because neither gives both halves and the
/// obvious single call gives the wrong answer:
///
/// - **`task_info`** for the times. `TASK_BASIC_INFO_64` counts threads that have already
///   finished and `TASK_THREAD_TIMES_INFO` counts the ones still running, so both are
///   needed — a process measured by the first alone appears to use no processor at all
///   until its threads exit.
/// - **`proc_pid_rusage`** for the counters, and *only* the counters. Its `ri_user_time`
///   looks like exactly the number wanted and is stale for the calling process: measured
///   against a burn of a known length it reported 0.005 s where the true figure was
///   0.214 s, agreed by `task_info` and `getrusage` independently. The cycle and
///   instruction counts in the same struct were right to the megahertz. So this reads
///   half of one struct and half of another, and the reason is written here because the
///   shorter version of this code is wrong in a way that reports success.
public enum CPUFootprint {
    /// Everything, from both interfaces, as close to one instant as two calls allow.
    ///
    /// - Returns: `nil` only when the times are unavailable. Missing counters are not
    ///   fatal — the times alone still answer "how many cores", which is the figure most
    ///   of this is for.
    public static func reading() -> CPUReading? {
        guard let times = threadTimes() else { return nil }
        let counters = hardwareCounters()
        return CPUReading(
            userSeconds: times.user, systemSeconds: times.system,
            cycles: counters?.cycles, instructions: counters?.instructions)
    }

    /// Runs `operation` and says what it cost.
    ///
    /// - Parameters:
    ///   - read: Where the readings come from. Injectable for the same reason every other
    ///     reader in this file is: the real figures move on their own, and a test that
    ///     asserted on them would be asserting on how busy the Mac was.
    ///   - clock: What the wall stretch is measured against.
    ///   - operation: The work to watch.
    /// - Returns: What `operation` returned, and the cost — `nil` when either reading
    ///   failed.
    /// - Throws: Rethrows whatever `operation` threw, with the cost discarded: the
    ///   processor time spent on a journey that did not finish describes nothing anybody
    ///   can act on.
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

    /// Cycles and instructions, and nothing else out of this struct — see the note on the
    /// type about why its times are not used.
    ///
    /// The buffer is passed by rebinding a pointer to the struct itself. The parameter is
    /// typed `rusage_info_t *`, which reads as a pointer to a pointer and is not: the
    /// kernel writes the whole struct at the address given. Handing it the address of a
    /// pointer variable instead compiles, runs, and overruns the stack.
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
