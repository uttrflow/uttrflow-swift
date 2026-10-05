// What the app does after a panel keystroke; a picture travels as a clip, since only the store opens files.
public import UttrflowClipboard

/// What the app does about an answered keystroke, held here so a test can reach the two decisions.
public enum PanelEffect: Sendable, Equatable {
    /// Still open. Draw the new state and wait for the next key.
    case redraw
    /// Put the panel away, having changed nothing.
    case close
    /// Carry this out in the store, then redraw; the panel stays up, since one errand is rarely the last.
    case applyAndRedraw(PanelChange)
    /// Close and put this text at the caret; `used` names the clip so the last-used clock keeps running.
    case closeAndInsert(String, used: Clip.ID)
    /// The same for a secret, whose words may only reach the clipboard marked concealed.
    case closeAndInsertConcealed(String, used: Clip.ID)
    /// The same with the formatted form, so the receiving application takes whichever it understands.
    case closeAndInsertFormatted(String, richText: String, used: Clip.ID)
    /// Put it on the clipboard, say why on the panel, and close a moment later; never called an insertion.
    case copyAndSay(String, PanelNotice, used: Clip.ID)
    /// The same for a secret, written with the concealed marker so clipboard histories keep it out.
    case copyConcealedAndSay(String, PanelNotice, used: Clip.ID)
    /// Put the picture at the caret; carries the clip because the bytes are a file only the store can open.
    case closeAndInsertImage(Clip)
    /// Put the picture on the clipboard and say why it could not be placed, as `copyAndSay` does for text.
    case copyImageAndSay(Clip, PanelNotice)
    /// Put this text on the clipboard and close, for the row's Copy.
    case closeAndCopy(String, richText: String?, used: Clip.ID)
    /// Put a secret on the clipboard marked concealed and close, for the row's Copy on a secret.
    case closeAndCopyConcealed(String, used: Clip.ID)
    /// Put the picture on the clipboard and close, for the row's Copy on a picture.
    case closeAndCopyImage(Clip)
    /// B8 — say the picture has gone, and leave the panel up so the row can be seen.
    case say(PanelNotice)
}

extension PanelOutcome {
    /// Inserting closes the panel, and what is inserted is the clip's text, never what the row drew.
    public var effect: PanelEffect {
        switch self {
        case .open: .redraw
        case .dismissed: .close
        case .insert(let clip) where clip.kind == .secret, .insertPlain(let clip) where clip.kind == .secret:
            .closeAndInsertConcealed(clip.text, used: clip.id)
        case .insert(let clip):
            // Plain is what a clip without a rich form has always been; the panel decided, this only reports.
            clip.richText.map {
                .closeAndInsertFormatted(clip.text, richText: $0, used: clip.id)
            } ?? .closeAndInsert(clip.text, used: clip.id)
        case .insertPlain(let clip): .closeAndInsert(clip.text, used: clip.id)
        case .insertCleaned(let clip) where clip.kind == .secret:
            .closeAndInsertConcealed(
                ClipTextSafety.removingDisplayHazards(from: clip.text), used: clip.id)
        case .insertCleaned(let clip):
            .closeAndInsert(
                ClipTextSafety.removingDisplayHazards(from: clip.text), used: clip.id)
        case .change(let change): .applyAndRedraw(change)
        case .copyOnly(let clip, let why) where clip.kind == .secret && clip.image == nil:
            .copyConcealedAndSay(clip.text, why.notice, used: clip.id)
        case .copyOnly(let clip, let why):
            clip.image == nil
                ? .copyAndSay(clip.text, why.notice, used: clip.id) : .copyImageAndSay(clip, why.notice)
        case .copyOnlyCleaned(let clip, let why) where clip.kind == .secret:
            .copyConcealedAndSay(
                ClipTextSafety.removingDisplayHazards(from: clip.text), why.notice, used: clip.id)
        case .copyOnlyCleaned(let clip, let why):
            .copyAndSay(
                ClipTextSafety.removingDisplayHazards(from: clip.text), why.notice, used: clip.id)
        case .copy(let clip) where clip.kind == .secret && clip.image == nil:
            .closeAndCopyConcealed(clip.text, used: clip.id)
        case .copy(let clip):
            clip.image == nil
                ? .closeAndCopy(clip.text, richText: clip.richText, used: clip.id) : .closeAndCopyImage(clip)
        case .insertImage(let clip): .closeAndInsertImage(clip)
        case .pictureMissing:
            .say(
                PanelNotice(
                    symbolName: "photo.badge.exclamationmark",
                    message: "That picture is no longer on this Mac"))
        }
    }
}
