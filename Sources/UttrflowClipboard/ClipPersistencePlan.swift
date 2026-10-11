// The saved-index contents while clips move between their two files.

/// Plans the saved-index contents during a clip's transition between files.
enum ClipPersistencePlan {
    /// What the saved file holds while clips move: the new saved list, plus the old copy of any leaving it.
    static func bridging(
        _ clips: [Clip], from wasSaved: [Clip], into nowHistory: [Clip]
    ) -> [Clip] {
        let leaving = Set(nowHistory.map(\.id)).intersection(wasSaved.map(\.id))
        guard !leaving.isEmpty else { return clips.filter(\.isKept) }
        let old = Dictionary(wasSaved.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return clips.compactMap { $0.isKept ? $0 : leaving.contains($0.id) ? old[$0.id] : nil }
    }

    /// Whether two lists hold exactly the same clips, whatever their order.
    static func holdsTheSameClips(_ one: [Clip], as other: [Clip]) -> Bool {
        guard one.count == other.count else { return false }
        let byID = Dictionary(other.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return byID.count == other.count && one.allSatisfy { byID[$0.id] == $0 }
    }
}
