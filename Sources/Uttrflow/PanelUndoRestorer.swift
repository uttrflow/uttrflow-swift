// Reverses the panel's last change: restores a delete's clips, or writes an edit's old text back.
import UttrflowClipboard
import UttrflowUX

enum PanelUndoRestorer {
    /// Reverses whichever change the claim holds, once its delete has finished.
    static func restore(
        _ claim: PanelUndoClaim, to clipboard: ClipboardStore, keeping retention: ClipRetention
    ) async throws(ClipboardStoreError) -> PanelNotice? {
        try await claim.waitForDelete()
        guard let edit = claim.edit else {
            return try await restore(claim.clips, to: clipboard, keeping: retention)
        }
        _ = try await clipboard.setText(edit.previousText, of: edit.id, keeping: retention)
        return nil
    }

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
