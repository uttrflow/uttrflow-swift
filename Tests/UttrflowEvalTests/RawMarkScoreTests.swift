// Tests the raw recogniser's marks and case scored per class with an interval over passages.
import Testing

@testable import UttrflowEval

@Suite("Raw mark score")
struct RawMarkScoreTests {
    @Test("a recogniser that writes no mark and no capital scores zero F1 per mark and the lower-case floor")
    func unmarkedOutput() {
        let score = RawMarkScore(
            passageID: "a", raw: "yes i will come tomorrow then lunch",
            reference: "Yes, I will come tomorrow. Then lunch.")
        #expect(score.marks.f1(of: .comma) == 0)
        #expect(score.marks.f1(of: .fullStop) == 0)
        #expect(score.capitalisation.accuracy(of: .sentenceStart) == 0)
        #expect(score.capitalisation.accuracy == score.lowerCaseBaseline.accuracy)
    }

    @Test("a matching output scores one everywhere and the interval collapses onto it")
    func exactOutput() {
        let reference = "Yes, I will come. Then lunch?"
        let report = RawMarkReport([
            RawMarkScore(passageID: "a", raw: reference, reference: reference),
            RawMarkScore(passageID: "b", raw: reference, reference: reference),
        ])
        #expect(report.f1(of: .comma)?.value == 1)
        #expect(report.f1(of: .comma)?.interval == 1...1)
        #expect(report.accuracy(of: .pronounI)?.value == 1)
    }

    @Test("an interval over passages brackets a pooled figure that differs between passages")
    func intervalBracketsValue() throws {
        let right = RawMarkScore(passageID: "a", raw: "Well, we left.", reference: "Well, we left.")
        let wrong = RawMarkScore(passageID: "b", raw: "Well we left.", reference: "Well, we left.")
        let report = RawMarkReport([right, wrong, right, wrong])
        let result = try #require(report.f1(of: .comma))
        #expect(result.interval.contains(result.value))
        #expect(result.interval.lowerBound < result.interval.upperBound)
    }

    @Test("a single passage has no interval to resample, so it reports the value alone")
    func singlePassage() throws {
        let report = RawMarkReport([RawMarkScore(passageID: "a", raw: "Hi.", reference: "Hi.")])
        let result = try #require(report.f1(of: .fullStop))
        #expect(result.interval == result.value...result.value)
    }
}
