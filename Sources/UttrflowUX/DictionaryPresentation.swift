// The Dictionary page: its rows, the inline editor, and the presenter that draws them.
public import Foundation
public import UttrflowDictionary

/// One word as the dictionary page lists it, drawn from ``DictionaryEntry`` and never a second rule.
public struct DictionaryRow: Sendable, Equatable, Identifiable {
    /// The entry's identity.
    public let id: UUID
    /// The spelling.
    public let word: String
    /// How it sounds; an em dash where the spelling is a fair guide, so the cell never reads as missing.
    public let pronunciation: String
    /// "Learned", "Added by you", "Seen on screen".
    public let origin: String
    /// "12 Aug".
    public let added: String
    /// How often it has been applied, as text.
    public let timesUsed: String
    /// How often the user has undone it, as text.
    public let timesUndone: String
    /// Whether the undo count is the reason this word is in trouble; drawn in red before it retires.
    public let undoneIsConcerning: Bool
    /// A word that undid itself more often than it helped; dimmed and badged, but still operable.
    public let isRetired: Bool
    /// "Retired", on a retired word.
    public let badge: MainPill?
    /// Restore on a retired word, delete on any other.
    public let actions: [MainAction]

    /// Builds a row from its parts.
    public init(
        id: UUID,
        word: String,
        pronunciation: String,
        origin: String,
        added: String,
        timesUsed: String,
        timesUndone: String,
        undoneIsConcerning: Bool,
        isRetired: Bool,
        badge: MainPill?,
        actions: [MainAction]
    ) {
        self.id = id
        self.word = word
        self.pronunciation = pronunciation
        self.origin = origin
        self.added = added
        self.timesUsed = timesUsed
        self.timesUndone = timesUndone
        self.undoneIsConcerning = undoneIsConcerning
        self.isRetired = isRetired
        self.badge = badge
        self.actions = actions
    }
}

/// The word being typed in; two fields and no identifier, since a row is never edited, only re-added.
public struct DictionaryDraft: Sendable, Equatable {
    /// The spelling typed so far.
    public let word: String
    /// How it sounds, when the spelling is not a fair guide. Blank is normal.
    public let pronunciation: String

    /// Starts empty unless given text.
    public init(word: String = "", pronunciation: String = "") {
        self.word = word
        self.pronunciation = pronunciation
    }
}

/// The word being written, in the row where it will end up; a separate type from the snippet editor.
public struct DictionaryEditor: Sendable, Equatable {
    /// The spelling typed so far.
    public let word: String
    /// The pronunciation typed so far.
    public let pronunciation: String
    /// The label on the spelling field.
    public let wordLabel: String
    /// The label on the pronunciation field.
    public let pronunciationLabel: String
    /// What the second field is for, said in the row, since the label alone does not explain it.
    public let pronunciationHint: String
    /// "New".
    public let badge: MainPill
    /// Why this cannot be saved yet, in words. Absent when it can.
    public let problem: String?
    /// Commits the word.
    public let save: MainAction
    /// Closes the editor unchanged.
    public let cancel: MainAction

    /// Whether Save is enabled.
    public var canSave: Bool { problem == nil }

    /// Builds the editor from its parts.
    public init(
        word: String,
        pronunciation: String,
        wordLabel: String,
        pronunciationLabel: String,
        pronunciationHint: String,
        badge: MainPill,
        problem: String?,
        save: MainAction,
        cancel: MainAction
    ) {
        self.word = word
        self.pronunciation = pronunciation
        self.wordLabel = wordLabel
        self.pronunciationLabel = pronunciationLabel
        self.pronunciationHint = pronunciationHint
        self.badge = badge
        self.problem = problem
        self.save = save
        self.cancel = cancel
    }
}

