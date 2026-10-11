// Reads each note's checklist once while its formatted content stays unchanged.
import UttrflowClipboard

/// Remembers the checklist count for each clip, so a panel keystroke does not parse its HTML again.
final class ChecklistProgresses: Sendable {
    private let entries = Memo<Clip.ID, String, (done: Int, total: Int)?>()
    private let parse: @Sendable (String) -> (done: Int, total: Int)?

    /// Builds an empty memo; `parse` lets a test count HTML scans.
    init(parse: @escaping @Sendable (String) -> (done: Int, total: Int)? = { NoteChecklist.progress(in: $0) })
    {
        self.parse = parse
    }

    /// The checked and total boxes, or `nil` when the clip has no checklist.
    func progress(of clip: Clip) -> (done: Int, total: Int)? {
        guard let html = clip.richText else { return nil }
        return entries.value(for: clip.id, source: html) { parse(html) }
    }

    /// Drops formatted content for clips no longer held by the panel snapshot.
    func prune(to clipIDs: Set<Clip.ID>) {
        entries.prune(to: clipIDs)
    }

}
