// Tests the per-group report over real speakers: counts on every row, speaker resampling, insufficient evidence.
import Testing

@testable import UttrflowEval

@Suite("The speaker-group report")
struct SpeakerGroupReportTests {
    /// A fixed invented slice: speakers named by group and number, each with several clips.
    private func slice(
        group: String, label: AccentLabelKind = .verified, speakers: Int, clips: Int, errors: Int,
        decisions: Int = 0, overrides: Int = 0
    ) -> [SpeakerClip] {
        (0..<speakers).flatMap { speaker in
            (0..<clips).map { _ in
                SpeakerClip(
                    speaker: "\(group)-\(speaker)", group: group, label: label,
                    errors: errors + speaker % 3, words: 20, decisions: decisions, falseOverrides: overrides)
            }
        }
    }

    @Test("prints speaker, word and decision counts and an interval on every row")
    func countsOnEveryRow() throws {
        let report = SpeakerGroupReport(clips: slice(group: "north", speakers: 8, clips: 5, errors: 1))
        let row = try #require(report.rows.first)
        #expect(row.speakers == 8)
        #expect(row.words == 800)
        let interval = try #require(row.interval)
        #expect(interval.contains(row.errorRate))
        #expect((row.minimumDetectableDifference ?? 0) > 0)
    }

    @Test("resamples speakers, so correlated clips widen the interval")
    func resamplesSpeakers() throws {
        let fewSpeakers = SpeakerGroupReport(clips: slice(group: "a", speakers: 4, clips: 20, errors: 1))
        let manySpeakers = SpeakerGroupReport(clips: slice(group: "a", speakers: 80, clips: 1, errors: 1))
        let narrow = try #require(manySpeakers.rows.first?.interval)
        let wide = try #require(fewSpeakers.rows.first?.interval)
        #expect(wide.upperBound - wide.lowerBound > narrow.upperBound - narrow.lowerBound)
    }

    @Test("prints insufficient evidence when decisions cannot support the bound")
    func insufficientEvidenceRow() throws {
        let small = SpeakerGroupReport(
            clips: slice(group: "east", speakers: 5, clips: 4, errors: 1, decisions: 10))
        #expect(small.rows.first?.decisionClaim == .insufficientEvidence(needed: 3_000))
        #expect(
            small.lines.contains { $0.hasPrefix("east\tverified") && $0.contains("insufficient evidence") })
        let large = SpeakerGroupReport(
            clips: slice(group: "west", speakers: 10, clips: 10, errors: 1, decisions: 40))
        #expect(large.rows.first?.decisionClaim == .upperBound(3.0 / 4_000))
    }

    @Test("a single speaker gives no rate interval")
    func oneSpeaker() {
        let report = SpeakerGroupReport(clips: slice(group: "solo", speakers: 1, clips: 9, errors: 2))
        #expect(report.rows.first?.interval == nil)
        #expect(report.lines[1].contains("insufficient evidence"))
    }

    @Test("never pools verified and self-described labels")
    func labelsStayApart() {
        let clips =
            slice(group: "south", speakers: 4, clips: 2, errors: 1)
            + slice(group: "south", label: .selfDescribed, speakers: 4, clips: 2, errors: 1)
        let report = SpeakerGroupReport(clips: clips)
        #expect(report.rows.map(\.label) == [.selfDescribed, .verified])
        #expect(report.differences.isEmpty)
    }

    @Test("flags a difference only when its interval excludes zero")
    func differenceVerdict() throws {
        let apart = SpeakerGroupReport(
            clips: slice(group: "a", speakers: 30, clips: 3, errors: 0)
                + slice(group: "b", speakers: 30, clips: 3, errors: 6))
        #expect(try #require(apart.differences.first).isDetected)
        let same = SpeakerGroupReport(
            clips: slice(group: "a", speakers: 6, clips: 3, errors: 1)
                + slice(group: "b", speakers: 6, clips: 3, errors: 1))
        let difference = try #require(same.differences.first)
        #expect(!difference.isDetected)
        #expect(same.lines.last?.contains("no difference detectable") == true)
    }

    @Test("gives the same report for the same slice every time")
    func deterministic() {
        let clips =
            slice(group: "a", speakers: 7, clips: 3, errors: 1)
            + slice(group: "b", speakers: 5, clips: 2, errors: 2)
        #expect(SpeakerGroupReport(clips: clips) == SpeakerGroupReport(clips: clips))
    }
}
