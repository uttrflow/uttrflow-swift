public import Foundation
public import UttrflowClipboard

/// What choosing something on a row means.
///
/// Named rather than carried as a closure, for the reason ``MainIntent`` gives: a row has
/// to be comparable in a test, and a closure is not.
public enum PanelIntent: Sendable, Equatable {
    /// Put this clip where the cursor was, and close. Exactly what Return does.
    case insert(Clip.ID)
    /// Put it back on the clipboard without pasting it, for a paste the user will make
    /// themselves, somewhere the panel cannot reach.
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
    /// F9 — put back the clip the last delete removed.
    ///
    /// Carries no identity because the clip no longer has one the panel can see: the
    /// store has forgotten it and only the app is still holding it.
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

    /// The keystroke this intent is, where the panel can answer it itself.
    ///
    /// `nil` for the ones only the store can carry out. The mapping lives here so that a
    /// row's Insert button and the Return key are provably one path: a second
    /// implementation of "insert the clip on this row" is a second thing to keep in step
    /// with the first, and the day they part is the day the mouse and the keyboard paste
    /// different clips.
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
        // D5 belongs here and not above. Running a formatter means running another
        // program, which this model cannot do, so the app has to hear about it. It used
        // to answer `.format` with a key, and both the view and the app short-circuit on
        // a key — so the intent went to the model, the model had nothing to do with it,
        // and the button did nothing at all. A key here is not a small inaccuracy; it is
        // the difference between the action happening and not.
        case .scope(let scope): .scope(scope)
        case .format, .copy, .pin, .unpin, .undoDelete, .keepQuery, .openAccessibilitySettings,
            .openSettings, .dictate:
            nil
        }
    }
}

/// What a bottom-bar button is drawn with.
///
/// Two cases rather than a string, because one of the four tabs is Uttrflow's own and the
/// mark is a `Shape` rather than anything a name can fetch. The alternative was a
/// reserved symbol name the view knew to intercept — a string that means "not a string",
/// which the copy tests cannot tell apart from a typo in a real one.
public enum PanelTabGlyph: Sendable, Equatable {
    case symbol(String)
    /// The Uttrflow mark, drawn at the size the bar asks for. Carries no colour of its
    /// own; the bar tints it like every other glyph, active or dim.
    case brandMark
}

