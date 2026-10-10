// What stays in a list of clips, and what is cut back, as pure functions over that list.

import UttrflowCore

import struct Foundation.UUID

/// The retention rules over a list of clips; see `Docs/retention-clock.md` and `Docs/clipboard-budget.md`.
struct RetentionPolicy: Sendable, Equatable {
    /// What each pool of clips may cost, and for how long.
    let budget: ClipboardBudget

    /// Spares every kept clip, then applies the window and the per-pool caps to the history.
    func retained(_ clips: [Clip], keeping retention: ClipRetention) -> [Clip] {
        held(clips, keeping: retention) { survives($0, keeping: retention) }
    }

    /// The same, plus what a clock too far ahead to be believed says is past. See `Docs/retention-clock.md`.
    func keptOnDisk(_ clips: [Clip], keeping retention: ClipRetention) -> [Clip] {
        held(clips, keeping: retention) { clip in
            let window = window(for: clip, keeping: retention)
            return window.keeps(clip.copiedAt) || !window.mayDelete(clip.copiedAt)
        }
    }

    /// The caps and quotas, over whichever clips the window has spared.
    func held(
        _ clips: [Clip], keeping retention: ClipRetention, _ survives: (Clip) -> Bool
    ) -> [Clip] {
        // Kept clips are not candidates at all: their pool has no tier to be an exception to.
        let history = clips.filter { ClipClass(of: $0).isEvictable }
        let surviving = history.filter(survives)

        // Per pool, so a morning of dictating cannot push out yesterday's ⌘C or a picture.
        var taken: [ClipClass: Int] = [:]
        var within: Set<UUID> = []
        for clip in surviving {
            let pool = ClipClass(of: clip)
            guard let tier = budget.tier(for: pool), taken[pool, default: 0] < tier.items
            else { continue }
            taken[pool, default: 0] += 1
            within.insert(clip.id)
        }

        // Filtered rather than concatenated, which keeps arrival order in one pass and without a sort.
        let kept = clips.filter { !ClipClass(of: $0).isEvictable || within.contains($0.id) }
        return withinDisk(withinMemory(kept))
    }

    /// What a clip costs this process to hold: its words, and deliberately not its picture's file.
    static func weight(of clip: Clip) -> Int {
        clip.text.utf8.count + (clip.richText?.utf8.count ?? 0)
    }

    /// Applies the same text-and-rich-text bound to copied clips and every stored edit.
    func fitsLargestClip(_ clip: Clip) -> Bool {
        budget.fitsLargestClip(weighing: Self.weight(of: clip))
    }

    /// What a list of clips costs this process to hold.
    static func weight(of clips: [Clip]) -> Int {
        clips.reduce(0) { $0 + weight(of: $1) }
    }

    /// Drops the least recently used clips of a text pool until it fits its memory quota.
    func withinMemory(_ clips: [Clip]) -> [Clip] {
        var dropped: Set<UUID> = []
        // Only the text pools: a picture's bytes are a file, and its thumbnail is bounded elsewhere.
        for pool in [ClipClass.copied, .dictation] {
            guard let tier = budget.tier(for: pool), tier.bytes > 0 else { continue }
            let list = clips.filter { ClipClass(of: $0) == pool }
            var weight = Self.weight(of: list)
            guard weight > tier.bytes else { continue }
            for clip in list.sorted(by: { ($0.lastUsedOrder ?? 0) < ($1.lastUsedOrder ?? 0) })
            where weight > tier.bytes {
                dropped.insert(clip.id)
                weight -= Self.weight(of: clip)
            }
        }
        return clips.filter { !dropped.contains($0.id) }
    }

    /// Drops the least recently used pictures until the folder fits its disk budget.
    func withinDisk(_ clips: [Clip]) -> [Clip] {
        guard budget.disk > 0 else { return clips }
        // Pinned pictures count toward the budget so pinning many of them cannot push the unpinned pool past the bound.
        let pictures = clips.filter { $0.kind == .image || $0.image != nil }
        var weight = pictures.reduce(0) { $0 + ($1.image?.bytes ?? 0) }
        guard weight > budget.disk else { return clips }
        var dropped: Set<UUID> = []
        // Only the un-kept pictures may be evicted; kept ones are exempt by the kept pool's rule.
        let evictable =
            pictures
            .filter { !$0.isKept }
            .sorted { ($0.lastUsedOrder ?? 0) < ($1.lastUsedOrder ?? 0) }
        for clip in evictable where weight > budget.disk {
            dropped.insert(clip.id)
            weight -= clip.image?.bytes ?? 0
        }
        return clips.filter { !dropped.contains($0.id) }
    }

    /// Whether an unkept clip is still inside its window; zero days keeps nothing.
    func survives(_ clip: Clip, keeping retention: ClipRetention) -> Bool {
        window(for: clip, keeping: retention).keeps(clip.copiedAt)
    }

    /// The promise this clip is held to, as the rule the three stores share states it.
    func window(for clip: Clip, keeping retention: ClipRetention) -> RetentionWindow {
        // The pool's own window where it has one, and the user's transcript setting for a dictation.
        let clipClass = ClipClass(of: clip)
        let days =
            clipClass == .dictation
            ? (retention.dictationDays ?? budget.tier(for: clipClass)?.days ?? retention.days)
            : (budget.tier(for: clipClass)?.days ?? retention.days)
        return RetentionWindow(days: days, now: retention.now)
    }
}
