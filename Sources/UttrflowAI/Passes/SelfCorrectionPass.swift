public import UttrflowCore

/// Removes the discarded half of a spoken correction when both halves share a shape. See `Docs/cleanup.md`.
public struct SelfCorrectionPass: CleaningPass {
    public static let id: PassID = "selfCorrection"

    public init() {}

    public func apply(_ draft: Draft) -> Draft {
        var draft = draft
        var live = draft.presentIndices
        var position = 0
        while position < live.count {
            let triggerLength = Restatement.triggerRun(at: position, in: live, of: draft)
            guard triggerLength > 0, position > 0, position + triggerLength < live.count,
                let start = Restatement.discardedStart(
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
}
