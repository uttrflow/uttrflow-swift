// The panel intent routing owner. See `Docs/panel.md`.
public import UttrflowClipboard

/// What choosing something on a row means, named rather than a closure so a row compares.
public enum PanelIntent: Sendable, Equatable {
    /// Put this clip where the cursor was, and close. Exactly what Return does.
    case insert(Clip.ID)
    /// Remove display hazards from this clip before putting it where the cursor was.
    case insertCleaned(Clip.ID)
    /// Put it back on the clipboard without pasting, for somewhere the panel cannot reach.
    case copy(Clip.ID)
    case pin(Clip.ID)
    case unpin(Clip.ID)
    case reveal(Clip.ID)
    /// Unmask a clip wrongly taken for a secret, and stop masking its text.
    case markNotSecret(Clip.ID)
    /// Mask a clip the detector missed, and keep it off the disk.
    case markSecret(Clip.ID)
    /// Name it, or rename it.
    case alias(Clip.ID)
    /// File it into a collection.
    case move(Clip.ID)
    /// Change the words of its text, keeping everything the user chose about it.
    case edit(Clip.ID)
    /// Immediately for an ordinary clip; after asking for one the user kept.
    case delete(Clip.ID)
    /// D4 — tidy the indentation of a code clip, changing nothing else about it.
    case reindent(Clip.ID)
    /// D5, D6 — run the installed formatter and show what it wants to change.
    case format(Clip.ID)
    /// E6 — make this plain clip a note, so it can be given formatting.
    case makeNote(Clip.ID)
    /// F9 — put back the clip the last delete removed, which only the app still holds.
    case undoDelete
    /// H3 — keep the text of a search that found nothing.
    case keepQuery(String)
    /// B5 — the one thing that would let Uttrflow paste for the user.
    case openAccessibilitySettings
    /// I1, I2 — start dictating into the search field, or stop.
    case dictate
    /// The bottom bar: which slice of the clipboard to browse.
    case scope(PanelScope)
    /// The bottom bar's way out of the panel, into Uttrflow's own settings.
    case openSettings
    /// G5 — rename the collection a chip names.
    case renameCategory(String)
    /// G6 — delete it, having first asked where its clips go.
    case deleteCategory(String)

    /// The keystroke this intent is, so the Insert button and Return are provably one path.
    public var key: PanelKey? {
        switch self {
        case .insert(let id): .choose(id)
        case .insertCleaned(let id): .chooseCleaned(id)
        case .reveal(let id): .reveal(id)
        case .alias(let id): .alias(id)
        case .move(let id): .move(id)
        case .edit(let id): .edit(id)
        case .delete(let id): .delete(id)
        case .reindent(let id): .reindent(id)
        case .makeNote(let id): .makeNote(id)
        case .renameCategory(let name): .renameCategory(name)
        case .deleteCategory(let name): .deleteCategory(name)
        // D5 — no key: running a formatter is another program, which only the app can do.
        case .scope(let scope): .scope(scope)
        case .format, .copy, .pin, .unpin, .markNotSecret, .markSecret, .undoDelete, .keepQuery,
            .openAccessibilitySettings, .openSettings, .dictate:
            nil
        }
    }

    /// A row action that writes directly to the store without first asking a question.
    public var immediateChange: PanelChange? {
        switch self {
        case .pin(let id): .setPinned(id, true)
        case .unpin(let id): .setPinned(id, false)
        case .markNotSecret(let id): .setSecret(id, false)
        case .markSecret(let id): .setSecret(id, true)
        default: nil
        }
    }
}
