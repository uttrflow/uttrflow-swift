// What the panel draws: intents, tabs, actions, rows, chips, and the presenter that builds them.
public import Foundation
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
    /// The chord that performs it without the pointer, shown in the menu so it can be found.
    public let shortcut: PanelChord?

    public var id: String { title }

    public init(
        title: String, symbolName: String, intent: PanelIntent, isDestructive: Bool = false,
        shortcut: PanelChord? = nil
    ) {
        self.title = title
        self.symbolName = symbolName
        self.intent = intent
        self.isDestructive = isDestructive
        self.shortcut = shortcut
    }
}

/// One clip, ready to draw.
public struct PanelRow: Sendable, Equatable, Identifiable {
    public let id: Clip.ID
    /// The one line the row shows — bullets, when the clip is masked.
    public let summary: String
    /// Additional pasted lines, including a final newline, shown beside the summary.
    public let additionalLineCount: Int
    public let kind: ClipKind
    /// Resolved sRGB for a colour clip, when its copied notation has a direct swatch.
    public let swatch: ClipColour?
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
    public internal(set) var isSelected: Bool
    /// Why this row is in the list. `nil` when nothing was typed and every clip is here.
    public let matched: PanelMatchField?
    /// What a picture or formatted-text row says about itself. See `Docs/panel.md`.
    public let measurements: String?
    /// How many boxes are checked in a note, when its formatted form contains a checklist.
    public let checklist: String?
    /// K4 — the picture to draw beside the row, or `nil` when there is none to draw.
    public let imageFile: URL?
    /// B8 — the picture has gone from disk, though the row stays. See `Docs/panel.md`.
    public let isImageMissing: Bool
    /// D1 — the language chip, short enough for a 420-point row: "ts", not "TypeScript".
    public let language: String?
    /// Whether the summary is monospaced, decided here so the view has no judgement to get wrong.
    public let isMonospaced: Bool
    /// Whether the clip contains invisible or control characters.
    public let containsDisplayHazards: Bool
    public let actions: [PanelAction]

    /// The bounded full-text preview, never on a masked row. See `Docs/panel.md`.
    public var tooltip: String? {
        isMasked ? nil : preview
    }
    /// The complete clip up to the clipboard module's preview bound.
    public let preview: String

    public init(
        id: Clip.ID,
        summary: String,
        additionalLineCount: Int = 0,
        preview: String = "",
        kind: ClipKind,
        swatch: ClipColour? = nil,
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
        checklist: String? = nil,
        imageFile: URL? = nil,
        isImageMissing: Bool = false,
        language: String? = nil,
        isMonospaced: Bool,
        containsDisplayHazards: Bool = false,
        actions: [PanelAction]
    ) {
        self.id = id
        self.summary = summary
        self.additionalLineCount = additionalLineCount
        self.preview = preview
        self.kind = kind
        self.swatch = swatch
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
        self.checklist = checklist
        self.imageFile = imageFile
        self.isImageMissing = isImageMissing
        self.language = language
        self.isMonospaced = isMonospaced
        self.containsDisplayHazards = containsDisplayHazards
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
    let selectedIndex: Int?
    let rowCacheID: UUID
    private let baseRows: [PanelRow]
    private let baseGroups: [PanelResultGroup]
    public var rows: [PanelRow] { markingSelected(baseRows, at: selectedIndex) }
    package var listRows: [PanelRow] { baseRows }
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
    public var groups: [PanelResultGroup] {
        guard let selectedRow, let field = selectedRow.matched else { return baseGroups }
        return baseGroups.map { group in
            guard group.field == field else { return group }
            return PanelResultGroup(
                field: group.field, title: group.title,
                rows: markingSelected(group.rows, at: group.rows.firstIndex { $0.id == selectedRow.id }),
                more: group.more)
        }
    }
    package var listGroups: [PanelResultGroup] { baseGroups }
    /// H3 — the one thing to do about an empty result, in the panel's vocabulary.
    public let emptyAction: PanelAction?
    /// B3–B5 — what the panel is saying about a clip it could only copy.
    public let notice: PanelNotice?
    /// I1–I7 — the microphone, and what it can do right now.
    public let microphone: PanelMicrophone
    /// H7 — what the list is scoped to when that differs from the chip last pressed.
    public let scope: String?
    /// What VoiceOver is told when each line appears in the open panel.
    public let announcements: [String]
    /// Stable identities for the corresponding lines, changed only when a new announcement event occurs.
    public let announcementIDs: [UUID]
    /// What VoiceOver says choosing a row will do, which is a copy when the panel cannot paste.
    public let rowHint: String

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
        scope: String? = nil,
        announcements: [String] = [],
        announcementIDs: [UUID] = [],
        rowHint: String = PanelPresenter.pasteRowHint
    ) {
        self.selectedIndex = rows.firstIndex(where: \.isSelected)
        self.rowCacheID = UUID()
        self.baseRows = rows
        self.filters = filters
        self.tabs = tabs
        self.categories = categories
        self.query = query
        self.searchPlaceholder = searchPlaceholder
        self.emptyState = emptyState
        self.hint = hint
        self.sheet = sheet
        self.baseGroups = groups
        self.emptyAction = emptyAction
        self.notice = notice
        self.microphone = microphone
        self.scope = scope
        self.announcements = announcements
        self.announcementIDs = announcementIDs
        self.rowHint = rowHint
    }

