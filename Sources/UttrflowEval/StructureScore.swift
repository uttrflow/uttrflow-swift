// Layout scored by where breaks and list items fall, aligned by word so a wrong word never moves a break.
import UttrflowCore

/// The kind of break that opens a line: a blank line before it, or a single line break.
enum BreakKind: String, Sendable, Equatable, Codable {
    case paragraph
    case line
}

/// One text's words with the break and list item each line opens, read by one rule from its lines.
struct LaidOutText: Equatable {
    /// One break: the index of the word it comes before, its kind, and whether its line is a list item.
    struct Break: Equatable {
        let wordIndex: Int
        let kind: BreakKind
        let opensListItem: Bool
        /// Whether the line before it ends in a closing mark.
        let followsSentenceEnd: Bool
        let followsListItem: Bool
    }

    let words: [String]
    let breaks: [Break]
    /// Indices of the words that open a list item, including a list that starts the text.
    let listItemStarts: Set<Int>

    init(_ text: String) {
        var words: [String] = []
        var breaks: [Break] = []
        var listItemStarts: Set<Int> = []
        var blankSinceLastLine = false
        var previousLine: (text: Substring, isListItem: Bool)?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingPrefix { $0.isWhitespace }
            guard !line.allSatisfy(\.isWhitespace) else {
                blankSinceLastLine = previousLine != nil
                continue
            }
            let marker = Self.listMarkerLength(line)
            let lineWords = Scorer.tokens(String(line.dropFirst(marker)))
            guard !lineWords.isEmpty else { continue }
            if let previous = previousLine, !words.isEmpty {
                breaks.append(
                    Break(
                        wordIndex: words.count, kind: blankSinceLastLine ? .paragraph : .line,
                        opensListItem: marker > 0, followsSentenceEnd: Self.endsSentence(previous.text),
                        followsListItem: previous.isListItem))
            }
            if marker > 0 { listItemStarts.insert(words.count) }
            words += lineWords
            previousLine = (line, marker > 0)
            blankSinceLastLine = false
        }
        self.words = words
        self.breaks = breaks
        self.listItemStarts = listItemStarts
    }

    /// The length of a leading list marker with its space ("- ", "* ", "• ", "1. ", "2) "), or 0.
    static func listMarkerLength(_ line: Substring) -> Int {
        var index = line.startIndex
        if let first = line.first, "-*•".contains(first) {
            index = line.index(after: index)
        } else {
            while index < line.endIndex, line[index].isNumber { index = line.index(after: index) }
            guard index > line.startIndex, index < line.endIndex, ".)".contains(line[index]) else { return 0 }
            index = line.index(after: index)
        }
        guard index < line.endIndex, line[index] == " " else { return 0 }
        return line.distance(from: line.startIndex, to: line.index(after: index))
    }

    static func endsSentence(_ line: Substring) -> Bool {
        guard let last = line.last(where: { !$0.isWhitespace && !"\"')”’".contains($0) }) else {
            return false
        }
        return ".!?:;…".contains(last)
    }
}

/// One case's layout: breaks and list items in the reference and the output, and those that agree.
struct StructureScore: Sendable, Equatable {
    let caseID: String
    let destination: Destination
    let referenceWords: Int
    let outputWords: Int
    let referenceBreaks: Int
    let outputBreaks: Int
    /// Output breaks at the reference's word position with the reference's kind.
    let correctBreaks: Int
    let referenceListItems: Int
    /// Reference list items the output also opens at the same word.
    let correctListItems: Int
    /// Output breaks the reference lacks, after a line that does not end a sentence or a list item.
    let breaksInsideSentence: Int

    /// Scores the layout of `output` against `testCase.expected`.
    init(output: String, for testCase: EvaluationCase) {
        let reference = LaidOutText(testCase.expected)
        let produced = LaidOutText(output)
        let referenceIndex = Self.referenceIndices(reference: reference.words, output: produced.words)
        let wanted = Dictionary(
            reference.breaks.map { ($0.wordIndex, $0.kind) }, uniquingKeysWith: { first, _ in first })
        var correct = 0
        var insideSentence = 0
        for outputBreak in produced.breaks {
            let target = referenceIndex[outputBreak.wordIndex]
            if let target, wanted[target] == outputBreak.kind {
                correct += 1
            } else if !outputBreak.followsSentenceEnd, !outputBreak.followsListItem,
                !outputBreak.opensListItem
            {
                insideSentence += 1
            }
        }
        let producedItems = Set(produced.listItemStarts.compactMap { referenceIndex[$0] })
        caseID = testCase.id
        destination = testCase.destination
        referenceWords = reference.words.count
        outputWords = produced.words.count
        referenceBreaks = reference.breaks.count
        outputBreaks = produced.breaks.count
        correctBreaks = correct
        referenceListItems = reference.listItemStarts.count
        correctListItems = reference.listItemStarts.intersection(producedItems).count
        breaksInsideSentence = insideSentence
    }

