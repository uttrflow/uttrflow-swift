import UttrflowCore
import Testing

@testable import UttrflowEval

@Suite("Describing the machine")
struct MachineDescriptionTests {
    /// Read off this Mac rather than typed into a document afterwards, which is the only
    /// way a set of figures cannot be quoted against the wrong hardware.
    @Test("reads this Mac")
    func readsThisMac() {
        let machine = MachineDescription.current()
        #expect(machine.chip.isEmpty == false)
        #expect(machine.chip != "unknown")
        #expect(machine.memoryBytes > 1_000_000_000)
        #expect(machine.operatingSystem.hasPrefix("macOS"))
    }
}

@Suite("Performance report")
struct PerformanceReportTests {
    private func reading(_ footprint: Int64) -> MemoryReading {
        MemoryReading(footprintBytes: footprint, residentBytes: footprint * 2)
    }

    private func timeline(_ footprints: [Int64], peak: Int64? = nil) -> MemoryTimeline {
        MemoryTimeline(
            samples: footprints.enumerated().map {
                MemorySample(label: "moment \($0.offset)", reading: reading($0.element))
            },
            peak: peak.map(reading)
        )
    }

    private func report(
        timeline: MemoryTimeline,
        utterances: [UtteranceProfile] = [],
        disk: DiskFootprint = DiskFootprint(speechModelBytes: 100, applicationBytes: nil)
    ) -> PerformanceReport {
        PerformanceReport(
            machine: MachineDescription(chip: "test", memoryBytes: 8, operatingSystem: "macOS"),
            modelLoad: ModelLoadProfile(first: .seconds(4), warm: .seconds(1), addedBytes: 10),
            timeline: timeline,
            leak: LeakCheck(footprints: []),
            utterances: utterances,
            disk: disk
        )
    }

    /// The first moment is a baseline, not a change, and showing its absolute value in
    /// the change column would read as a jump from nothing.
    @Test("the first moment has no change to report")
    func firstIncrementIsAbsent() {
        #expect(timeline([10, 30, 25]).increments == [nil, 20, -5])
        #expect(timeline([]).increments.isEmpty)
    }

    @Test("the peak is the highest of everything seen, sampled or not")
    func peakIsTheHighest() {
        #expect(report(timeline: timeline([10, 90], peak: 120)).peakFootprintBytes == 120)
        #expect(report(timeline: timeline([10, 90])).peakFootprintBytes == 90)
        #expect(report(timeline: timeline([])).peakFootprintBytes == nil)
    }

    /// Driven by the pipeline's own list of stages, so a stage added to the product turns
    /// up in the report the day something times it.
    @Test("only stages something timed are listed")
    func timedStages() {
        let utterance = UtteranceProfile(
            length: .short, audioSeconds: 3,
            endToEnd: DurationSummary(
                typical: .seconds(1), slowest: .seconds(1), samples: 1, failures: 0),
            stages: [
                StageLatency(
                    stage: .transformation, typical: .seconds(1), slowest: .seconds(1), samples: 1,
                    failures: 0)
            ],
            unmeasuredStages: [.capture, .transcription, .insertion])
        let report = report(timeline: timeline([1]), utterances: [utterance])
        #expect(report.timedStages == [.transformation])
        #expect(report.scaling(of: .transformation).verdict == .undetermined)
        #expect(report.scaling.verdict == .undetermined)
    }

    @Test("a disk figure adds up only what was measured")
    func diskTotals() {
        #expect(DiskFootprint(speechModelBytes: 100, applicationBytes: nil).totalBytes == 100)
        #expect(DiskFootprint(speechModelBytes: 100, applicationBytes: 20).totalBytes == 120)
    }

    @Test("warming saves a stated fraction of the first load")
    func warmSaving() {
        let load = ModelLoadProfile(first: .seconds(4), warm: .seconds(1), addedBytes: nil)
        #expect(load.savedByWarming == 0.75)
        #expect(ModelLoadProfile(first: .seconds(4), warm: nil, addedBytes: nil).savedByWarming == nil)
    }

    /// A warm load that somehow took longer is not a negative saving; the honest thing
    /// to say is that it saved nothing.
    @Test("a slower warm load saves nothing rather than a negative amount")
    func warmSavingNeverNegative() {
        let load = ModelLoadProfile(first: .seconds(1), warm: .seconds(4), addedBytes: nil)
        #expect(load.savedByWarming == 0)
        #expect(ModelLoadProfile(first: .zero, warm: .seconds(1), addedBytes: nil).savedByWarming == nil)
    }
}
