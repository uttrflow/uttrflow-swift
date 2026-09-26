// Decides whether work that finishes after its keypress may still write into the panel.
public import UttrflowClipboard

/// The panel as it stood when slow work was asked for, so its result lands only where it was asked for.
public struct PanelLateRequest: Sendable, Equatable {
    /// The count of panel opens at the keypress; a close and reopen changes it.
    public let opens: Int
    /// The sheet that was over the list at the keypress.
    public let sheet: PanelSheet?

    /// Records the open and the sheet a keypress was made in.
    public init(opens: Int, sheet: PanelSheet?) {
        self.opens = opens
        self.sheet = sheet
    }

    /// Whether the panel is the one open this was asked in, still showing; enough for a late notice.
    public func isSameOpen(_ snapshot: PanelSnapshot?, opens current: Int) -> Bool {
        snapshot != nil && current == opens
    }

    /// Whether a late result may be written: the same open, still showing, with no other sheet opened since.
    public func stillOwns(_ snapshot: PanelSnapshot?, opens current: Int) -> Bool {
        guard isSameOpen(snapshot, opens: current) else { return false }
        return snapshot?.sheet == sheet
    }
}

/// A formatter run on one clip, remembered so a late or superseded result is dropped rather than shown.
public struct PanelFormatRequest: Sendable, Equatable {
    /// Where the run was asked for.
    public let owner: PanelLateRequest
    /// The clip being formatted.
    public let clip: Clip.ID
    /// The text handed to the formatter, which the diff is built from.
    public let text: String
    /// Which run this is; a later Format on the panel supersedes every earlier one.
    public let run: Int

    /// Records one formatter run.
    public init(owner: PanelLateRequest, clip: Clip.ID, text: String, run: Int) {
        self.owner = owner
        self.clip = clip
        self.text = text
        self.run = run
    }

    /// Whether this run's result may open its sheet: still the latest run, same open, same sheet, same text.
    public func accepts(into snapshot: PanelSnapshot?, opens: Int, latestRun: Int) -> Bool {
        guard run == latestRun, owner.stillOwns(snapshot, opens: opens), let snapshot else {
            return false
        }
        return snapshot.clips.first(where: { $0.id == clip })?.text == text
    }
}
