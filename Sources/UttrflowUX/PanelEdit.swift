// Editing a clip's text from the panel: which clips may be edited, and what Save sends the store.
import UttrflowClipboard

extension PanelSnapshot {
    /// Said once before Save makes a kept clip a secret, which the store never writes to disk.
    static let unsavedSecretWarning = "This will no longer be saved between launches"

    /// Any text on screen, except one whose formatted form plain editing would discard. See `Docs/panel.md`.
    func isEditable(_ clip: Clip) -> Bool {
        clip.image == nil && clip.richText == nil && !isMasked(clip)
    }

    /// Opens Edit on the clip's whole text; a clip that cannot be edited opens nothing.
    func editing(_ id: Clip.ID) -> PanelResponse {
        guard let clip = clip(id), isEditable(clip) else { return stayingOpen }
        return opening(.editing(id, draft: clip.text))
    }

    /// Whether Save would send anything: changed text that is not blank and that the store would keep.
    func canSave(_ draft: String, over clip: Clip) -> Bool {
        draft != clip.text && ClipContent.isWorthKeeping(draft)
            && ClipboardBudget.standard.fitsLargestClip(weighing: draft.utf8.count)
    }

    /// Save, which first warns once when the edit would stop a kept clip being saved.
    func committingEdit(_ id: Clip.ID, draft: String) -> PanelResponse {
        guard let clip = clip(id), canSave(draft, over: clip) else { return stayingOpen }
        if !hasWarnedOfUnsavedSecret, wouldStopBeingSaved(clip, as: draft) {
            var next = self
            next.hasWarnedOfUnsavedSecret = true
            return PanelResponse(state: next, outcome: .open)
        }
        return PanelResponse(state: closingSheet(), outcome: .change(.editText(id, draft)))
    }

    /// Whether a kept clip now on disk would become a secret, which the store holds in memory only.
    private func wouldStopBeingSaved(_ clip: Clip, as draft: String) -> Bool {
        clip.isKept && clip.kind != .secret && ClipKindDetector.kind(of: draft) == .secret
    }
}
