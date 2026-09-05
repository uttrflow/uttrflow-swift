// What a panel keystroke asks the store to do, and the sheets that ask the user first.
public import UttrflowClipboard

/// Something only the store can carry out, named as a value so the decision is testable without the actor.
public enum PanelChange: Sendable, Equatable {
    /// `nil` removes the alias, which can make a clip unkept again, and retention runs from that moment.
    case setAlias(Clip.ID, String?)
    /// `nil` takes it out of every collection without deleting it.
    case setCategory(Clip.ID, String?)
    /// Removes a clip; the app keeps it for an undo.
    case delete(Clip.ID)
    /// Keep what was searched for as a clip; a search that finds nothing often means the thing never got copied.
    case create(String)
    /// The clip with its text replaced by something the user agreed to, from a re-indenter or formatter.
    case rewriteText(Clip.ID, String)
    /// The note form of a clip, replaced; ``Clip/text`` is left alone, which keeps the original recoverable.
    case setRichText(Clip.ID, String)
    /// A collection renamed; every clip in it moves with the name and no alias is touched.
    case renameCategory(from: String, to: String)
    /// A collection removed; `nil` means its clips keep no collection, a name files them there instead.
    case deleteCategory(String, movingClipsTo: String?)
    /// G6 — the other answer: the clips go with it.
    case deleteCategoryAndClips(String)
    /// Puts back a deleted clip with its alias and category; the whole clip, since its identity is gone.
    case restore(Clip)
}

/// What the panel has put on top of the list, one at a time so `esc` always has one meaning.
public enum PanelSheet: Sendable, Equatable {
    /// Naming a clip; `draft` is what has been typed, uncorrected, so the field never fights the user.
    case aliasing(Clip.ID, draft: String)
    /// Filing a clip; `draft` is a new collection being named, empty while choosing an existing one.
    case moving(Clip.ID, draft: String)
    /// F8 — asked only for a clip whose loss is not cheap.
    case confirmingDelete(Clip.ID)
    /// G5 — renaming a collection. `draft` is the new name as typed.
    case renamingCategory(String, draft: String)
    /// G6 — deleting a collection that holds clips, and choosing what happens to them.
    case deletingCategory(String, keepingClips: Bool)
    /// A formatter's result awaiting agreement, carried here because a second run could differ.
    case formatting(Clip.ID, formatted: String)

    /// The clip this sheet is about; `nil` for the two sheets that are about a collection.
    public var clip: Clip.ID? {
        switch self {
        case .aliasing(let id, _), .moving(let id, _), .confirmingDelete(let id),
            .formatting(let id, _):
            id
        case .renamingCategory, .deletingCategory: nil
        }
    }

    /// The collection this sheet is about, where it is about one.
    public var category: String? {
        switch self {
        case .renamingCategory(let name, _), .deletingCategory(let name, _): name
        case .aliasing, .moving, .confirmingDelete, .formatting: nil
        }
    }

    /// What has been typed into the sheet, where the sheet takes typing at all.
    public var draft: String {
        switch self {
        case .aliasing(_, let draft), .moving(_, let draft), .renamingCategory(_, let draft):
            draft
        case .confirmingDelete, .deletingCategory, .formatting: ""
        }
    }
}

extension PanelSnapshot {
    /// Opens the sheet a row action asks for.
    func opening(_ sheet: PanelSheet) -> PanelResponse {
        var next = self
        next.sheet = sheet
        return PanelResponse(state: next, outcome: .open)
    }

    /// F7, F8 — delete, with or without asking.
    func deleting(_ id: Clip.ID) -> PanelResponse {
        guard let clip = clip(id) else { return stayingOpen }
        guard !clip.isKept else { return opening(.confirmingDelete(id)) }
        return PanelResponse(state: closingSheet(), outcome: .change(.delete(id)))
    }

