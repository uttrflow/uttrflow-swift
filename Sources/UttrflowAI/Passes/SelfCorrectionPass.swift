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
            guard let (discarded, through) = discarded(at: position, in: live, of: draft) else {
                position += 1
                continue
            }
            if through {
                matchCase(of: live[discarded.lowerBound], onto: live[discarded.upperBound], in: &draft)
            }
            // Read through a stop, the discarded half's stops were the pause and leave with it.
            for index in live[discarded] { draft.remove(at: index, by: Self.id, carryingMarks: !through) }
            live.removeSubrange(discarded)
            position = discarded.lowerBound
        }
        return draft
    }

    /// The half the correction at `position` takes back, trigger included, and whether it reads through a stop, or nil.
    private func discarded(
        at position: Int, in live: [Int], of draft: Draft
    ) -> (span: Range<Int>, through: Bool)? {
        let trigger = Restatement.triggerRun(at: position, in: live, of: draft)
        guard trigger > 0, position > 0, position + trigger < live.count,
            let start = Restatement.discardedStart(
                before: position, after: position + trigger, in: live, of: draft)
        else { return nil }
        let through = Restatement.standsAlone(position, before: position + trigger, in: live, of: draft)
        return (start..<(position + trigger), through)
    }

    /// Lowers the restart's capital when the word it replaces was lower case, since only the stop gave it one.
    private func matchCase(of anchor: Int, onto restart: Int, in draft: inout Draft) {
        let said = draft.words[anchor].text
        let again = draft.words[restart].text
        guard WordShape.lowercased(said) == said, WordShape.lowercased(again) != again else { return }
        draft.replace(at: restart, with: WordShape.lowercased(again), by: Self.id)
    }
}
