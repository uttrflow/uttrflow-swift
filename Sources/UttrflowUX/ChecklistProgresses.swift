// Reads each note's checklist once while its formatted content stays unchanged.
private import Synchronization
import UttrflowClipboard

/// Remembers the checklist count for each clip, so a panel keystroke does not parse its HTML again.
final class ChecklistProgresses: Sendable {
    /// The formatted content and its count; a changed note replaces this entry.
    private struct Entry {
        let html: String
        let progress: (done: Int, total: Int)?
    }

    private let entries = Mutex<[Clip.ID: Entry]>([:])
    private let parse: @Sendable (String) -> (done: Int, total: Int)?

    /// Builds an empty memo; `parse` lets a test count HTML scans.
    init(parse: @escaping @Sendable (String) -> (done: Int, total: Int)? = { NoteChecklist.progress(in: $0) })
    {
        self.parse = parse
    }

    /// The checked and total boxes, or `nil` when the clip has no checklist.
    func progress(of clip: Clip) -> (done: Int, total: Int)? {
        guard let html = clip.richText else { return nil }
        if let known = entries.withLock({ $0[clip.id] }), known.html == html {
            return known.progress
        }
        let progress = parse(html)
        entries.withLock { $0[clip.id] = Entry(html: html, progress: progress) }
        return progress
    }

    /// Drops formatted content for clips no longer held by the panel snapshot.
    func prune(to clipIDs: Set<Clip.ID>) {
        entries.withLock { cached in
            for id in cached.keys.filter({ !clipIDs.contains($0) }) {
                cached.removeValue(forKey: id)
            }
        }
    }

}
