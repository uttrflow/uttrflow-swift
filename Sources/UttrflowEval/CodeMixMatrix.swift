// The grid of how Hindi and English combine inside one sentence, and how many corpus cases fill each cell.

/// One cell of the code-mixing grid: which language frames the sentence, what is inserted, and where.
public struct CodeMixCell: Sendable, Equatable, Hashable, Codable {
    /// The language whose grammar carries the sentence.
    public enum Frame: String, Sendable, Equatable, CaseIterable, Codable {
        case english
        case hindi
    }

    /// The kind of material from the other language at the switch.
    public enum Kind: String, Sendable, Equatable, CaseIterable, Codable {
        case noun
        case verb
        case number
        case name
        case particle
        case questionTag = "question-tag"
    }

    /// Where in the sentence the switch falls.
    public enum Position: String, Sendable, Equatable, CaseIterable, Codable {
        case start
        case middle
        case end
    }

    public let frame: Frame
    public let kind: Kind
    public let position: Position

    public init(_ frame: Frame, _ kind: Kind, _ position: Position) {
        self.frame = frame
        self.kind = kind
        self.position = position
    }

    /// Every cell, frame first, then kind, then position.
    public static let all: [CodeMixCell] = Frame.allCases.flatMap { frame in
        Kind.allCases.flatMap { kind in Position.allCases.map { CodeMixCell(frame, kind, $0) } }
    }
}

/// How many corpus cases fill each code-mixing cell, and whether that is enough.
public struct CodeMixMatrix: Sendable, Equatable {
    /// The fewest cases a cell needs to count as covered.
    public static let coveredFloor = 4

    /// One cell's row: its case ids, in corpus order.
    public struct Row: Sendable, Equatable {
        public let cell: CodeMixCell
        public let caseIDs: [String]

        public var isCovered: Bool { caseIDs.count >= CodeMixMatrix.coveredFloor }
    }

    public let rows: [Row]

    /// The matrix read from `cases`, one row per cell whether or not anything fills it.
    public init(cases: [EvaluationCase] = EvaluationCorpus.all) {
        rows = CodeMixCell.all.map { cell in
            Row(cell: cell, caseIDs: cases.filter { $0.codeMix == cell }.map(\.id))
        }
    }

    /// The matrix as the Markdown page `Docs/code-mixing-matrix.md` holds.
    public var markdown: String {
        var lines = [
            "# Code-mixing coverage matrix",
            "",
            "Generated from the `codeMix` tags in `EvaluationCorpus`; do not edit by hand.",
            "Regenerate with `UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter CodeMixMatrixTests`.",
            "A cell is covered at \(Self.coveredFloor) cases.",
            "",
            "| Frame | Kind | Position | Cases | Covered |",
            "|---|---|---|---|---|",
        ]
        for row in rows {
            let cell = row.cell
            lines.append(
                "| \(cell.frame.rawValue) | \(cell.kind.rawValue) | \(cell.position.rawValue) "
                    + "| \(row.caseIDs.count) | \(row.isCovered ? "yes" : "no") |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
