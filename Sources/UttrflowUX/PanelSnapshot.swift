public import Foundation
public import UttrflowClipboard

/// The tabs across the top of the panel.
///
/// Five, and no more: the tabs are aimed at with a glance rather than read, and a row of
/// them long enough to need reading costs more than the filtering saves. Everything the
/// user copies lands under exactly one of them, so nothing is reachable by search alone.
/// Which slice of the clipboard the bottom bar is showing.
///
/// A different axis from ``PanelFilter``, which is about what a clip *is*. This is about
/// how the user has treated it — kept, filed, or neither — so the two combine rather than
/// override: Pinned and Images together are the pictures worth keeping.
///
/// The bar existed before this did. Its four buttons were drawn, three of them disabled
/// and the fourth wired to an empty closure, so every one of them was dead. They are the
/// most reachable controls on the panel, which is a poor place to keep decoration.
public enum PanelScope: String, Sendable, Equatable, CaseIterable, Codable {
    case history
    /// What Uttrflow itself made — dictations, and clips kept from the panel.
    ///
    /// Its own tab rather than a heading inside History, because the two are filled at
    /// different rates: a dictation happens every minute or two and a ⌘C happens when it
    /// happens, so in one list the dictations are always the newest thing and always at
    /// the top. Separating them is the only arrangement in which the recency of either
    /// means anything. See ``ClipOrigin``.
    case uttrflow
    case pinned
    case collections

    public var title: String {
        switch self {
        case .history: "History"
        case .uttrflow: "From Uttrflow"
        case .pinned: "Pinned"
        case .collections: "Collections"
        }
    }

    /// What the tab is drawn with.
    ///
    /// Not a symbol name for every case, because ``uttrflow`` is drawn with the mark
    /// itself: no SF Symbol says "this app", and the nearest ones — a waveform, a
    /// microphone — say "dictation", which is only half of what the tab holds. The
    /// presenter still decides, and the view still only draws; it is the vocabulary that
    /// has grown a second word.
    public var glyph: PanelTabGlyph {
        switch self {
        case .history: .symbol("doc.on.clipboard")
        case .uttrflow: .brandMark
        // A pin, not a star. The row draws `pin.fill` on a pinned clip and the tab drew a
        // star for the same idea, so the panel had two glyphs for one thing and neither
        // taught the other. A star also means "favourite" on this platform, which is a
        // judgement about a clip; a pin is a place you put one.
        case .pinned: .symbol("pin")
        case .collections: .symbol("tag")
        }
    }

    /// Whether this tab shows a given clip.
    ///
    /// - Parameters:
    ///   - clip: The clip being considered.
    ///   - inCollection: Whether a collection chip is currently chosen. It has to be
    ///     asked, because otherwise the two arrivals tabs and a collection chip contradict
    ///     each other and the list is empty every time: History shows what has not been
    ///     put anywhere, a chip asks for what was put in one, and nothing is both.
    ///     Choosing a collection means the collection is the place being looked at, so the
    ///     filing stops being a reason to hide the clip — while a pin still is, because
    ///     that is a different place with a tab of its own.
    /// - Returns: Whether the clip belongs in this tab as it is currently narrowed.
    public func admits(_ clip: Clip, inCollection: Bool = false) -> Bool {
        switch self {
        // No longer everything: History is what the user copied. What Uttrflow made is
        // one tab along, and a search reaches both — see ``PanelSnapshot/results``.
        //
        // And neither shows a pinned clip. Pinning is the user saying "keep this where I
        // can find it", and a clip that answered from two tabs at once made the Pinned tab
        // a second copy of the list rather than a place: every pin doubled a row, and the
        // longer you used the panel the more of History was things you had already filed
        // away. A pin moves a clip; it does not duplicate it.
        case .history:
            clip.origin == .copied && !PanelSnapshot.isPutAway(clip, inCollection: inCollection)
        case .uttrflow:
            clip.origin == .uttrflow && !PanelSnapshot.isPutAway(clip, inCollection: inCollection)
        // Both origins, deliberately. These two are about what the user did with a clip
        // rather than where it came from, and somebody who pinned a dictation pinned it
        // to have it beside the rest of what they pinned — which is now the only place it
        // is, since the two above let it go.
        case .pinned: clip.isPinned
        case .collections: PanelSnapshot.name(clip.category) != nil
        }
    }
}