/// Everything the dictionary page is drawn from.
public struct DictionarySnapshot: Sendable, Equatable {
    /// In the store's order, retired entries included, so a word said to have stopped can be seen.
    public let entries: [DictionaryEntry]
    /// Set while the inline editor is open.
    public let draft: DictionaryDraft?
    /// Why the last Save did not happen, when the store refused it; known only after the button is pressed.
    public let refusal: String?
    /// What has been typed into the search field.
    public let query: String
    /// The clock the page is drawn against.
    public let now: Date

    /// Builds a snapshot; everything but the clock defaults to empty.
    public init(
        entries: [DictionaryEntry] = [], draft: DictionaryDraft? = nil, refusal: String? = nil,
        query: String = "", now: Date
    ) {
        self.entries = entries
        self.draft = draft
        self.refusal = refusal
        self.query = query
        self.now = now
    }
}

/// What the dictionary page shows.
public struct DictionaryPresentation: Sendable, Equatable {
    /// The title, caption, search field and Add button across the top.
    public let chrome: MainPageChrome
    /// "24 words Uttrflow knows and a general model does not".
    public let caption: String
    /// The words that match the query.
    public let rows: [DictionaryRow]
    /// The open editor, above the rows. Present only while a word is being written.
    public let editor: DictionaryEditor?
    /// Absent while the editor is open, so the user is not told the dictionary is empty mid-entry.
    public let emptyState: MainEmptyState?
    /// What the origins mean, under the rows.
    public let footnote: String?

    /// Builds the page from its parts.
    public init(
        chrome: MainPageChrome,
        caption: String,
        rows: [DictionaryRow],
        editor: DictionaryEditor?,
        emptyState: MainEmptyState?,
        footnote: String?
    ) {
        self.chrome = chrome
        self.caption = caption
        self.rows = rows
        self.editor = editor
        self.emptyState = emptyState
        self.footnote = footnote
    }
}

/// Turns the personal dictionary into the page that explains it.
public enum DictionaryPresenter {
    /// What the empty search field says.
    public static let searchPlaceholder = "Search words"

    /// The undo count worth pointing at; below the retirement threshold so a word is seen going wrong first.
    static let concerningUndos = 2

