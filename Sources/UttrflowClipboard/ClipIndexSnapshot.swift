// The three loaded clipboard snapshots and their reconciliation, without file I/O.

import Foundation

/// Owns known index contents and the live list assembled from them.
struct ClipIndexSnapshot {
    /// What the saved file is known to hold, which the migration off one file makes differ from memory.
    var savedOnDisk: [Clip]?

    /// What the history file is known to hold, so an edit to a kept clip leaves it unwritten.
    var historyOnDisk: [Clip]?

    /// The history and the saved clips as one list, or `nil` before the files have been read.
    var wholeList: [Clip]?

    /// Reconciles both loaded indexes while retaining unknown history as unknown.
    mutating func load(
        saved: [Clip], history: [Clip], at historyFile: URL, unreplaceable: Set<URL>
    ) -> [Clip] {
        savedOnDisk = saved
        let savedIDs = Set(saved.map(\.id))
        // An unreplaceable file is unknown rather than empty, so every save still meets its refusal.
        historyOnDisk = unreplaceable.contains(historyFile) ? nil : history
        let stored = saved + history.filter { !savedIDs.contains($0.id) }
        let list = ClipOrdering.uniqueAliases(
            in: ClipOrdering.interleaving(
                saved: ClipOrdering.orderedForDisplay(stored.filter(\.isKept)),
                history: ClipOrdering.orderedForDisplay(stored.filter { !$0.isKept })))
        let normalized = ClipOrdering.numberedForEviction(list)
        return normalized
    }

    /// Returns the currently loaded clips belonging to one index.
    func current(in url: URL, savedFile: URL) -> [Clip] {
        url == savedFile ? (savedOnDisk ?? []) : (historyOnDisk ?? [])
    }

    /// Replaces one index's clips in memory after its background detector pass commits.
    mutating func replace(_ clips: [Clip], in url: URL, savedFile: URL) {
        let byID = Dictionary(clips.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        // A clip the pass judged secret is not persistable, so it leaves the list with its index entry.
        let dropped = Set(current(in: url, savedFile: savedFile).map(\.id)).subtracting(byID.keys)
        if url == savedFile {
            savedOnDisk = clips
        } else {
            historyOnDisk = clips
        }
        wholeList = wholeList?.compactMap { clip in
            guard !dropped.contains(clip.id) else { return nil }
            guard let fresh = byID[clip.id], fresh.text == clip.text else { return clip }
            return clip.reclassified(as: ClipClassification(kind: fresh.kind, language: fresh.language))
        }
    }
}
