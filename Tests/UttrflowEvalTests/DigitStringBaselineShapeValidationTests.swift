// Checks saved digit-string comparisons reject duplicate shape names without terminating.
import Foundation
import Testing

@testable import UttrflowEval

/// Exercises decoded shape identity and the unchanged digit-string comparison rules.
@Suite("Digit-string baseline shape validation")
struct DigitStringBaselineShapeValidationTests {
    private let row = """
        {"shape":"oh-for-zero","rawExact":2,"finalExact":2,"cases":2}
        """

    private func decoded(shapes: String, label: String = "synthetic") throws -> DigitStringBaseline {
        let json = """
            {"label":"\(label)","recordedAt":"2026-01-01T00:00:00Z","shapes":[\(shapes)]}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DigitStringBaseline.self, from: Data(json.utf8))
    }

    private var duplicateFailure: Result<[DigitShape], DigitStringBaseline.Incomparable> {
        .failure(.init(reason: "shape names must be unique in each digit-string report"))
    }

    @Test func duplicateBaselineShapesAreIncomparable() throws {
        let baseline = try decoded(shapes: "\(row),\(row)")
        let measured = try decoded(shapes: row)
        #expect(baseline.shapes.count == 2)
        #expect(baseline.worsened(in: measured) == duplicateFailure)
    }

    @Test func duplicateMeasuredShapesAreIncomparable() throws {
        let baseline = try decoded(shapes: row)
        let measured = try decoded(shapes: "\(row),\(row)")
        #expect(measured.shapes.count == 2)
        #expect(baseline.worsened(in: measured) == duplicateFailure)
    }

    @Test func duplicatesInBothReportsAreIncomparable() throws {
        let duplicated = try decoded(shapes: "\(row),\(row)")
        #expect(duplicated.worsened(in: duplicated) == duplicateFailure)
    }

    @Test func labelMismatchRetainsPrecedence() throws {
        let baseline = try decoded(shapes: "\(row),\(row)")
        let measured = try decoded(shapes: row, label: "other")
        #expect(
            baseline.worsened(in: measured)
                == .failure(.init(reason: "measured \"other\", baseline \"synthetic\"")))
    }

    @Test func emptyReportsRemainComparable() throws {
        let empty = try decoded(shapes: "")
        #expect(empty.worsened(in: empty) == .success([]))
    }

    @Test(arguments: ["rawExact", "finalExact"])
    func uniqueReportsRetainBothRegressionGates(field: String) throws {
        let baseline = try decoded(shapes: row)
        let measured = try decoded(
            shapes: row.replacingOccurrences(of: "\"\(field)\":2", with: "\"\(field)\":1"))
        #expect(baseline.worsened(in: baseline) == .success([]))
        #expect(baseline.worsened(in: measured) == .success([.ohForZero]))
    }

    @Test func differentCaseCountsRemainIncomparable() throws {
        let baseline = try decoded(shapes: row)
        let measured = try decoded(shapes: row.replacingOccurrences(of: "\"cases\":2", with: "\"cases\":1"))
        #expect(
            baseline.worsened(in: measured)
                == .failure(.init(reason: "the cases per shape differ from the baseline's")))
    }

    @Test func reorderedUniqueShapesRemainIncomparable() throws {
        let time = row.replacingOccurrences(of: "oh-for-zero", with: "time")
        let baseline = try decoded(shapes: "\(row),\(time)")
        let measured = try decoded(shapes: "\(time),\(row)")
        #expect(
            baseline.worsened(in: measured)
                == .failure(.init(reason: "the cases per shape differ from the baseline's")))
    }
}
