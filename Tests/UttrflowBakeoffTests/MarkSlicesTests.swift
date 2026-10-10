// Tests that stored bake-off results keep punctuation per case, so it can be read per destination and per language.
import Foundation
import Testing
import UttrflowCore
@testable import UttrflowEval
@testable import uttrflow_bakeoff

struct MarkSlicesTests {
    static let wanted = "First, the plan. Then, the test?"
    static let withoutCommas = "First the plan. Then the test?"

    /// One attempted case scored on its marks only.
    static func score(_ sample: EvaluationCase, output: String) -> CaseScore {
        let marks = PunctuationTally.measure(output, against: wanted)
        return CaseScore(
            caseID: sample.id, similarity: 1, markAccuracy: marks.accuracy, keptEverythingRequired: true,
            lost: [], isExact: false, marks: marks)
    }

    static func stored(_ scores: [CaseScore]) -> StoredReport {
        StoredReport(EvaluationReport(label: "rules", scores: scores, durations: scores.map { _ in .zero }))
    }

    @Test("commas lost only in English lower English comma F1 and leave Hindi and every other mark whole")
    func languageSlice() throws {
        let english = try #require(EvaluationCorpus.all.first { $0.language == .english })
        let hindi = try #require(EvaluationCorpus.all.first { $0.language == .hindi })
        let report = Self.stored([
            Self.score(english, output: Self.withoutCommas), Self.score(hindi, output: Self.wanted),
        ])
        let englishMarks = try #require(report.marks(where: { $0.language == "en" }))
        let hindiMarks = try #require(report.marks(where: { $0.language == "hi" }))
        #expect(englishMarks.f1(of: .comma) == 0)
        #expect(englishMarks.f1(of: .fullStop) == 1)
        #expect(englishMarks.f1(of: .question) == 1)
        #expect(hindiMarks.f1(of: .comma) == 1)
    }

    @Test("a slice is summed only over its own destination")
    func destinationSlice() throws {
        let plain = try #require(EvaluationCorpus.all.first { $0.destination == .plain })
        let other = try #require(EvaluationCorpus.all.first { $0.destination != .plain })
        let report = Self.stored([
            Self.score(plain, output: Self.wanted), Self.score(other, output: Self.withoutCommas),
        ])
        let plainMarks = try #require(report.marks(where: { $0.destination == Destination.plain.rawValue }))
        let otherMarks = try #require(report.marks(where: { $0.destination == other.destination.rawValue }))
        #expect(plainMarks.f1(of: .comma) == 1)
        #expect(otherMarks.f1(of: .comma) == 0)
        #expect(otherMarks.wanted[.comma] == 2)
    }

    @Test("a result stored before marks were kept per case has no slice, rather than a perfect one")
    func olderResultHasNoSlice() throws {
        let json: [String: Any] = [
            "passRate": 1.0, "meanSimilarity": 1.0, "medianSeconds": 0.0, "slowestSeconds": 0.0,
            "declinedCount": 0, "lostWordCount": 0,
            "cases": [
                [
                    "caseID": "case-1", "category": "everyday", "destination": "plain", "similarity": 1.0,
                    "lost": [String](), "passed": true, "declined": false,
                ]
            ],
        ]
        let report = try JSONDecoder().decode(
            StoredReport.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(report.marks(where: { _ in true }) == nil)
    }
}