public enum PanelFilter: String, Sendable, Equatable, CaseIterable, Codable {
    case all
    case text
    case links
    case code
    case images

    /// The label on the tab.
    public var title: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .links: "Links"
        case .code: "Code"
        case .images: "Images"
        }
    }

    /// What this tab admits, as a sentence about one clip would name it.
    ///
    /// Read only where a tab has nothing under it. ``all`` has a noun so the table is
    /// total rather than because it will ever be read: while anything at all has been
    /// copied, All has something in it.
    var noun: String {
        switch self {
        case .all: "a clip"
        case .text: "plain text"
        case .links: "a link"
        case .code: "code"
        case .images: "an image"
        }
    }

    /// Whether a clip belongs under this tab.
    ///
    /// Every kind is admitted by exactly one tab besides ``all``. A kind admitted by none
    /// would be findable only by searching for it, which the user would experience as the
    /// app having lost it. ``ClipKind/secret`` and ``ClipKind/colour`` sit under Text
    /// because that is what they are — a token and a hex code are both text somebody
    /// copied out of a document, and giving either its own tab would advertise the one
    /// thing this panel exists to keep quiet about.
    public func admits(_ kind: ClipKind) -> Bool {
        switch self {
        case .all: true
        case .text: kind == .text || kind == .secret || kind == .colour || kind == .filePath
        case .links: kind == .link
        case .code: kind == .code
        case .images: kind == .image
        }
    }
}

/// Everything the panel is drawn from, and everything a keystroke can change.
///
/// One value rather than a view's scattered pieces of state. The whole product is three
/// keystrokes — ⇧⌘V, down twice, Return — so every one of them has to be reproducible
/// exactly, in a test, without a screen. A field held by the view is a field the model
/// cannot reason about, and the first thing to go wrong would be the one thing this panel
/// must never get wrong: which clip Return means.
public struct PanelSnapshot: Sendable, Equatable {
    /// The highest ⌘-number a category chip can be given. Nine because there is no ⌘10,
    /// and because ⌘0 already opens the main window from the menu bar.
    public static let shortcutLimit = 9

    /// Newest first, in the order the store keeps them.
    ///
    /// Not re-sorted here for the reason the history page gives: the clock belongs to
    /// whoever wrote the list, and a Mac whose clock moved must not be able to shuffle
    /// the rows under a user who is counting them.
    public var clips: [Clip]
    /// What has been typed into the search field.
    public var query: String
    public var filter: PanelFilter
    /// Which slice the bottom bar is showing. Combines with ``filter`` rather than
    /// replacing it; see ``PanelScope``.
    public var scope: PanelScope = .history
    /// The collection being shown, or `nil` for all of them.
    public var category: String?
    /// The clip the user has arrowed to, held by identity rather than by row number.
    ///
    /// A row number would point at a different clip the moment anything is copied while
    /// the panel is open: the list is newest-first, so a new clip pushes every row down
    /// and the highlight would silently slide onto the neighbour of the one being aimed
    /// at. `nil` means "wherever the top is" — where a freshly opened panel sits, and
    /// where every change to what is listed puts it back.
    public var selection: Clip.ID?
    /// The sheet on top of the list — naming a clip, filing it, or confirming a delete
    /// — or `nil` when the panel is just a list.
    ///
    /// Part of the snapshot rather than the view because `esc` and Return mean different
    /// things depending on it, and a view that owned this would be a second place that
    /// decides what a key does.
    public var sheet: PanelSheet?

    /// Whether a delete can still be taken back.
    ///
    /// Set by the app, which is the only thing holding the deleted clip — the store has
    /// forgotten it. Here so that the panel can *offer* the undo: an undo nobody is told
    /// about is one only the author of the shortcut will ever use.
    public var canUndoDelete: Bool = false

    /// B3–B5 — whether choosing a clip will place it at the caret or only copy it.
    ///
    /// Set by the app when the panel opens: it is a fact about the machine at that
    /// moment, not something the panel can work out. Defaults to the good case so that
    /// every test that does not care about it reads as the ordinary path.
    public var insertion: PanelInsertion = .atCaret