    init(
        rows: [PanelRow], filters: [PanelFilterChip], tabs: [PanelTab],
        categories: [PanelCategoryChip], query: String, searchPlaceholder: String,
        emptyState: MainEmptyState?, hint: String, sheet: PanelSheetPresentation?,
        groups: [PanelResultGroup], emptyAction: PanelAction?, notice: PanelNotice?,
        microphone: PanelMicrophone, scope: String?, announcements: [String],
        announcementIDs: [UUID], rowHint: String, selectedIndex: Int?, rowCacheID: UUID
    ) {
        self.selectedIndex = selectedIndex
        self.rowCacheID = rowCacheID
        self.baseRows = rows
        self.filters = filters
        self.tabs = tabs
        self.categories = categories
        self.query = query
        self.searchPlaceholder = searchPlaceholder
        self.emptyState = emptyState
        self.hint = hint
        self.sheet = sheet
        self.baseGroups = groups
        self.emptyAction = emptyAction
        self.notice = notice
        self.microphone = microphone
        self.scope = scope
        self.announcements = announcements
        self.announcementIDs = announcementIDs
        self.rowHint = rowHint
    }

    /// Whether the footer is offering ⌘Z to put a deleted clip back, which is then what ⌘Z does.
    public var offersUndo: Bool { hint == PanelPresenter.undoHint || hint == PanelPresenter.searchUndoHint }

    /// The key that opens the keyboard guide, said under the list but not under a sheet's own keys.
    package var shortcutsHint: String? { sheet == nil ? PanelPresenter.shortcutsHint : nil }

    /// The row Return would insert, so neither the view nor the app counts rows itself.
    public var selectedRow: PanelRow? {
        guard let selectedIndex, baseRows.indices.contains(selectedIndex) else { return nil }
        var row = baseRows[selectedIndex]
        row.isSelected = true
        return row
    }

    var selectedRowID: UUID? { selectedRow?.id }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        let sameSmallFields =
            lhs.selectedIndex == rhs.selectedIndex
            && lhs.filters == rhs.filters && lhs.tabs == rhs.tabs
            && lhs.categories == rhs.categories && lhs.query == rhs.query
            && lhs.searchPlaceholder == rhs.searchPlaceholder && lhs.emptyState == rhs.emptyState
            && lhs.hint == rhs.hint && lhs.sheet == rhs.sheet && lhs.emptyAction == rhs.emptyAction
            && lhs.notice == rhs.notice && lhs.microphone == rhs.microphone && lhs.scope == rhs.scope
            && lhs.announcements == rhs.announcements && lhs.announcementIDs == rhs.announcementIDs
            && lhs.rowHint == rhs.rowHint
        guard sameSmallFields else { return false }
        if lhs.rowCacheID == rhs.rowCacheID { return true }
        return lhs.baseRows == rhs.baseRows && lhs.baseGroups == rhs.baseGroups
    }
}

