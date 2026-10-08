// How many corpus cases each destination and kind of field has, and which cells the formatter treats apart.
import Foundation
import UttrflowCore

/// The corpus read as a grid of destination by field kind, so a cell with behaviour and no cases is visible.
public struct DestinationMatrix: Sendable, Equatable {
    /// The fewest cases a cell with behaviour of its own needs.
    static let floor = 8

    /// One destination and one kind of field in it.
    struct Cell: Sendable, Hashable, CustomStringConvertible {
        let destination: Destination
        let kind: FieldKind

        init(_ destination: Destination, _ kind: FieldKind) {
            self.destination = destination
            self.kind = kind
        }

        var description: String { "\(destination.rawValue)/\(kind.rawValue)" }

        /// Whether the formatter writes this field apart: the primary field always, any other where its formatter differs.
        var hasOwnBehaviour: Bool {
            guard kind != .primary else { return true }
            let app = Self.representative(kind)
            let situation = Situation(app: app, insertion: app.insertionPoint, destination: destination)
            return DestinationFormatter.fieldKind(of: situation) == kind
                && DestinationFormatter.standard(for: situation)
                    != DestinationFormatter.standard(for: destination)
        }

        /// A field of this kind with nothing else on screen, as Accessibility reports one.
        static func representative(_ kind: FieldKind) -> AppContext {
            switch kind {
            case .primary: .unknown
            case .oneLine: AppContext(accessibilityRole: "AXTextField", isMultiline: false)
            case .search: AppContext(accessibilityRole: "AXSearchField")
            case .recipient: AppContext(fieldLabel: "To")
            case .subject: AppContext(fieldLabel: "Subject")
            }
        }
    }

    /// One cell's case ids, in corpus order.
    struct Row: Sendable, Equatable {
        let cell: Cell
        let caseIDs: [String]
        let hasOwnBehaviour: Bool

        /// Whether the cell has behaviour of its own and fewer cases than the floor.
        var isUnderFloor: Bool { hasOwnBehaviour && caseIDs.count < DestinationMatrix.floor }
    }

    let rows: [Row]

    /// The matrix read from `cases`, one row per destination and field kind whether or not any case is in it.
    public init(cases: [EvaluationCase] = EvaluationCorpus.all) {
        let kinds = Dictionary(grouping: cases) { testCase in
            Cell(testCase.destination, DestinationFormatter.fieldKind(of: testCase.situation))
        }
        rows = Destination.allCases.flatMap { destination in
            FieldKind.allCases.map { kind in
                let cell = Cell(destination, kind)
                return Row(
                    cell: cell, caseIDs: (kinds[cell] ?? []).map(\.id), hasOwnBehaviour: cell.hasOwnBehaviour)
            }
        }
    }

    /// The row of one cell.
    func row(_ cell: Cell) -> Row? { rows.first { $0.cell == cell } }

    /// What one cell shows: its count, and why that count is short or has no floor.
    private func entry(_ cell: Cell) -> String {
        guard let row = row(cell) else { return "" }
        if !row.hasOwnBehaviour { return "\(row.caseIDs.count), none shipped" }
        return row.isUnderFloor ? "\(row.caseIDs.count), under \(Self.floor)" : "\(row.caseIDs.count)"
    }

    /// The matrix as plain lines, one per destination, as the bake-off prints it.
    public var lines: [String] {
        let width = 18
        let header =
            "destination".padding(toLength: 14, withPad: " ", startingAt: 0)
            + FieldKind.allCases.map { $0.rawValue.padding(toLength: width, withPad: " ", startingAt: 0) }
            .joined()
        return [header]
            + Destination.allCases.map { destination in
                destination.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
                    + FieldKind.allCases.map {
                        entry(Cell(destination, $0)).padding(toLength: width, withPad: " ", startingAt: 0)
                    }.joined()
            }
    }

    /// The matrix as the Markdown page `Docs/destination-matrix.md` holds.
    var markdown: String {
        var lines = [
            "# Destination coverage matrix",
            "",
            "Generated from `EvaluationCorpus.all`; do not edit by hand.",
            "Regenerate with `UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter DestinationMatrixTests`.",
            "A case's cell is its own destination and the field kind `DestinationFormatter.fieldKind(of:)` reads",
            "from its context. A cell has behaviour of its own when the formatter writes that field differently",
            "from the destination's primary field, and then needs \(Self.floor) cases; any other is listed as none shipped.",
            "",
            "| Destination | " + FieldKind.allCases.map(\.rawValue).joined(separator: " | ") + " |",
            "|---|" + String(repeating: "---|", count: FieldKind.allCases.count),
        ]
        for destination in Destination.allCases {
            let entries = FieldKind.allCases.map { entry(Cell(destination, $0)) }
            lines.append("| \(destination.rawValue) | " + entries.joined(separator: " | ") + " |")
        }
        let under = rows.filter(\.isUnderFloor).map { "`\($0.cell)`" }
        lines += ["", "Cells under the floor: \(under.isEmpty ? "none" : under.joined(separator: ", "))."]
        return lines.joined(separator: "\n") + "\n"
    }
}
