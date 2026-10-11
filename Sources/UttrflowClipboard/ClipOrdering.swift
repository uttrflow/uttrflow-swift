// The order clips are shown, numbered for eviction and kept in, as pure functions over lists.

/// The order rules for a list of clips; no file, no actor, no clock. See `Docs/clipboard-store.md`.
enum ClipOrdering {
    /// Keeps the first clip holding an alias and removes that alias from later clips.
    static func uniqueAliases(in clips: [Clip]) -> [Clip] {
        var aliases: Set<String> = []
        return clips.map { clip in
            guard let alias = clip.alias else { return clip }
            guard aliases.insert(alias).inserted else {
                var unnamed = clip
                unnamed.alias = nil
                return unnamed
            }
            return clip
        }
    }

    /// Keeps stored use orders that are whole and distinct, so a reopened list equals the one that wrote it.
    static func numberedForEviction(_ list: [Clip]) -> [Clip] {
        let stored = list.compactMap(\.lastUsedOrder)
        if stored.count == list.count, Set(stored).count == list.count { return list }
        let ordered = list.enumerated().sorted { left, right in
            switch (left.element.lastUsedOrder, right.element.lastUsedOrder) {
            case (let leftOrder?, let rightOrder?):
                return leftOrder == rightOrder ? left.offset < right.offset : leftOrder < rightOrder
            case (nil, nil):
                let leftDate = left.element.lastUsedAt
                let rightDate = right.element.lastUsedAt
                return leftDate == rightDate ? left.offset < right.offset : leftDate < rightDate
            case (nil, .some):
                return true
            case (.some, nil):
                return false
            }
        }
        var orderByIndex = Array(repeating: UInt64(0), count: list.count)
        for (order, clip) in ordered.enumerated() {
            orderByIndex[clip.offset] = UInt64(order + 1)
        }
        return list.enumerated().map { pair in
            pair.element.orderedForEviction(orderByIndex[pair.offset])
        }
    }

    /// The two lists as one, newest used first; a merge keeps each persisted pool's order intact.
    static func interleaving(saved: [Clip], history: [Clip]) -> [Clip] {
        var out: [Clip] = []
        out.reserveCapacity(saved.count + history.count)
        var left = 0
        var right = 0
        while left < saved.count, right < history.count {
            if precedesForDisplay(saved[left], history[right]) {
                out.append(saved[left])
                left += 1
            } else {
                out.append(history[right])
                right += 1
            }
        }
        out.append(contentsOf: saved[left...])
        out.append(contentsOf: history[right...])
        return out
    }

    /// Sorts each persisted pool by its monotonic use order, retaining arrival order for legacy clips.
    static func orderedForDisplay(_ clips: [Clip]) -> [Clip] {
        clips.enumerated().sorted { left, right in
            if precedesForDisplay(left.element, right.element) { return true }
            if precedesForDisplay(right.element, left.element) { return false }
            return left.offset < right.offset
        }.map(\.element)
    }

    /// Compares by persisted use order and falls back to arrival time only before an order was stored.
    static func precedesForDisplay(_ left: Clip, _ right: Clip) -> Bool {
        switch (left.lastUsedOrder, right.lastUsedOrder) {
        case (let leftOrder?, let rightOrder?):
            return leftOrder == rightOrder ? left.copiedAt > right.copiedAt : leftOrder > rightOrder
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return left.copiedAt > right.copiedAt
        }
    }
}
