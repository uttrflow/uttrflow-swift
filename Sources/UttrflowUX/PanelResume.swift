// Reopening the panel where the user left it, when the dismissal was a moment ago.
public import Foundation
public import UttrflowClipboard

/// Where the user was when the panel last closed, since a dismissal is usually an accident.
public struct PanelResume: Sendable, Equatable {
    /// Which bottom-bar tab was showing; needed because a tab hides clips, so the selection depends on it.
    public let scope: PanelScope
    /// The collection that was open.
    public let category: String?
    /// The clip the highlight was on.
    public let selection: Clip.ID?
    /// A7 — a half-typed alias is kept, not discarded silently.
    public let sheet: PanelSheet?
    /// When the panel closed.
    public let closedAt: Date

    /// Builds a resume point; the scope defaults to History.
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
    /// How long a dismissal counts as an accident: twenty seconds, long enough to fumble and reopen.
    public static let resumeWindow: TimeInterval = 20

    /// A panel opened over what the user was last doing, restoring the place and nothing else.
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
        // Only a collection that still exists, or the panel opens on an empty list with a chip for nothing.
        if let category = resume.category, snapshot.categories.contains(category) {
            snapshot.category = category
        }
        // Only a clip the reopened tab and collection show; otherwise the aim would silently move.
        let insideCollection = snapshot.category != nil
        if let selection = resume.selection,
            clips.contains(where: {
                $0.id == selection && resume.scope.admits($0, inCollection: insideCollection)
            })
        {
            snapshot.selection = selection
        }
        // Only a sheet whose subject still exists, or the panel reopens asking about nothing.
        if let sheet = resume.sheet {
            // A clip's sheet needs the clip; a collection's needs the collection.
            let subjectSurvives =
                sheet.clip.map { id in clips.contains { $0.id == id } }
                ?? sheet.category.map(snapshot.categories.contains) ?? false
            if subjectSurvives { snapshot.sheet = sheet }
        }
        return snapshot
    }
}
