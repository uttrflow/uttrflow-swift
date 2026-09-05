// The clipboard a test panel is opened over: a fixed clock, three clips, and a panel builder.
import Foundation
import UttrflowClipboard

@testable import UttrflowUX

/// The clipboard a test panel is opened over.
enum PanelFixture {
    /// A fixed region.
    static let locale = Locale(identifier: "en_GB")

    /// Mid-afternoon on 15 June 2025, the same instant the history suite uses, so "2 minutes ago" agrees.
    static let now = Date(timeIntervalSince1970: 1_750_000_800)

    /// One clip, plain and unkept unless said otherwise.
    static func clip(
        _ text: String = "Hello there",
        kind: ClipKind = .text,
        minutesAgo: Int = 0,
        alias: String? = nil,
        category: String? = nil,
        isPinned: Bool = false,
        origin: ClipOrigin = .copied
    ) -> Clip {
        Clip(
            text: text, kind: kind, copiedAt: now.addingTimeInterval(Double(-minutesAgo) * 60),
            origin: origin,
            alias: alias, category: category, isPinned: isPinned)
    }

    /// Three clips newest first, held rather than rebuilt so a test can compare identities.
    static let clips = [
        clip("The first thing", minutesAgo: 1),
        clip("The second thing", minutesAgo: 2),
        clip("The third thing", minutesAgo: 3),
    ]

    /// A panel over these clips at the fixed clock.
    static func panel(
        _ clips: [Clip] = clips,
        query: String = "",
        filter: PanelFilter = .all,
        category: String? = nil,
        revealed: Set<Clip.ID> = []
    ) -> PanelSnapshot {
        PanelSnapshot(
            clips: clips, query: query, filter: filter, category: category, revealed: revealed,
            now: now, locale: locale)
    }
}
