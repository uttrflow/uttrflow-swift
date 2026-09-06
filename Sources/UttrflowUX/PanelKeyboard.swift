// The panel's keyboard: every key it accepts, what a key does, and moving and choosing.
public import UttrflowClipboard

/// Everything the panel can be told, one vocabulary for keyboard and mouse so a click and Return agree.
public enum PanelKey: Sendable, Equatable {
    /// Move the highlight down one row.
    case down
    /// Move the highlight up one row.
    case up
    /// The whole contents of the search field after the keystroke, since the field belongs to the platform.
    case search(String)
    /// The top tabs: which kind of clip is being browsed.
    case filter(PanelFilter)
    /// The bottom bar: which slice of the clipboard is being browsed.
    case scope(PanelScope)
    /// ⌘1…⌘9, as the number is printed beside the chip.
    case category(number: Int)
    /// Choose the highlighted clip, or commit the open sheet.
    case `return`
    /// Close the sheet, or the panel.
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
    /// Typing into the open sheet; distinct from ``search(_:)`` because the two fields never both take keys.
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
    /// ⌘-Return: choose the highlighted clip without its formatting.
    case returnPlain
}

/// What a keystroke did, beyond changing what is on screen.
public enum PanelOutcome: Sendable, Equatable {
    /// Still open. Redraw, and wait for the next key.
    case open
    /// Chosen: the whole clip goes back into whatever the user was typing in, and the panel closes.
    case insert(Clip)
    /// The store must carry this out; the panel stays open, since filing is rarely the only errand.
    case change(PanelChange)
    /// The clip goes to the clipboard and the panel says why it could not be placed; never silent.
    case copyOnly(Clip, PanelInsertionObstacle)
    /// Chosen with ⌘ held: the words and none of the formatting, a choice the user makes, not a mode.
    case insertPlain(Clip)
    /// A picture goes to the caret as a picture, which is a different write from a string.
    case insertImage(Clip)
    /// The picture this clip refers to is missing from disk, so there is nothing to paste.
    case pictureMissing(Clip)
    /// Closed with nothing chosen. Whatever the user was doing is untouched.
    case dismissed
}

/// The panel after a keystroke, and what the app must do about it.
public struct PanelResponse: Sendable, Equatable {
    /// The panel as it now stands.
    public let state: PanelSnapshot
    /// What the app must do about it.
    public let outcome: PanelOutcome

    /// Pairs a state with its outcome.
    public init(state: PanelSnapshot, outcome: PanelOutcome) {
        self.state = state
        self.outcome = outcome
    }
}

extension PanelSnapshot {
    /// This panel unchanged and still open, which is what a key that could not act answers.
    var stayingOpen: PanelResponse { PanelResponse(state: self, outcome: .open) }
}

extension PanelSnapshot {
    /// One keystroke, as a pure function of state, so which clip Return means is computed, not accumulated.
    public func applying(_ key: PanelKey) -> PanelResponse {
        switch key {
        case .down: PanelResponse(state: moving(by: 1), outcome: .open)
        case .up: PanelResponse(state: moving(by: -1), outcome: .open)
        case .search(let text): PanelResponse(state: listing { $0.query = text }, outcome: .open)
        // One chip at a time across the row: choosing a kind or a collection clears the other.
        case .filter(let filter):
            PanelResponse(
                state: listing {
                    $0.filter = filter; $0.category = nil
                }, outcome: .open)
        case .scope(let scope): PanelResponse(state: listing { $0.scope = scope }, outcome: .open)
        case .category(let number): PanelResponse(state: jumping(to: number), outcome: .open)
        // Return belongs to the sheet while one is open; nothing is pasted from behind an unfinished alias.
        case .return: sheet == nil ? resolving(results.selected) : committingSheet()
        // Escape has one meaning: a sheet takes it before the panel, and otherwise the panel closes.
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
        // Opens keeping the clips: the destructive answer is never the preselected default.
        case .deleteCategory(let name): opening(.deletingCategory(name, keepingClips: true))
        case .reindent(let id): reindenting(id)
        case .makeNote(let id): promoting(id)
        case .tickBox(let id, let index): ticking(id, box: index)
        case .returnPlain: sheet == nil ? resolvingPlain(results.selected) : committingSheet()
        case .choosePlain(let id): choosingPlain(id)
        }
    }

    /// A run of keystrokes answering what the last did; keys after one that closed the panel are dropped.
    public func applying(_ keys: [PanelKey]) -> PanelResponse {
        var response = PanelResponse(state: self, outcome: .open)
        for key in keys {
            guard response.outcome == .open else { return response }
            response = response.state.applying(key)
        }
        return response
    }

    // MARK: - Moving

    /// ↓ and ↑, which stop at the ends rather than wrapping, so an overshoot never pastes the wrong clip.
    func moving(by rows: Int) -> PanelSnapshot {
        let visible = results
        guard let current = visible.selectedIndex else { return self }
        var next = self
        next.selection = visible.rows[min(max(current + rows, 0), visible.rows.count - 1)].id
        return next
    }

    /// ⌘1 is All and the categories run from ⌘2; a number nothing is filed under does nothing.
    func jumping(to number: Int) -> PanelSnapshot {
        let names = categories
        // Not capped at the shortcut limit, which is only about which numbers are printed.
        guard number >= 1, number <= names.count + 1 else { return self }
        return listing {
            $0.category = number == 1 ? nil : names[number - 2]
            // ⌘1 means everything, so it clears the kind as well as the collection.
            $0.filter = .all
        }
    }

    /// A change to what is listed, which always puts the selection back at the top.
    func listing(_ change: (inout PanelSnapshot) -> Void) -> PanelSnapshot {
        var next = self
        change(&next)
        next.selection = nil
        return next
    }

    // MARK: - Choosing

    /// Return and a click; nothing selected means an empty list, and the panel stays open.
    func resolving(_ clip: Clip?) -> PanelResponse {
        guard let clip else { return stayingOpen }
        // A missing picture is refused before the obstacle check; "nothing to paste" is not "cannot place".
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

    /// The same resolution with the formatting left behind; it passes the same obstacle check.
    func resolvingPlain(_ clip: Clip?) -> PanelResponse {
        guard let clip else { return stayingOpen }
        switch insertion {
        case .atCaret:
            return PanelResponse(state: self, outcome: .insertPlain(clip))
        case .clipboardOnly(let obstacle):
            return PanelResponse(state: self, outcome: .copyOnly(clip, obstacle))
        }
    }

    /// ⌘-click, which is ⌘-Return on the row under the pointer.
    func choosingPlain(_ id: Clip.ID) -> PanelResponse {
        guard let row = results.rows.first(where: { $0.id == id }) else { return stayingOpen }
        var next = self
        next.selection = id
        return next.resolvingPlain(row.clip)
    }

    /// A click on a row takes the selection and resolves; a row not in the list is ignored.
    func choosing(_ id: Clip.ID) -> PanelResponse {
        guard let row = results.rows.first(where: { $0.id == id }) else { return stayingOpen }
        var next = self
        next.selection = id
        // Through `resolving`, so keyboard and mouse have one answer because they ask one function.
        return next.resolving(row.clip)
    }

    /// Unmasking is its own key, so a secret never reveals itself as the highlight passes over it.
    func revealing(_ id: Clip.ID) -> PanelSnapshot {
        var next = self
        next.revealed.insert(id)
        return next
    }
}
