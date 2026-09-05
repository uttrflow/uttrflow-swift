public import Foundation
public import UttrflowClipboard

/// What choosing something on a row means, named rather than a closure so a row compares.
public enum PanelIntent: Sendable, Equatable {
    /// Put this clip where the cursor was, and close. Exactly what Return does.
    case insert(Clip.ID)
    /// Put it back on the clipboard without pasting, for somewhere the panel cannot reach.
    case copy(Clip.ID)
    case pin(Clip.ID)
    case unpin(Clip.ID)
    case reveal(Clip.ID)
    /// Name it, or rename it.
    case alias(Clip.ID)
    /// File it into a collection.
    case move(Clip.ID)
    /// Immediately for an ordinary clip; after asking for one the user kept.
    case delete(Clip.ID)
    /// D4 — tidy the indentation of a code clip, changing nothing else about it.
    case reindent(Clip.ID)
    /// D5, D6 — run the installed formatter and show what it wants to change.
    case format(Clip.ID)
    /// E6 — make this plain clip a note, so it can be given formatting.
    case makeNote(Clip.ID)
    /// E5 — tick or untick a box in a note.
    case tickBox(Clip.ID, index: Int)
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
        case .reveal(let id): .reveal(id)
        case .alias(let id): .alias(id)
        case .move(let id): .move(id)
        case .delete(let id): .delete(id)
        case .reindent(let id): .reindent(id)
        case .makeNote(let id): .makeNote(id)
        case .tickBox(let id, let index): .tickBox(id, index: index)
        case .renameCategory(let name): .renameCategory(name)
        case .deleteCategory(let name): .deleteCategory(name)
        // D5 — no key: running a formatter is another program, which only the app can do.
        case .scope(let scope): .scope(scope)
        case .format, .copy, .pin, .unpin, .undoDelete, .keepQuery, .openAccessibilitySettings,
            .openSettings, .dictate:
            nil
        }
    }
}

/// What a bottom-bar button is drawn with, as cases rather than a name a `Shape` cannot answer.
public enum PanelTabGlyph: Sendable, Equatable {
    case symbol(String)
    /// The Uttrflow mark, tinted by the bar like every other glyph.
    case brandMark
}

/// One button in the bottom bar, carrying an intent because the bar mixes slices with a way out.
public struct PanelTab: Sendable, Equatable, Identifiable {
    public let title: String
    public let glyph: PanelTabGlyph
    public let intent: PanelIntent
    public let isActive: Bool

    public var id: String { title }

    public init(title: String, glyph: PanelTabGlyph, intent: PanelIntent, isActive: Bool) {
        self.title = title
        self.glyph = glyph
        self.intent = intent
        self.isActive = isActive
    }
}

/// One thing a row offers.
public struct PanelAction: Sendable, Equatable, Identifiable {
    public let title: String
    public let symbolName: String
    public let intent: PanelIntent
    /// Whether this action takes something away, decided here. See `Docs/panel.md`.
    public let isDestructive: Bool

    public var id: String { title }

    public init(
        title: String, symbolName: String, intent: PanelIntent, isDestructive: Bool = false
    ) {
        self.title = title
        self.symbolName = symbolName
        self.intent = intent
        self.isDestructive = isDestructive
    }
}

/// One clip, ready to draw.
public struct PanelRow: Sendable, Equatable, Identifiable {
    public let id: Clip.ID
    /// The one line the row shows — bullets, when the clip is masked.
    public let summary: String
    public let kind: ClipKind
    /// SF Symbol for the icon at the head of the row.
    public let symbolName: String
    /// How long ago, in words, for ``detail`` — the row itself does not draw it.
    public let when: String
    /// The ⋯ menu's line — "Text · 41 minutes ago · Claude" — joined only where each part exists.
    public let detail: String
    /// The handle the user gave it, shown as they typed it.
    public let alias: String?
    public let category: String?
    public let isPinned: Bool
    /// Whether bullets are drawn rather than the clip, so nothing mistakes one for the other.
    public let isMasked: Bool
    public let isSelected: Bool
    /// Why this row is in the list. `nil` when nothing was typed and every clip is here.
    public let matched: PanelMatchField?
    /// K4 — what a picture row says about itself, since it has no text. See `Docs/panel.md`.
    public let measurements: String?
    /// K4 — the picture to draw beside the row, or `nil` when there is none to draw.
    public let imageFile: URL?
    /// B8 — the picture has gone from disk, though the row stays. See `Docs/panel.md`.
    public let isImageMissing: Bool
    /// E5 — how much of a checklist is done, as "2 of 5", or `nil` when it has no boxes.
    public let checklist: String?
    /// D1 — the language chip, short enough for a 420-point row: "ts", not "TypeScript".
    public let language: String?
    /// Whether the summary is monospaced, decided here so the view has no judgement to get wrong.
    public let isMonospaced: Bool
    public let actions: [PanelAction]

