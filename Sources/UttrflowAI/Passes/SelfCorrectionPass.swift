public import UttrflowCore

/// Removes the discarded half of a spoken correction when both halves share a shape. See `Docs/cleanup.md`.
public struct SelfCorrectionPass: CleaningPass {
    public static let id: PassID = .selfCorrection

    /// Phrases that announce a correction, longest first so "no sorry" is one trigger rather than two.
    static let triggers: [[String]] = [
        ["no", "sorry"], ["scratch", "that"], ["never", "mind"], ["i", "mean"],
        ["no"], ["sorry"], ["wait"], ["actually"],
    ]

    /// How many words back the discarded half may reach.
    static let reach = 6

    /// Words a restated phrase may not anchor on, because a fresh clause starts with them far more often.
    static let weakAnchors: Set<String> = [
        "i", "i'm", "i'll", "i've", "i'd", "we", "you", "he", "she", "they", "it", "it's", "that",
        "this", "there", "yes", "yeah", "ok", "okay", "oh", "well",
    ]

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            let triggerLength = triggerRun(at: position, in: live, of: draft)
            guard triggerLength > 0, position > 0, position + triggerLength < live.count,
                let start = discardedStart(
                    before: position, after: position + triggerLength, in: live, of: draft)
            else {
                position += 1
                continue
            }
            for index in live[start..<position + triggerLength] { draft.remove(at: index, by: Self.id) }
            live.removeSubrange(start..<position + triggerLength)
            position = start
        }
        return draft
    }

    /// How many words at `position` are trigger phrases run together, such as "no wait".
    private func triggerRun(at position: Int, in live: [Int], of draft: Draft) -> Int {
        var length = 0
        while let next = triggerLength(at: position + length, in: live, of: draft) { length += next }
        return length
    }

    private func triggerLength(at position: Int, in live: [Int], of draft: Draft) -> Int? {
        for trigger in Self.triggers where position + trigger.count <= live.count {
            let keys = live[position..<position + trigger.count].map { draft.shape(at: $0).key }
            if keys == trigger { return trigger.count }
        }
        return nil
    }

    /// Where the discarded half starts, or nil when the halves do not match in shape.
    private func discardedStart(
        before trigger: Int, after restart: Int, in live: [Int], of draft: Draft
    ) -> Int? {
        let earliest = max(0, trigger - Self.reach)
        let firstAfter = draft.shape(at: live[restart]).key
        if NumberWords.isNumber(firstAfter), NumberWords.isNumber(draft.shape(at: live[trigger - 1]).key) {
            var start = trigger - 1
            while start > earliest, NumberWords.isNumber(draft.shape(at: live[start - 1]).key) { start -= 1 }
            return start
        }
        guard !Self.weakAnchors.contains(firstAfter) else { return nil }
        for candidate in stride(from: trigger - 1, through: earliest, by: -1) {
            let shape = draft.shape(at: live[candidate])
            if shape.key == firstAfter { return candidate }
            if shape.endsSentence { return nil }
        }
        return nil
    }
}