/// One button in the bottom bar.
///
/// `intent` rather than a bare scope, because the bar mixes two kinds of thing: four
/// slices of the clipboard and one way out of it. A view that had to tell them apart
/// would be deciding, which is not its job.
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
    /// Whether this action takes something away.
    ///
    /// Decided here rather than inferred by whoever draws it. The view's guess would have
    /// been the trash symbol or the last position in the list, and both are true of Delete
    /// today by coincidence: an action added after it, or given a different icon, would
    /// silently stop being marked.
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
    /// How long ago, in words: "2 minutes ago".
    ///
    /// No longer drawn on the row. It said "1 day ago" on eleven rows at once — a column
    /// repeating itself down the panel, answering a question nobody asks while scanning.
    /// It survives inside ``detail``, which the ⋯ menu puts above one clip at the moment
    /// that clip is being asked about.
    public let when: String
    /// The line under the clip's own words in the ⋯ menu: what it is, when it arrived and
    /// where from — "Text · 41 minutes ago · Claude".
    ///
    /// Assembled here because each part is a presentation decision and two of them are
    /// conditional: a clip old enough to predate the source being recorded has no "where
    /// from", and saying so would be a dangling separator.
    public let detail: String
    /// The handle the user gave it, shown as they typed it.
    public let alias: String?
    public let category: String?
    public let isPinned: Bool
    /// Whether what is drawn is bullets rather than the clip. Said out loud so the view
    /// can mark the row, and so nothing downstream mistakes the bullets for the text.
    public let isMasked: Bool
    public let isSelected: Bool
    /// Why this row is in the list. `nil` when nothing was typed and every clip is here.
    public let matched: PanelMatchField?
    /// K4 — what a picture clip says about itself: "PNG · 1024 × 768 · 240 KB".
    ///
    /// A picture has no text, so without this its row is a blank line with an icon. The
    /// numbers are what distinguishes one screenshot from the four below it.
    public let measurements: String?
    /// K4 — the picture to draw beside the row, or `nil` when there is none to draw.
    public let imageFile: URL?
    /// B8 — the picture this row is about is no longer on disk.
    ///
    /// The row stays: the clip is still a real record of something copied, and removing it
    /// would look like the app had lost it rather than the file having gone.
    public let isImageMissing: Bool
    /// E5 — how much of a checklist is done, as "2 of 5", or `nil` when the clip has no
    /// boxes. A checklist is the one kind of note whose state is the interesting part.
    public let checklist: String?
    /// D1 — the language chip, or `nil` when there is no confident answer. Short, because
    /// it sits on a 420-point row: "ts", not "TypeScript".
    public let language: String?
    /// Whether the summary is set in a monospaced face. Decided here, like everything
    /// else about the row, so that the view has no judgement of its own to get wrong.
    public let isMonospaced: Bool
    public let actions: [PanelAction]

    /// C6 — the whole line, shown after a pause, because a row truncates and a pointer
    /// resting on one is a question about the rest.
    ///
    /// `nil` on a masked row. Not because the secret would otherwise escape — ``summary``
    /// is already bullets by then, so the tooltip would show bullets too — but because a
    /// tooltip exists to give back what the row had to cut, and a masked row cut nothing
    /// the pointer is entitled to. A panel of bullets appearing under the cursor would
    /// read as the mask being lifted, and it is not.
    ///
    /// Here rather than in the view, where it used to be a conditional on `.help` that no
    /// test could reach — the same place the menu bar's lost shift modifier was hiding.
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
    /// The ⌘-number printed beside it. Absent past the ninth, because there is no ⌘10
    /// and printing a shortcut that does not work is worse than printing none.
    public let shortcut: Int?
    /// Which collection this is, counting from 2 — 1 belongs to "everything".
    ///
    /// Separate from ``shortcut`` because they answer different questions. A shortcut is
    /// what is *printed*, and stops at the ninth; a position is what pressing the chip
    /// *means*, and does not. Reusing the shortcut for both made every collection past
    /// the ninth send 0, which the snapshot rejects — so the tenth chip was drawn like
    /// the others, said nothing about being different, and did nothing when clicked.
    public let position: Int
    public let isActive: Bool

    /// The number pressing this chip sends.
    ///
    /// Its own position, unless this is already the collection being shown — then 1,
    /// which means everything. That is the whole way out of a collection: press it
    /// again. There is no "All" chip beside the collections, because the row they share
    /// already begins with the kind filters' own All, and two chips reading "All" a few
    /// points apart, meaning different things, reads as a bug rather than a choice.
    public var chosen: Int { isActive ? 1 : position }

    /// Distinct even from a collection somebody has named "All": the identity is the
    /// collection itself, and the chip that shows everything is the one with no
    /// collection behind it.
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
    /// Empty when nothing has been filed anywhere: a lone "All" chip is a row of the
    /// panel spent telling the user something they can already see.
    public let categories: [PanelCategoryChip]
    public let query: String
    public let searchPlaceholder: String
    /// Set when — and only when — ``rows`` is empty, and it says which of the four
    /// nothings this is.
    public let emptyState: MainEmptyState?
    /// The line along the bottom that teaches the three keystrokes.
    public let hint: String
    /// Where the clips live, said out loud along the very bottom.
    ///
    /// A panel holding everything the user has copied invites the question, and the
    /// answer has to be here rather than in the view. This line replaced one that said
    /// the history was "synced across devices", under a tick — a sentence copied from
    /// the reference design of a product that does sync, describing one that does not.
    /// It was in the view, where the copy tests cannot see it, which is exactly how it
    /// survived; every other word the panel says is decided here for that reason.
    /// The sheet on top of the list — naming, filing or confirming a delete — or `nil`
    /// when the panel is just a list.
    public let sheet: PanelSheetPresentation?
    /// H1 — the same rows, cut into the runs the list is drawn in. Empty when nothing
    /// has been typed, because then no row is here for a reason worth heading.
    public let groups: [PanelResultGroup]
    /// H3 — the one thing to do about an empty result set, or nothing when there is
    /// nothing sensible to offer. Separate from ``MainEmptyState/action``, which speaks
    /// the main window's vocabulary rather than the panel's.
    public let emptyAction: PanelAction?
    /// B3–B5 — what the panel is saying about a clip it could only copy.
    public let notice: PanelNotice?
    /// I1–I7 — the microphone, and what it can do right now.
    public let microphone: PanelMicrophone
    /// H7 — what the list is scoped to, when that differs from the chip the user last
    /// pressed. `nil` while browsing, where the active chip already says it.
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

    /// The row Return would insert. Lets the view scroll it into sight, and lets the app
    /// aim a row action at it, without either of them counting rows for itself.
    public var selectedRow: PanelRow? { rows.first { $0.isSelected } }
}