    /// Draws the Dictionary page from a snapshot.
    public static func page(
        for snapshot: DictionarySnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> DictionaryPresentation {
        let listed = matches(snapshot.entries, query: snapshot.query, locale: locale)
        let rows = listed.map { row(for: $0, locale: locale) }
        let editor = snapshot.draft.map { self.editor(for: $0, in: snapshot) }

        return DictionaryPresentation(
            chrome: MainPageChrome(
                title: "Dictionary",
                caption: "Names and terms Uttrflow would otherwise get wrong.",
                search: snapshot.entries.isEmpty
                    ? nil
                    : MainSearchField(placeholder: searchPlaceholder, query: snapshot.query),
                addAction: MainAction(title: "Add Word", symbolName: "plus", intent: .addWord)),
            caption: """
                \(MainFormatting.count(snapshot.entries.count, "word", "words")) Uttrflow knows \
                and a general model does not
                """,
            rows: rows,
            editor: editor,
            emptyState: rows.isEmpty && editor == nil ? emptyState(for: snapshot) : nil,
            footnote: rows.isEmpty ? nil : footnote(for: listed))
    }

    /// What the three origins mean, and what a retired word is only when one is on screen.
    static func footnote(for entries: [DictionaryEntry]) -> String {
        let origins = """
            Learned means you said a word again over the spelling Uttrflow got wrong, and it \
            kept yours. Seen on screen means the title of what you were working in kept \
            saying it while you spoke. Added by you means you typed it in here. Every word \
            here stays on this Mac.
            """
        guard entries.contains(where: { !$0.isTrustworthy }) else { return origins }
        return """
            \(origins) A word you undo more often than you keep retires itself and stops being \
            applied. Restore to try again.
            """
    }

    // MARK: - Searching

    /// Matches the spelling and the pronunciation, ignoring case and accents.
    static func matches(
        _ entries: [DictionaryEntry], query: String, locale: Locale
    ) -> [DictionaryEntry] {
        SearchQuery.matches(entries, query: query, locale: locale) { [$0.word, $0.pronunciation] }
    }

    // MARK: - One word

    /// One entry as a row, with Restore on a retired word and Delete on every one.
    static func row(for entry: DictionaryEntry, locale: Locale) -> DictionaryRow {
        let isRetired = !entry.isTrustworthy
        return DictionaryRow(
            id: entry.id,
            word: entry.word,
            pronunciation: entry.pronunciation ?? "—",
            origin: title(for: entry.origin),
            added: entry.firstSeen.formatted(.dateTime.day().month(.abbreviated).locale(locale)),
            timesUsed: "\(entry.timesUsed)",
            timesUndone: "\(entry.timesReverted)",
            undoneIsConcerning: entry.timesReverted > concerningUndos,
            isRetired: isRetired,
            badge: isRetired ? MainPill(text: "Retired", tone: .warning) : nil,
            actions: (isRetired ? [MainAction(title: "Restore", intent: .restoreWord(entry.id))] : [])
                + [.delete(.forgetWord(entry.id))])
    }

    /// The user's words for where a word came from; "Seen on screen" rather than "observed".
    public static func title(for origin: WordOrigin) -> String {
        switch origin {
        case .learned: "Learned"
        case .added: "Added by you"
        case .observed: "Seen on screen"
        }
    }

    // MARK: - Writing one

    /// The inline editor over a draft, with the reason it cannot be saved yet.
    static func editor(
        for draft: DictionaryDraft, in snapshot: DictionarySnapshot
    ) -> DictionaryEditor {
        DictionaryEditor(
            word: draft.word,
            pronunciation: draft.pronunciation,
            wordLabel: "Write it as",
            pronunciationLabel: "Say it like",
            pronunciationHint: """
                Leave this blank unless the spelling misleads. “Nikhil” written, “Nikkel” \
                said.
                """,
            badge: MainPill(text: "New"),
            problem: problem(with: draft, in: snapshot),
            save: MainAction(
                title: "Save",
                intent: .saveWord(word: draft.word, pronunciation: draft.pronunciation)),
            cancel: MainAction(title: "Cancel", intent: .cancelWordEdit))
    }

    /// Why a draft cannot be saved; an existing word is refused, since re-adding resets its counters.
    static func problem(with draft: DictionaryDraft, in snapshot: DictionarySnapshot) -> String? {
        let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
        // The store's refusal wins: it is the more recent fact and about the attempt the user made.
        if let refusal = snapshot.refusal, !word.isEmpty { return refusal }
        if word.isEmpty { return "A word needs a spelling." }
        // Case only, matching ``PersonalDictionaryStore/add(_:)``, so "café" is not refused over "cafe".
        let clash = snapshot.entries.contains {
            $0.word.compare(word, options: .caseInsensitive) == .orderedSame
        }
        return clash ? "“\(word)” is already in your dictionary." : nil
    }

    // MARK: - Nothing to show

    /// No matches, or no words at all.
    static func emptyState(for snapshot: DictionarySnapshot) -> MainEmptyState {
        let query = SearchQuery.needle(in: snapshot.query)
        if !query.isEmpty {
            return .noMatches("No word in your dictionary looks or sounds like “\(query)”.")
        }
        return MainEmptyState(
            symbolName: "character.book.closed",
            title: "No words of your own yet",
            message: """
                Uttrflow learns the names, products and jargon a general model has never heard. \
                Select a word it spelt wrong, say it again, and the spelling you keep lands \
                here. So does a term the title of your window keeps showing while you say it.
                """,
            action: MainAction(title: "Add a Word", symbolName: "plus", intent: .addWord),
            footnote: """
                Nothing is pre-loaded. An empty dictionary means Uttrflow has not yet changed a \
                single word of yours.
                """)
    }
}
