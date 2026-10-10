// Digit strings and codes scored by their exact characters, on the recogniser's text and again after the rules.
public import UttrflowCore

/// The way a digit string or code is spoken, which is what makes a recogniser or a rule get it wrong.
public enum DigitShape: String, Sendable, Equatable, CaseIterable, Codable {
    /// Order and reference numbers of eight or more digits, read one digit at a time.
    case longString = "long-string"
    /// Letters and digits mixed in one code: flight, case and booking references.
    case alphanumeric
    /// A zero read as "oh" or as "zero" inside a run of digits.
    case ohForZero = "oh-for-zero"
    /// Digits spoken in groups or pairs, as people read a long number back.
    case grouped
    /// A digit said twice or more in a row, or as "double" and "triple".
    case repeated
    /// A clock time, where the colon is part of the value.
    case time
    /// A year followed in the same sentence by another number.
    case yearThenNumber = "year-then-number"
}

/// One sentence read aloud and the spans in it that must come back character for character.
public struct DigitStringCase: Sendable, Equatable, Identifiable {
    public let id: String
    public let shape: DigitShape
    /// The sentence as a person says it, in words, so the synthesiser reads the digits the way people do.
    public let spoken: String
    /// The numbers or codes the sentence holds, in order, as they must be written.
    public let spans: [String]

    public init(id: String, shape: DigitShape, spoken: String, spans: [String]) {
        self.id = id
        self.shape = shape
        self.spoken = spoken
        self.spans = spans
    }
}

/// Finds a span in a text by its exact characters, with spaces, hyphens and letter case not counted.
public enum DigitSpan {
    /// Whether `text` holds every span in order, each as a run of whole words.
    public static func holds(_ spans: [String], in text: String) -> Bool {
        let tokens = self.tokens(text)
        var start = 0
        for span in spans {
            guard let found = run(of: key(span), in: tokens, from: start) else { return false }
            start = found.upperBound
        }
        return true
    }

    /// A word or span as it is compared: upper case, hyphens dropped, outer punctuation off.
    static func key(_ text: String) -> String {
        let trimmed = text.drop { !$0.isLetter && !$0.isNumber }
            .reversed().drop { !$0.isLetter && !$0.isNumber }.reversed()
        return String(trimmed).uppercased().filter { $0 != "-" && !$0.isWhitespace }
    }

    /// The words of `text` as keys, empty ones left out.
    static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map { key(String($0)) }.filter { !$0.isEmpty }
    }

    /// The first run of whole tokens at or after `start` whose characters join to `target`.
    static func run(of target: String, in tokens: [String], from start: Int) -> Range<Int>? {
        guard !target.isEmpty else { return nil }
        for first in tokens.indices where first >= start {
            var joined = ""
            for last in first..<tokens.count {
                joined += tokens[last]
                if joined == target { return first..<(last + 1) }
                if !target.hasPrefix(joined) { break }
            }
        }
        return nil
    }
}

/// One case scored on the recogniser's text and on the text the rules made of it.
public struct DigitStringOutcome: Sendable, Equatable {
    public let caseID: String
    public let shape: DigitShape
    /// Whether the recogniser's own text holds every span exactly.
    public let rawExact: Bool
    /// Whether the text after the rules holds every span exactly.
    public let finalExact: Bool
    /// The passes that touched a span's characters where the rules lost a span the recogniser had right.
    public let blamed: [PassID]

    /// Scores `raw` and `final` for `testCase`, reading the passes to blame from `record`.
    public init(_ testCase: DigitStringCase, raw: String, final: String, record: CleaningRecord?) {
        caseID = testCase.id
        shape = testCase.shape
        rawExact = DigitSpan.holds(testCase.spans, in: raw)
        finalExact = DigitSpan.holds(testCase.spans, in: final)
        let lost = rawExact && !finalExact
        let spans = testCase.spans.map(DigitSpan.key)
        blamed =
            lost
            ? (record?.changes ?? []).filter { Self.touches($0, spans: spans) }.map(\.step) : []
    }

    /// Whether a change removed, rewrote or added a word made of a span's characters or holding a digit.
    private static func touches(_ change: CleaningRecord.Change, spans: [String]) -> Bool {
        let words = change.removed + change.inserted + change.replaced.flatMap { [$0.from, $0.to] }
        return words.map(DigitSpan.key).contains { word in
            !word.isEmpty && (word.contains(where: \.isNumber) || spans.contains { $0.contains(word) })
        }
    }
}

/// Exact-match rates per shape, on the recogniser's text and after the rules, and the passes behind any loss.
public struct DigitStringReport: Sendable, Equatable {
    /// One shape's rates and the passes blamed for spans the rules lost.
    public struct Row: Sendable, Equatable {
        public let shape: DigitShape
        public let raw: Proportion
        public let final: Proportion
        /// Each blamed pass and the number of cases it was blamed in.
        public let blamed: [PassID: Int]

        /// Whether the rules leave fewer exact spans than the recogniser wrote.
        public var isWorseAfterRules: Bool { final.hits < raw.hits }
    }

    public let rows: [Row]

    /// One row per shape, in the order shapes are declared, leaving out shapes with no case.
    public init(_ outcomes: [DigitStringOutcome]) {
        rows = DigitShape.allCases.compactMap { shape in
            let mine = outcomes.filter { $0.shape == shape }
            guard !mine.isEmpty else { return nil }
            return Row(
                shape: shape,
                raw: Proportion(hits: mine.filter(\.rawExact).count, of: mine.count),
                final: Proportion(hits: mine.filter(\.finalExact).count, of: mine.count),
                blamed: Dictionary(mine.flatMap(\.blamed).map { ($0, 1) }, uniquingKeysWith: +))
        }
    }

    /// The shapes where the rules do worse than the recogniser, which each want an issue against the passes named.
    public var worseAfterRules: [Row] { rows.filter(\.isWorseAfterRules) }

    /// The table the documentation carries, one row per shape.
    public var table: String {
        func cell(_ share: Proportion) -> String {
            guard let value = share.value, let interval = share.interval else { return "n/a" }
            return String(
                format: "%.2f (%.2f-%.2f, %d/%d)", value, interval.lowerBound, interval.upperBound,
                share.hits, share.total)
        }
        let lines = rows.map { row in
            let blamed = row.blamed.sorted { ($1.value, $0.key.rawValue) < ($0.value, $1.key.rawValue) }
                .map { "\($0.key.rawValue) (\($0.value))" }.joined(separator: ", ")
            return
                "| \(row.shape.rawValue) | \(cell(row.raw)) | \(cell(row.final)) | \(blamed.isEmpty ? "-" : blamed) |"
        }
        return
            (["| Shape | Raw exact | Final exact | Passes that lost a span |", "|---|---|---|---|"] + lines)
            .joined(separator: "\n")
    }
}
