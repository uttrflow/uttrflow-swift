// What an undo of a deleted clip settled on.

/// The settled clipboard after undo and whether the restored alias conflicts.
public struct ClipboardRestoreResult: Sendable, Equatable {
    public let clips: [Clip]
    public let aliasWasAlreadyInUse: Bool

    package init(clips: [Clip], aliasWasAlreadyInUse: Bool) {
        self.clips = clips
        self.aliasWasAlreadyInUse = aliasWasAlreadyInUse
    }
}
