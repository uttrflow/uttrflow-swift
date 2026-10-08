// Number cases scored without folding number words, keeping a wrong form, a wrong value and a false conversion apart.
import UttrflowCore

/// The kind of number a case is about, or `staysWords` for number words that must not become numerals.
public enum SemioticClass: String, Sendable, Equatable, CaseIterable, Codable {
    case cardinal
    case ordinal
    case decimal
    case fraction
    case money
    case measure
    case date
    case time
    case telephone
    case electronic
    case staysWords = "stays-words"

    /// The formatting matrix row the class is counted under.
    public var formattingClass: FormattingClass { .numbers }
}

/// One number case's three outcomes, which need different fixes.
public struct NumberGrammarScore: Sendable, Equatable {
    /// Whether the output is the expected text exactly, whitespace at the ends aside.
    public let isExact: Bool
    /// Whether the numbers read out of the output differ from the reference's: an unrelated number, not a style slip.
    public let isValueError: Bool
    /// Numerals the output has beyond the reference's, each a number word that should have stayed a word.
    public let falseConversions: Int

    public init(expected: String, output: String) {
        let reference = NumberReading(expected)
        let produced = NumberReading(output)
        isExact = Self.trimmed(expected) == Self.trimmed(output)
        isValueError = reference.values != produced.values
        falseConversions = max(0, produced.numerals - reference.numerals)
    }

    private static func trimmed(_ text: String) -> String {
        String(text.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}

/// The values a text holds in order, read from numerals and number words alike, and how many were numerals.
struct NumberReading: Equatable {
    private(set) var values: [Double] = []
    private(set) var numerals = 0

    init(_ text: String) {
        let tokens = Self.tokens(text)
        var index = tokens.startIndex
        while index < tokens.endIndex {
            if let parts = Self.numeral(tokens[index]) {
                values += parts
                numerals += 1
                index += 1
            } else if let spoken = NumberWords.cardinal(tokens[index...]), spoken.count > 0 {
                values.append(Double(spoken.value))
                index += spoken.count
            } else {
                index += 1
            }
        }
    }

    /// Lowercased words, keeping a full stop, comma or colon that sits between two digits.
    private static func tokens(_ text: String) -> [String] {
        let characters = Array(text.lowercased())
        var tokens: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            let joinsDigits =
                ".,:".contains(character) && index > 0 && index + 1 < characters.count
                && characters[index - 1].isNumber && characters[index + 1].isNumber
            if character.isLetter || character.isNumber || joinsDigits {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// A numeral's values: a time or ratio gives one per colon part, an ordinal suffix is dropped, grouping commas go.
    private static func numeral(_ token: String) -> [Double]? {
        var body = Substring(token)
        for suffix in ["st", "nd", "rd", "th"] where body.hasSuffix(suffix) {
            body = body.dropLast(suffix.count)
        }
        guard NumberWords.digits(String(body)) != nil else { return nil }
        let parts = body.split(separator: ":").map { Double($0.filter { $0 != "," }) }
        guard parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}

/// Number cases' scores totalled per semiotic class and place policy.
public struct NumberGrammarReport: Sendable, Equatable {
    /// One class under one policy.
    public struct Row: Sendable, Equatable {
        public let semioticClass: SemioticClass
        public let policy: String
        public let cases: Int
        public let exact: Int
        public let valueErrors: Int
        public let falseConversions: Int
    }

    public let rows: [Row]

    /// The report over each tagged case and what an engine wrote for it; untagged cases are skipped.
    public init(_ results: [(testCase: EvaluationCase, output: String)]) {
        let tagged = results.compactMap { result in
            result.testCase.semiotic.map { semiotic in
                (
                    semiotic: semiotic,
                    policy: Self.label(DestinationFormatter.standard(for: result.testCase.situation).numbers),
                    score: NumberGrammarScore(expected: result.testCase.expected, output: result.output)
                )
            }
        }
        rows = SemioticClass.allCases.flatMap { semiotic in
            Self.policies.map { policy in
                let scores = tagged.filter { $0.semiotic == semiotic && $0.policy == policy }.map(\.score)
                return Row(
                    semioticClass: semiotic, policy: policy, cases: scores.count,
                    exact: scores.filter(\.isExact).count, valueErrors: scores.filter(\.isValueError).count,
                    falseConversions: scores.map(\.falseConversions).reduce(0, +))
            }
        }
    }

    private static let policies = [label(.fromTen), label(.always)]

    private static func label(_ policy: NumberPolicy) -> String {
        switch policy {
        case .fromTen: "from-ten"
        case .always: "always"
        }
    }

    /// The report as the Markdown page `Docs/number-grammar.md` holds.
    public var markdown: String {
        var lines = [
            "# Number grammar by semiotic class",
            "",
            "Generated from the `semiotic` tags in `EvaluationCorpus` run through the rules engine; do not edit by hand.",
            "Regenerate with `UTTRFLOW_UPDATE_GOLDEN=1 swift test --filter NumberGrammarScoreTests`.",
            "Scored without folding number words: exact match, value errors (the numbers read differ),",
            "and false conversions (numerals beyond the reference's). Every class counts under the `numbers` matrix row.",
            "",
            "| Class | Policy | Cases | Exact | Value errors | False conversions |",
            "|---|---|---|---|---|---|",
        ]
        for row in rows {
            lines.append(
                "| \(row.semioticClass.rawValue) | \(row.policy) | \(row.cases) | \(row.exact) "
                    + "| \(row.valueErrors) | \(row.falseConversions) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
