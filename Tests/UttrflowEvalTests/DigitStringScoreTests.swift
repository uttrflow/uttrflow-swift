import Testing
import UttrflowCore

@testable import UttrflowEval

@Suite("Scoring digit strings and codes by their exact characters")
struct DigitStringScoreTests {
    @Test("a span matches across spaces, hyphens, case and outer punctuation")
    func matchesItsCharacters() {
        #expect(DigitSpan.holds(["QX417"], in: "Our flight is qx-417."))
        #expect(DigitSpan.holds(["456789"], in: "The number is 456, 789."))
        #expect(DigitSpan.holds(["7:45"], in: "The call is at 7:45."))
        #expect(DigitSpan.holds(["2024", "300"], in: "In 2024 we shipped 300 units."))
    }

    @Test(
        "a wrong character, a missing span, a span inside a longer number or spans out of order do not match")
    func refusesNearMisses() {
        #expect(!DigitSpan.holds(["7:45"], in: "The call is at 7.45."))
        #expect(!DigitSpan.holds(["405"], in: "The meeting is in room four oh five."))
        #expect(!DigitSpan.holds(["405"], in: "The meeting is in room 4056."))
        #expect(!DigitSpan.holds(["2024", "300"], in: "We shipped 300 units in 2024."))
        #expect(!DigitSpan.holds([""], in: "Anything at all."))
    }

    @Test("a loss the rules made is blamed on the pass that touched the span, and no other")
    func blamesThePassThatLostTheSpan() {
        let testCase = DigitStringCase(
            id: "t", shape: .ohForZero, spoken: "room four oh five", spans: ["405"])
        let record = CleaningRecord(changes: [
            .init(step: .firstWord, replaced: [.init(from: "room", to: "Room")]),
            .init(step: .numberForms, replaced: [.init(from: "405", to: "4 05")]),
        ])
        let lost = DigitStringOutcome(testCase, raw: "room 405", final: "Room 4 O5", record: record)
        #expect(lost.rawExact && !lost.finalExact)
        #expect(lost.blamed == [.numberForms])

        let kept = DigitStringOutcome(testCase, raw: "room 405", final: "Room 405.", record: record)
        #expect(kept.finalExact && kept.blamed.isEmpty)
    }

    @Test("rows are per shape, flag a shape the rules make worse and print the passes blamed")
    func reportsPerShape() {
        let oh = DigitStringCase(id: "a", shape: .ohForZero, spoken: "", spans: ["405"])
        let time = DigitStringCase(id: "b", shape: .time, spoken: "", spans: ["7:45"])
        let record = CleaningRecord(changes: [.init(step: .numberForms, removed: ["405"])])
        let report = DigitStringReport([
            DigitStringOutcome(oh, raw: "405", final: "", record: record),
            DigitStringOutcome(oh, raw: "405", final: "405", record: nil),
            DigitStringOutcome(time, raw: "7 45", final: "7:45", record: nil),
        ])
        #expect(report.rows.map(\.shape) == [.ohForZero, .time])
        #expect(report.worseAfterRules.map(\.shape) == [.ohForZero])
        #expect(report.rows[1].raw.hits == 0 && report.rows[1].final.hits == 1)
        #expect(
            report.table.contains(
                "| oh-for-zero | 1.00 (0.34-1.00, 2/2) | 0.50 (0.09-0.91, 1/2) | numberForms (1) |"))
        #expect(report.table.contains("| time | 0.00 (0.00-0.79, 0/1) | 1.00 (0.21-1.00, 1/1) | - |"))
        #expect(DigitStringReport([]).table.split(separator: "\n").count == 2)
    }

    @Test(
        "the class holds at least eighty cases, ten or more per shape, each id unique and each span written")
    func classIsBigEnough() {
        let all = DigitStringCorpus.all
        #expect(all.count >= 80)
        #expect(Set(all.map(\.id)).count == all.count)
        for shape in DigitShape.allCases {
            #expect(all.filter { $0.shape == shape }.count >= 10, "\(shape.rawValue)")
        }
        #expect(all.allSatisfy { !$0.spans.isEmpty && !$0.spoken.contains(where: \.isNumber) })
        #expect(all.allSatisfy { DigitSpan.holds($0.spans, in: $0.spans.joined(separator: " ")) })
    }
}
