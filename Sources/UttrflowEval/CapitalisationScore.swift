// Capitalisation scored per reason a reference word has its case, beside what doing nothing scores.
import UttrflowCore

/// Why a reference word is written in the case it is, read from the reference text by one rule.
public enum CapitalisationClass: String, CaseIterable, Sendable, Codable, CodingKeyRepresentable {
    /// The pronoun "I", including the "I" of a contraction such as "I'm".
    case pronounI = "I"
    /// Two or more letters, all capitals, such as "NASA".
    case acronym
    /// A capital after a small letter, such as "iPhone" or "YoY".
    case innerCapital = "inner capital"
    /// The first word of the text or of a sentence.
    case sentenceStart = "sentence start"
    /// A leading capital inside a sentence: a name, a place or a dictionary spelling.
    case capitalised
    /// No capitals at all; a wrong capital here is the over-capitalising failure.
    case lowerCase = "lower case"
    /// No letter with a case, such as a number.
    case uncased

    /// The class of `word`, where `opensSentence` says whether a sentence begins at it.
    static func of(_ word: String, opensSentence: Bool) -> CapitalisationClass {
        let letters = word.filter(\.isLetter)
        let cased = letters.filter { $0.isUppercase || $0.isLowercase }
        guard !cased.isEmpty else { return .uncased }
        if word == "I" { return .pronounI }
        if cased.count >= 2, cased.allSatisfy(\.isUppercase) { return .acronym }
        if zip(cased, cased.dropFirst()).contains(where: { $0.isLowercase && $1.isUppercase }) {
            return .innerCapital
        }
        if opensSentence { return .sentenceStart }
        return cased.contains(where: \.isUppercase) ? .capitalised : .lowerCase
    }
}

/// Aligned reference words and how many kept their case, counted per class.
public struct CapitalisationTally: Sendable, Equatable, Codable {
    public private(set) var matched: [CapitalisationClass: Int]
    public private(set) var correct: [CapitalisationClass: Int]

    public init(
        matched: [CapitalisationClass: Int] = [:], correct: [CapitalisationClass: Int] = [:]
    ) {
        self.matched = matched
        self.correct = correct
    }

    mutating func record(_ wordClass: CapitalisationClass, correct isCorrect: Bool) {
        matched[wordClass, default: 0] += 1
        if isCorrect { correct[wordClass, default: 0] += 1 }
    }

    /// The share of matched words in `wordClass` whose case is right; `nil` when none matched.
    public func accuracy(of wordClass: CapitalisationClass) -> Double? {
        let count = matched[wordClass] ?? 0
        guard count > 0 else { return nil }
        return Double(correct[wordClass] ?? 0) / Double(count)
    }

    /// The share over every class, which is the one figure `caseAccuracy` has always reported.
    public var accuracy: Double {
        let count = matched.values.reduce(0, +)
        guard count > 0 else { return 1 }
        return Double(correct.values.reduce(0, +)) / Double(count)
    }

    /// Both tallies counted together, so a corpus total is the sum of its cases.
    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            matched: lhs.matched.merging(rhs.matched, uniquingKeysWith: +),
            correct: lhs.correct.merging(rhs.correct, uniquingKeysWith: +))
    }

    /// The class whose accuracy fell furthest below `other`'s, or `nil` when none fell.
    public func mostDegraded(comparedWith other: Self) -> CapitalisationClass? {
        let drops = CapitalisationClass.allCases.compactMap { wordClass -> (CapitalisationClass, Double)? in
            guard let mine = accuracy(of: wordClass), let theirs = other.accuracy(of: wordClass),
                mine < theirs
            else { return nil }
            return (wordClass, theirs - mine)
        }
        return drops.max { $0.1 < $1.1 }?.0
    }

    /// Tallies `produced` against `wanted`, aligned on lower-cased words so case alone never breaks a match.
    static func measure(_ produced: [String], against wanted: [ClassifiedWord]) -> Self {
        let alignment = WordErrorRate.measure(
            reference: wanted.map { $0.word.lowercased() }, hypothesis: produced.map { $0.lowercased() })
        var tally = Self()
        var producedIndex = 0
        var wantedIndex = 0
        for operation in alignment.alignment {
            switch operation {
            case .match:
                let reference = wanted[wantedIndex]
                tally.record(reference.wordClass, correct: produced[producedIndex] == reference.word)
                producedIndex += 1
                wantedIndex += 1
            case .substitution:
                producedIndex += 1
                wantedIndex += 1
            case .deletion:
                wantedIndex += 1
            case .insertion:
                producedIndex += 1
            }
        }
        return tally
    }
}

/// One reference word with its capitalisation class.
struct ClassifiedWord: Equatable {
    let word: String
    let wordClass: CapitalisationClass

    /// The words of `text` in order, a sentence opening at the start, after a line break and after a closing mark followed by space.
    static func words(of text: String) -> [ClassifiedWord] {
        var found: [ClassifiedWord] = []
        var word = ""
        var opens = true
        var closed = false
        var spaced = false
        func flush() {
            guard !word.isEmpty else { return }
            found.append(ClassifiedWord(word: word, wordClass: .of(word, opensSentence: opens)))
            word = ""
            opens = false
        }
        for character in text {
            if character.isLetter || character.isNumber {
                if word.isEmpty, closed, spaced { opens = true }
                closed = false
                spaced = false
                word.append(character)
                continue
            }
            flush()
            if character.isNewline {
                opens = true
            } else if ".!?".contains(character) {
                closed = true
                spaced = false
            } else if character.isWhitespace, closed {
                spaced = true
            }
        }
        flush()
        return found
    }
}
