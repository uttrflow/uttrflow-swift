// Background detector transformations, separated from the actor's task and write lifecycle.

import Foundation

/// Classifies batches and reconciles detector-owned fields against the current clipboard snapshot.
enum ClipReclassification {
    /// Caps classifier work between cooperative background yields.
    private static let batchSize = 100

    /// Keeps each batch's detector work and cooperative yield in the detached caller.
    static func classify(_ candidates: [Clip]) async -> [Clip] {
        var result: [Clip] = []
        result.reserveCapacity(candidates.count)
        for start in stride(from: 0, to: candidates.count, by: batchSize) {
            let end = min(start + batchSize, candidates.count)
            for clip in candidates[start..<end] {
                result.append(clip.reclassified(as: ClipKindDetector.classification(of: clip.text)))
            }
            await Task.yield()
        }
        return result
    }

    /// Applies detector-owned fields only when the classified snapshot still names the current text.
    static func merge(
        _ updated: [Clip], from snapshot: [Clip], into current: [Clip]
    ) -> (clips: [Clip], coversCurrentText: Bool) {
        let replacements = Dictionary(updated.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        let snapshotByID = Dictionary(snapshot.map { ($0.id, $0) }, uniquingKeysWith: { _, newer in newer })
        var coversCurrentText = true
        let clips = current.map { clip -> Clip in
            // Pictures are classified from their bytes at arrival and never enter text detection.
            guard clip.image == nil, clip.files == nil else { return clip }
            guard let old = snapshotByID[clip.id], old.text == clip.text,
                let replacement = replacements[clip.id]
            else {
                coversCurrentText = false
                return clip
            }
            // A detector update never erases a clip the user pinned, named, tagged or filed: it keeps its stored kind.
            guard !(clip.isKept && replacement.kind == .secret) else { return clip }
            return clip.reclassified(
                as: ClipClassification(kind: replacement.kind, language: replacement.language))
        }
        return (clips, coversCurrentText)
    }

    /// Keeps live eviction order and the user's secrecy answers on the reconciled records.
    static func ordered(
        _ clips: [Clip], in wholeList: [Clip], secrecy: inout ClipSecrecyOverrides
    ) -> [Clip] {
        let orders = Dictionary(
            wholeList.compactMap { clip in clip.lastUsedOrder.map { (clip.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        return clips.map { clip in
            let ordered = orders[clip.id].map(clip.orderedForEviction) ?? clip
            return ordered.image == nil && ordered.files == nil ? secrecy.applied(to: ordered) : ordered
        }
    }
}
