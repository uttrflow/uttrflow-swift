public import UttrflowClipboard

/// Everything the panel can be told.
///
/// One vocabulary for the keyboard and the mouse, deliberately. A click on a row has to
/// be indistinguishable from Return on it, and two doors into the same state is exactly
/// how two behaviours that were meant to be one come to differ.
public enum PanelKey: Sendable, Equatable {
    case down
    case up
    /// The whole contents of the search field after the keystroke, not the character
    /// that was typed. The field belongs to the platform — it has its own selection,
    /// its own deletion, its own dictation — and the only thing this model can know
    /// about it without reimplementing all of that is what it now says.
    case search(String)
    case filter(PanelFilter)
    /// The bottom bar: which slice of the clipboard is being browsed.
    case scope(PanelScope)
    /// ⌘1…⌘9, as the number is printed beside the chip.
    case category(number: Int)
    case `return`
    case escape
    /// A row was clicked, or its Insert was chosen from the row's own actions.
    case choose(Clip.ID)
    /// Show what a masked clip actually says.
    case reveal(Clip.ID)
    /// Name a clip, or rename it.
    case alias(Clip.ID)
    /// File a clip into a collection.
    case move(Clip.ID)
    /// F7, F8 — immediately for an ordinary clip, after asking for a kept one.
    case delete(Clip.ID)
    /// Typing into whatever sheet is open. Distinct from ``search(_:)`` because the two
    /// fields are never both taking keys, and one case for both would make which field a
    /// keystroke reached depend on state the key itself does not carry.
    case draft(String)
    /// G5, G6 — the two things that can be done to a collection rather than to a clip.
    case renameCategory(String)
    case deleteCategory(String)
    /// D4 — tidy a code clip's indentation.
    case reindent(Clip.ID)
    /// E6 — promote a plain clip to a note.
    case makeNote(Clip.ID)
    /// E5 — tick or untick the nth box of a note.
    case tickBox(Clip.ID, index: Int)
    /// B6 — Return or a click with ⌘ held.
    case choosePlain(Clip.ID)
    case returnPlain
}

/// What a keystroke did, beyond changing what is on screen.
public enum PanelOutcome: Sendable, Equatable {
    /// Still open. Redraw, and wait for the next key.
    case open
    /// Chosen: this goes back into whatever the user was typing in, and the panel closes.
    ///
    /// Carries the whole clip rather than its identity, because the app is about to
    /// insert it into another application and asking the store a second question — after
    /// the panel has gone — is a chance to get a different answer.
    case insert(Clip)
    /// The store must carry this out. The panel stays open: filing or naming a clip is
    /// rarely the only thing somebody came to do.
    case change(PanelChange)
    /// B3–B5 — the clip goes to the clipboard, and the panel says why it could not be
    /// placed. Never silent: a panel that closes having done nothing is the one outcome
    /// the specification forbids outright.
    case copyOnly(Clip, PanelInsertionObstacle)
    /// B6 — chosen with ⌘ held: the words, and none of the formatting.
    ///
    /// A real choice rather than a mode, because for a note or a formatted snippet the
    /// user knows which of the two they want and the app cannot.
    case insertPlain(Clip)
    /// K4 — a picture goes to the caret as a picture, which is a different write from a
    /// string and cannot travel as one.
    case insertImage(Clip)
    /// B8 — the picture this clip was is no longer on disk, so there is nothing to paste.
    case pictureMissing(Clip)
    /// Closed with nothing chosen. Whatever the user was doing is untouched.
    case dismissed
}

/// The panel after a keystroke, and what the app must do about it.
public struct PanelResponse: Sendable, Equatable {
    public let state: PanelSnapshot
    public let outcome: PanelOutcome

    public init(state: PanelSnapshot, outcome: PanelOutcome) {
        self.state = state
        self.outcome = outcome
    }
}

