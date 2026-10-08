// What the panel says when it has nothing to list, told apart by why.
internal import UttrflowClipboard

extension PanelPresenter {
    /// The nothings, told apart, because what to do about each one differs.
    static func emptyState(for snapshot: PanelSnapshot) -> MainEmptyState {
        let query = snapshot.needle

        // The only nothing that is about the clipboard rather than the narrowing.
        if snapshot.clips.isEmpty {
            return MainEmptyState(
                symbolName: "doc.on.clipboard",
                title: "Nothing copied yet",
                message: "Whatever you copy turns up here, ready to put back.")
        }

        // Emptied by tidying, not by never copying. See `Docs/panel.md`.
        if query.isEmpty, snapshot.filter == .all, PanelSnapshot.name(snapshot.category) == nil,
            let arrivals = arrivalsOrigin(of: snapshot.scope),
            snapshot.clips.contains(where: { $0.origin == arrivals })
        {
            return MainEmptyState(
                symbolName: "tray",
                title: "Nothing loose",
                message: arrivals == .copied
                    ? "Everything you have copied is pinned or filed."
                    : "Everything Uttrflow made is pinned or filed.")
        }

        // The kind chip is the one narrowing a search keeps, so an empty search names it and the way out.
        if !query.isEmpty, snapshot.filter != .all {
            if snapshot.hasWholeTextMatch {
                return .noMatches(
                    "A clip with this exact text is under another kind. Choose All to search every kind."
                )
            }
            return .noMatches(
                "Nothing under \(snapshot.filter.title) mentions “\(query)”. Choose All to search everything."
            )
        }

        if snapshot.hasWholeTextMatch {
            return .noMatches("A clip with this exact text is already in your history.")
        }

        // A search spans every tab and collection, so naming one would describe a constraint not applied.
        if !query.isEmpty {
            // Not "nothing you have copied": a search spans what Uttrflow made too.
            return .noMatches("Nothing on your clipboard mentions “\(query)”.")
        }

        return narrowedEmptyState(for: snapshot)
    }

    /// Which arrivals tab this is, of the two that list what has not been put anywhere.
    static func arrivalsOrigin(of scope: PanelScope) -> ClipOrigin? {
        switch scope {
        case .history: .copied
        case .uttrflow: .uttrflow
        case .pinned, .collections: nil
        }
    }

    /// What to say when the narrowing hid everything, assembled from every narrowing that is on. See `Docs/panel.md`.
    static func narrowedEmptyState(for snapshot: PanelSnapshot) -> MainEmptyState {
        let category = PanelSnapshot.name(snapshot.category)
        let kind = snapshot.filter == .all ? nil : snapshot.filter
        let place = place(for: snapshot.scope, category: category)

        guard let kind else {
            return MainEmptyState(
                symbolName: place.symbolName, title: place.title, message: place.alone)
        }
        return MainEmptyState(
            symbolName: place.symbolName,
            title: "No \(kind.title) \(place.suffix)",
            message: "Nothing \(place.subject) is \(kind.noun).")
    }

    /// Where the user is looking: a tab, a collection, or both. Total, so no case needs its own sentence.
    static func place(for scope: PanelScope, category: String?) -> PanelEmptyPlace {
        switch (scope, category) {
        case (.pinned, .some(let name)):
            PanelEmptyPlace(
                symbolName: "pin", title: "Nothing pinned in \(name)",
                suffix: "pinned in \(name)", subject: "pinned in \(name)",
                alone: "Nothing filed in \(name) is pinned.")
        case (.pinned, .none):
            PanelEmptyPlace(
                symbolName: "pin", title: "Nothing pinned", suffix: "pinned",
                subject: "you have pinned",
                alone: "Pin a clip and it waits here, however long it has been.")
        case (.uttrflow, .some(let name)):
            // Named as both, or the shared arm says three things that are false here.
            PanelEmptyPlace(
                symbolName: "waveform", title: "Nothing from Uttrflow in \(name)",
                suffix: "from Uttrflow in \(name)", subject: "Uttrflow made in \(name)",
                alone: "Nothing filed in \(name) came from Uttrflow.")
        case (_, .some(let name)):
            PanelEmptyPlace(
                symbolName: "folder", title: "Nothing in \(name)", suffix: "in \(name)",
                subject: "filed in \(name)",
                alone: "Nothing you have copied is filed here.")
        case (.collections, .none):
            PanelEmptyPlace(
                symbolName: "tag", title: "Nothing filed", suffix: "filed",
                subject: "you have filed",
                alone: "Move a clip into a collection and it turns up here.")
        case (.uttrflow, .none):
            PanelEmptyPlace(
                // A waveform, not the mark, which would read as branding on an empty screen.
                symbolName: "waveform", title: "Nothing from Uttrflow", suffix: "from Uttrflow",
                subject: "Uttrflow has made",
                alone: "Dictate something and it waits here, out of the way of what you copy.")
        case (.history, .none):
            PanelEmptyPlace(
                symbolName: "doc.on.clipboard", title: "Nothing copied yet", suffix: "copied",
                subject: "you have copied",
                // The empty-clipboard sentence, which is the plain truth on this tab too.
                alone: "Whatever you copy turns up here, ready to put back.")
        }
    }
}
