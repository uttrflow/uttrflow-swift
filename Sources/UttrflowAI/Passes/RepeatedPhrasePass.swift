public import UttrflowCore

/// Removes a run of two to four words said twice in a row, keeping the second: "so I was I was thinking".
public struct RepeatedPhrasePass: PieceCleaningPass {
    public static let id: PassID = .repeatedPhrase
    public static let laws: Set<PassLaw> = [.idempotent, .addsNoWords, .latinOnly]
    public static let orderIndependentWith: Set<PassID> = [.stammers]
    public static let removes: RemovalGrant = .repetition

    static let lengths = 2...4
    /// Chains said on purpose, matched at every alignment since a repeated chain also repeats each rotation.
    private static let deliberateChains = [
        ["on", "and"], ["again", "and"], ["more", "and"], ["and", "so", "on"],
    ]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            if let length = FalseStartRestart.prefixLength(at: position, in: live, of: draft) {
                for index in live[position..<position + length] {
                    draft.remove(at: index, by: Self.id, carryingMarks: true)
                }
                live.removeSubrange(position..<position + length)
                continue
            }
            guard let length = repeatLength(at: position, in: live, of: draft) else {
                position += 1
                continue
            }
            for index in live[position..<position + length] {
                draft.remove(at: index, by: Self.id, carryingMarks: true)
            }
            live.removeSubrange(position..<position + length)
        }
        return draft
    }

    /// The longest run at `position` repeated verbatim right after itself, with no punctuation inside.
    private func repeatLength(at position: Int, in live: [Int], of draft: Draft) -> Int? {
        for length in Self.lengths.reversed() where position + 2 * length <= live.count {
            let first = live[position..<position + length]
            let second = live[position + length..<position + 2 * length]
            let keys = first.map { draft.shape(at: $0).key }
            let sameWords = zip(first, second).allSatisfy {
                draft.shape(at: $0).key == draft.shape(at: $1).key
            }
            let unbroken = !(first + second.dropLast()).contains { draft.shape(at: $0).endsClause }
            if sameWords, unbroken, !Self.isDeliberate(keys) { return length }
        }
        return nil
    }

    /// Whether the run is said twice on purpose: one word, a name, a spelled code, or a familiar chain.
    private static func isDeliberate(_ keys: [String]) -> Bool {
        Set(keys).count == 1 || keys.allSatisfy(FunctionWords.isContent) || keys.allSatisfy(isCodeSymbol)
            || deliberateChains.contains { repeatsCycle(of: $0, keys) }
    }

    /// Whether `keys` is whole turns of `chain` starting from any of its words: "and on and on" turns "on and".
    private static func repeatsCycle(of chain: [String], _ keys: [String]) -> Bool {
        guard keys.count.isMultiple(of: chain.count) else { return false }
        return chain.indices.contains { offset in
            keys.indices.allSatisfy { keys[$0] == chain[(offset + $0) % chain.count] }
        }
    }

    /// A single letter or a number, the symbols a spelled code repeats by design: "one a one a".
    private static func isCodeSymbol(_ key: String) -> Bool {
        key.count == 1 && LetterRun.isLetterName(key) || NumberWords.isNumber(key)
    }
}

/// Recognizes a few incomplete constructions only when a fresh clause follows them.
enum FalseStartRestart {
    private static let subjects: Set<String> = [
        "i", "i'd", "i'll", "i'm", "i've", "we", "we'd", "we'll", "we're", "we've",
        "you", "you'd", "you'll", "you're", "you've", "he", "he'd", "he'll", "he's",
        "she", "she'd", "she'll", "she's", "they", "they'd", "they'll", "they're", "they've",
    ]

    /// Finite forms that cannot complete a modal, so a modal before them was abandoned rather than stammered.
    private static let finiteAfterModal: Set<String> = [
        "can", "could", "will", "would", "shall", "should", "may", "might", "must",
        "am", "is", "are", "was", "were", "has", "does", "did",
    ]

