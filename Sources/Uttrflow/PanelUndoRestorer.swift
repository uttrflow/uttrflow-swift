// Restores every clip from one grouped-delete undo and reports alias conflicts once.
import UttrflowClipboard
import UttrflowUX

enum PanelUndoRestorer {
    /// Restores clips in their saved order and releases picture holds after every write succeeds.
    static func restore(
        _ clips: [Clip], to clipboard: ClipboardStore, keeping retention: ClipRetention
    ) async throws(ClipboardStoreError) -> PanelNotice? {
        var aliasConflict = false
        for clip in clips {
            let result = try await clipboard.restoreReportingAliasConflict(
                clip, keeping: retention)
            aliasConflict = aliasConflict || result.aliasWasAlreadyInUse
        }
        await clipboard.forgetHeldPictures()
        return aliasConflict ? .restoreWithoutAlias : nil
    }
}