extension PanelSnapshot {
    /// One keystroke.
    ///
    /// Every key is a function from state to state, with nothing kept between calls. The
    /// panel opens over whatever the user is doing and closes a second later, and the
    /// only reason it can be trusted with that second is that the answer to "which clip
    /// does Return mean" is computed, not accumulated.
    public func applying(_ key: PanelKey) -> PanelResponse {
        switch key {
        case .down: PanelResponse(state: moving(by: 1), outcome: .open)
        case .up: PanelResponse(state: moving(by: -1), outcome: .open)
        case .search(let text): PanelResponse(state: listing { $0.query = text }, outcome: .open)
        // One chip at a time across the whole row.
        //
        // A kind and a collection are different questions, and combining them answers a
        // real one — "the pictures in db". But they share a row now, and a row of chips
        // reads as one set whatever divider is drawn in it: two of them lit looked like
        // a bug every time somebody saw it. Choosing either clears the other, so what is
        // on screen and what the list is doing are the same thing.
        case .filter(let filter):
            PanelResponse(
                state: listing {
                    $0.filter = filter; $0.category = nil
                }, outcome: .open)
        case .scope(let scope): PanelResponse(state: listing { $0.scope = scope }, outcome: .open)
        case .category(let number): PanelResponse(state: jumping(to: number), outcome: .open)
        // Return belongs to the sheet while one is open. Inserting a clip from behind a
        // half-typed alias would be a paste the user did not ask for.
        case .return: sheet == nil ? resolving(results.selected) : committingSheet()
        // One meaning, always. A two-stage escape — clear the search, then close — makes
        // the user look at the screen to find out what the key will do, which costs more
        // than the occasional second press it saves.
        // A sheet takes `esc` before the panel does. Closing the whole panel because
        // somebody backed out of naming a clip would throw away the list they were
        // working through, and there is no way back to where they were.
        case .escape:
            sheet == nil
                ? PanelResponse(state: self, outcome: .dismissed)
                : PanelResponse(state: closingSheet(), outcome: .open)
        case .choose(let id): choosing(id)
        case .reveal(let id): PanelResponse(state: revealing(id), outcome: .open)
        case .alias(let id): opening(.aliasing(id, draft: aliasDraft(for: id)))
        case .move(let id): opening(.moving(id, draft: ""))
        case .delete(let id): deleting(id)
        case .draft(let text): PanelResponse(state: drafting(text), outcome: .open)
        case .renameCategory(let name): opening(.renamingCategory(name, draft: name))
        // Opens keeping the clips, because that is the answer that loses nothing and the
        // destructive one should never be the preselected default.
        case .deleteCategory(let name): opening(.deletingCategory(name, keepingClips: true))
        case .reindent(let id): reindenting(id)
        case .makeNote(let id): promoting(id)
        case .tickBox(let id, let index): ticking(id, box: index)
        case .returnPlain: sheet == nil ? resolvingPlain(results.selected) : committingSheet()
        case .choosePlain(let id): choosingPlain(id)
        }
    }

    /// A run of keystrokes, answering what the last one did.
    ///
    /// The product is a sequence — open, ↓, ↓, Return — and a model that can only be
    /// asked about one key at a time is a model whose tests describe the gesture in prose
    /// instead of making it. Keys after one that closed the panel are not applied: the
    /// panel is gone, and pretending otherwise would let a test assert something no user
    /// could do.
    public func applying(_ keys: [PanelKey]) -> PanelResponse {
        var response = PanelResponse(state: self, outcome: .open)
        for key in keys {
            guard response.outcome == .open else { return response }
            response = response.state.applying(key)
        }
        return response
    }

    // MARK: - Moving

    /// ↓ and ↑, which stop at the ends rather than wrapping round.
    ///
    /// This is a list somebody is stabbing at. Wrapping means that holding ↓ one beat too
    /// long silently teleports the highlight from the bottom of the list to the top, and
    /// the next Return inserts the newest clip instead of the oldest one being aimed at —
    /// a wrong paste into somebody else's document, with no travel on screen to warn that
    /// it happened. Stopping is self-correcting: an overshoot leaves the user exactly
    /// where they already were, which is where they were trying to get to. Wrapping only
    /// ever helps in a list long enough that the user should have typed instead.
    func moving(by rows: Int) -> PanelSnapshot {
        let visible = results
        guard let current = visible.selectedIndex else { return self }
        var next = self
        next.selection = visible.rows[min(max(current + rows, 0), visible.rows.count - 1)].id
        return next
    }

    /// ⌘1 is All, and the categories run from ⌘2.
    ///
    /// The way out of a category needs a key of its own, or somebody who pressed ⌘3 has
    /// to reach for the mouse to see everything again — and ``PanelKey/escape`` is not
    /// that key, because it means "close this" and must not also mean "undo the last
    /// thing I pressed". A number nothing is filed under does nothing at all: a jump that
    /// silently landed somewhere else would be worse than a jump that missed.
    func jumping(to number: Int) -> PanelSnapshot {
        let names = categories
        // Not capped at the shortcut limit. That limit is about which numbers are
        // *printed* — there is no ⌘10 — and capping the jump too meant a collection past
        // the ninth could not be chosen by any means, including the mouse.
        guard number >= 1, number <= names.count + 1 else { return self }
        return listing {
            $0.category = number == 1 ? nil : names[number - 2]
            // The other half of the one-chip-at-a-time rule; see `.filter` above.
            // Command-1 means everything, so it clears the kind as well as the
            // collection — otherwise "show me everything" would leave a filter on.
            $0.filter = .all
        }
    }