    /// The incomplete prefix length when a restart follows at a clause boundary.
    static func prefixLength(at position: Int, in live: [Int], of draft: Draft) -> Int? {
        guard position == 0 || isClauseBoundary(before: position, in: live, of: draft) else { return nil }
        guard position < live.count else { return nil }
        let remaining = live.count - position
        func key(_ offset: Int) -> String { draft.shape(at: live[position + offset]).key }

        if remaining >= 5, key(0) == "i", ["went", "walked", "drove", "headed"].contains(key(1)),
            key(2) == "to", ["a", "an", "the"].contains(key(3)), isSubject(key(4)),
            isUnbroken(0..<4, at: position, in: live, of: draft)
        {
            return 4
        }
        if remaining >= 4, ["can", "could", "would", "should"].contains(key(0)),
            isSubject(key(1)), key(2) == key(1), finiteAfterModal.contains(key(3)),
            isUnbroken(0..<2, at: position, in: live, of: draft)
        {
            return 2
        }
        if remaining >= 4, key(0) == "let", key(1) == "me", isSubject(key(2)),
            isRestartVerb(key(3)), isUnbroken(0..<2, at: position, in: live, of: draft)
        {
            return 2
        }
        if remaining >= 6, subjects.contains(key(0)), ["was", "were", "is", "are", "am"].contains(key(1)),
            key(2) == "going", key(3) == "to", isSubject(key(4)), isRestartVerb(key(5)),
            isUnbroken(0..<4, at: position, in: live, of: draft)
        {
            return 4
        }
        if remaining >= 9, ["the", "this", "that"].contains(key(0)),
            ["problem", "point", "thing", "question"].contains(key(1)), key(2) == "is",
            (3...7).map(key).elementsEqual(["what", "i", "wanted", "to", "say"]), key(8) == "is",
            isUnbroken(0..<3, at: position, in: live, of: draft)
        {
            return 3
        }
        return nil
    }

    /// Whether every removed token belongs to one of the recognized incomplete prefixes.
    static func coversRemoval(at index: Int, in draft: Draft) -> Bool {
        guard draft.words.indices.contains(index), isRemovedByRepeatedPhrase(draft.words[index]) else {
            return false
        }
        var removed = index...index
        while removed.lowerBound > draft.words.startIndex,
            isRemovedByRepeatedPhrase(draft.words[removed.lowerBound - 1])
        {
            removed = (removed.lowerBound - 1)...removed.upperBound
        }
        while removed.upperBound + 1 < draft.words.endIndex,
            isRemovedByRepeatedPhrase(draft.words[removed.upperBound + 1])
        {
            removed = removed.lowerBound...(removed.upperBound + 1)
        }
        let live = (draft.presentIndices + Array(removed)).sorted()
        guard let position = live.firstIndex(of: removed.lowerBound),
            let length = prefixLength(at: position, in: live, of: draft)
        else { return false }
        return live[position..<position + length].contains(index)
    }

    private static func isClauseBoundary(before position: Int, in live: [Int], of draft: Draft) -> Bool {
        guard position > 0 else { return true }
        let previous = live[position - 1]
        return draft.shape(at: previous).endsClause || draft.words[previous].isLayoutMark
    }

    private static func isUnbroken(
        _ range: Range<Int>, at position: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        !range.contains { draft.shape(at: live[position + $0]).endsClause }
    }

    private static func isSubject(_ key: String) -> Bool { subjects.contains(key) }

    private static func isRestartVerb(_ key: String) -> Bool {
        !["a", "an", "the", "to", "and", "or", "but", "if", "when", "because", "that"].contains(key)
    }

    private static func isRemovedByRepeatedPhrase(_ word: Draft.Word) -> Bool {
        guard case .removed(let pass) = word.state else { return false }
        return pass == RepeatedPhrasePass.id
    }
}
