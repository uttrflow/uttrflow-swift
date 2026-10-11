import Foundation
import Testing
import UttrflowCore
import UttrflowTestSupport

@testable import UttrflowEval

/// The destination coverage matrix: every cell with behaviour of its own has its floor of cases, and the page matches.
@Suite("The destination coverage matrix")
struct DestinationMatrixTests {
    /// The generated page, three folders above this test file.
    static let page = URL(fileURLWithPath: "\(#filePath)").deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Docs/destination-matrix.md")

    /// Cells with behaviour of their own still short of the floor, a baseline that only shrinks.
    static let owedCases: Set<String> = []

    @Test("gives every cell with behaviour of its own the floor of cases, apart from those still owed")
    func everyCellHoldsTheFloor() {
        for row in DestinationMatrix().rows where row.isUnderFloor {
            #expect(
                Self.owedCases.contains(row.cell.description),
                "\(row.cell) has \(row.caseIDs.count) cases, under \(DestinationMatrix.floor)")
        }
    }

    @Test("lists no owed cell that has reached the floor or has no behaviour of its own")
    func owedListHasNoStaleEntry() {
        let under = Set(DestinationMatrix().rows.filter(\.isUnderFloor).map(\.cell.description))
        for owed in Self.owedCases {
            #expect(under.contains(owed), "\(owed) is no longer owed; remove it")
        }
    }

    @Test("gives a field kind behaviour of its own only where the formatter writes it differently")
    func ownBehaviourFollowsTheFormatter() {
        typealias Cell = DestinationMatrix.Cell
        #expect(Destination.allCases.allSatisfy { Cell($0, .primary).hasOwnBehaviour })
        #expect(Destination.allCases.allSatisfy { Cell($0, .search).hasOwnBehaviour })
        #expect(Cell(.document, .oneLine).hasOwnBehaviour)
        #expect(!Cell(.spreadsheet, .oneLine).hasOwnBehaviour)
        #expect(!Cell(.terminal, .oneLine).hasOwnBehaviour)
        #expect(Cell(.email, .recipient).hasOwnBehaviour)
        #expect(Cell(.email, .subject).hasOwnBehaviour)
        #expect(!Cell(.messaging, .recipient).hasOwnBehaviour)
        #expect(!Cell(.document, .subject).hasOwnBehaviour)
    }

    @Test("puts a case in the cell its destination and field read as")
    func placesACase() {
        let field = EvaluationCase(
            id: "field", category: .oneLineField, spoken: "room twelve", expected: "Room 12",
            context: AppContext(accessibilityRole: "AXTextField", isMultiline: false), destination: .document)
        let subject = EvaluationCase(
            id: "subject", category: .contextual, spoken: "invoice", expected: "Invoice",
            context: AppContext(fieldLabel: "Subject"), destination: .email)
        let matrix = DestinationMatrix(cases: [field, subject])
        #expect(matrix.row(.init(.document, .oneLine))?.caseIDs == ["field"])
        #expect(matrix.row(.init(.email, .subject))?.caseIDs == ["subject"])
        #expect(matrix.row(.init(.email, .primary))?.isUnderFloor == true)
        #expect(matrix.row(.init(.spreadsheet, .oneLine))?.isUnderFloor == false)
        #expect(matrix.rows.count == Destination.allCases.count * FieldKind.allCases.count)
    }

    @Test("matches Docs/destination-matrix.md, which is generated from the corpus")
    func pageMatchesCorpus() throws {
        let generated = DestinationMatrix().markdown
        let environment = ProcessInfo.processInfo.environment
        if environment[GoldenFile.updateVariable] == "1", environment["CI"] == nil {
            try generated.write(to: Self.page, atomically: true, encoding: .utf8)
        }
        let recorded = try String(contentsOf: Self.page, encoding: .utf8)
        #expect(recorded == generated, "rerun with \(GoldenFile.updateVariable)=1 to regenerate the page")
    }
}