/// Turns the panel's state into the panel.
///
/// Pure, and the only place that decides what the panel says. The view draws exactly
/// this, so the highlight, the mask over a secret and the words under the list cannot
/// tell three different stories about the same moment.
public enum PanelPresenter {
    /// Says what the field is for *and* teaches the one thing that makes the panel fast.
    public static let searchPlaceholder = "Search, or type an alias"

    /// What is drawn under an empty list is the truth about why it is empty; what is
    /// drawn under a full one is the gesture, because the panel is most people's first
    /// and last lesson in how it works.
    public static let hint = "↑↓ to choose · ⏎ to paste · esc to close"
    public static let emptyHint = "esc to close"
    /// While a sheet is up, `esc` backs out of it rather than closing the panel and
    /// Return commits it rather than pasting. Saying so is the difference between one
    /// press of esc and two by reflex, the second of which loses the list.
    public static let sheetHint = "⏎ to save · esc to go back"
    /// Offered, not merely available. F7 trades the confirmation dialog away *for* this
    /// undo, so an undo nobody is told about turns that trade into a loss — the clip is
    /// gone with neither a question beforehand nor a way back afterwards.
    public static let undoHint = "Deleted · ⌘Z to put it back"

    /// Which line goes under the list.
    ///
    /// The undo takes precedence while it is live, because it expires in seconds and the
    /// keys it displaces are on screen every other moment of the panel's life.
    static func hint(for snapshot: PanelSnapshot, isEmpty: Bool) -> String {
        if snapshot.sheet != nil { return sheetHint }
        if snapshot.canUndoDelete { return undoHint }
        return isEmpty ? emptyHint : hint
    }

    /// A fixed number of bullets, not one per character.
    ///
    /// The length of a token is worth something to whoever is looking over the user's
    /// shoulder, and a mask that leaks it is a mask that only pretends to work.
    static let mask = String(repeating: "•", count: 12)

