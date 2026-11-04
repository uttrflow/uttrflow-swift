// Editing a clip's text from the panel: which clips may be edited, and what Save sends the store.
import UttrflowClipboard

extension PanelSnapshot {
    /// Any text on screen, except one whose formatted form plain editing would lose. See `Docs/panel.md`.
    func isEditable(_ clip: Clip) -> Bool {
        clip.image == nil && clip.files == nil && !isMasked(clip)
            && clip.richText.map(NotePromotion.isEditableNote) ?? true
    }

    /// What the Edit field shows: a note's plain form, where its boxes read `[ ] ` and `[x] `.
    private func editableText(of clip: Clip) -> String {
        clip.richText.map(RichTextPlainForm.plainText(fromHTML:)) ?? clip.text
    }

    /// Opens Edit on the clip's whole text; a clip that cannot be edited opens nothing.
    func editing(_ id: Clip.ID) -> PanelResponse {
        guard let clip = clip(id), isEditable(clip) else { return stayingOpen }
        return opening(.editing(id, draft: editableText(of: clip)))
    }

    /// Whether Save would send anything: changed text that is not blank and that the store would keep.
    func canSave(_ draft: String, over clip: Clip) -> Bool {
        draft != editableText(of: clip) && ClipContent.isWorthKeeping(draft)
            && ClipboardBudget.standard.fitsLargestClip(weighing: draft.utf8.count)
    }

    /// Save.
    func committingEdit(_ id: Clip.ID, draft: String) -> PanelResponse {
        guard let clip = clip(id), canSave(draft, over: clip) else { return stayingOpen }
        return PanelResponse(state: closingSheet(), outcome: .change(.editText(id, draft)))
    }

    /// Format and Re-indent.
    func committingRewrite(_ id: Clip.ID, to formatted: String) -> PanelResponse {
        guard clip(id) != nil else { return stayingOpen }
        return PanelResponse(state: closingSheet(), outcome: .change(.rewriteText(id, formatted)))
    }
}