    /// For each output word, the reference word it aligns with, where it matches or replaces one.
    static func referenceIndices(reference: [String], output: [String]) -> [Int: Int] {
        var mapping: [Int: Int] = [:]
        var referenceIndex = 0
        var outputIndex = 0
        for operation in WordErrorRate.measure(reference: reference, hypothesis: output).alignment {
            switch operation {
            case .match, .substitution:
                mapping[outputIndex] = referenceIndex
                referenceIndex += 1
                outputIndex += 1
            case .deletion:
                referenceIndex += 1
            case .insertion:
                outputIndex += 1
            }
        }
        return mapping
    }
}

/// Break precision, recall and over-segmentation over a group of cases, summed as counts.
struct StructureRates: Sendable, Equatable {
    let cases: Int
    let referenceWords: Int
    let outputWords: Int
    let referenceBreaks: Int
    let outputBreaks: Int
    let correctBreaks: Int
    let referenceListItems: Int
    let correctListItems: Int
    let breaksInsideSentence: Int

    init(_ scores: [StructureScore]) {
        cases = scores.count
        referenceWords = scores.reduce(0) { $0 + $1.referenceWords }
        outputWords = scores.reduce(0) { $0 + $1.outputWords }
        referenceBreaks = scores.reduce(0) { $0 + $1.referenceBreaks }
        outputBreaks = scores.reduce(0) { $0 + $1.outputBreaks }
        correctBreaks = scores.reduce(0) { $0 + $1.correctBreaks }
        referenceListItems = scores.reduce(0) { $0 + $1.referenceListItems }
        correctListItems = scores.reduce(0) { $0 + $1.correctListItems }
        breaksInsideSentence = scores.reduce(0) { $0 + $1.breaksInsideSentence }
    }

    /// Share of output breaks the reference has; `nil` with no output break.
    var precision: Double? { outputBreaks == 0 ? nil : Double(correctBreaks) / Double(outputBreaks) }
    /// Share of reference breaks the output has; `nil` with no reference break.
    var recall: Double? { referenceBreaks == 0 ? nil : Double(correctBreaks) / Double(referenceBreaks) }

    var f1: Double? {
        guard let precision, let recall, precision + recall > 0 else { return nil }
        return 2 * precision * recall / (precision + recall)
    }

    /// Output breaks per 100 words less the reference's, so a positive figure is over-segmentation.
    var overSegmentation: Double {
        Self.perHundred(outputBreaks, outputWords) - Self.perHundred(referenceBreaks, referenceWords)
    }

    /// Share of reference list items the output opens at the same word; `nil` with no list item.
    var listItemAccuracy: Double? {
        referenceListItems == 0 ? nil : Double(correctListItems) / Double(referenceListItems)
    }

    private static func perHundred(_ count: Int, _ words: Int) -> Double {
        words == 0 ? 0 : Double(count) * 100 / Double(words)
    }
}

/// One engine's layout scores, read per destination.
struct StructureReport: Sendable, Equatable {
    let scores: [StructureScore]

    init(scores: [StructureScore]) {
        self.scores = scores
    }

    /// Each destination's rates, in declaration order, leaving out a destination with no case.
    var byDestination: [(destination: Destination, rates: StructureRates)] {
        Destination.allCases.compactMap { destination in
            let scores = scores.filter { $0.destination == destination }
            return scores.isEmpty ? nil : (destination, StructureRates(scores))
        }
    }

    var overall: StructureRates { StructureRates(scores) }

    /// Each destination's rates as one line, keyed by destination, as the committed baseline holds them.
    var baseline: [String: String] {
        var lines = Dictionary(
            uniqueKeysWithValues: byDestination.map { ($0.destination.rawValue, Self.line($0.rates)) })
        lines["all"] = Self.line(overall)
        return lines
    }

    var table: String {
        let rows = byDestination.map { ($0.destination.rawValue, $0.rates) } + [("all", overall)]
        return rows.map { label, rates in
            "\(label.padding(toLength: 14, withPad: " ", startingAt: 0)) \(Self.line(rates))"
        }
        .joined(separator: "\n")
    }

    static func line(_ rates: StructureRates) -> String {
        [
            "cases=\(rates.cases)", "breaks=\(rates.referenceBreaks)", "output-breaks=\(rates.outputBreaks)",
            "correct=\(rates.correctBreaks)", "precision=\(percent(rates.precision))",
            "recall=\(percent(rates.recall))", "f1=\(percent(rates.f1))",
            "over-segmentation=\(String(format: "%+.2f", rates.overSegmentation))",
            "list-items=\(rates.correctListItems)/\(rates.referenceListItems)",
            "inside-sentence=\(rates.breaksInsideSentence)",
        ].joined(separator: " ")
    }

    private static func percent(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.1f%%", value * 100)
    }
}
