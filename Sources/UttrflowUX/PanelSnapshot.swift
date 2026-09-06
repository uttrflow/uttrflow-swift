// The panel's state: the scope and filter tabs, and the snapshot every keystroke transforms.
public import Foundation
public import UttrflowClipboard

/// Which slice of the clipboard the bottom bar shows: kept, filed, or neither. Combines with ``PanelFilter``.
public enum PanelScope: String, Sendable, Equatable, CaseIterable, Codable {
    /// What the user copied and has not pinned or filed.
    case history
    /// What Uttrflow itself made — dictations and clips kept from the panel; see ``ClipOrigin``.
    case uttrflow
    /// What the user pinned, whichever origin it has.
    case pinned
    /// What the user filed into a collection.
    case collections

    /// The label on the button.
    public var title: String {
        switch self {
        case .history: "History"
        case .uttrflow: "From Uttrflow"
        case .pinned: "Pinned"
        case .collections: "Collections"
        }
    }

    /// What the tab is drawn with; ``uttrflow`` uses the mark itself, since no SF Symbol says "this app".
    public var glyph: PanelTabGlyph {
        switch self {
        case .history: .symbol("doc.on.clipboard")
        case .uttrflow: .brandMark
        // A pin, not a star: the row draws a pin for the same idea, and a star means "favourite" here.
        case .pinned: .symbol("pin")
        case .collections: .symbol("tag")
        }
    }

    /// Whether this tab shows a clip; a chosen collection stops filing hiding it, while a pin still does.
    public func admits(_ clip: Clip, inCollection: Bool = false) -> Bool {
        switch self {
        // History is what the user copied and has not put away; a pin moves a clip, never duplicates it.
        case .history:
            clip.origin == .copied && !PanelSnapshot.isPutAway(clip, inCollection: inCollection)
        case .uttrflow:
            clip.origin == .uttrflow && !PanelSnapshot.isPutAway(clip, inCollection: inCollection)
        // Both origins: these tabs are about what the user did with a clip, not where it came from.
        case .pinned: clip.isPinned
        case .collections: PanelSnapshot.name(clip.category) != nil
        }
    }
}

/// The five tabs across the top, by what a clip is; every clip lands under exactly one of them.
public enum PanelFilter: String, Sendable, Equatable, CaseIterable, Codable {
    /// Every kind.
    case all
    /// Plain text, secrets, colours and file paths.
    case text
    /// Links.
    case links
    /// Code.
    case code
    /// Pictures.
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

    /// What this tab admits, as a sentence about one clip would name it; read only where a tab is empty.
    var noun: String {
        switch self {
        case .all: "a clip"
        case .text: "plain text"
        case .links: "a link"
        case .code: "code"
        case .images: "an image"
        }
    }

    /// Whether a clip belongs under this tab; secrets and colours sit under Text so nothing advertises them.
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

/// Everything the panel is drawn from and everything a keystroke can change, so every key is testable.
public struct PanelSnapshot: Sendable, Equatable {
    /// The highest ⌘-number a category chip can be given: there is no ⌘10, and ⌘0 opens the main window.
    public static let shortcutLimit = 9

    /// Newest first, as the store keeps them; never re-sorted here, since the clock belongs to the writer.
    public var clips: [Clip]
    /// What has been typed into the search field.
    public var query: String
    /// Which kind of clip the top tabs are showing.
    public var filter: PanelFilter
    /// Which slice the bottom bar shows; combines with ``filter`` rather than replacing it.
    public var scope: PanelScope = .history
    /// The collection being shown, or `nil` for all of them.
    public var category: String?
    /// The arrowed-to clip, held by identity so a new clip cannot shift the highlight; `nil` means the top.
    public var selection: Clip.ID?
    /// The sheet over the list, or `nil`; held here because it changes what esc and Return mean.
    public var sheet: PanelSheet?

    /// Whether a delete can still be taken back; set by the app, which alone still holds the clip.
    public var canUndoDelete: Bool = false

    /// Whether choosing a clip places it at the caret or only copies it; set by the app when the panel opens.
    public var insertion: PanelInsertion = .atCaret

    /// What the panel says about the last thing it did; set by the app and cleared when the panel next opens.
    public var notice: PanelNotice?

    /// What the panel's microphone is doing; set by the app, which owns the pipeline.
    public var dictation: PanelDictation = .ready

    /// Where the pictures are kept, so a row can name its file; handed in because the folder is the store's.
    public var imagesFolder: URL?
    /// The picture clips whose files are missing from disk; worked out by the app when it loads the list.
    public var missingImages: Set<Clip.ID> = []

    /// The languages a formatter is installed for; asked of the machine by the app when the panel opens.
    public var formattableLanguages: Set<CodeLanguage> = []
    /// The secrets the user has deliberately unmasked; a reveal never outlives the panel that asked.
    public var revealed: Set<Clip.ID>
    /// The clock the timestamps are measured against, injected so "2 minutes ago" is testable.
    public var now: Date
    /// Carried in the state because alias matching folds case and accents by it.
    public var locale: Locale

    /// Builds a panel over these clips; the scope starts on History.
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

    /// The collections the clips are filed into, in first-met order so ⌘-numbers stay stable.
    public var categories: [String] {
        var seen: [String] = []
        for clip in clips {
            guard let name = Self.name(clip.category), !seen.contains(name) else { continue }
            seen.append(name)
        }
        return seen
    }

    /// The query as it is searched, trimmed; empty means the panel is browsing.
    var needle: String { SearchQuery.needle(in: query) }

    /// Whether anything has been typed, which is what leaves the tab and collection behind.
    var isSearching: Bool { !needle.isEmpty }

    /// The clip with this identity, or `nil` once the store has dropped it.
    func clip(_ id: Clip.ID) -> Clip? {
        clips.first { $0.id == id }
    }

    /// The collection spelt like `name` in any case, ignoring `excluded`; `nil` when there is none.
    func existingCategory(named name: String, besides excluded: String? = nil) -> String? {
        categories.first { $0 != excluded && $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Whether the clip lives elsewhere: pinned, or filed while no collection is open; an alias is no place.
    static func isPutAway(_ clip: Clip, inCollection: Bool = false) -> Bool {
        if clip.isPinned { return true }
        return !inCollection && name(clip.category) != nil
    }

    /// A category name as compared and drawn, or `nil` for blank, so no chip is ever nameless.
    static func name(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