private func markingSelected(_ rows: [PanelRow], at index: Int?) -> [PanelRow] {
    guard let index, rows.indices.contains(index) else { return rows }
    var values = rows
    values[index].isSelected = true
    return values
}

/// Turns the panel's state into the panel, and is the only place that decides what it says.
public enum PanelPresenter {
    /// Says what the field is for *and* teaches the one thing that makes the panel fast.
    public static let searchPlaceholder = "Search, or type an alias"

    /// The gesture, drawn under a full list, because the panel is most people's only lesson in it.
    public static let hint = "↑↓ to choose · ⏎ to paste · ⌘⏎ plain · ⌘Z undo · esc to close"
    public static let emptyHint = "esc to close"
    /// A sheet's own keys, which differ from the list's. See `Docs/panel.md`.
    public static let sheetHint = "⏎ to save · esc to go back"
    /// Offered rather than merely available, because F7 traded the dialog away for it.
    public static let undoHint = "Deleted · ⌘Z restores the last delete only"
    /// While searching, Escape clears the query before it closes anything. See `Docs/panel.md`.
    package static let searchHint = "esc to clear search"
    /// The undo offer while searching, which still says what Escape does first.
    package static let searchUndoHint = "Deleted · ⌘Z restores the last delete only · esc clears search"
    /// Drawn beside the list's hint, so the keyboard guide is found without opening a row menu.
    package static let shortcutsHint = "⌘/ shortcuts"

    /// The undo offer as VoiceOver says it, with the key spelled out rather than drawn.
    public static let undoAnnouncement = "Deleted. Command-Z restores only the most recent deletion."
    /// What choosing a row does when the panel can paste.
    public static let pasteRowHint = "Pastes where you were typing"
    /// What choosing a row does when the panel can only copy.
    public static let copyRowHint = "Copies to the clipboard, to paste yourself with Command-V"

    /// The notice and the undo offer, as spoken; the controller posts each appearance. See `Docs/app-quick-panel.md`.
    static func announcements(for snapshot: PanelSnapshot) -> [String] {
        [snapshot.notice?.message, snapshot.canUndoDelete ? undoAnnouncement : nil].compactMap { $0 }
    }

    /// Event identities parallel to `announcements`, so a repeated action is spoken after a redraw.
    static func announcementIDs(for snapshot: PanelSnapshot) -> [UUID] {
        [snapshot.notice?.announcementID, snapshot.canUndoDelete ? snapshot.undoAnnouncementID : nil]
            .compactMap { $0 }
    }

    /// What VoiceOver says a row does, so a copy-only panel never promises a paste.
    static func rowHint(for insertion: PanelInsertion) -> String {
        insertion == .atCaret ? pasteRowHint : copyRowHint
    }

    /// Which line goes under the list; a sheet's keys win over the undo offer. See `Docs/panel.md`.
    static func hint(for snapshot: PanelSnapshot, isEmpty: Bool) -> String {
        if snapshot.sheet != nil { return sheetHint }
        if snapshot.canUndoDelete { return snapshot.isSearching ? searchUndoHint : undoHint }
        if snapshot.isSearching { return searchHint }
        return isEmpty ? emptyHint : hint
    }

    /// A fixed count, not one per character, so the mask cannot leak a token's length.
    static let mask = String(repeating: "•", count: 12)

