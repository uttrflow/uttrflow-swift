// Tests the performance profiler against a scripted machine.
import UttrflowCore
import UttrflowTestSupport
import Synchronization
import Testing

@testable import UttrflowEval

/// A machine whose memory reads `base + step × readings`, since how often the profiler polls is scheduling.
private final class FakeMemory: Sendable {
    private let base: Int64
    private let step: Int64
    private let reads = Mutex(Int64(0))

    init(base: Int64 = 100_000_000, step: Int64 = 0) {
        self.base = base
        self.step = step
    }

    var read: @Sendable () -> MemoryReading? {
        // `self` rather than a capture list: `Mutex` is non-copyable, and the class is `Sendable`.
        {
            let taken = self.reads.withLock { count -> Int64 in
                defer { count += 1 }
                return count
            }
            let value = self.base + self.step * taken
            return MemoryReading(footprintBytes: value, residentBytes: value * 2)
        }
    }
}

/// Counts what the profiler asks for, so the order and number of calls can be asserted.
private final class Calls: Sendable {
    let loads = Mutex(0)
    let dictations = Mutex<[ProfilePassage.Length]>([])
    let phases = Mutex<[PerformanceProfiler.Phase]>([])
}

@Suite("Performance profiler")
struct PerformanceProfilerTests {
    private let disk = DiskFootprint(speechModelBytes: 646, applicationBytes: 13)

    private func recordings() -> [ProfileRecording] {
        [
            ProfileRecording(passage: ProfileCorpus.short, audioSeconds: 3),
            ProfileRecording(passage: ProfileCorpus.medium, audioSeconds: 14),
            ProfileRecording(passage: ProfileCorpus.long, audioSeconds: 58),
        ]
    }

    private func profile(
        configuration: PerformanceProfiler.Configuration = .init(repetitions: 2, leakRepetitions: 3),
        memory: FakeMemory = FakeMemory(),
        calls: Calls = Calls(),
        loads: Bool = true,
        stages: @escaping @Sendable (ProfileRecording) -> [StageMeasurement] = { _ in
            [.init(stage: .transcription, duration: .seconds(1), succeeded: true)]
        }
    ) async -> PerformanceReport {
        let clock = ManualClock()
        return await PerformanceProfiler(configuration: configuration).run(
            recordings: recordings(),
            disk: disk,
            machine: MachineDescription(chip: "test", memoryBytes: 8, operatingSystem: "macOS"),
            read: memory.read,
            clock: clock,
            onPhase: { phase in calls.phases.withLock { $0.append(phase) } },
            loadSpeechModel: {
                calls.loads.withLock { $0 += 1 }
                clock.advance(by: .seconds(calls.loads.withLock { $0 } == 1 ? 4 : 1))
                return loads
            },
            dictate: { recording in
                calls.dictations.withLock { $0.append(recording.passage.length) }
                clock.advance(by: .seconds(2))
                return stages(recording)
            }
        )
    }

