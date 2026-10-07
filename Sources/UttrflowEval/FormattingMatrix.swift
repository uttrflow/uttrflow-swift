// The formatting case classes and how well the corpus covers each one.

/// One class of formatting decision the tidier makes, which corpus cases are tagged with.
public enum FormattingClass: String, Sendable, Equatable, CaseIterable, Codable {
    case sentenceBoundaries = "sentence-boundaries"
    case commas
    case questions
    case quotesAndBrackets = "quotes-and-brackets"
    case ellipses
    case capitalisationAndTokens = "capitalisation-and-tokens"
    case numbers
    case lists
    case paragraphs
    case corrections
    case perDestination = "per-destination"
    case codeAndMarkdown = "code-and-markdown"
    case hinglish
    case textAfterCaret = "text-after-caret"
    /// Prose in a technical app whose notation words must stay words.
    case abstention
}

/// How many corpus cases each formatting class has, and whether that is enough.
public struct FormattingMatrix: Sendable, Equatable {
    /// The fewest tagged cases a class needs to count as covered.
    public static let coveredFloor = 5

    /// How well one class is covered.
    public enum Coverage: String, Sendable, Equatable {
        case covered
        case partial
        case uncovered
    }

    /// One class's row: its tagged case ids, in corpus order.
    public struct Row: Sendable, Equatable {
        public let formattingClass: FormattingClass
        public let caseIDs: [String]

        public var coverage: Coverage {
            if caseIDs.count >= FormattingMatrix.coveredFloor { return .covered }
            return caseIDs.isEmpty ? .uncovered : .partial
        }
    }

    public let rows: [Row]

    /// The matrix read from `cases`, one row per class whether or not anything is tagged with it.
    public init(cases: [EvaluationCase] = EvaluationCorpus.all + EvaluationCorpus.abstention) {
        rows = FormattingClass.allCases.map { formattingClass in
            Row(
                formattingClass: formattingClass,
                caseIDs: cases.filter { $0.classes.contains(formattingClass) }.map(\.id))
        }
    }

    /// The matrix as the Markdown page `Docs/formatting-matrix.md` holds.
    public var markdown: String {
        var lines = [
            "# Formatting coverage matrix",
            "",
            "Generated from the `classes` tags in `EvaluationCorpus.all` and `EvaluationCorpus.abstention`; do not edit by hand.",
            "Regenerate with `UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter FormattingMatrixTests`.",
            "A class is covered at \(Self.coveredFloor) tagged cases, partial below that, uncovered at none.",
            "The owner is `FormattingClass.ownership`; `both` means the passes after the model have the last word.",
            "",
            "| Class | Owner | Passes | Cases | Coverage | Case ids |",
            "|---|---|---|---|---|---|",
        ]
        for row in rows {
            let ids = row.caseIDs.map { "`\($0)`" }.joined(separator: ", ")
            let ownership = row.formattingClass.ownership
            let passes = ownership.passes.map { "`\($0)`" }.joined(separator: ", ")
            lines.append(
                "| \(row.formattingClass.rawValue) | \(ownership.owner.rawValue) | \(passes) | \(row.caseIDs.count) "
                    + "| \(row.coverage.rawValue) | \(ids) |"
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
