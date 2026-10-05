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
        let tags = LexicalClass.tags(ofWords: words)
        var result: [Boundary] = []
        for index in words.indices.dropFirst() {
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