    /// A change to *what is listed*, which always puts the selection back at the top.
    ///
    /// The rule that makes the panel predictable, and it is one rule: when the user
    /// changes the list, the selection goes to the top; when the world changes the list —
    /// something copied while the panel is open — the selection stays on the clip it was
    /// on, because it is held by identity. So narrowing a search can never leave the
    /// highlight on a row that has scrolled out of the results, and typing an alias in
    /// full always leaves Return pointing at the clip that alias names.
    func listing(_ change: (inout PanelSnapshot) -> Void) -> PanelSnapshot {
        var next = self
        change(&next)
        next.selection = nil
        return next
    }

    // MARK: - Choosing

    /// Return, and a click, which are the same thing said two ways.
    ///
    /// Nothing selected means an empty list, and the panel stays open: the user has typed
    /// a search that matches nothing, and closing would throw away what they typed along
    /// with the panel.
    func resolving(_ clip: Clip?) -> PanelResponse {
        guard let clip else { return PanelResponse(state: self, outcome: .open) }
        // Decided here rather than after the fact. Once the panel has closed there is
        // nowhere left to say that the words only reached the clipboard, and B3–B5 all
        // turn on the user being told which of the three happened.
        // B8 — refused before the obstacle check, because "there is nothing to paste" is a
        // different answer from "it could not be placed", and the second would send the
        // user to press ⌘V for something that is not on the clipboard either.
        if clip.image != nil, missingImages.contains(clip.id) {
            return PanelResponse(state: self, outcome: .pictureMissing(clip))
        }
        switch insertion {
        case .atCaret:
            return PanelResponse(
                state: self, outcome: clip.image != nil ? .insertImage(clip) : .insert(clip))
        case .clipboardOnly(let obstacle):
            return PanelResponse(state: self, outcome: .copyOnly(clip, obstacle))
        }
    }

    /// B6 — the same resolution, with the formatting deliberately left behind.
    ///
    /// It goes through the same obstacle check as the ordinary one, so ⌘-Return on a
    /// machine that cannot place text still copies and still says so. Only the formatting
    /// differs; everything about *whether it lands* is the same question.
    func resolvingPlain(_ clip: Clip?) -> PanelResponse {
        guard let clip else { return PanelResponse(state: self, outcome: .open) }
        switch insertion {
        case .atCaret:
            return PanelResponse(state: self, outcome: .insertPlain(clip))
        case .clipboardOnly(let obstacle):
            return PanelResponse(state: self, outcome: .copyOnly(clip, obstacle))
        }
    }

    /// ⌘-click, which is ⌘-Return on the row under the pointer.
    func choosingPlain(_ id: Clip.ID) -> PanelResponse {
        guard let row = results.rows.first(where: { $0.id == id }) else {
            return PanelResponse(state: self, outcome: .open)
        }
        var next = self
        next.selection = id
        return next.resolvingPlain(row.clip)
    }

    /// A click on a row: it takes the selection and resolves, in that order, so that the
    /// state left behind agrees with what was inserted. A click on a row that is not in
    /// the list cannot come from the drawn panel, and is ignored rather than trusted.
    func choosing(_ id: Clip.ID) -> PanelResponse {
        guard let row = results.rows.first(where: { $0.id == id }) else {
            return PanelResponse(state: self, outcome: .open)
        }
        var next = self
        next.selection = id
        // Through `resolving`, not straight to `.insert`. Answering here was a second
        // implementation of what Return means, and it had already drifted: it reported an
        // insertion on a machine where nothing could be inserted, so a click with no caret
        // claimed to have placed text that only reached the clipboard. Keyboard and mouse
        // have one answer because they ask one function.
        return next.resolving(row.clip)
    }

    /// Unmasking is its own key rather than a side effect of arrowing onto a row: the
    /// panel is opened in meetings and on shared screens, and a secret that reveals
    /// itself as the highlight passes over it protects nobody.
    func revealing(_ id: Clip.ID) -> PanelSnapshot {
        var next = self
        next.revealed.insert(id)
        return next
    }
}
