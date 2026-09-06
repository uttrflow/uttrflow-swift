public import UttrflowCore

/// Removes the discarded half of a spoken correction a trigger phrase announces. See `Docs/cleanup.md`.
public struct SelfCorrectionPass: CleaningPass {
    public static let id: PassID = .selfCorrection

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
            for index in live[discarded] { draft.remove(at: index, by: Self.id) }
            live.removeSubrange(discarded)
            position = discarded.lowerBound
        }
        return draft
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
