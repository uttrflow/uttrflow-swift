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
            guard !endsSentence(trigger - 1, in: live, of: draft) else { return nil }
            var start = trigger - 1
            while start > earliest, NumberWords.isNumber(draft.shape(at: live[start - 1]).key),
                !endsSentence(start - 1, in: live, of: draft)
            {
                start -= 1
            }
            guard !coordinates(start, before: trigger, in: live, of: draft) else { return nil }
            return start
        }
        guard !weakAnchors.contains(firstAfter) else { return nil }
        for candidate in stride(from: trigger - 1, through: earliest, by: -1) {
            if draft.shape(at: live[candidate]).key == firstAfter {
                guard holdsContent(candidate..<trigger, in: live, of: draft),
                    !coordinates(candidate, before: trigger, in: live, of: draft)
                else { return nil }
                return candidate
            }
            if endsSentence(candidate, in: live, of: draft) { return nil }
        }
        return nil
    }

    /// Whether the word at `position` closes a sentence, which no anchor may reach past to take words out of the sentence before.
    private static func endsSentence(_ position: Int, in live: [Int], of draft: Draft) -> Bool {
        draft.shape(at: live[position]).endsSentence
    }

    /// Whether the words the correction would take back hold anything the speaker meant.
    private static func holdsContent(_ span: Range<Int>, in live: [Int], of draft: Draft) -> Bool {
        span.contains { FunctionWords.isContent(draft.shape(at: live[$0]).key) }
    }

    /// Whether the trigger heads each item of a list rather than correcting one, the word before the half it would take back being the trigger over again.
    private static func coordinates(
        _ start: Int, before trigger: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        start > 0 && draft.shape(at: live[start - 1]).key == draft.shape(at: live[trigger]).key
    }
}