    public static func present(_ snapshot: PanelSnapshot) -> PanelPresentation {
        let results = snapshot.results
        let context = PanelRowMemo.Context(
            needle: snapshot.needle, locale: snapshot.locale, now: snapshot.now,
            imagesFolder: snapshot.imagesFolder, formattableLanguages: snapshot.formattableLanguages,
            revealed: snapshot.revealed, missingImages: snapshot.missingImages)
        let rows = snapshot.rowMemo.rows(
            listID: results.listID, results: results.rows, context: context
        ) { result in
            row(for: result, in: snapshot, isSelected: false)
        }
        // An unread list is an unknown, not a nothing, so neither sentence below is said yet.
        let saysNothing = rows.isEmpty && !snapshot.isAwaitingList

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
            emptyState: saysNothing ? emptyState(for: snapshot) : nil,
            // A sheet has its own keys, so the list's line would be teaching the wrong ones.
            hint: hint(for: snapshot, isEmpty: rows.isEmpty),
            sheet: sheet(for: snapshot),
            groups: snapshot.rowMemo.groups(for: results.listID) {
                groups(for: rows, omitted: results.omitted, isSearching: snapshot.isSearching)
            },
            emptyAction: saysNothing ? emptyAction(for: snapshot) : nil,
            notice: snapshot.notice,
            microphone: microphone(for: snapshot.dictation),
            scope: scope(for: snapshot),
            announcements: announcements(for: snapshot),
            announcementIDs: announcementIDs(for: snapshot),
            rowHint: rowHint(for: snapshot.insertion), selectedIndex: results.selectedIndex,
            rowCacheID: snapshot.rowMemo.presentationID
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
            summary: isMasked ? mask : ClipTextSafety.escaped(excerpt ?? clip.summary),
            additionalLineCount: isMasked ? 0 : clip.additionalLineCount,
            preview: isMasked ? mask : ClipTextSafety.escaped(clip.preview),
            kind: clip.kind,
            swatch: !isMasked && clip.kind == .colour
                ? ClipKindDetector.colour(in: clip.text)
                : nil,
            symbolName: symbolName(for: clip.kind),
            when: when,
            detail: detail(of: clip, when: when),
            alias: clip.alias,
            category: PanelSnapshot.name(clip.category),
            isPinned: clip.isPinned,
            isMasked: isMasked,
            isSelected: isSelected,
            matched: result.match,
            measurements: isMasked ? nil : measurements(of: clip, in: snapshot),
            checklist: isMasked ? nil : checklistProgress(of: clip, in: snapshot),
            imageFile: isGone
                ? nil
                : clip.image.flatMap { image in
                    snapshot.imagesFolder?.appending(path: image.file, directoryHint: .notDirectory)
                },
            isImageMissing: isGone,
            // Never on a masked row, which says as little as possible until asked.
            language: isMasked ? nil : clip.language?.chip,
            isMonospaced: isMonospaced(clip.kind),
            containsDisplayHazards: ClipTextSafety.containsDisplayHazards(clip.text),
            actions: actions(for: clip, isMasked: isMasked, in: snapshot)
        )
    }

    /// One symbol per kind, so a row is told apart before it is read.
    static func symbolName(for kind: ClipKind) -> String {
        switch kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .secret: "key"
        case .colour: "paintpalette"
        case .filePath: "folder"
        case .image: "photo"
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
        if clip.image == nil, ClipTextSafety.containsDisplayHazards(clip.text) {
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
        if snapshot.reindentOffers.offers(clip) {
            actions.append(
                PanelAction(
                    title: "Re-indent", symbolName: "text.alignleft",
                    intent: .reindent(clip.id), shortcut: PanelRowAction.reindent.chord))
        }
        // E6 — never on a note already, or promoting replaces what the user wrote, and never on a picture, which has no text.
        if clip.richText == nil, clip.image == nil {
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
        } else if clip.image == nil {
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

    /// What a picture or formatted-text row says, or why a picture cannot. See `Docs/panel.md`.
    static func measurements(of clip: Clip, in snapshot: PanelSnapshot) -> String? {
        guard let image = clip.image else {
            guard clip.richText != nil else { return nil }
            return "\(clip.text.count) characters"
        }
        if snapshot.missingImages.contains(clip.id) {
            return "The picture is no longer on this Mac"
        }
        let weight = fileSize(image.bytes)
        guard let from = clip.source?.trimmingCharacters(in: .whitespaces), !from.isEmpty else {
            return "\(image.dimensions) · \(weight)"
        }
        return "\(from) · \(weight)"
    }

    /// How many checklist boxes are checked, without copying any note text into the row.
    static func checklistProgress(of clip: Clip, in snapshot: PanelSnapshot) -> String? {
        guard let progress = snapshot.checklistProgresses.progress(of: clip) else { return nil }
        return "\(progress.done) of \(progress.total)"
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
}