    /// C6 — the whole line for a truncated row, and never on a masked one. See `Docs/panel.md`.
    public var tooltip: String? {
        isMasked ? nil : summary
    }

    public init(
        id: Clip.ID,
        summary: String,
        kind: ClipKind,
        symbolName: String,
        when: String,
        detail: String = "",
        alias: String?,
        category: String?,
        isPinned: Bool,
        isMasked: Bool,
        isSelected: Bool,
        matched: PanelMatchField?,
        measurements: String? = nil,
        imageFile: URL? = nil,
        isImageMissing: Bool = false,
        checklist: String? = nil,
        language: String? = nil,
        isMonospaced: Bool,
        actions: [PanelAction]
    ) {
        self.id = id
        self.summary = summary
        self.kind = kind
        self.symbolName = symbolName
        self.when = when
        self.detail = detail
        self.alias = alias
        self.category = category
        self.isPinned = isPinned
        self.isMasked = isMasked
        self.isSelected = isSelected
        self.matched = matched
        self.measurements = measurements
        self.imageFile = imageFile
        self.isImageMissing = isImageMissing
        self.checklist = checklist
        self.language = language
        self.isMonospaced = isMonospaced
        self.actions = actions
    }
}

/// One tab across the top.
public struct PanelFilterChip: Sendable, Equatable, Identifiable {
    public let title: String
    public let filter: PanelFilter
    public let isActive: Bool

    public var id: String { filter.rawValue }

    public init(title: String, filter: PanelFilter, isActive: Bool) {
        self.title = title
        self.filter = filter
        self.isActive = isActive
    }
}

/// One collection, and the number that jumps to it.
public struct PanelCategoryChip: Sendable, Equatable, Identifiable {
    public let title: String
    /// The collection, or `nil` for the chip that shows all of them.
    public let category: String?
    /// The ⌘-number printed beside it, absent past the ninth. See `Docs/panel.md`.
    public let shortcut: Int?
    /// Which collection this is, counting from 2, and not the same as ``shortcut``. See `Docs/panel.md`.
    public let position: Int
    public let isActive: Bool

    /// What pressing this chip sends: its position, or 1 when it is already chosen. See `Docs/panel.md`.
    public var chosen: Int { isActive ? 1 : position }

    /// The collection itself, so a collection named "All" is still distinct from everything.
    public var id: String { category ?? "" }

    public init(
        title: String, category: String?, shortcut: Int?, position: Int, isActive: Bool
    ) {
        self.title = title
        self.category = category
        self.shortcut = shortcut
        self.position = position
        self.isActive = isActive
    }
}

/// What the quick panel shows.
public struct PanelPresentation: Sendable, Equatable {
    public let rows: [PanelRow]
    public let filters: [PanelFilterChip]
    /// The bottom bar, left to right.
    public let tabs: [PanelTab]
    /// Empty when nothing is filed anywhere, rather than a lone chip saying nothing.
    public let categories: [PanelCategoryChip]
    public let query: String
    public let searchPlaceholder: String
    /// Set only when ``rows`` is empty, naming which of the four nothings this is.
    public let emptyState: MainEmptyState?
    /// The line along the bottom that teaches the three keystrokes.
    public let hint: String
    /// The sheet over the list — naming, filing or confirming a delete — or `nil` for a plain list.
    public let sheet: PanelSheetPresentation?
    /// H1 — the same rows cut into runs, and empty until something is typed.
    public let groups: [PanelResultGroup]
    /// H3 — the one thing to do about an empty result, in the panel's vocabulary.
    public let emptyAction: PanelAction?
    /// B3–B5 — what the panel is saying about a clip it could only copy.
    public let notice: PanelNotice?
    /// I1–I7 — the microphone, and what it can do right now.
    public let microphone: PanelMicrophone
    /// H7 — what the list is scoped to when that differs from the chip last pressed.
    public let scope: String?