    /// What the panel is saying about the last thing it did, if anything.
    ///
    /// Set by the app after an outcome it has to report, and cleared when the panel next
    /// opens. On the snapshot rather than the view so the sentence is decided in the one
    /// place every other word of the panel is decided.
    public var notice: PanelNotice?

    /// I1–I7 — what the panel's microphone is doing. Set by the app, which owns the
    /// pipeline; the panel only draws it and says what pressing it would do.
    public var dictation: PanelDictation = .ready

    /// K4 — where the pictures are kept, so a row can name the file it should draw.
    ///
    /// Handed in rather than known, because the folder belongs to the store and this
    /// module has no business computing paths.
    public var imagesFolder: URL?
    /// B8 — the picture clips whose files are no longer on disk.
    ///
    /// Worked out by the app when it loads the list, not here: whether a file exists is a
    /// question about the machine at a moment, and a presenter that asked it would give a
    /// different answer every time it was called with the same input.
    public var missingImages: Set<Clip.ID> = []

    /// D5 — the languages a formatter is actually installed for.
    ///
    /// Asked of the machine by the app when the panel opens, because it is a question
    /// about what is on this disk. An action offered where no formatter exists is an offer
    /// that fails when pressed, which is worse than no offer.
    public var formattableLanguages: Set<CodeLanguage> = []
    /// The secrets the user has deliberately unmasked.
    ///
    /// A wish about identities rather than a flag on a clip: the store owns the clips,
    /// and a reveal must not outlive the panel it was asked for. The panel is built anew
    /// each time it opens, so nothing is ever revealed twice over.
    public var revealed: Set<Clip.ID>
    /// The clock the timestamps are measured against. Injected, so that a row saying
    /// "2 minutes ago" says it in a test as reliably as it does on screen.
    public var now: Date
    /// Carried in the state rather than passed to each transition, because a keystroke's
    /// meaning depends on it: whether what was typed *is* a clip's alias is decided by
    /// folding case and accents, and a transition taking an environment parameter would
    /// be one the app could drive two different ways on the same panel.
    public var locale: Locale

    public init(
        clips: [Clip],
        query: String = "",
        filter: PanelFilter = .all,
        category: String? = nil,
        selection: Clip.ID? = nil,
        revealed: Set<Clip.ID> = [],
        sheet: PanelSheet? = nil,
        now: Date,
        locale: Locale = .autoupdatingCurrent
    ) {
        self.clips = clips
        self.query = query
        self.filter = filter
        self.category = category
        self.selection = selection
        self.revealed = revealed
        self.sheet = sheet
        self.now = now
        self.locale = locale
    }

    /// The collections the clips are filed into, in the order they are first met.
    ///
    /// Derived rather than stored, so a category cannot outlive the last clip in it and
    /// leave a chip that shows an empty list. First-met order rather than alphabetical
    /// because the numbers beside them are muscle memory: sorting would renumber
    /// somebody's ⌘2 the day they file a clip under "Addresses".
    public var categories: [String] {
        var seen: [String] = []
        for clip in clips {
            guard let name = Self.name(clip.category), !seen.contains(name) else { continue }
            seen.append(name)
        }
        return seen
    }

    /// Whether the user has given this clip somewhere else to live.
    ///
    /// The two tabs of arrivals — History and From Uttrflow — show what has *not* been put
    /// anywhere, so that a clip appears in exactly one place and the panel's tabs are
    /// places rather than overlapping views of one list. Otherwise every pin and every
    /// filing doubled a row, and the longer the panel was used the more of History was
    /// things the user had already dealt with.
    ///
    /// Deliberately not ``Clip/isKept``, which counts an alias too. An alias is a name,
    /// not a place: there is no Aliased tab for a clip to move to, so a clip that left
    /// History for having been named would be reachable only by somebody who remembered
    /// the name — which is the opposite of what naming it was for.
    static func isPutAway(_ clip: Clip, inCollection: Bool = false) -> Bool {
        if clip.isPinned { return true }
        return !inCollection && name(clip.category) != nil
    }

    /// A category name as it is compared and drawn, or `nil` if it is no name at all.
    ///
    /// Blank is treated as absent so a clip filed under a space cannot produce a chip
    /// with nothing written on it, which the user would read as a bug and click anyway.
    static func name(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
