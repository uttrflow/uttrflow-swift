public import UttrflowCore

/// Removes the discarded half of a spoken correction a trigger phrase announces. See `Docs/cleanup.md`.
public struct SelfCorrectionPass: CleaningPass {
    public static let id: PassID = .selfCorrection
    public static let removes: RemovalGrant = .retraction

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            guard let discarded = discarded(at: position, in: live, of: draft) else {
                position += 1
                continue
            }
            let stray = strayComma(closing: discarded, triggeredAt: position, in: live, of: draft)
            for index in live[discarded] { draft.remove(at: index, by: Self.id, carryingMarks: true) }
            if let stray {
                draft.replace(at: stray, with: String(draft.words[stray].text.dropLast()), by: Self.id)
            }
            live.removeSubrange(discarded)
            position = discarded.lowerBound
        }
        return draft
    }

    /// Words that open a clause a comma must close, so a comma after the restatement is the sentence's own.
    static let subordinators: Set<String> = [
        "if", "when", "whenever", "because", "although", "though", "once", "after", "before", "since",
        "unless", "while", "as",
    ]

    /// The restatement's closing comma, when a comma before the trigger set the correction off and nothing else needs it.
    private func strayComma(
        closing discarded: Range<Int>, triggeredAt trigger: Int, in live: [Int], of draft: Draft
    ) -> Int? {
        guard draft.shape(at: live[trigger - 1]).suffix == "," else { return nil }
        // As many words as were taken back, which is how long the restatement that replaces them runs.
        let restatement =
            discarded
            .upperBound..<min(
                live.count, discarded.upperBound + trigger - discarded.lowerBound)
        guard let closing = restatement.first(where: { draft.shape(at: live[$0]).endsClause }),
            closing < live.count - 1, draft.shape(at: live[closing]).suffix == ",",
            !opensWithSubordinator(before: discarded.lowerBound, in: live, of: draft)
        else { return nil }
        return live[closing]
    }

    /// Whether the sentence holding `position` opens with a subordinate clause no comma has closed yet.
    private func opensWithSubordinator(before position: Int, in live: [Int], of draft: Draft) -> Bool {
        var start = position
        while start > 0, !draft.shape(at: live[start - 1]).endsSentence,
            !draft.words[live[start - 1]].isLayoutMark
        {
            start -= 1
        }
        guard start < position, Self.subordinators.contains(draft.shape(at: live[start]).key) else {
            return false
        }
        return !(start..<position).contains { draft.shape(at: live[$0]).endsClause }
    }

    /// The half the correction at `position` takes back, trigger included, or nil when the halves do not match.
    private func discarded(at position: Int, in live: [Int], of draft: Draft) -> Range<Int>? {
        let trigger = Restatement.triggerRun(at: position, in: live, of: draft)
        guard trigger > 0, position > 0, position + trigger < live.count,
            let start = Restatement.discardedStart(
                before: position, after: position + trigger, in: live, of: draft)
        else { return nil }
        return start..<(position + trigger)
    }
}
