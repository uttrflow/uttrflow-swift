public import Foundation
public import UttrflowDictionary

/// One word, as the dictionary page lists it.
///
/// Drawn from ``DictionaryEntry`` and never from a copy of it. In particular
/// ``isRetired`` is ``DictionaryEntry/isTrustworthy`` inverted rather than a second
/// rule: the store decides which words it will apply, and a page that decided
/// separately could show a word as retired while the recogniser was still using it.
public struct DictionaryRow: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let word: String
    /// How it sounds. An em dash where the spelling is a fair guide, because an empty
    /// cell in a table reads as missing data rather than as "nothing to say".
    public let pronunciation: String
    /// "Learned", "Added by you", "Seen on screen".
    public let origin: String
    /// "12 Aug".
    public let added: String
    public let timesUsed: String
    public let timesUndone: String
    /// Whether the undo count is the reason this word is in trouble. Drawn in red, so
    /// a word about to retire itself can be seen before it does.
    public let undoneIsConcerning: Bool
    /// A word that undid itself more often than it helped. Dimmed, badged, and — unlike
    /// everything else about it — still operable, because the way out is a button on it.
    public let isRetired: Bool
    public let badge: MainPill?
    /// Restore on a retired word, delete on any other.
    public let actions: [MainAction]

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

/// The word being typed in.
///
/// Two fields and no identifier, because a dictionary row offers Restore and Delete and
/// never Edit: a word whose spelling was wrong is deleted and re-added, and carrying an
/// `editing` identifier here would model an operation the page does not have.
public struct DictionaryDraft: Sendable, Equatable {
    public let word: String
    /// How it sounds, when the spelling is not a fair guide. Blank is normal.
    public let pronunciation: String

    public init(word: String = "", pronunciation: String = "") {
        self.word = word
        self.pronunciation = pronunciation
    }
}

/// The word being written, in the row where it will end up.
///
/// Inline for the same reason the snippet editor is: two fields do not deserve a modal
/// window. The two editors are deliberately separate types rather than one generic pair
/// of text fields — they share an arity and nothing else, and the rules about what may
/// be saved are entirely different.
public struct DictionaryEditor: Sendable, Equatable {
    public let word: String
    public let pronunciation: String
    public let wordLabel: String
    public let pronunciationLabel: String
    /// What the second field is for, said in the row: nobody guesses what a Uttrflow
    /// "pronunciation" is meant to look like from the label alone.
    public let pronunciationHint: String
    public let badge: MainPill
    /// Why this cannot be saved yet, in words. Absent when it can.
    public let problem: String?
    public let save: MainAction
    public let cancel: MainAction

    public var canSave: Bool { problem == nil }

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
    /// In the order the store keeps them, retired entries included — the store lists
    /// them on purpose, and a user told a word has stopped being used and unable to see
    /// it has been told nothing useful.
    public let entries: [DictionaryEntry]
    /// Set while the inline editor is open.
    public let draft: DictionaryDraft?
    /// Why the last Save did not happen, when the store refused it.
    ///
    /// Separate from the draft because it is not something the user typed, and separate
    /// from the presenter's own rules because those are known before the button is
    /// pressed. A disk that will not take the word is only discovered afterwards, and
    /// without somewhere to say so the editor sits there with an enabled button that
    /// does nothing — which is the failure this whole page was rewired to remove.
    public let refusal: String?
    public let query: String
    public let now: Date

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
    public let chrome: MainPageChrome
    /// "24 words Uttrflow knows and a general model does not".
    public let caption: String
    public let rows: [DictionaryRow]
    /// The open editor, above the rows. Present only while a word is being written.
    public let editor: DictionaryEditor?
    /// Absent while the editor is open: telling the user the dictionary is empty
    /// underneath the box they are filling in would be telling them off for the thing
    /// they are doing.
    public let emptyState: MainEmptyState?
    public let footnote: String?

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
    public static let searchPlaceholder = "Search words"

    /// The count at which an undo tally is worth pointing at.
    ///
    /// Below ``DictionaryEntry/isTrustworthy``'s threshold on purpose: the point of
    /// colouring the number is to show a word going wrong *before* it retires itself,
    /// so somebody can look at it while there is still a choice.
    static let concerningUndos = 2

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

    /// What the three origins mean, and — when one has actually happened — what a
    /// retired word is.
    ///
    /// The retirement sentence appears only when there is a retired word on screen.
    /// Explaining a state nothing is in teaches the user to skip the small print, and
    /// then they skip it on the day it matters.
    ///
    /// Every sentence here names the thing the user actually did, in the words they
    /// would use for it, and the two automatic ones are written narrowly on purpose.
    /// "Seen on screen" is the title of the window they were working in and not
    /// everything in front of them, because the title is all Uttrflow reads. A page that
    /// describes more than the product does is worse than one that says nothing: the
    /// user waits for something that is never going to happen.
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
    ///
    /// The pronunciation is searchable because it is how the user thinks of the word
    /// they cannot spell, which is the whole reason it is written down.
    static func matches(
        _ entries: [DictionaryEntry], query: String, locale: Locale
    ) -> [DictionaryEntry] {
        SearchQuery.matches(entries, query: query, locale: locale) { [$0.word, $0.pronunciation] }
    }

    // MARK: - One word

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

    /// The user's words for where a word came from.
    ///
    /// ``WordOrigin/observed`` reads as "Seen on screen" because that is what observing
    /// actually was — the term was in front of them while they spoke. "Observed" is the
    /// mechanism's name, and the mechanism is not the user's problem.
    public static func title(for origin: WordOrigin) -> String {
        switch origin {
        case .learned: "Learned"
        case .added: "Added by you"
        case .observed: "Seen on screen"
        }
    }

    // MARK: - Writing one

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

    /// Why a draft cannot be saved, said before the button is pressed.
    ///
    /// A word already in the dictionary is refused rather than saved over the top.
    /// ``PersonalDictionaryStore/add(_:)`` replaces an entry spelling the same word, and
    /// a replacement arrives with its counters at zero — so a user re-adding “kubectl” to
    /// change how it sounds would silently throw away everything the app had learned
    /// about it. Refusing sends them to the row that already exists, which is the one
    /// they meant.
    static func problem(with draft: DictionaryDraft, in snapshot: DictionarySnapshot) -> String? {
        let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
        // The store's refusal wins over this page's own rules. It is the more recent
        // fact, and it is about the attempt the user actually made.
        if let refusal = snapshot.refusal, !word.isEmpty { return refusal }
        if word.isEmpty { return "A word needs a spelling." }
        // Case only, matching ``PersonalDictionaryStore/add(_:)`` exactly. Ignoring
        // accents as well made the page refuse a word the store would happily have kept:
        // with "cafe" stored, typing "café" was told it was already in the dictionary and
        // sent to look for a row that is not there. Two spellings of one word are also
        // something a personal dictionary of unusual words has a fair claim to hold.
        let clash = snapshot.entries.contains {
            $0.word.compare(word, options: .caseInsensitive) == .orderedSame
        }
        return clash ? "“\(word)” is already in your dictionary." : nil
    }

    // MARK: - Nothing to show

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
