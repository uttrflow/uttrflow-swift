import Testing

@testable import UttrflowEval

private func reading(
    user: Double, system: Double, cycles: UInt64? = nil, instructions: UInt64? = nil
) -> CPUReading {
    CPUReading(
        userSeconds: user, systemSeconds: system, cycles: cycles, instructions: instructions)
}

@Suite("Reading this process's processor use")
struct CPUFootprintTests {
    @Test("A reading off the real machine has both halves")
    func realReading() {
        guard let reading = CPUFootprint.reading() else {
            Issue.record("the kernel would not report processor time")
            return
        }
        // System time may be zero on a very short-lived process, so it is bounded rather than required.
        #expect(reading.userSeconds > 0)
        #expect(reading.systemSeconds >= 0)
        #expect(reading.cpuSeconds == reading.userSeconds + reading.systemSeconds)
    }

    /// `proc_pid_rusage` reports a stale `ri_user_time` for the calling process. See Docs/eval-profiling.md.
    @Test("Processor time keeps up with work actually done")
    func timesAreNotStale() {
        guard let before = CPUFootprint.reading() else {
            Issue.record("the kernel would not report processor time")
            return
        }
        var accumulator = 0.0
        for step in 1...12_000_000 { accumulator += Double(step).squareRoot() }
        #expect(accumulator > 0)
        guard let after = CPUFootprint.reading() else {
            Issue.record("the kernel stopped reporting processor time")
            return
        }
        // Deliberately loose: "moved by the right order", not "took exactly so long" on a busy machine.
        #expect(after.cpuSeconds - before.cpuSeconds > 0.001)
    }

    @Test("Counters that only rise")
    func countersRise() {
        guard let before = CPUFootprint.reading(), let after = CPUFootprint.reading() else {
            Issue.record("the kernel would not report processor time")
            return
        }
        #expect(after.cpuSeconds >= before.cpuSeconds)
        if let first = before.cycles, let second = after.cycles { #expect(second >= first) }
    }

    @Test("Measuring hands back what the work returned, and what it cost")
    func measuring() async {
        let (value, cost) = await CPUFootprint.measuring(
            read: { reading(user: 1, system: 0.25, cycles: 100, instructions: 250) }
        ) {
            "done"
        }
        #expect(value == "done")
        // Both readings come from one stub, so every difference is zero: the subtraction happened.
        #expect(cost?.cpuSeconds == 0)
        #expect(cost?.cycles == 0)
    }

    @Test("A failed reading is not a cost of zero")
    func unreadable() async {
        let (_, cost) = await CPUFootprint.measuring(read: { nil }) { 1 }
        #expect(cost == nil)
    }

    @Test("Work that threw reports no cost")
    func throwing() async {
        struct Failure: Error {}
        await #expect(throws: Failure.self) {
            try await CPUFootprint.measuring(read: CPUFootprint.reading) {
                throw Failure()
            }
        }
    }
}

@Suite("What a stretch of work cost")
struct CPUCostTests {
    @Test("Cores is processor seconds over wall seconds")
    func cores() {
        let cost = CPUCost(userSeconds: 6, systemSeconds: 2, wallSeconds: 2)
        #expect(cost.cpuSeconds == 8)
        #expect(cost.cores == 4)
        #expect(cost.systemShare == 0.25)
    }

    @Test("A stretch of no length has no core figure")
    func instantaneous() {
        let cost = CPUCost(userSeconds: 1, systemSeconds: 0, wallSeconds: 0)
        #expect(cost.cores == nil)
    }

    @Test("Work of no length has no kernel share")
    func nothingSpent() {
        #expect(CPUCost(userSeconds: 0, systemSeconds: 0, wallSeconds: 1).systemShare == nil)
    }

    @Test("The implied clock and instructions per cycle are derived, not stored")
    func derivedCounters() {
        let cost = CPUCost(
            userSeconds: 2, systemSeconds: 0, wallSeconds: 1,
            cycles: 8_000_000_000, instructions: 16_000_000_000)
        #expect(cost.gigahertz == 4)
        #expect(cost.instructionsPerCycle == 2)
    }

    @Test("Without counters there is no clock to imply")
    func noCounters() {
        let cost = CPUCost(userSeconds: 1, systemSeconds: 0, wallSeconds: 1)
        #expect(cost.gigahertz == nil)
        #expect(cost.instructionsPerCycle == nil)
    }

