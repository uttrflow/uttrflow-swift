// What the panel draws: intents, tabs, actions, rows, chips, and the presenter that builds them.
public import Foundation
public import UttrflowClipboard

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
    /// The tags the user gave it, shown as chips after the name.
    public let tags: [String]
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
    /// The names of a file clip's files in copy order, which a row of several shows only the first of.
    public let fileNames: [String]
    /// Some of a file clip's files have gone, so Return would refuse it; `measurements` says which.
    public let isFileMissing: Bool
    /// D1 — the language chip, short enough for a 420-point row: "ts", not "TypeScript".
    public let language: String?
    /// Whether the summary is monospaced, decided here so the view has no judgement to get wrong.
    public let isMonospaced: Bool
    /// Whether the clip contains invisible or control characters.
    public let containsDisplayHazards: Bool
    /// The real host of a link row, or `nil` for any other row.
    public let linkHost: LinkHostDisplay?
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
        tags: [String] = [],
        category: String?,
        isPinned: Bool,
        isMasked: Bool,
        isSelected: Bool,
        matched: PanelMatchField?,
        measurements: String? = nil,
        checklist: String? = nil,
        imageFile: URL? = nil,
        isImageMissing: Bool = false,
        fileNames: [String] = [],
        isFileMissing: Bool = false,
        language: String? = nil,
        isMonospaced: Bool,
        containsDisplayHazards: Bool = false,
        linkHost: LinkHostDisplay? = nil,
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
        self.tags = tags
        self.category = category
        self.isPinned = isPinned
        self.isMasked = isMasked
        self.isSelected = isSelected
        self.matched = matched
        self.measurements = measurements
        self.checklist = checklist
        self.imageFile = imageFile
        self.isImageMissing = isImageMissing
        self.fileNames = fileNames
        self.isFileMissing = isFileMissing
        self.language = language
        self.isMonospaced = isMonospaced
        self.containsDisplayHazards = containsDisplayHazards
        self.linkHost = linkHost
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
            revealed: snapshot.revealed, missingImages: snapshot.missingImages,
            missingFiles: snapshot.missingFiles)
        let rows = PanelCache.current.rowMemo.rows(
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
            groups: PanelCache.current.rowMemo.groups(for: results.listID, in: context) {
                groups(for: rows, omitted: results.omitted, isSearching: snapshot.isSearching)
            },
            emptyAction: saysNothing ? emptyAction(for: snapshot) : nil,
            notice: snapshot.notice,
            microphone: microphone(for: snapshot.dictation),
            scope: scope(for: snapshot),
            announcements: announcements(for: snapshot),
            announcementIDs: announcementIDs(for: snapshot),
            rowHint: rowHint(for: snapshot.insertion), selectedIndex: results.selectedIndex,
            rowCacheID: PanelCache.current.rowMemo.presentationID
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
            tags: clip.tags,
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
            fileNames: clip.files?.map(\.name) ?? [],
            isFileMissing: snapshot.missingFiles[clip.id] != nil,
            // Never on a masked row, which says as little as possible until asked.
            language: isMasked ? nil : clip.language?.chip,
            isMonospaced: isMonospaced(clip.kind),
            containsDisplayHazards: ClipTextSafety.containsDisplayHazards(clip.text),
            linkHost: isMasked || clip.kind != .link ? nil : LinkHostDisplay.parse(clip.text),
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
        case .file: "doc.on.doc"
        }
    }

    /// What a picture or formatted-text row says, or why a picture cannot. See `Docs/panel.md`.
    static func measurements(of clip: Clip, in snapshot: PanelSnapshot) -> String? {
        if clip.files != nil {
            return snapshot.missingFiles[clip.id].map { PanelNotice.filesMissing($0).message }
        }
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
        guard let progress = PanelCache.current.checklistProgresses.progress(of: clip) else { return nil }
        return "\(progress.done) of \(progress.total)"
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