    public init(
        rows: [PanelRow],
        filters: [PanelFilterChip],
        tabs: [PanelTab] = [],
        categories: [PanelCategoryChip],
        query: String,
        searchPlaceholder: String,
        emptyState: MainEmptyState?,
        hint: String,
        sheet: PanelSheetPresentation? = nil,
        groups: [PanelResultGroup] = [],
        emptyAction: PanelAction? = nil,
        notice: PanelNotice? = nil,
        microphone: PanelMicrophone = PanelPresenter.microphone(for: .ready),
        scope: String? = nil
    ) {
        self.rows = rows
        self.filters = filters
        self.tabs = tabs
        self.categories = categories
        self.query = query
        self.searchPlaceholder = searchPlaceholder
        self.emptyState = emptyState
        self.hint = hint
        self.sheet = sheet
        self.groups = groups
        self.emptyAction = emptyAction
        self.notice = notice
        self.microphone = microphone
        self.scope = scope
    }

    /// The row Return would insert, so neither the view nor the app counts rows itself.
    public var selectedRow: PanelRow? { rows.first { $0.isSelected } }
}

/// Turns the panel's state into the panel, and is the only place that decides what it says.
public enum PanelPresenter {
    /// Says what the field is for *and* teaches the one thing that makes the panel fast.
    public static let searchPlaceholder = "Search, or type an alias"

    /// The gesture, drawn under a full list, because the panel is most people's only lesson in it.
    public static let hint = "↑↓ to choose · ⏎ to paste · esc to close"
    public static let emptyHint = "esc to close"
    /// A sheet's own keys, which differ from the list's. See `Docs/panel.md`.
    public static let sheetHint = "⏎ to save · esc to go back"
    /// Offered rather than merely available, because F7 traded the dialog away for it.
    public static let undoHint = "Deleted · ⌘Z to put it back"

    /// Which line goes under the list, undo first because it expires. See `Docs/panel.md`.
    static func hint(for snapshot: PanelSnapshot, isEmpty: Bool) -> String {
        if snapshot.sheet != nil { return sheetHint }
        if snapshot.canUndoDelete { return undoHint }
        return isEmpty ? emptyHint : hint
    }

    /// A fixed count, not one per character, so the mask cannot leak a token's length.
    static let mask = String(repeating: "•", count: 12)

    public static func present(_ snapshot: PanelSnapshot) -> PanelPresentation {
        let results = snapshot.results
        let rows = results.rows.enumerated().map { position, result in
            row(for: result, in: snapshot, isSelected: position == results.selectedIndex)
        }

        return PanelPresentation(
            rows: rows,
            // Off while a collection is chosen, or All and the collection would both light.
            filters: PanelFilter.allCases.map {
                PanelFilterChip(
                    title: $0.title, filter: $0,
                    isActive: shownCategory(for: snapshot) == nil && $0 == snapshot.filter)
            },
            tabs: tabs(for: snapshot),
            categories: categories(for: snapshot),
            query: snapshot.query,
            searchPlaceholder: searchPlaceholder,
            emptyState: rows.isEmpty ? emptyState(for: snapshot) : nil,
            // A sheet has its own keys, so the list's line would be teaching the wrong ones.
            hint: hint(for: snapshot, isEmpty: rows.isEmpty),
            sheet: sheet(for: snapshot),
            groups: groups(for: rows, omitted: results.omitted, isSearching: snapshot.isSearching),
            emptyAction: rows.isEmpty ? emptyAction(for: snapshot) : nil,
            notice: snapshot.notice,
            microphone: microphone(for: snapshot.dictation),
            scope: scope(for: snapshot)
        )
    }

