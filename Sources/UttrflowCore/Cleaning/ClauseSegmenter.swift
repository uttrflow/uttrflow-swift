public import Foundation
import NaturalLanguage

/// Where one clause ends and the next begins, read from lexical class and, when known, pause length.
public enum ClauseSegmenter {
    /// What shows that a new clause starts at a word.
    public enum Evidence: Equatable, Sendable {
        /// An interjection or sentence adverb opens the sentence before its clause.
        case afterOpener
        /// A conjunction joins two clauses that each have their own subject and verb.
        case coordinatedClause
        /// The speaker paused at least `pauseThreshold` before the word.
        case pause
    }

    /// One clause start: the index of the word that opens it, and why.
    public struct Boundary: Equatable, Sendable {
        public let index: Int
        public let evidence: Evidence

        public init(index: Int, evidence: Evidence) {
            self.index = index
            self.evidence = evidence
        }
    }

    /// The silence before a word that counts as a clause break when nothing else shows one.
    public static let pauseThreshold: TimeInterval = 0.35

    /// Clause starts in `words`; `pauses[i]` is the silence after word `i`, or `nil` when no timing is known.
    public static func boundaries(in words: [String], pauses: [TimeInterval?] = []) -> [Boundary] {
        let shapes = words.map(WordShape.init)
        let tags = LexicalClass.tags(ofWords: shapes.map(\.core))
        let held = heldWhole(shapes)
        var result: [Boundary] = []
        for index in words.indices.dropFirst() where !held.contains(index) {
            if let evidence = lexicalEvidence(before: index, tags: tags) {
                result.append(Boundary(index: index, evidence: evidence))
            } else if pauses.indices.contains(index - 1), let pause = pauses[index - 1],
                pause >= pauseThreshold
            {
                result.append(Boundary(index: index, evidence: .pause))
            }
        }
        return result
    }

    /// Words a clause may not start at: inside a quote or bracket, or a number or the word joining two numbers.
    private static func heldWhole(_ shapes: [WordShape]) -> Set<Int> {
        var held = Set<Int>()
        var open: [Character] = []
        for (index, shape) in shapes.enumerated() {
            if !open.isEmpty { held.insert(index) }
            for mark in shape.prefix where isOpener(mark) { open.append(mark) }
            for mark in shape.suffix where isCloser(mark) && !open.isEmpty { open.removeLast() }
        }
        let numbers = shapes.map { isNumber($0.core) }
        for index in shapes.indices where numbers[index] {
            held.insert(index)
            if index >= 2, numbers[index - 2] { held.insert(index - 1) }
        }
        return held
    }

    private static func isOpener(_ mark: Character) -> Bool {
        WordShape.openingQuotes.contains(mark) || WordShape.bracketOpeners.values.contains(mark)
    }

    private static func isCloser(_ mark: Character) -> Bool {
        mark == "\"" || mark == "'" || mark == "\u{201D}" || mark == "\u{2019}" || mark == "\u{00BB}"
            || WordShape.bracketOpeners.keys.contains(mark)
    }

    private static func isNumber(_ core: String) -> Bool {
        core.first?.isNumber == true && core.allSatisfy { $0.isNumber || $0 == "." || $0 == "," }
    }

    private static func lexicalEvidence(before index: Int, tags: [NLTag?]) -> Evidence? {
        if index == 1, opensSentence(tags) { return .afterOpener }
        if tags[index] == .conjunction, hasSubjectAndVerb(tags[..<index]),
            startsClause(tags[(index + 1)...])
        {
            return .coordinatedClause
        }
        return nil
    }

    private static func opensSentence(_ tags: [NLTag?]) -> Bool {
        guard tags.count > 2 else { return false }
        let rest = tags.dropFirst()
        switch tags[0] {
        case .interjection: return rest.contains(.verb)
        case .adverb: return startsClause(rest)
        default: return false
        }
    }

    private static func hasSubjectAndVerb(_ tags: ArraySlice<NLTag?>) -> Bool {
        let clause = tags.reversed().prefix { $0 != .conjunction }
        return clause.contains(.verb) && clause.contains { isSubject($0) }
    }

    /// Whether the words open with a subject followed by its verb, after any adverbs.
    private static func startsClause(_ tags: ArraySlice<NLTag?>) -> Bool {
        let afterAdverbs = tags.drop { $0 == .adverb }
        guard let first = afterAdverbs.first, isSubject(first) else { return false }
        let clause = afterAdverbs.prefix { $0 != .conjunction }
        return clause.contains(.verb)
    }

    private static func isSubject(_ tag: NLTag?) -> Bool {
        tag == .pronoun || tag == .noun || tag == .determiner || tag == .personalName
    }
}
