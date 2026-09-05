/// Where the discarded half of a spoken correction begins, shared by the pass inside one piece and the joiner between two. See `Docs/cleanup.md`.
public enum Restatement {
    /// Phrases that announce a correction, longest first so "no sorry" is one trigger rather than two.
    public static let triggers: [[String]] = [
        ["no", "sorry"], ["no", "wait"], ["wait", "sorry"], ["scratch", "that"], ["never", "mind"],
        ["i", "mean"],
        ["no"], ["sorry"], ["actually"],
    ]

    /// How many words back the discarded half may reach.
    public static let reach = 6

    /// How many words of function words a repeated frame may hold.
    public static let longestFrame = 3

    /// Words a restated phrase may not anchor on, because a fresh clause starts with them far more often.
    public static let weakAnchors: Set<String> = [
        "i", "i'm", "i'll", "i've", "i'd", "we", "you", "he", "she", "they", "it", "it's", "that",
        "this", "there", "yes", "yeah", "ok", "okay", "oh", "well",
    ]

    /// How many words at `position` are trigger phrases run together, such as "no wait".
    public static func triggerRun(at position: Int, in live: [Int], of draft: Draft) -> Int {
        var length = 0
        while let next = triggerLength(at: position + length, in: live, of: draft) { length += next }
        return length
    }

    private static func triggerLength(at position: Int, in live: [Int], of draft: Draft) -> Int? {
        for trigger in triggers where position + trigger.count <= live.count {
            let keys = live[position..<position + trigger.count].map { draft.shape(at: $0).key }
            if keys == trigger { return trigger.count }
        }
        return nil
    }

    /// Where the discarded half starts, or nil when the halves do not match in shape.
    public static func discardedStart(
        before trigger: Int, after restart: Int, in live: [Int], of draft: Draft
    ) -> Int? {
        let earliest = max(0, trigger - reach)
        let firstAfter = draft.shape(at: live[restart]).key
        if NumberWords.isNumber(firstAfter), NumberWords.isNumber(draft.shape(at: live[trigger - 1]).key) {
            var start = trigger - 1
            while start > earliest, NumberWords.isNumber(draft.shape(at: live[start - 1]).key) { start -= 1 }
            return start
        }
        guard !weakAnchors.contains(firstAfter) else { return nil }
        for candidate in stride(from: trigger - 1, through: earliest, by: -1) {
            let shape = draft.shape(at: live[candidate])
            if shape.key == firstAfter {
                return holdsContent(candidate..<trigger, in: live, of: draft) ? candidate : nil
            }
            if shape.endsSentence { return nil }
        }
        return nil
    }

    /// The words a restatement with no trigger takes back at `position`, or nil when none starts there.
    public static func repeatedFrame(at position: Int, in live: [Int], of draft: Draft) -> Range<Int>? {
        for length in 1...longestFrame {
            if let span = frame(length, at: position, in: live, of: draft) { return span }
        }
        return nil
    }

    /// Where the half a piece restates begins, when that piece opens at `position` with no trigger.
    public static func frameStart(endingAt position: Int, in live: [Int], of draft: Draft) -> Int? {
        let earliest = max(0, position - longestFrame - 1)
        for start in stride(from: position - 1, through: earliest, by: -1)
        where repeatedFrame(at: start, in: live, of: draft)?.upperBound == position {
            return start
        }
        return nil
    }

    /// Whether the words the correction would take back hold anything the speaker meant.
    private static func holdsContent(_ span: Range<Int>, in live: [Int], of draft: Draft) -> Bool {
        span.contains { FunctionWords.isContent(draft.shape(at: live[$0]).key) }
    }

    /// The frame of `length` function words repeated at `position`, each followed by a different content word.
    private static func frame(
        _ length: Int, at position: Int, in live: [Int], of draft: Draft
    ) -> Range<Int>? {
        let restart = position + length + 1
        let after = restart + length
        guard after < live.count else { return nil }
        let keys = (position..<(after + 1)).map { draft.shape(at: live[$0]).key }
        let opening = Array(keys[0..<length])
        guard let first = opening.first, FunctionWords.prepositions.contains(first),
            !(length == 1 && FunctionWords.correlatives.contains(first)),
            opening.allSatisfy({ FunctionWords.holds($0) && !FunctionWords.clauseOpeners.contains($0) }),
            opening == Array(keys[(length + 1)..<(2 * length + 1)]),
            FunctionWords.isContent(keys[length]), FunctionWords.isContent(keys[2 * length + 1]),
            keys[length] != keys[2 * length + 1],
            !(position..<restart).contains(where: { draft.shape(at: live[$0]).endsClause })
        else { return nil }
        return position..<restart
    }
}