    // MARK: - A row

    static func row(
        for result: PanelResult, in snapshot: PanelSnapshot, isSelected: Bool
    ) -> PanelRow {
        let clip = result.clip
        let isMasked = clip.kind == .secret && !snapshot.revealed.contains(clip.id)
        let isGone = clip.image != nil && snapshot.missingImages.contains(clip.id)
        // H5 — never on a masked clip, or the excerpt prints the secret. See `Docs/panel.md`.
        let excerpt =
            isMasked || result.match != .content
            ? nil
            : self.excerpt(of: clip.text, around: snapshot.needle, locale: snapshot.locale)
        // The same words the history page uses, or "just now" means two things.
        let when = HistoryPresenter.when(
            clip.copiedAt, relativeTo: snapshot.now, locale: snapshot.locale)
        return PanelRow(
            id: clip.id,
            summary: isMasked ? mask : (excerpt ?? clip.summary),
            kind: clip.kind,
            symbolName: symbolName(for: clip.kind),
            when: when,
            detail: detail(of: clip, when: when),
            alias: clip.alias,
            category: PanelSnapshot.name(clip.category),
            isPinned: clip.isPinned,
            isMasked: isMasked,
            isSelected: isSelected,
            matched: result.match,
            measurements: measurements(of: clip, in: snapshot),
            imageFile: isGone
                ? nil
                : clip.image.flatMap { image in
                    snapshot.imagesFolder?.appending(path: image.file, directoryHint: .notDirectory)
                },
            isImageMissing: isGone,
            // E5 — a ticked box is content, so its count belongs on the row.
            checklist: isMasked
                ? nil
                : clip.richText.flatMap(NoteChecklist.progress(in:)).map {
                    "\($0.done) of \($0.total)"
                },
            // Never on a masked row, which says as little as possible until asked.
            language: isMasked ? nil : clip.language?.chip,
            isMonospaced: isMonospaced(clip.kind),
            actions: actions(for: clip, isMasked: isMasked, in: snapshot)
        )
    }

