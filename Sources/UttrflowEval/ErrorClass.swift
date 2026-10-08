// Sorts each scored recogniser error into one linguistic class, so each class has a count, not a guess.

internal import Foundation
public import UttrflowCore

/// The linguistic class of one aligned error, in the order a classifier tries them.
public enum ErrorClass: String, Sendable, Equatable, CaseIterable, Codable {
    /// One word that comes out as two, or two as one, with the same letters once spaces go.
    case wordBoundary = "word boundary"
    /// A word that sounds the same as the one it stands in for.
    case homophone
    /// A number, or a number's written form, on either side.
    case numeralForm = "numeral form"
    /// Another form of the same word ("try", "tried").
    case inflection
    /// A small structural word ("the", "of", "and").
    case functionWord = "function word"
    /// A name the passage capitalises mid-sentence.
    case properNoun = "proper noun"
    case other
}

/// Classifies the errors of an alignment; deterministic, so two runs over one results file agree.
public struct ErrorClassifier: Sendable {
    /// Whether two words sound the same; the caller passes it so the harness links no dictionary.
    let sameSound: @Sendable (String, String) -> Bool
    /// Case-folded words the reference text writes as names.
    let properNouns: Set<String>

    public init(
        sameSound: @escaping @Sendable (String, String) -> Bool = { _, _ in false },
        properNouns: Set<String> = []
    ) {
        self.sameSound = sameSound
        self.properNouns = Set(properNouns.map { $0.lowercased() })
    }

    /// One class per non-match operation, in alignment order.
    public func classify(_ alignment: [WordErrorRate.Operation]) -> [ErrorClass] {
        let boundary = boundaryIndices(alignment)
        return alignment.indices.compactMap { index in
            let operation = alignment[index]
            if case .match = operation { return nil }
            return boundary.contains(index) ? .wordBoundary : classify(operation)
        }
    }

    /// Counts per class over many alignments; a class nobody hit is absent.
    public func counts(_ alignments: [[WordErrorRate.Operation]]) -> [ErrorClass: Int] {
        alignments.flatMap(classify).reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    private func classify(_ operation: WordErrorRate.Operation) -> ErrorClass {
        let words: [String]
        switch operation {
        case .match: return .other
        case .substitution(let reference, let hypothesis):
            if sameSound(reference, hypothesis) { return .homophone }
            words = [reference, hypothesis]
        case .deletion(let word), .insertion(let word): words = [word]
        }
        if words.contains(where: Self.isNumeral) { return .numeralForm }
        if words.count == 2, Self.shareStem(words[0], words[1]) { return .inflection }
        if words.allSatisfy(FunctionWords.holds) { return .functionWord }
        if words.contains(where: { properNouns.contains($0.lowercased()) }) { return .properNoun }
        return .other
    }

    /// Indices of a substitution and an insertion or deletion beside it whose letters join to the other side.
    private func boundaryIndices(_ alignment: [WordErrorRate.Operation]) -> Set<Int> {
        var found: Set<Int> = []
        for index in alignment.indices {
            guard case .substitution(let reference, let hypothesis) = alignment[index] else { continue }
            for neighbour in [index - 1, index + 1] where alignment.indices.contains(neighbour) {
                let before = neighbour < index
                let joins: Bool
                switch alignment[neighbour] {
                case .insertion(let word):
                    let joined = before ? word + hypothesis : hypothesis + word
                    joins = Self.letters(reference) == Self.letters(joined)
                case .deletion(let word):
                    let joined = before ? word + reference : reference + word
                    joins = Self.letters(hypothesis) == Self.letters(joined)
                default: joins = false
                }
                if joins { found.formUnion([index, neighbour]) }
            }
        }
        return found
    }

    static func letters(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    static func isNumeral(_ word: String) -> Bool {
        word.contains(where: \.isNumber) || numberWords.contains(word.lowercased())
    }

    static let numberWords: Set<String> = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven",
        "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen",
        "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety", "hundred",
        "thousand", "million", "billion", "first", "second", "third", "half", "percent",
    ]

    /// Whether two different words reduce to one stem under the suffix table below.
    static func shareStem(_ word: String, _ other: String) -> Bool {
        let word = word.lowercased()
        let other = other.lowercased()
        guard word != other else { return false }
        return !stems(word).isDisjoint(with: stems(other))
    }

    /// Endings an English inflection adds, each with the stem ending it takes the place of.
    static let suffixes: [(ending: String, restore: String)] = [
        ("ies", "y"), ("ied", "y"), ("ing", ""), ("ing", "e"), ("est", ""), ("er", ""), ("es", ""),
        ("ed", ""), ("ed", "e"), ("'s", ""), ("s", ""), ("d", ""),
    ]

    /// The word and every stem it could be an inflection of; a stem under three letters does not count.
    static func stems(_ word: String) -> Set<String> {
        var result: Set<String> = [word]
        for (ending, restore) in suffixes where word.hasSuffix(ending) {
            let stem = String(word.dropLast(ending.count))
            guard stem.count >= 2 else { continue }
            result.insert(stem + restore)
            if restore.isEmpty, let last = stem.last, stem.dropLast().last == last {
                result.insert(String(stem.dropLast()))
            }
        }
        return result.filter { $0.count >= 3 }
    }
}

extension TranscriptionReport {
    /// Each error class that occurs, with its count and share of every error, largest first.
    public func errorClasses(
        by classifier: ErrorClassifier
    ) -> [(errorClass: ErrorClass, count: Int, share: Double)] {
        let counts = classifier.counts(scored.compactMap { $0.wordErrorRate?.alignment })
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        return ErrorClass.allCases.compactMap { errorClass in
            counts[errorClass].map { (errorClass, $0, Double($0) / Double(total)) }
        }
        .sorted { ($1.count, $0.errorClass.rawValue) < ($0.count, $1.errorClass.rawValue) }
    }
}
