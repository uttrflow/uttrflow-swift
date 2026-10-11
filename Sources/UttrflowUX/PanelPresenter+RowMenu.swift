// The row menu's presentation. See `Docs/panel.md`.
import Foundation
import UttrflowClipboard

extension PanelPresenter {
    /// Insert first because it is what the row is for, then reveal, and pinning last.
    static func actions(
        for clip: Clip, isMasked: Bool, in snapshot: PanelSnapshot
    )
        -> [PanelAction]
    {
        var actions = [
            PanelAction(title: "Insert", symbolName: "arrow.down.doc", intent: .insert(clip.id))
        ]
        if clip.image == nil, clip.files == nil, ClipTextSafety.containsDisplayHazards(clip.text) {
            actions.append(
                PanelAction(
                    title: "Paste cleaned", symbolName: "text.badge.minus",
                    intent: .insertCleaned(clip.id)))
        }
        if isMasked {
            actions.append(
                PanelAction(
                    title: "Reveal", symbolName: "eye", intent: .reveal(clip.id),
                    shortcut: PanelRowAction.reveal.chord))
        }
        actions.append(
            PanelAction(
                title: "Copy", symbolName: "doc.on.doc", intent: .copy(clip.id),
                shortcut: PanelRowAction.copy.chord))
        actions.append(
            clip.isPinned
                ? PanelAction(
                    title: "Unpin", symbolName: "pin.slash", intent: .unpin(clip.id),
                    shortcut: PanelRowAction.pin.chord)
                : PanelAction(
                    title: "Pin", symbolName: "pin", intent: .pin(clip.id),
                    shortcut: PanelRowAction.pin.chord))
        // Rename when there is a name, or the user expects a second alias.
        actions.append(
            PanelAction(
                title: clip.alias == nil ? "Name" : "Rename", symbolName: "tag",
                intent: .alias(clip.id), shortcut: PanelRowAction.alias.chord))
        actions.append(
            PanelAction(
                title: "Move", symbolName: "folder", intent: .move(clip.id),
                shortcut: PanelRowAction.move.chord))
        if snapshot.isEditable(clip) {
            actions.append(
                PanelAction(
                    title: "Edit", symbolName: "pencil", intent: .edit(clip.id),
                    shortcut: PanelRowAction.edit.chord))
        }
        // D4, D5 — offered only where it would do something and a formatter exists.
        if let language = clip.language, snapshot.formattableLanguages.contains(language) {
            actions.append(
                PanelAction(
                    title: "Format", symbolName: "wand.and.stars", intent: .format(clip.id),
                    shortcut: PanelRowAction.format.chord))
        }
        if PanelCache.current.reindentOffers.offers(clip) {
            actions.append(
                PanelAction(
                    title: "Re-indent", symbolName: "text.alignleft",
                    intent: .reindent(clip.id), shortcut: PanelRowAction.reindent.chord))
        }
        // E6 — never on a note already, or promoting replaces what the user wrote, and never on a picture, which has no text.
        if clip.richText == nil, clip.image == nil, clip.files == nil {
            actions.append(
                PanelAction(
                    title: "Make a note", symbolName: "square.and.pencil",
                    intent: .makeNote(clip.id), shortcut: PanelRowAction.makeNote.chord))
        }
        // The user's answer outranks the detector's guess, in either direction; a picture has no text to judge.
        if clip.kind == .secret {
            actions.append(
                PanelAction(
                    title: "This is not a secret", symbolName: "lock.open", intent: .markNotSecret(clip.id),
                    shortcut: PanelRowAction.secrecy.chord))
        } else if clip.image == nil, clip.files == nil {
            actions.append(
                PanelAction(
                    title: "Treat as secret", symbolName: "lock", intent: .markSecret(clip.id),
                    shortcut: PanelRowAction.secrecy.chord))
        }
        // Last, and the only one that repeating does not undo.
        actions.append(
            PanelAction(
                title: "Delete", symbolName: "trash", intent: .delete(clip.id),
                isDestructive: true, shortcut: PanelRowAction.delete.chord))
        return actions
    }

    /// What the ⋯ menu says under the clip's words: kind, age and source, where each exists.
    static func detail(of clip: Clip, when: String) -> String {
        var parts = [noun(for: clip.kind).capitalized, when]
        if let from = clip.source?.trimmingCharacters(in: .whitespaces), !from.isEmpty {
            parts.append(from)
        }
        return parts.joined(separator: " · ")
    }

    /// The kind, as somebody would say it out loud.
    static func noun(for kind: ClipKind) -> String {
        switch kind {
        case .text: "text"
        case .link: "link"
        case .code: "code"
        case .secret: "secret"
        case .colour: "colour"
        case .image: "image"
        case .filePath: "file path"
        case .file: "file"
        }
    }
}
