// Tests the seam ledger: the cuts a change may name, each with a reason, that the baseline does not list.
import Foundation
import Testing

@testable import UttrflowEval

@Suite("Seam ledger")
struct SeamLedgerTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    private static let baseline = SeamBaseline(cuts: ["alpha@1"])

    @Test("a cut the ledger names is tolerated and one nobody names still fails")
    func namedCutsAreTolerated() throws {
        let ledger = try SeamLedger(parsing: "beta@2 a name the joiner capitalises\n")
        let keys = ["alpha@1", "beta@2", "gamma@3"]
        #expect(ledger.unnamed(among: keys, baseline: Self.baseline) == ["gamma@3"])
    }

    @Test("comments and blank lines are ignored")
    func skipsCommentsAndBlanks() throws {
        let ledger = try SeamLedger(parsing: "# why\n\nbeta@2 reason\n")
        #expect(ledger.entries == [SeamLedger.Entry(cut: "beta@2", reason: "reason")])
    }

    @Test("a line with no reason, no cut or a repeated cut is refused")
    func refusesBadLines() {
        #expect(throws: SeamLedger.Failure.noReason(line: 1)) { try SeamLedger(parsing: "beta@2\n") }
        #expect(throws: SeamLedger.Failure.noReason(line: 2)) { try SeamLedger(parsing: "a@1 ok\nb@2   \n") }
        #expect(throws: SeamLedger.Failure.notACut(line: 1)) { try SeamLedger(parsing: "beta why\n") }
        #expect(throws: SeamLedger.Failure.notACut(line: 1)) { try SeamLedger(parsing: "@2 why\n") }
        let twice = "a@1 x\na@1 y\n"
        #expect(throws: SeamLedger.Failure.listedTwice(cut: "a@1")) { try SeamLedger(parsing: twice) }
    }

    @Test("appended lines name each cut with the reason and read back")
    func linesRoundTrip() throws {
        let text = SeamLedger.lines(for: ["a@1", "a@2,3"], reason: "the stop the joiner writes")
        #expect(try SeamLedger(parsing: text).cuts == ["a@1", "a@2,3"])
    }

    @Test("the committed ledger parses and names no cut the baseline already lists")
    func committedLedgerIsWellFormed() throws {
        let url = Self.root.appending(path: "Scripts/seam_ledger.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        let ledger = try SeamLedger(parsing: text)
        let data = try Data(contentsOf: Self.root.appending(path: "Scripts/seam_baseline.json"))
        let baseline = try JSONDecoder().decode(SeamBaseline.self, from: data)
        let listed = Set(baseline.cuts).union(baseline.osDependent?.cuts ?? [])
        #expect(ledger.cuts.isDisjoint(with: listed))
    }
}