    /// One symbol per kind, so a row is told apart before it is read.
    static func symbolName(for kind: ClipKind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .secret: "key.fill"
        case .colour: "paintpalette"
        case .filePath: "folder"
        case .image: "photo"
        }
    }

    /// Where characters matter one by one, and masked the same way so revealing does not jump.
    static func isMonospaced(_ kind: ClipKind) -> Bool {
        switch kind {
        // A path is read character by character, as code is.
        case .code, .colour, .secret, .filePath: true
        case .text, .link, .image: false
        }
    }

    /// Insert first because it is what the row is for, then reveal, and pinning last.
    static func actions(
        for clip: Clip, isMasked: Bool, in snapshot: PanelSnapshot
    )
        -> [PanelAction]
    {
        var actions = [
            PanelAction(title: "Insert", symbolName: "arrow.down.doc", intent: .insert(clip.id))
        ]
        if isMasked {
            actions.append(PanelAction(title: "Reveal", symbolName: "eye", intent: .reveal(clip.id)))
        }
        actions.append(PanelAction(title: "Copy", symbolName: "doc.on.doc", intent: .copy(clip.id)))
        actions.append(
            clip.isPinned
                ? PanelAction(title: "Unpin", symbolName: "pin.slash", intent: .unpin(clip.id))
                : PanelAction(title: "Pin", symbolName: "pin", intent: .pin(clip.id)))
        // Rename when there is a name, or the user expects a second alias.
        actions.append(
            PanelAction(
                title: clip.alias == nil ? "Name" : "Rename", symbolName: "tag",
                intent: .alias(clip.id)))
        actions.append(PanelAction(title: "Move", symbolName: "folder", intent: .move(clip.id)))
        // D4, D5 — offered only where it would do something and a formatter exists.
        if let language = clip.language, snapshot.formattableLanguages.contains(language) {
            actions.append(
                PanelAction(
                    title: "Format", symbolName: "wand.and.stars", intent: .format(clip.id)))
        }
        if clip.kind == .code, CodeReindent.reindented(clip.text) != nil {
            actions.append(
                PanelAction(
                    title: "Re-indent", symbolName: "text.alignleft", intent: .reindent(clip.id)))
        }
        // E6 — never on a note already, or promoting replaces what the user wrote.
        if clip.richText == nil {
            actions.append(
                PanelAction(
                    title: "Make a note", symbolName: "square.and.pencil",
                    intent: .makeNote(clip.id)))
        }
        // Last, and the only one that repeating does not undo.
        actions.append(
            PanelAction(
                title: "Delete", symbolName: "trash", intent: .delete(clip.id),
                isDestructive: true))
        return actions
    }

    /// K4, B8 — what a picture row says, or why it cannot. See `Docs/panel.md`.
    static func measurements(of clip: Clip, in snapshot: PanelSnapshot) -> String? {
        guard let image = clip.image else { return nil }
        if snapshot.missingImages.contains(clip.id) {
            return "The picture is no longer on this Mac"
        }
        let weight = fileSize(image.bytes)
        guard let from = clip.source?.trimmingCharacters(in: .whitespaces), !from.isEmpty else {
            return "\(image.dimensions) · \(weight)"
        }
        return "\(from) · \(weight)"
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
        }
    }

    /// Round numbers, because nobody reads a screenshot's size to the byte.
    static func fileSize(_ bytes: Int) -> String {
        if bytes >= 1_000_000 { return "\(bytes / 1_000_000) MB" }
        if bytes >= 1_000 { return "\(bytes / 1_000) KB" }
        return "\(bytes) bytes"
    }

    // MARK: - The chips

    /// The collection drawn as chosen, which a query replaces with All. See `Docs/panel.md`.
    static func shownCategory(for snapshot: PanelSnapshot) -> String? {
        snapshot.isSearching ? nil : PanelSnapshot.name(snapshot.category)
    }

    /// One chip per collection, numbered from 2; no "All" chip, since the shared row begins with one.
    static func categories(for snapshot: PanelSnapshot) -> [PanelCategoryChip] {
        // A query spans every tab, so All is the chip that is true.
        let active = shownCategory(for: snapshot)
        return snapshot.categories.enumerated().map { offset, name in
            let number = offset + 2
            return PanelCategoryChip(
                title: name, category: name,
                shortcut: number <= PanelSnapshot.shortcutLimit ? number : nil,
                position: number,
                isActive: active == name)
        }
    }

    /// The bottom bar: four slices the list can be, then settings, which it cannot.
    static func tabs(for snapshot: PanelSnapshot) -> [PanelTab] {
        PanelScope.allCases.map {
            PanelTab(
                title: $0.title, glyph: $0.glyph, intent: .scope($0),
                isActive: $0 == snapshot.scope)
        }
            + [
                PanelTab(
                    title: "Settings", glyph: .symbol("slider.horizontal.3"),
                    intent: .openSettings, isActive: false)
            ]
    }

    /// Where the panel is looking, named four ways because the narrowing changes the wording.
    public struct PanelEmptyPlace: Sendable, Equatable {
        /// The glyph above the sentence.
        public let symbolName: String
        /// The heading when this is the only thing narrowing.
        public let title: String
        /// How the place reads after a kind, as in "No Code **in db**".
        public let suffix: String
        /// How it reads as the subject of a sentence: "Nothing **filed in db** is code."
        public let subject: String
        /// The whole sentence when this is the only thing narrowing.
        public let alone: String

        public init(
            symbolName: String, title: String, suffix: String, subject: String, alone: String
        ) {
            self.symbolName = symbolName
            self.title = title
            self.suffix = suffix
            self.subject = subject
            self.alone = alone
        }
    }

    // MARK: - Nothing to show

    /// The nothings, told apart, because what to do about each one differs.
    static func emptyState(for snapshot: PanelSnapshot) -> MainEmptyState {
        let query = snapshot.needle

        // The only nothing that is about the clipboard rather than the narrowing.
        if snapshot.clips.isEmpty {
            return MainEmptyState(
                symbolName: "doc.on.clipboard",
                title: "Nothing copied yet",
                message: "Whatever you copy turns up here, ready to put back.")
        }

        // Emptied by tidying, not by never copying. See `Docs/panel.md`.
        if query.isEmpty, snapshot.filter == .all, PanelSnapshot.name(snapshot.category) == nil,
            let arrivals = arrivalsOrigin(of: snapshot.scope),
            snapshot.clips.contains(where: { $0.origin == arrivals })
        {
            return MainEmptyState(
                symbolName: "tray",
                title: "Nothing loose",
                message: arrivals == .copied
                    ? "Everything you have copied is pinned or filed."
                    : "Everything Uttrflow made is pinned or filed.")
        }

        // A search spans everything, so naming a tab would describe a constraint not applied.
        if !query.isEmpty {
            // Not "nothing you have copied": a search spans what Uttrflow made too.
            return .noMatches("Nothing on your clipboard mentions “\(query)”.")
        }

        return narrowedEmptyState(for: snapshot)
    }

    /// Which arrivals tab this is, of the two that list what has not been put anywhere.
    static func arrivalsOrigin(of scope: PanelScope) -> ClipOrigin? {
        switch scope {
        case .history: .copied
        case .uttrflow: .uttrflow
        case .pinned, .collections: nil
        }
    }

    /// What to say when the narrowing hid everything, assembled from every narrowing that is on. See `Docs/panel.md`.
    static func narrowedEmptyState(for snapshot: PanelSnapshot) -> MainEmptyState {
        let category = PanelSnapshot.name(snapshot.category)
        let kind = snapshot.filter == .all ? nil : snapshot.filter
        let place = place(for: snapshot.scope, category: category)

        guard let kind else {
            return MainEmptyState(
                symbolName: place.symbolName, title: place.title, message: place.alone)
        }
        return MainEmptyState(
            symbolName: place.symbolName,
            title: "No \(kind.title) \(place.suffix)",
            message: "Nothing \(place.subject) is \(kind.noun).")
    }

    /// Where the user is looking: a tab, a collection, or both. Total, so no case needs its own sentence.
    static func place(for scope: PanelScope, category: String?) -> PanelEmptyPlace {
        switch (scope, category) {
        case (.pinned, .some(let name)):
            PanelEmptyPlace(
                symbolName: "pin", title: "Nothing pinned in \(name)",
                suffix: "pinned in \(name)", subject: "pinned in \(name)",
                alone: "Nothing filed in \(name) is pinned.")
        case (.pinned, .none):
            PanelEmptyPlace(
                symbolName: "pin", title: "Nothing pinned", suffix: "pinned",
                subject: "you have pinned",
                alone: "Pin a clip and it waits here, however long it has been.")
        case (.uttrflow, .some(let name)):
            // Named as both, or the shared arm says three things that are false here.
            PanelEmptyPlace(
                symbolName: "waveform", title: "Nothing from Uttrflow in \(name)",
                suffix: "from Uttrflow in \(name)", subject: "Uttrflow made in \(name)",
                alone: "Nothing filed in \(name) came from Uttrflow.")
        case (_, .some(let name)):
            PanelEmptyPlace(
                symbolName: "folder", title: "Nothing in \(name)", suffix: "in \(name)",
                subject: "filed in \(name)",
                alone: "Nothing you have copied is filed here.")
        case (.collections, .none):
            PanelEmptyPlace(
                symbolName: "tag", title: "Nothing filed", suffix: "filed",
                subject: "you have filed",
                alone: "Move a clip into a collection and it turns up here.")
        case (.uttrflow, .none):
            PanelEmptyPlace(
                // A waveform, not the mark, which would read as branding on an empty screen.
                symbolName: "waveform", title: "Nothing from Uttrflow", suffix: "from Uttrflow",
                subject: "Uttrflow has made",
                alone: "Dictate something and it waits here, out of the way of what you copy.")
        case (.history, .none):
            PanelEmptyPlace(
                symbolName: "doc.on.clipboard", title: "Nothing copied yet", suffix: "copied",
                subject: "you have copied",
                // The empty-clipboard sentence, which is the plain truth on this tab too.
                alone: "Whatever you copy turns up here, ready to put back.")
        }
    }
}