    @Test("the timeline names every moment, in the order they happen")
    func timelineIsOrdered() async {
        let report = await profile()
        #expect(
            report.timeline.samples.map(\.label) == [
                "idle, nothing loaded", "speech model loaded", "after one dictation",
                "after 3 dictations", "after the length sweep",
            ])
    }

    /// The first dictation pays for buffers every later one reuses, and counting it would look like a leak.
    @Test("the leak check watches exactly the repetitions asked for, after a warm-up")
    func leakLoopExcludesWarmUp() async {
        let calls = Calls()
        let report = await profile(calls: calls)

        #expect(report.leak.footprints.count == 3)
        let mediumDictations = calls.dictations.withLock { $0 }.count { $0 == .medium }
        #expect(mediumDictations == 1 + 3 + 2, "warm-up, then the leak loop, then the sweep")
    }

    /// Memory that only climbs is the defect this command exists to find, and the verdict must come up.
    @Test("memory that only ever climbs comes back as a leak")
    func reportsALeak() async {
        let report = await profile(memory: FakeMemory(step: 20_000_000))
        #expect(report.leak.footprints == report.leak.footprints.sorted())
        #expect(report.leak.neverFellBack)
        #expect(report.leak.verdict == .leaking)
        #expect(report.leak.passed == false)
    }

    @Test("memory that stays put comes back clean")
    func reportsNoLeak() async {
        let report = await profile()
        #expect(report.leak.growthBytes == 0)
        #expect(report.leak.verdict == .clean)
        #expect(report.leak.passed)
    }

    @Test("each length is timed the number of times configured")
    func timesEveryLength() async {
        let report = await profile()
        #expect(report.utterances.map(\.length) == [.short, .medium, .long])
        #expect(report.utterances.map(\.endToEnd.samples) == [2, 2, 2])
        #expect(report.utterances.map(\.audioSeconds) == [3, 14, 58])
        #expect(report.utterances.allSatisfy { $0.endToEnd.typical == .seconds(2) })
    }

    /// Audio read off disk means capture is never timed here, and a zero would read as "instant".
    @Test("stages nothing timed are named rather than shown as zero")
    func namesUnmeasuredStages() async {
        let report = await profile()
        #expect(report.timedStages == [.transcription])
        #expect(
            report.utterances.first?.unmeasuredStages == [
                .capture, .correction, .transformation, .expansion, .insertion,
            ])
    }

    @Test("a dictation that failed is counted, not dropped")
    func countsFailures() async {
        let report = await profile(stages: { _ in
            [.init(stage: .transcription, duration: .seconds(1), succeeded: false)]
        })
        #expect(report.utterances.allSatisfy { $0.endToEnd.failures == 2 })
    }

    @Test("a dictation that produced no timings at all is a failure too")
    func emptyStagesAreFailures() async {
        let report = await profile(stages: { _ in [] })
        #expect(report.utterances.allSatisfy { $0.endToEnd.failures == 2 })
        #expect(report.timedStages.isEmpty)
    }

    /// A profile of a recogniser that did not load would be a page of zeroes posing as a result.
    @Test("a model that will not load stops the profile rather than reporting zeroes")
    func refusesToProfileWithoutAModel() async {
        let calls = Calls()
        let report = await profile(calls: calls, loads: false)
        #expect(report.utterances.isEmpty)
        #expect(report.leak.footprints.isEmpty)
        #expect(report.modelLoad.warm == nil)
        #expect(calls.dictations.withLock { $0 }.isEmpty)
        #expect(report.timeline.samples.count == 2, "idle and the failed load are still real")
    }

    /// The user meets the first load; the warm one comes last, or it would double every footprint above.
    @Test("the model is loaded twice, and the warm load comes after everything else")
    func measuresBothLoads() async {
        let calls = Calls()
        let report = await profile(calls: calls)
        #expect(calls.loads.withLock { $0 } == 2)
        #expect(report.modelLoad.first == .seconds(4))
        #expect(report.modelLoad.warm == .seconds(1))
        #expect(calls.phases.withLock { $0 }.last == .measuringWarmLoad)
    }

    @Test("what the loaded model added is the difference between the first two moments")
    func reportsWhatTheModelAdded() async {
        // Nothing reads memory between the two moments, so the difference is exactly one step.
        let report = await profile(memory: FakeMemory(step: 690))
        #expect(report.modelLoad.addedBytes == 690)
    }

    @Test("progress is announced for every phase")
    func announcesProgress() async {
        let calls = Calls()
        _ = await profile(calls: calls)
        let phases = calls.phases.withLock { $0 }
        #expect(phases.first == .loadingModel)
        #expect(phases.contains(.warmingUp))
        #expect(phases.contains(.repeating(dictation: 3, of: 3)))
        #expect(phases.contains(.timing(.long, run: 2, of: 2)))
    }

    /// Without polling, a spike that settled before the next named moment would never appear.
    @Test("the peak is folded in from readings taken during the dictations")
    func recordsThePeak() async {
        let report = await profile(memory: FakeMemory(step: 1_000))
        let highestLeakReading = report.leak.footprints.max() ?? 0
        #expect((report.timeline.peak?.footprintBytes ?? 0) >= highestLeakReading)
        #expect(report.timeline.peak?.residentBytes == (report.timeline.peak?.footprintBytes ?? 0) * 2)
        #expect((report.peakFootprintBytes ?? 0) >= highestLeakReading)
    }

    @Test("the disk figures are carried through untouched")
    func carriesDisk() async {
        let report = await profile()
        #expect(report.disk == disk)
        #expect(report.machine.chip == "test")
    }

    /// A machine that will not answer at all must not silently become a row of zeroes.
    @Test("no memory readings means no timeline rather than a zeroed one")
    func handlesUnreadableMemory() async {
        let clock = ManualClock()
        let report = await PerformanceProfiler(
            configuration: .init(repetitions: 1, leakRepetitions: 1)
        ).run(
            recordings: recordings(), disk: disk,
            machine: MachineDescription(chip: "test", memoryBytes: 8, operatingSystem: "macOS"),
            read: { nil }, clock: clock,
            loadSpeechModel: { true },
            dictate: { _ in [] }
        )
        #expect(report.timeline.samples.isEmpty)
        #expect(report.timeline.peak == nil)
        #expect(report.leak.footprints.isEmpty)
        #expect(report.leak.verdict == .undetermined)
        #expect(report.modelLoad.addedBytes == nil)
    }
}

@Suite("The passages the profile speaks")
struct ProfileCorpusTests {
    @Test("one passage of each length, shortest first")
    func oneOfEachLength() {
        #expect(ProfileCorpus.all.map(\.length) == ProfilePassage.Length.allCases)
        #expect(ProfilePassage.Length.allCases.map(\.targetSeconds) == [3, 15, 60])
    }

    /// Three lengths rather than two, because two points cannot show a bend.
    @Test("the passages get longer, and none is empty")
    func lengthsIncrease() {
        let lengths = ProfileCorpus.all.map(\.text.count)
        #expect(lengths == lengths.sorted())
        #expect(ProfileCorpus.all.allSatisfy { !$0.text.isEmpty })
        #expect(Set(ProfileCorpus.all.map(\.id)).count == 3)
    }

    @Test("a passage is reachable by its length")
    func lookUpByLength() {
        for passage in ProfileCorpus.all {
            #expect(ProfileCorpus.passage(passage.length) == passage)
        }
    }

    /// Fillers, a restart and a version number are what the recogniser meets, not clean prose.
    @Test("the paragraph carries the things that make dictation hard")
    func passagesAreRealistic() {
        #expect(ProfileCorpus.medium.text.contains("um"))
        #expect(ProfileCorpus.medium.text.contains("two point four point one"))
        #expect(ProfileCorpus.long.text.contains("Arjun"))
    }
}