    public static func present(_ snapshot: PanelSnapshot) -> PanelPresentation {
        let results = snapshot.results
        let rows = results.rows.enumerated().map { position, result in
            row(for: result, in: snapshot, isSelected: position == results.selectedIndex)
        }

        return PanelPresentation(
            rows: rows,
            // Off entirely while a collection is the chosen chip. The kind is `.all` in
            // that state, so without this the row would light All *and* the collection —
            // two chips on at once, which is the thing the single-selection rule exists
            // to prevent.
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
            // A sheet has its own keys, so the line teaching the list's keys would be
            // teaching the wrong ones while one is open.
            hint: hint(for: snapshot, isEmpty: rows.isEmpty),
            sheet: sheet(for: snapshot),
            groups: groups(
                for: rows, omitted: results.omitted,
                isSearching: !snapshot.query.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty),
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
        // H5 — a content match further down a long clip is shown where it was found. A
        // masked clip is never re-cut: the mask is the whole point, and an excerpt around
        // the match would print the part of the secret the user searched for.
        let excerpt =
            isMasked || result.match != .content
            ? nil
            : self.excerpt(
                of: clip.text,
                around: snapshot.query.trimmingCharacters(in: .whitespacesAndNewlines),
                locale: snapshot.locale)
        return PanelRow(
            id: clip.id,
            summary: isMasked ? mask : (excerpt ?? clip.summary),
            kind: clip.kind,
            symbolName: symbolName(for: clip.kind),
            // The same words the history page uses for the same user's own moments: two
            // lists that describe "just now" differently make the app look assembled.
            when: HistoryPresenter.when(
                clip.copiedAt, relativeTo: snapshot.now, locale: snapshot.locale),
            detail: detail(of: clip, in: snapshot),
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
            // E5 — a ticked box is content, so its count belongs on the row. Not on a
            // masked one: how much of a hidden thing is done is still something about it.
            checklist: isMasked
                ? nil
                : clip.richText.flatMap(NoteChecklist.progress(in:)).map {
                    "\($0.done) of \($0.total)"
                },
            // Never on a masked row. The language of a credential is not a secret, but a
            // chip is one more thing on a row whose entire point is to say as little as
            // possible until the user asks.
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

    /// Where the characters matter one by one rather than as words. A masked secret is
    /// bullets and set the same way, so revealing one does not make the row jump.
    static func isMonospaced(_ kind: ClipKind) -> Bool {
        switch kind {
        // A path is monospaced for the same reason code is: it is read character by
        // character, and a mistyped one fails in a way that looks like a missing file.
        case .code, .colour, .secret, .filePath: true
        case .text, .link, .image: false
        }
    }

    /// Insert first, because it is what the row is for. Reveal comes next on a masked
    /// row — it is the thing that has to happen before the user can judge the rest — and
    /// pinning is last, because it is about tomorrow rather than about this second.
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
        // Reads Rename when there is already a name: "Name" over a clip that has one
        // invites the user to expect a second alias rather than a change to the one it has.
        actions.append(
            PanelAction(
                title: clip.alias == nil ? "Name" : "Rename", symbolName: "tag",
                intent: .alias(clip.id)))
        actions.append(PanelAction(title: "Move", symbolName: "folder", intent: .move(clip.id)))
        // D4 — offered only when it would do something. `reindented` answers `nil` both for
        // a clip that is already consistent and for every clip it cannot be certain about,
        // so the presence of this action is itself the promise that pressing it is safe.
        // D5 — offered only where a formatter for that language is installed. Never
        // automatic: a formatter rewrites code, and the user asks for that or it does not
        // happen.
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
        // E6 — offered only on a clip that is not already a note. Promoting twice would
        // replace a note the user has written with a fresh copy of its own plain text,
        // which is the one way this action could destroy something.
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

    /// K4 — what a picture row says about itself, and B8 — what it says instead when the
    /// picture has gone. The reason replaces the numbers rather than joining them: the
    /// size of a file that is not there is not the useful half.
    /// What a picture row says about itself: where it came from, and what it weighs.
    ///
    /// The application, not the pixel dimensions, because the question a row has to
    /// answer is "which screenshot is this" and 922 × 1362 does not answer it. The name
    /// of the file would be better still and there is never one: a screenshot copied
    /// with the keyboard puts raw PNG on the pasteboard and nothing else — no URL, no
    /// name — and an image file copied in Finder arrives as a path, which becomes a file
    /// clip whose row already shows that path. So the application it was taken from is
    /// the identifying thing that actually exists, and it is the one people recognise.
    ///
    /// Dimensions are the fallback rather than the answer, for the clips old enough to
    /// predate the source being recorded.
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

    /// What the ⋯ menu says under the clip's own words.
    ///
    /// Three parts, joined only where they exist. The kind is named as the user would name
    /// it rather than as the enum spells it; the source is absent on clips that predate it
    /// being recorded, and on anything Uttrflow made it is the word "Dictation", which is
    /// the one case where the provenance is worth more than the application name.
    static func detail(of clip: Clip, in snapshot: PanelSnapshot) -> String {
        var parts = [noun(for: clip.kind).capitalized]
        parts.append(
            HistoryPresenter.when(
                clip.copiedAt, relativeTo: snapshot.now, locale: snapshot.locale))
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

    /// The collection the row draws as chosen, which is not always the one the snapshot
    /// holds.
    ///
    /// While there is a query the search spans every collection, so drawing one as chosen
    /// would tell the user their search had been narrowed when it had not — and the rows
    /// from other collections would read as a bug. The snapshot keeps its collection
    /// regardless: this is what is *shown*, and emptying the field brings it straight
    /// back.
    static func shownCategory(for snapshot: PanelSnapshot) -> String? {
        let searching = !snapshot.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return searching ? nil : PanelSnapshot.name(snapshot.category)
    }

    static func categories(for snapshot: PanelSnapshot) -> [PanelCategoryChip] {
        let names = snapshot.categories
        guard !names.isEmpty else { return [] }

        // While there is a query the search spans every tab, so All is the chip that is
        // true. Drawing the open tab as active over a result set that is not confined to
        // it would tell the user their search had been narrowed when it had not — and
        // the rows from other tabs would read as a bug.
        //
        // The snapshot keeps its category regardless: this is what is *shown*, and
        // emptying the search field brings the tab straight back.
        let active = shownCategory(for: snapshot)
        // No "All" chip at all.
        //
        // The collections share a row with the kind filters, and that row already begins
        // with an "All" meaning every *kind*. A second one a few points away meaning
        // every *collection* reads as a bug rather than as a choice — and drawing it
        // only while a collection was chosen just moved the confusion to the moment
        // somebody was looking at it.
        //
        // The way out of a collection is the collection itself, pressed again; see
        // `PanelCategoryChip.chosen`. Command-1 still means everything, so the
        // collections keep numbering from 2 whether anything is drawn for 1 or not.
        var chips: [PanelCategoryChip] = []
        for (offset, name) in names.enumerated() {
            let number = offset + 2
            chips.append(
                PanelCategoryChip(
                    title: name, category: name,
                    shortcut: number <= PanelSnapshot.shortcutLimit ? number : nil,
                    position: number,
                    isActive: active == name))
        }
        return chips
    }

    /// The bottom bar: the four slices of the clipboard, then the way to settings.
    ///
    /// Settings is last and never drawn as active, because it is not a place the panel
    /// can be — it is a door out of it. Everything before it is somewhere the list can
    /// actually be, and exactly one of those is on.
    ///
    /// The order is ``PanelScope``'s own, which puts From Uttrflow second — beside
    /// History, since the two are the same question asked of two streams, and before the
    /// two tabs that are about what the user did with a clip rather than where it came
    /// from.
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

    /// Where the panel is looking, for the sentence an empty one has to write.
    ///
    /// Four strings rather than one, because the same place is named differently depending
    /// on what else is narrowing: "Nothing pinned" on its own, "No Code pinned" as a title
    /// beside a kind, and "Nothing you have pinned is code" as the sentence under it.
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
        let query = snapshot.query.trimmingCharacters(in: .whitespacesAndNewlines)

        // A clipboard with nothing in it, which is the only one of these that is about
        // the clipboard rather than about what the user has narrowed it to.
        if snapshot.clips.isEmpty {
            return MainEmptyState(
                symbolName: "doc.on.clipboard",
                title: "Nothing copied yet",
                message: "Whatever you copy turns up here, ready to put back.")
        }

        // An arrivals tab emptied by the user having put everything away, which is a
        // different thing from never having copied anything and now common enough to be
        // worth telling apart: pinning and filing both take a clip out of here, so
        // somebody who keeps a tidy clipboard arrives at an empty History with fifty clips
        // in the panel. "Nothing copied yet" over a full clipboard is the specific-and-
        // wrong sentence this file has been corrected for twice.
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

        // A search spans everything by design, so nothing else is narrowing here and
        // naming the tab would be describing a constraint that is not applied.
        if !query.isEmpty {
            return MainEmptyState(
                symbolName: "magnifyingglass",
                title: "No matches",
                // "Nothing you have copied" was true while the clipboard was one list.
                // A search now spans what Uttrflow made as well, and on a clipboard of
                // nothing but dictations that sentence told the user their search had
                // looked somewhere it had not.
                message: "Nothing on your clipboard mentions “\(query)”.")
        }

        return narrowedEmptyState(for: snapshot)
    }

    /// Which arrivals tab this is, if it is one.
    ///
    /// The two that list what has not been put anywhere. Pinned and Collections are the
    /// places clips are put, so an empty one of those means the user has not put anything
    /// there — which their own sentences already say.
    static func arrivalsOrigin(of scope: PanelScope) -> ClipOrigin? {
        switch scope {
        case .history: .copied
        case .uttrflow: .uttrflow
        case .pinned, .collections: nil
        }
    }

    /// What to say when the clipboard has clips in it and the narrowing has hidden all
    /// of them.
    ///
    /// Assembled from the narrowings that are actually on, rather than picked from the
    /// first one that matches. Picking the first is how the panel came to say "Nothing
    /// in db — nothing you have copied is filed here" while the Code filter was also on:
    /// there were clips in db, and the sentence told the user there were not. An empty
    /// state that names one of two reasons is worse than a vague one, because it is
    /// specific and wrong.
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

    /// Where the user is looking: a tab, a collection, or both at once.
    ///
    /// Total, since History stopped meaning everything. It used to answer `nil` for
    /// History with no collection, because that combination narrowed by kind alone and
    /// there was no place to name — and the sentence for it was written separately. Now
    /// History is "what you copied", so it has a name like the other three, and the
    /// separate sentence would have been a second place deciding the same words. What an
    /// empty History says therefore gained the word: "No Links **copied**", beside "No
    /// Code pinned" and "No Code filed", which is the shape the table was already in.
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
            // Named as both, because it is both. The shared arm below says "Nothing in
            // db — nothing you have copied is filed here", and on this tab every clause
            // of that is false: db is not empty, the clips in it were not copied, and
            // the reason the list is empty is the tab rather than the collection. That is
            // the same specific-and-wrong sentence this table was corrected for once
            // before, arriving on a new axis.
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
                // A waveform rather than the mark: this is the glyph above a sentence,
                // where a logo would read as branding on an empty screen, and the tab
                // that got the user here is already wearing it.
                symbolName: "waveform", title: "Nothing from Uttrflow", suffix: "from Uttrflow",
                subject: "Uttrflow has made",
                alone: "Dictate something and it waits here, out of the way of what you copy.")
        case (.history, .none):
            PanelEmptyPlace(
                symbolName: "doc.on.clipboard", title: "Nothing copied yet", suffix: "copied",
                subject: "you have copied",
                // The same sentence a wholly empty clipboard gets, and deliberately so:
                // this tab is now reachable while the clipboard holds a hundred
                // dictations and not one ⌘C, and in that state "nothing copied yet" is
                // the plain truth rather than a claim about the file.
                alone: "Whatever you copy turns up here, ready to put back.")
        }
    }
}
