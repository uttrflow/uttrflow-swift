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

    /// Words that head an answer, which a second answer pairs with rather than takes back.
    public static let answerHeads: Set<String> = [
        "yes", "yeah", "yep", "no", "nope", "sorry", "thanks", "thank", "okay", "ok",
    ]

    /// Words a restated phrase may not anchor on, because a fresh clause starts with them far more often.
    public static let weakAnchors = Set([
        "i", "i'm", "i'll", "i've", "i'd", "we", "you", "he", "she", "they", "it", "it's", "that",
        "this", "there", "yes", "yeah", "ok", "okay", "oh", "well",
    ]).union(hindiSubjects)

    /// Hindi pronouns and subject words, romanised and in Devanagari, which start a fresh clause as English ones do.
    static let hindiSubjects: Set<String> = [
        "main", "mai", "maine", "mujhe", "hum", "humne", "tum", "aap", "wo", "woh", "ye", "yeh",
        "mera", "meri", "mere", "मैं", "मैंने", "मुझे", "हम", "तुम", "आप", "वो", "वह", "ये", "यह",
        "मेरा", "मेरी", "मेरे",
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
        let through = standsAlone(trigger, before: restart, in: live, of: draft)
        if NumberWords.isNumber(firstAfter),
            let end = numberEnd(before: trigger, after: restart, in: live, of: draft)
        {
            guard through || !endsSentence(trigger - 1, in: live, of: draft) else { return nil }
            var start = end
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
            if endsSentence(candidate, in: live, of: draft), !(through && candidate == trigger - 1) {
                return nil
            }
        }
        return nil
    }

    /// Whether the trigger is a sentence of its own after a full stop ("Tuesday. Scratch that. Wednesday"), which is a pause rather than two sentences.
    public static func standsAlone(
        _ trigger: Int, before restart: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        guard trigger > 0, restart > trigger, restart <= live.count else { return false }
        let phrase = (trigger..<restart).map { draft.shape(at: live[$0]) }
        // A bare "No." is an answer far more often than a correction.
        guard phrase.map(\.key) != ["no"] else { return false }
        return closesWithAStop(trigger - 1, in: live, of: draft)
            && closesWithAStop(restart - 1, in: live, of: draft)
            && phrase.allSatisfy { !$0.suffix.contains(where: { "?!".contains($0) }) }
    }

    /// Whether the word ends its sentence with a full stop, rather than a question or an exclamation.
    private static func closesWithAStop(_ position: Int, in live: [Int], of draft: Draft) -> Bool {
        let suffix = draft.shape(at: live[position]).suffix
        return suffix.contains(".") && !suffix.contains(where: { "?!".contains($0) })
    }

    /// The last word of the number taken back, stepping over a unit the restatement repeats ("twelve boxes i mean fifteen boxes").
    private static func numberEnd(
        before trigger: Int, after restart: Int, in live: [Int], of draft: Draft
    ) -> Int? {
        let unit = trigger - 1
        let unitKey = draft.shape(at: live[unit]).key
        if NumberWords.isNumber(unitKey) { return unit }
        guard unit > 0, NumberWords.isNumber(draft.shape(at: live[unit - 1]).key),
            !endsSentence(unit - 1, in: live, of: draft)
        else { return nil }
        var next = restart
        while next < live.count, NumberWords.isNumber(draft.shape(at: live[next]).key) {
            // A unit past a stop belongs to the next sentence, not to this restatement.
            guard !endsSentence(next, in: live, of: draft) else { return nil }
            next += 1
        }
        guard next < live.count, draft.shape(at: live[next]).key == unitKey else { return nil }
        return unit - 1
    }

    /// Whether the word at `position` closes a sentence, which no anchor may reach past to take words out of the sentence before.
    private static func endsSentence(_ position: Int, in live: [Int], of draft: Draft) -> Bool {
        draft.shape(at: live[position]).endsSentence
    }

    /// Whether the words the correction would take back hold anything the speaker meant.
    private static func holdsContent(_ span: Range<Int>, in live: [Int], of draft: Draft) -> Bool {
        span.contains { FunctionWords.isContent(draft.shape(at: live[$0]).key) }
    }

    /// Whether the trigger heads each item of a list rather than correcting one: the word before the half it would take back is the trigger over again, or an answer this trigger answers ("yes … no …", "thanks … sorry …").
    private static func coordinates(
        _ start: Int, before trigger: Int, in live: [Int], of draft: Draft
    ) -> Bool {
        guard start > 0 else { return false }
        let before = draft.shape(at: live[start - 1]).key
        let head = draft.shape(at: live[trigger]).key
        return before == head || (answerHeads.contains(before) && answerHeads.contains(head))
    }
}