    @Test("No cycles, no instructions per cycle")
    func noCycles() {
        let cost = CPUCost(
            userSeconds: 1, systemSeconds: 0, wallSeconds: 1, cycles: 0, instructions: 10)
        #expect(cost.instructionsPerCycle == nil)
    }

    @Test("The difference between two readings")
    func between() {
        let cost = CPUCost.between(
            reading(user: 1, system: 0.5, cycles: 100, instructions: 300),
            reading(user: 4, system: 1.0, cycles: 400, instructions: 900),
            wallSeconds: 1.5)
        #expect(cost?.userSeconds == 3)
        #expect(cost?.systemSeconds == 0.5)
        #expect(cost?.cycles == 300)
        #expect(cost?.instructions == 600)
    }

    @Test("A missing reading at either end is not a cost")
    func missingEnd() {
        #expect(CPUCost.between(nil, reading(user: 1, system: 0), wallSeconds: 1) == nil)
        #expect(CPUCost.between(reading(user: 1, system: 0), nil, wallSeconds: 1) == nil)
    }

    /// Unsigned subtraction would report the wrap as nineteen quintillion cycles of work.
    @Test("A counter that went backwards is dropped, not wrapped")
    func wentBackwards() {
        let cost = CPUCost.between(
            reading(user: 1, system: 0, cycles: 400, instructions: 900),
            reading(user: 2, system: 0, cycles: 100, instructions: 300),
            wallSeconds: 1)
        #expect(cost?.cycles == nil)
        #expect(cost?.instructions == nil)
        #expect(cost?.userSeconds == 1)
    }

    @Test("Several costs add up")
    func total() {
        let total = CPUCost.total(of: [
            CPUCost(userSeconds: 1, systemSeconds: 0.5, wallSeconds: 2, cycles: 10, instructions: 20),
            CPUCost(userSeconds: 2, systemSeconds: 0.5, wallSeconds: 3, cycles: 30, instructions: 40),
        ])
        #expect(total?.userSeconds == 3)
        #expect(total?.systemSeconds == 1)
        #expect(total?.wallSeconds == 5)
        #expect(total?.cycles == 40)
        #expect(total?.instructions == 60)
    }

    /// A total that dropped the missing piece would read as complete and be short.
    @Test("A counter missing from one piece makes the total absent")
    func partialCounters() {
        let total = CPUCost.total(of: [
            CPUCost(userSeconds: 1, systemSeconds: 0, wallSeconds: 1, cycles: 10, instructions: 20),
            CPUCost(userSeconds: 1, systemSeconds: 0, wallSeconds: 1),
        ])
        #expect(total?.userSeconds == 2)
        #expect(total?.cycles == nil)
        #expect(total?.instructions == nil)
    }

    @Test("Nothing to total")
    func empty() {
        #expect(CPUCost.total(of: []) == nil)
    }
}

@Suite("Processor cost in a length profile")
struct UtteranceProfileCPUTests {
    private func profile(cpu: CPUCost?, runs: Int, audioSeconds: Double = 10) -> UtteranceProfile {
        UtteranceProfile(
            length: .medium, audioSeconds: audioSeconds,
            endToEnd: DurationSummary(
                typical: .seconds(1), slowest: .seconds(1), samples: runs, failures: 0),
            stages: [], unmeasuredStages: [], cpu: cpu, runs: runs)
    }

    @Test("Per dictation is the total over the runs it covers")
    func perDictation() {
        let measured = profile(
            cpu: CPUCost(userSeconds: 6, systemSeconds: 0, wallSeconds: 3), runs: 3)
        #expect(measured.cpuSecondsPerDictation == 2)
        #expect(measured.cpuSecondsPerAudioSecond == 0.2)
    }

    @Test("No runs, no per-dictation figure")
    func noRuns() {
        #expect(
            profile(cpu: CPUCost(userSeconds: 1, systemSeconds: 0, wallSeconds: 1), runs: 0)
                .cpuSecondsPerDictation == nil)
    }

    @Test("No processor reading, no figure")
    func unmeasured() {
        #expect(profile(cpu: nil, runs: 3).cpuSecondsPerDictation == nil)
        #expect(profile(cpu: nil, runs: 3).cpuSecondsPerAudioSecond == nil)
    }

    @Test("Silence has no per-second cost")
    func noAudio() {
        let measured = profile(
            cpu: CPUCost(userSeconds: 1, systemSeconds: 0, wallSeconds: 1), runs: 1,
            audioSeconds: 0)
        #expect(measured.cpuSecondsPerAudioSecond == nil)
    }
}
