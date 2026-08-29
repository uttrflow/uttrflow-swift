public import Foundation
public import UttrflowClipboard

/// Where the user was when the panel last closed.
///
/// A3 and A7 are the same problem seen twice: this panel is dismissed constantly and by
/// design — a stray click, a wrong key, a change of mind — and losing the tab somebody was
/// browsing or the alias they were halfway through typing punishes an accident that the
/// interface positively invites.
public struct PanelResume: Sendable, Equatable {
    /// Which of the bottom-bar tabs was showing.
    ///
    /// Carried for the same reason the collection is, and it became necessary at the same
    /// moment the bar gained a tab that hides clips: while History admitted everything, a
    /// panel reopening on History showed the remembered clip whatever tab it had been
    /// found under, so losing the tab cost nothing. Now a dictation selected under From
    /// Uttrflow is not in History's rows at all, the selection falls back to the top, and
    /// the user reopens aimed at a different clip.
    public let scope: PanelScope
    public let category: String?
    public let selection: Clip.ID?
    /// A7 — a half-typed alias is kept, not discarded silently.
    public let sheet: PanelSheet?
    public let closedAt: Date

    public init(
        scope: PanelScope = .history, category: String?, selection: Clip.ID?,
        sheet: PanelSheet?, closedAt: Date
    ) {
        self.scope = scope
        self.category = category
        self.selection = selection
        self.sheet = sheet
        self.closedAt = closedAt
    }
}

extension PanelSnapshot {
    /// How long a dismissal counts as an accident.
    ///
    /// Twenty seconds. Long enough to cover the fumble this exists for — dismissing,
    /// realising, reopening — and short enough that the panel is back at Home by the next
    /// time somebody reaches for it deliberately. A panel that remembered for an hour
    /// would open in a collection the user had forgotten choosing, which is the same
    /// disorientation in the other direction.
    public static let resumeWindow: TimeInterval = 20

    /// A panel opened over what the user was last doing, where that was a moment ago.
    ///
    /// Everything except the place is deliberately not restored. The clips are read fresh,
    /// the search field starts empty, and nothing revealed stays revealed — a secret
    /// unmasked before an accidental dismissal must not still be unmasked when the panel
    /// comes back, because the room may have changed.
    public static func opening(
        clips: [Clip],
        now: Date,
        locale: Locale = .autoupdatingCurrent,
        insertion: PanelInsertion = .atCaret,
        resuming resume: PanelResume? = nil
    ) -> PanelSnapshot {
        var snapshot = PanelSnapshot(clips: clips, now: now, locale: locale)
        snapshot.insertion = insertion

        guard let resume, now.timeIntervalSince(resume.closedAt) <= resumeWindow else {
            return snapshot
        }
        // The tab first, because what the two below are checked against depends on it.
        snapshot.scope = resume.scope
        // Only a collection that still exists. One whose last clip has since aged out
        // would open the panel on an empty list with a chip for nothing.
        if let category = resume.category, snapshot.categories.contains(category) {
            snapshot.category = category
        }
        // Only a clip that is still there *and* that the reopened tab shows. A selection
        // the tab does not admit is not restored at all: it would silently fall back to
        // the top, which reads as the panel having moved the user's aim rather than
        // having lost the clip.
        //
        // Asked of the tab *and* the collection together, because a collection chip lifts
        // the arrivals rule — see ``PanelScope/admits(_:inCollection:)``. Asking the tab
        // alone said no to every filed clip, so reopening inside a collection always
        // landed on its first row rather than the one the user had arrowed to.
        let insideCollection = snapshot.category != nil
        if let selection = resume.selection,
            clips.contains(where: {
                $0.id == selection && resume.scope.admits($0, inCollection: insideCollection)
            })
        {
            snapshot.selection = selection
        }
        // And only a sheet about a clip that still exists, or the panel would reopen
        // asking a question about something that has gone.
        if let sheet = resume.sheet {
            // A sheet about a clip that has gone would reopen the panel asking a question
            // about nothing; one about a collection is checked the same way.
            let subjectSurvives =
                sheet.clip.map { id in clips.contains { $0.id == id } }
                ?? sheet.category.map(snapshot.categories.contains) ?? false
            if subjectSurvives { snapshot.sheet = sheet }
        }
        return snapshot
    }
}
