// Tests measuring disagreement between repeated recogniser runs over the same audio.
import Testing

@testable import UttrflowEval

@Suite("Run-to-run spread")
struct RunToRunSpreadTests {
    private let first = TranscriptionCase(
        id: "first", language: .english, stressor: .everyday,
        romanised: "ship the build on friday morning")
    private let second = TranscriptionCase(
        id: "second", language: .english, stressor: .everyday,
        romanised: "the review is due today")

    private func run(_ firstText: String, _ secondText: String) -> TranscriptionReport {
        TranscriptionReport(
            label: "run",
            scores: [
                TranscriptionScorer.score(firstText, against: first),
                TranscriptionScorer.score(secondText, against: second),
            ])
    }

    @Test("identical runs have no spread and every passage agrees")
    func identical() {
        let spread = RunToRunSpread(runs: [
            run("ship the build on friday morning", "the review is due today"),
            run("ship the build on friday morning", "the review is due today"),
        ])
        #expect(spread.differing.isEmpty)
        #expect(spread.identicalPassageRate == 1)
        #expect(spread.overallSpreadPercentagePoints == 0)
        #expect(spread.passages.map(\.identicalTextRate) == [1, 1])
    }

    @Test("names the passage that differs and its rate spread")
    func differingPassage() throws {
        let spread = RunToRunSpread(runs: [
            run("ship the build on friday morning", "the review is due today"),
            run("ship the build on friday morning", "the review is due today"),
            run("ship the bill on friday morning", "the review is due today"),
            run("ship the build on friday morning", "the review is due today"),
        ])
        #expect(spread.differing.map(\.id) == ["first"])
        #expect(spread.identicalPassageRate == 0.5)
        let passage = try #require(spread.passages.first)
        #expect(passage.runs == 4)
        #expect(passage.distinctTranscripts == 2)
        #expect(passage.identicalTextRate == 0.75)
        let points = try #require(passage.spreadPercentagePoints)
        #expect(abs(points - 100.0 / 6) < 1e-9)
        let overall = try #require(spread.overallSpreadPercentagePoints)
        #expect(abs(overall - 100.0 / 11) < 1e-9)
    }

    @Test("counts a punctuation-only difference as different text even when the rate is equal")
    func surfaceDifferenceIsNotIdentical() {
        let spread = RunToRunSpread(runs: [
            run("ship the build on friday morning", "the review is due today"),
            run("Ship the build on Friday morning.", "the review is due today"),
        ])
        #expect(spread.differing.map(\.id) == ["first"])
        #expect(spread.passages.first?.spreadPercentagePoints == 0)
    }

    @Test("prints the methodology table row with the machine it was measured on")
    func tableRow() {
        let spread = RunToRunSpread(runs: [
            run("ship the build on friday morning", "the review is due today"),
            run("ship the bill on friday morning", "the review is due today"),
        ])
        let machine = MachineDescription(
            chip: "Example Chip", memoryBytes: 0, operatingSystem: "macOS Version 1.0 (Build 1A1)")
        #expect(
            spread.tableRow(on: machine)
                == "| Example Chip | macOS Version 1.0 (Build 1A1) | 2 | 1 of 2 (50.0%) | 9.09 | first |")
        #expect(RunToRunSpread(runs: []).tableRow(on: machine).hasSuffix("| 0 | n/a | n/a | none |"))
    }

    @Test("reports nothing measured for no runs rather than zero spread")
    func empty() {
        let spread = RunToRunSpread(runs: [])
        #expect(spread.identicalPassageRate == nil)
        #expect(spread.overallSpreadPercentagePoints == nil)
    }
}