    /// Commits the open sheet; with nothing to commit it stays open so the reason is still on screen.
    func committingSheet() -> PanelResponse {
        switch sheet {
        case .none:
            return stayingOpen

        case .aliasing(let id, let draft):
            let proposal = PanelAlias.propose(draft, for: id, among: clips, locale: locale)
            // An emptied field is how an alias is removed, and is always allowed.
            if proposal.corrected.isEmpty {
                return PanelResponse(state: closingSheet(), outcome: .change(.setAlias(id, nil)))
            }
            guard proposal.isUsable else { return stayingOpen }
            return PanelResponse(
                state: closingSheet(), outcome: .change(.setAlias(id, proposal.corrected)))

        case .moving(let id, let draft):
            let named = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !named.isEmpty else { return stayingOpen }
            // A name that already exists files the clip there rather than making a twin collection.
            let existing = existingCategory(named: named)
            return PanelResponse(
                state: closingSheet(), outcome: .change(.setCategory(id, existing ?? named)))

        case .confirmingDelete(let id):
            return PanelResponse(state: closingSheet(), outcome: .change(.delete(id)))

        case .formatting(let id, let formatted):
            return PanelResponse(
                state: closingSheet(), outcome: .change(.rewriteText(id, formatted)))

        case .renamingCategory(let name, let draft):
            let renamed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !renamed.isEmpty, renamed != name else { return stayingOpen }
            // Renaming onto an existing name would be a merge, which nobody asked for; nothing happens.
            guard existingCategory(named: renamed, besides: name) == nil else { return stayingOpen }
            var next = closingSheet()
            // Followed here as well as in the store, so the chips do not flicker through the old name.
            if next.category == name { next.category = renamed }
            return PanelResponse(
                state: next, outcome: .change(.renameCategory(from: name, to: renamed)))

        case .deletingCategory(let name, let keepingClips):
            var next = closingSheet()
            // The tab being deleted cannot stay open over a collection that is gone.
            if next.category == name { next.category = nil }
            return PanelResponse(
                state: next,
                outcome: .change(
                    keepingClips
                        ? .deleteCategory(name, movingClipsTo: nil)
                        : .deleteCategoryAndClips(name)))
        }
    }

    /// Types into the open sheet; ignored when there is none, so a stray keystroke cannot resurrect it.
    func drafting(_ text: String) -> PanelSnapshot {
        var next = self
        switch sheet {
        case .aliasing(let id, _): next.sheet = .aliasing(id, draft: text)
        case .moving(let id, _): next.sheet = .moving(id, draft: text)
        case .renamingCategory(let name, _): next.sheet = .renamingCategory(name, draft: text)
        case .confirmingDelete, .deletingCategory, .formatting, .none: return self
        }
        return next
    }

    /// Tidies a code clip, checking again at the moment it acts because the clip may have changed.
    func reindenting(_ id: Clip.ID) -> PanelResponse {
        guard let clip = clip(id), let tidied = CodeReindent.reindented(clip.text) else {
            return stayingOpen
        }
        return PanelResponse(state: self, outcome: .change(.rewriteText(id, tidied)))
    }

    /// Gives a plain clip a rich form; refuses one that has it, so a written note is never overwritten.
    func promoting(_ id: Clip.ID) -> PanelResponse {
        guard let clip = clip(id), clip.richText == nil else { return stayingOpen }
        return PanelResponse(
            state: self, outcome: .change(.setRichText(id, NotePromotion.note(from: clip.text))))
    }

    /// E5 — tick or untick one box, and write it.
    func ticking(_ id: Clip.ID, box index: Int) -> PanelResponse {
        guard let note = clip(id)?.richText, let ticked = NoteChecklist.toggling(index, in: note)
        else { return stayingOpen }
        return PanelResponse(state: self, outcome: .change(.setRichText(id, ticked)))
    }

    /// What the alias field opens showing: the clip's current alias, so renaming is the same gesture.
    func aliasDraft(for id: Clip.ID) -> String {
        clip(id)?.alias ?? ""
    }

    /// The panel with no sheet over it.
    func closingSheet() -> PanelSnapshot {
        var next = self
        next.sheet = nil
        return next
    }
}
