// Calculates clip edits and the transition from kept clips back into ordinary history.

import Foundation

/// Shares single and collection edit rules while the actor retains loading and persistence.
enum ClipEdits {
    /// Applies an edit, secrecy answers and size limits before refreshing an unkept clip.
    static func changing(
        _ id: UUID, in stored: [Clip], keeping retention: ClipRetention,
        secrecy: inout ClipSecrecyOverrides, policy: RetentionPolicy,
        lastUsedOrder: inout UInt64, _ edit: (inout Clip) -> Void
    ) throws(ClipboardStoreError) -> [Clip] {
        var clips = stored
        if let index = clips.firstIndex(where: { $0.id == id }) {
            let wasKept = clips[index].isKept
            edit(&clips[index])
            // An edit that asked the detector again must not overrule the user's answer about this text.
            clips[index] = secrecy.applied(to: clips[index])
            guard policy.fitsLargestClip(clips[index]) else { throw .couldNotWrite }
            if resetAgeIfUnkept(
                &clips[index], wasKept: wasKept, keeping: retention, lastUsedOrder: &lastUsedOrder)
            {
                let fresh = clips.remove(at: index)
                clips.insert(fresh, at: 0)
            }
        }
        return clips
    }

    /// Moves a collection and promotes only clips that lose their final keeping marker.
    static func movingCategory(
        _ name: String, to destination: String?, in stored: [Clip], keeping retention: ClipRetention,
        lastUsedOrder: inout UInt64
    ) -> [Clip] {
        var clips = stored
        var freshlyUnkept: Set<UUID> = []
        for index in clips.indices where clips[index].category == name {
            let wasKept = clips[index].isKept
            clips[index].category = destination
            if resetAgeIfUnkept(
                &clips[index], wasKept: wasKept, keeping: retention, lastUsedOrder: &lastUsedOrder)
            {
                freshlyUnkept.insert(clips[index].id)
            }
        }
        if !freshlyUnkept.isEmpty {
            clips =
                clips.filter { freshlyUnkept.contains($0.id) }
                + clips.filter { !freshlyUnkept.contains($0.id) }
        }
        return clips
    }

    /// Resets a clip's age when this edit removes its last keeping marker.
    private static func resetAgeIfUnkept(
        _ clip: inout Clip, wasKept: Bool, keeping retention: ClipRetention, lastUsedOrder: inout UInt64
    ) -> Bool {
        guard wasKept && !clip.isKept else { return false }
        clip = clip.recopied(at: retention.now, order: nextUseOrder(&lastUsedOrder))
        return true
    }

    /// Advances the same persisted eviction sequence without overflowing.
    static func nextUseOrder(_ lastUsedOrder: inout UInt64) -> UInt64 {
        if lastUsedOrder < .max { lastUsedOrder += 1 }
        return lastUsedOrder
    }
}
