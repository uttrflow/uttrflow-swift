// Punctuation scored per mark, each mark placed by the word alignment rather than by a word count.
import UttrflowCore

/// One kind of punctuation mark, scored on its own so a regression in one is not hidden by the others.
public enum MarkClass: String, CaseIterable, Sendable, Codable, CodingKeyRepresentable {
    case comma
    case fullStop = "full stop"
    case question
    case exclamation
    case colon
    case semicolon
    case dash
    case ellipsis
    case quote
    case bracket

    /// The class of one punctuation character, or `nil` for one that is not scored or is inside a word.
    static func of(_ character: Character, between before: Character?, and after: Character?) -> MarkClass? {
        let insideWord = before.map(isWordCharacter) == true && after.map(isWordCharacter) == true
        switch character {
        case ",": return .comma
        case ".": return .fullStop
        case "?": return .question
        case "!": return .exclamation
        case ":": return .colon
        case ";": return .semicolon
        case "…": return .ellipsis
        case "—", "–": return .dash
        case "-": return insideWord ? nil : .dash
        case "\"", "“", "”", "«", "»": return .quote
        case "'", "‘", "’": return insideWord ? nil : .quote
        case "(", ")", "[", "]", "{", "}": return .bracket
        default: return nil
        }
    }

    static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

/// A text's words, lowercased, and each mark keyed by how many of those words come before it.
struct PunctuatedWords {
    var words: [String] = []
    var marks: [(slot: Int, mark: MarkClass)] = []

    init(_ text: String) {
        let characters = Array(text)
        var word = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if MarkClass.isWordCharacter(character) {
                word.append(contentsOf: character.lowercased())
                index += 1
                continue
            }
            if !word.isEmpty {
                words.append(word)
                word = ""
            }
            // A run of one character is one mark, so "..." is an ellipsis and "--" one dash.
            var end = index + 1
            while end < characters.count, characters[end] == character { end += 1 }
            let before = index > 0 ? characters[index - 1] : nil
            let after = end < characters.count ? characters[end] : nil
            if character == ".", end - index >= 3 {
                marks.append((words.count, .ellipsis))
            } else if let mark = MarkClass.of(character, between: before, and: after) {
                marks.append((words.count, mark))
            }
            index = end
        }
        if !word.isEmpty { words.append(word) }
    }
}

/// Marks wanted, produced and agreed per class, and which class was written in place of which.
public struct PunctuationTally: Sendable, Equatable, Codable {
    public private(set) var wanted: [MarkClass: Int]
    public private(set) var produced: [MarkClass: Int]
    public private(set) var correct: [MarkClass: Int]
    /// Wanted class to the class written at the same aligned place instead, such as a full stop for a question.
    public private(set) var substitutions: [MarkClass: [MarkClass: Int]]

    public init(
        wanted: [MarkClass: Int] = [:], produced: [MarkClass: Int] = [:], correct: [MarkClass: Int] = [:],
        substitutions: [MarkClass: [MarkClass: Int]] = [:]
    ) {
        self.wanted = wanted
        self.produced = produced
        self.correct = correct
        self.substitutions = substitutions
    }

    /// Aligns the two texts' words with `WordErrorRate` and compares the marks that follow each aligned place.
    public static func measure(_ output: String, against reference: String) -> PunctuationTally {
        let wantedText = PunctuatedWords(reference)
        let producedText = PunctuatedWords(output)
        let alignment = WordErrorRate.measure(reference: wantedText.words, hypothesis: producedText.words)
            .alignment
        // Each reference place maps to the output place it lands on; a deleted word's place lands where it would have been.
        var place = [0]
        var outputWords = 0
        for operation in alignment {
            switch operation {
            case .insertion: outputWords += 1
            case .deletion: place.append(outputWords)
            case .match, .substitution:
                outputWords += 1
                place.append(outputWords)
            }
        }
        var wantedAt: [Int: [MarkClass]] = [:]
        for (slot, mark) in wantedText.marks { wantedAt[place[slot], default: []].append(mark) }
        var producedAt: [Int: [MarkClass]] = [:]
        for (slot, mark) in producedText.marks { producedAt[slot, default: []].append(mark) }

        var tally = PunctuationTally()
        for (_, mark) in wantedText.marks { tally.wanted[mark, default: 0] += 1 }
        for (_, mark) in producedText.marks { tally.produced[mark, default: 0] += 1 }
        for slot in Set(wantedAt.keys).union(producedAt.keys) {
            var missed = wantedAt[slot] ?? []
            var extra = producedAt[slot] ?? []
            for mark in missed where extra.contains(mark) {
                tally.correct[mark, default: 0] += 1
                extra.remove(at: extra.firstIndex(of: mark) ?? 0)
                missed.remove(at: missed.firstIndex(of: mark) ?? 0)
            }
            for (wanted, written) in zip(missed, extra) {
                tally.substitutions[wanted, default: [:]][written, default: 0] += 1
            }
        }
        return tally
    }

    /// Precision and recall's harmonic mean for one class; `nil` when it is neither wanted nor produced.
    public func f1(of mark: MarkClass) -> Double? {
        let wantedCount = wanted[mark] ?? 0
        let producedCount = produced[mark] ?? 0
        guard wantedCount + producedCount > 0 else { return nil }
        return 2 * Double(correct[mark] ?? 0) / Double(wantedCount + producedCount)
    }

    /// Correct over produced for one class; `nil` when none was produced.
    public func precision(of mark: MarkClass) -> Double? {
        let count = produced[mark] ?? 0
        return count > 0 ? Double(correct[mark] ?? 0) / Double(count) : nil
    }

    /// Correct over wanted for one class; `nil` when none was wanted.
    public func recall(of mark: MarkClass) -> Double? {
        let count = wanted[mark] ?? 0
        return count > 0 ? Double(correct[mark] ?? 0) / Double(count) : nil
    }

    /// The mean F1 over the classes present, the one figure `markAccuracy` reports; 1 when no mark is in either text.
    public var accuracy: Double {
        let scores = MarkClass.allCases.compactMap(f1(of:))
        guard !scores.isEmpty else { return 1 }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// Both tallies counted together, so a corpus total is the sum of its cases.
    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            wanted: lhs.wanted.merging(rhs.wanted, uniquingKeysWith: +),
            produced: lhs.produced.merging(rhs.produced, uniquingKeysWith: +),
            correct: lhs.correct.merging(rhs.correct, uniquingKeysWith: +),
            substitutions: lhs.substitutions.merging(rhs.substitutions) {
                $0.merging($1, uniquingKeysWith: +)
            })
    }
}
