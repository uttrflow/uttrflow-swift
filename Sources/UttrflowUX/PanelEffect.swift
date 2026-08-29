// A `public import` now: ``PanelEffect/closeAndInsertImage(_:)`` carries a whole clip,
// because the bytes of a picture are a file only the store can open and this module has no
// business opening files. Text still travels as text — that is why the plain case carries
// a `String` and not a clip.
public import UttrflowClipboard

/// What the app has to do about a keystroke the panel has already answered.
///
/// Split out from the wiring on purpose. `AppDelegate` is excluded from the coverage
/// gate on the grounds that it holds no decisions — "wiring only; every decision it
/// relays is tested elsewhere" — so the two decisions below have to live somewhere a
/// test can reach, or they would ship unexamined in the one file nothing checks.
public enum PanelEffect: Sendable, Equatable {
    /// Still open. Draw the new state and wait for the next key.
    case redraw
    /// Put the panel away, having changed nothing.
    case close
    /// Carry this out in the store, then draw the panel again from what comes back.
    ///
    /// The panel deliberately stays up. Filing or naming a clip is rarely the only thing
    /// somebody opened it to do, and a panel that dismissed itself after each one would
    /// have to be summoned again for the next.
    case applyAndRedraw(PanelChange)
    /// Put the panel away, then put this exact text where the caret is.
    ///
    /// Carries the text rather than the clip because the caller's next move is to hand
    /// it to `TextInserting`, and a caller holding a whole clip is a caller that can
    /// reach for the wrong field of it.
    ///
    /// `used` is the identity of the clip this text came from, and it is here because
    /// *which clip the user chose* is a decision this module made and the app should not
    /// have to work out again. It is an identifier rather than the clip for the same
    /// reason the text is a string: nothing downstream can paste an id by mistake.
    ///
    /// Eviction ranks by ``Clip/lastUsedAt``, so a paste that does not report which clip
    /// it pasted leaves that clock stopped — and least-recently-used quietly degrades
    /// into least-recently-*copied*, which is the rule it was introduced to replace.
    case closeAndInsert(String, used: Clip.ID)
    /// E2 — the same, carrying the formatted form so the receiving application can take
    /// whichever it understands.
    case closeAndInsertFormatted(String, richText: String, used: Clip.ID)
    /// B3–B5 — put it on the clipboard, say so on the panel, and close a moment later so
    /// the sentence can be read. Not `closeAndInsert` with a different message: nothing
    /// is being inserted, and calling it insertion is how "it did nothing" gets reported
    /// as a success.
    case copyAndSay(String, PanelNotice, used: Clip.ID)
    /// K4 — put the picture where the caret is. Carries the clip because the bytes are a
    /// file only the store can open, and this module has no business opening files.
    case closeAndInsertImage(Clip)
    /// B8 — say the picture has gone, and leave the panel up so the row can be seen.
    case say(PanelNotice)
}

extension PanelOutcome {
    /// The two decisions this type exists to hold.
    ///
    /// **Inserting closes the panel.** The product is three keystrokes — open, arrow,
    /// Return — and a panel still on screen after the third is a fourth. It also sits
    /// over the very application the text has just been put into, hiding the thing the
    /// user needs to see to know it worked.
    ///
    /// **What is inserted is `text`, never what the row drew.** A row shows one line and
    /// masks a secret; both are presentation, and both are wrong to paste. Reaching for
    /// the drawn string truncates a multi-line clip to its first line, or pastes a row
    /// of bullets where a token should be — silently in each case, because a paste that
    /// succeeds with the wrong string reports success.
    public var effect: PanelEffect {
        switch self {
        case .open: .redraw
        case .dismissed: .close
        case .insert(let clip):
            // B6 — plain is what a clip without a rich form has always been, and what
            // ⌘-Return asks for on one that has. The modifier is stripped before it gets
            // here: the panel decided, and this only reports.
            clip.richText.map {
                .closeAndInsertFormatted(clip.text, richText: $0, used: clip.id)
            } ?? .closeAndInsert(clip.text, used: clip.id)
        case .insertPlain(let clip): .closeAndInsert(clip.text, used: clip.id)
        case .change(let change): .applyAndRedraw(change)
        case .copyOnly(let clip, let why): .copyAndSay(clip.text, why.notice, used: clip.id)
        case .insertImage(let clip): .closeAndInsertImage(clip)
        case .pictureMissing:
            .say(
                PanelNotice(
                    symbolName: "photo.badge.exclamationmark",
                    message: "That picture is no longer on this Mac"))
        }
    }
}
