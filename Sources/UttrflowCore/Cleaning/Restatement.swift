/// Where the discarded half of a spoken correction begins, once a trigger phrase announces one. See `Docs/cleanup.md`.
public enum Restatement {
    /// Phrases that announce a correction, longest first so "no sorry" is one trigger rather than two.
    public static let triggers: [[String]] = [
        ["no", "sorry"], ["no", "wait"], ["wait", "sorry"], ["scratch", "that"], ["never", "mind"],
        ["i", "mean"],
        ["no"], ["sorry"], ["actually"],
    ]

    /// How many words back the discarded half may reach.
    public static let reach = 6

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

    /// Whether the words the correction would take back hold anything the speaker meant.
    private static func holdsContent(_ span: Range<Int>, in live: [Int], of draft: Draft) -> Bool {
        span.contains { FunctionWords.isContent(draft.shape(at: live[$0]).key) }
    }
}
