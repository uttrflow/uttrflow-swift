public import UttrflowClipboard

/// Something only the store can carry out.
///
/// Kept as a value rather than done where it is decided, for the reason the whole panel
/// is built this way: the store is an actor and the panel is a pure function of its
/// state, so the decision and the write happen in different places and only the decision
/// is testable. Naming the write makes it testable too.
public enum PanelChange: Sendable, Equatable {
    /// `nil` removes the alias, which can make a clip unkept again — that is the user
    /// saying they no longer need it, and the store applies the retention window from
    /// that moment.
    case setAlias(Clip.ID, String?)
    /// `nil` takes it out of every collection without deleting it.
    case setCategory(Clip.ID, String?)
    case delete(Clip.ID)
    /// H3 — keep what was searched for as a clip, because a search that found nothing is
    /// often somebody discovering they never copied the thing they meant to.
    case create(String)
    /// D4, D6 — the same clip with its text replaced by something the user agreed to.
    ///
    /// One case for both, because the store does the same thing either way and the
    /// difference — whether a re-indenter or a formatter produced it — is already settled
    /// by the time this is made. Both have passed the same guard.
    case rewriteText(Clip.ID, String)
    /// E5, E6 — the note form of a clip, replaced. Ticking a box and promoting a plain
    /// clip are the same write: both leave ``Clip/text`` alone and change only the rich
    /// form, which is what keeps the original recoverable.
    case setRichText(Clip.ID, String)
    /// G5 — a collection renamed. Every clip in it moves with the name; nothing else
    /// about them changes, and in particular no alias is touched.
    case renameCategory(from: String, to: String)
    /// G6 — a collection removed, and where its clips went.
    ///
    /// The destination is part of the change rather than a separate step, because a
    /// collection deleted without deciding is a set of clips orphaned silently.
    /// `nil` means they keep no collection; a name means they are filed there instead.
    case deleteCategory(String, movingClipsTo: String?)
    /// G6 — the other answer: the clips go with it.
    case deleteCategoryAndClips(String)
    /// F9 — puts back a deleted clip with its alias and its category, which is why it
    /// carries the whole clip rather than an identity. The identity is gone by then.
    case restore(Clip)
}

/// What the panel has put on top of the list.
///
/// One at a time, and never more: these all ask for a single answer about a single clip,
/// and a panel that could stack them would be a panel where `esc` has no obvious meaning.
public enum PanelSheet: Sendable, Equatable {
    /// F1, F2 — naming a clip. `draft` is what has been typed, uncorrected, because the
    /// field must show what the user is typing and not fight them character by character.
    case aliasing(Clip.ID, draft: String)
    /// G1, G2 — filing a clip. `draft` is a new collection being named, and empty while
    /// the user is merely choosing among the ones that exist.
    case moving(Clip.ID, draft: String)
    /// F8 — asked only for a clip whose loss is not cheap.
    case confirmingDelete(Clip.ID)
    /// G5 — renaming a collection. `draft` is the new name as typed.
    case renamingCategory(String, draft: String)
    /// G6 — deleting a collection that holds clips, and choosing what happens to them.
    case deletingCategory(String, keepingClips: Bool)
    /// D6 — a formatter has produced something, and the user has not agreed to it yet.
    /// The result is carried on the sheet rather than reapplied on accept: running the
    /// formatter twice could produce a different answer, and the user agreed to *this* one.
    case formatting(Clip.ID, formatted: String)

    /// The clip this sheet is about, where it is about one.
    ///
    /// Optional because two of them are not: renaming and deleting a collection are about
    /// the collection. Answering with an invented identity would keep the type total and
    /// make every caller's `contains` quietly false.
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
        case .formatting: nil
        case .aliasing, .moving, .confirmingDelete: nil
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
    ///
    /// Deleting is the one that branches, and F7 and F8 disagree on purpose. An ordinary
    /// clip goes immediately with an undo, because a confirmation for something the user
    /// can reverse in a second is a dialog that teaches people to dismiss dialogs. A
    /// pinned or aliased clip asks first: the alias is muscle memory, the undo window is
    /// only a few seconds, and losing it silently costs more than the click.
    func opening(_ sheet: PanelSheet) -> PanelResponse {
        var next = self
        next.sheet = sheet
        return PanelResponse(state: next, outcome: .open)
    }

    /// F7, F8 — delete, with or without asking.
    func deleting(_ id: Clip.ID) -> PanelResponse {
        guard let clip = clips.first(where: { $0.id == id }) else {
            return PanelResponse(state: self, outcome: .open)
        }
        guard !clip.isKept else { return opening(.confirmingDelete(id)) }
        return PanelResponse(state: closingSheet(), outcome: .change(.delete(id)))
    }

    /// Commits whatever the open sheet was asking for.
    ///
    /// Answers `.open` rather than a change when there is nothing to commit — an empty
    /// alias, a taken one, no collection chosen — so that Return on an unfinished sheet
    /// leaves it open with the reason on screen instead of quietly doing nothing.
    func committingSheet() -> PanelResponse {
        switch sheet {
        case .none:
            return PanelResponse(state: self, outcome: .open)

        case .aliasing(let id, let draft):
            let proposal = PanelAlias.propose(draft, for: id, among: clips, locale: locale)
            // An emptied field is how an alias is removed, and is always allowed.
            if proposal.corrected.isEmpty {
                return PanelResponse(state: closingSheet(), outcome: .change(.setAlias(id, nil)))
            }
            guard proposal.isUsable else { return PanelResponse(state: self, outcome: .open) }
            return PanelResponse(
                state: closingSheet(), outcome: .change(.setAlias(id, proposal.corrected)))

        case .moving(let id, let draft):
            let named = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !named.isEmpty else { return PanelResponse(state: self, outcome: .open) }
            // G3 — a name that already exists files the clip there rather than making a
            // second collection with the same name, which nobody could tell apart.
            let existing = categories.first { $0.caseInsensitiveCompare(named) == .orderedSame }
            return PanelResponse(
                state: closingSheet(), outcome: .change(.setCategory(id, existing ?? named)))

        case .confirmingDelete(let id):
            return PanelResponse(state: closingSheet(), outcome: .change(.delete(id)))

        case .formatting(let id, let formatted):
            return PanelResponse(
                state: closingSheet(), outcome: .change(.rewriteText(id, formatted)))

        case .renamingCategory(let name, let draft):
            let renamed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !renamed.isEmpty, renamed != name else {
                return PanelResponse(state: self, outcome: .open)
            }
            // Renaming onto a name that already exists is a merge, and merging is not
            // what the user asked for. They are told, and nothing happens until they
            // choose a different word.
            guard
                !categories.contains(where: {
                    $0 != name && $0.caseInsensitiveCompare(renamed) == .orderedSame
                })
            else {
                return PanelResponse(state: self, outcome: .open)
            }
            var next = closingSheet()
            // Followed here as well as in the store, so the chips and the open tab do not
            // flicker through the old name while the write is in flight.
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

    /// Types into the open sheet. Ignored when there is none, so a stray keystroke
    /// between closing a sheet and the view noticing cannot resurrect it.
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

    /// D4 — tidy a code clip, or do nothing if there is nothing safe to do.
    ///
    /// The check runs again here rather than trusting the action's presence. A clip can
    /// change between the row being drawn and the button being pressed — the store
    /// reloads, the clip is edited — and re-indenting is one of the few things here that
    /// rewrites a clip's own text, so it asks the question at the moment it acts.
    func reindenting(_ id: Clip.ID) -> PanelResponse {
        guard let clip = clips.first(where: { $0.id == id }),
            let tidied = CodeReindent.reindented(clip.text)
        else { return PanelResponse(state: self, outcome: .open) }
        return PanelResponse(state: self, outcome: .change(.rewriteText(id, tidied)))
    }

    /// E6 — give a plain clip a rich form so it can be formatted.
    ///
    /// Refuses a clip that already has one: promoting twice would replace a note the user
    /// has written with a fresh copy of its own plain text, which is the one way this
    /// action could destroy something.
    func promoting(_ id: Clip.ID) -> PanelResponse {
        guard let clip = clips.first(where: { $0.id == id }), clip.richText == nil else {
            return PanelResponse(state: self, outcome: .open)
        }
        return PanelResponse(
            state: self, outcome: .change(.setRichText(id, NotePromotion.note(from: clip.text))))
    }

    /// E5 — tick or untick one box, and write it.
    func ticking(_ id: Clip.ID, box index: Int) -> PanelResponse {
        guard let clip = clips.first(where: { $0.id == id }), let note = clip.richText,
            let ticked = NoteChecklist.toggling(index, in: note)
        else { return PanelResponse(state: self, outcome: .open) }
        return PanelResponse(state: self, outcome: .change(.setRichText(id, ticked)))
    }

    /// What the alias field opens showing.
    ///
    /// The clip's current alias, so that naming and renaming are the same gesture and an
    /// existing name can be adjusted rather than retyped. Empty for a clip that has none.
    func aliasDraft(for id: Clip.ID) -> String {
        clips.first { $0.id == id }?.alias ?? ""
    }

    func closingSheet() -> PanelSnapshot {
        var next = self
        next.sheet = nil
        return next
    }
}
