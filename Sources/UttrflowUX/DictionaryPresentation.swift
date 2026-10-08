// The Dictionary page: its rows, the inline editor, and the presenter that draws them.
public import Foundation
public import UttrflowDictionary

/// Where a word came from as its chip says it, with a retired word counted apart from its origin.
public enum DictionarySource: String, Sendable, Equatable, CaseIterable {
    case added
    case learned
    case seen
    case shipped
    case retired

    /// The chip's words.
    public var title: String {
        switch self {
        case .added: "Added by you"
        case .learned: "Learned"
        case .seen: "Seen on screen"
        case .shipped: "Shipped"
        case .retired: "Retired"
        }
    }

    /// The source an entry is listed under.
    public init(_ entry: DictionaryEntry) {
        guard entry.isTrustworthy else {
            self = .retired
            return
        }
        switch entry.origin {
        case .added: self = .added
        case .learned: self = .learned
        case .observed: self = .seen
        case .shipped: self = .shipped
        }
    }
}

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
    /// The chip the row wears, "Retired" in place of the origin once the word has retired.
    public let source: DictionarySource
    /// "12 Aug", or "12 Aug 2024" outside the current year.
    public let added: String
    /// How often it has been applied, as text.
    public let timesUsed: String
    /// How often the user has undone it, as text.
    public let timesUndone: String
    /// "Used 3 times", what VoiceOver reads for the use count.
    public let timesUsedSpoken: String
    /// "Undone 2 times", what VoiceOver reads for the undo count.
    public let timesUndoneSpoken: String
    /// Whether the recogniser is given the word now, and why not when it is not.
    public let prompt: DictionaryPromptChip
    /// Whether the word has been undone at all, which tints the count.
    public let hasBeenUndone: Bool
    /// Whether the undo count is the reason this word is in trouble; drawn in red before it retires.
    public let undoneIsConcerning: Bool
    /// A word that undid itself more often than it helped; dimmed and badged, but still operable.
    public let isRetired: Bool
    /// "Sounds like ‘OpenAI’" when another entry competes for the same sound; absent otherwise.
    public let soundsLike: String?
    /// Says the word once to see whether it is recognised.
    public let tryIt: MainAction?
    /// What the latest try of this word showed, under the row; absent unless this word was tried.
    public let trial: DictionaryTrialLine?
    /// Merge, when the entry sharing its sound is this word spelt another way; then Restore, then Delete.
    public let actions: [MainAction]

    /// Builds a row from its parts.
    public init(
        id: UUID,
        word: String,
        pronunciation: String,
        origin: String,
        source: DictionarySource,
        added: String,
        timesUsed: String,
        timesUndone: String,
        timesUsedSpoken: String,
        timesUndoneSpoken: String,
        prompt: DictionaryPromptChip,
        hasBeenUndone: Bool,
        undoneIsConcerning: Bool,
        isRetired: Bool,
        soundsLike: String? = nil,
        tryIt: MainAction? = nil,
        trial: DictionaryTrialLine? = nil,
        actions: [MainAction]
    ) {
        self.tryIt = tryIt
        self.trial = trial
        self.id = id
        self.word = word
        self.pronunciation = pronunciation
        self.origin = origin
        self.source = source
        self.added = added
        self.timesUsed = timesUsed
        self.timesUndone = timesUndone
        self.timesUsedSpoken = timesUsedSpoken
        self.timesUndoneSpoken = timesUndoneSpoken
        self.prompt = prompt
        self.hasBeenUndone = hasBeenUndone
        self.undoneIsConcerning = undoneIsConcerning
        self.isRetired = isRetired
        self.soundsLike = soundsLike
        self.actions = actions
    }
}

/// One row's recogniser-prompt chip: short text, the full reason, and whether the word is given.
public struct DictionaryPromptChip: Sendable, Equatable {
    /// "In prompt · 3".
    public let text: String
    /// The whole reason, read by VoiceOver and shown on hover.
    public let spoken: String
    /// Whether the recogniser is given this word.
    public let isInPrompt: Bool

    /// Builds a chip from its parts.
    public init(text: String, spoken: String, isInPrompt: Bool) {
        self.text = text
        self.spoken = spoken
        self.isInPrompt = isInPrompt
    }

    /// The chip for one standing, worded from ``WorkingSet/Standing`` and never a second ranking.
    public init(_ standing: WorkingSet.Standing?) {
        switch standing {
        case .inPrompt(let rank):
            self.init(
                text: "In prompt · \(rank)", spoken: "Given to the recogniser, ranked \(rank)",
                isInPrompt: true)
        case .belowLimit(let rank, let limit):
            self.init(
                text: "Ranked \(rank) · top \(limit)",
                spoken: "Not given to the recogniser: ranked \(rank), and only \(limit) words are given",
                isInPrompt: false)
        case .sharesSound(let holder):
            self.init(
                text: "Sounds like \(holder)",
                spoken: "Not given to the recogniser: \u{201C}\(holder)\u{201D} already holds its sound",
                isInPrompt: false)
        case .retired:
            self.init(
                text: "Retired", spoken: "Not given to the recogniser: undone more often than kept",
                isInPrompt: false)
        case .unusedInferred:
            self.init(
                text: "Unused",
                spoken:
                    "Not given to the recogniser: never kept in \(Int(WorkingSet.unusedInferredLifetimeDays)) days",
                isInPrompt: false)
        case .tooLong(let rank):
            self.init(
                text: "No room · \(rank)",
                spoken: "Not given to the recogniser: ranked \(rank), but the last prompt had no room for it",
                isInPrompt: false)
        case nil:
            self.init(text: "—", spoken: "Not ranked", isInPrompt: false)
        }
    }
}

/// The word being typed in, and the entry it edits when opened from a row's Edit.
public struct DictionaryDraft: Sendable, Equatable {
    /// The entry being changed, or `nil` for a new word.
    public let editing: UUID?
    /// The spelling typed so far.
    public let word: String
    /// How it sounds, when the spelling is not a fair guide. Blank is normal.
    public let pronunciation: String

    /// Starts empty unless given text.
    public init(editing: UUID? = nil, word: String = "", pronunciation: String = "") {
        self.editing = editing
        self.word = word
        self.pronunciation = pronunciation
    }

    /// Nothing typed yet, so there is nothing to complain about; see `problem(with:in:)`.
    public var isUntouched: Bool { word.isEmpty && pronunciation.isEmpty }
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
    /// What the index will do with the pronunciation as typed; absent when it keys as an ordinary sounded phrase.
    public let pronunciationNote: String?
    /// "New".
    public let badge: MainPill
    /// Why this cannot be saved yet, in words. Absent when it can.
    public let problem: String?
    /// Respells the entry this draft would duplicate; present only when there is one.
    public let replace: MainAction?
    /// The duplicate's pronunciations, which Replace keeps ahead of those typed.
    public let kept: [String]
    /// Commits the word.
    public let save: MainAction
    /// Closes the editor unchanged.
    public let cancel: MainAction
    /// Says the typed word once to see whether it is recognised; absent until there is a spelling.
    public let tryIt: MainAction?
    /// What the latest try of the typed word showed.
    public let trial: DictionaryTrialLine?

    /// Whether Save is enabled.
    public var canSave: Bool { problem == nil && (!word.isEmpty || !pronunciation.isEmpty) }

    /// Builds the editor from its parts.
    public init(
        word: String,
        pronunciation: String,
        wordLabel: String,
        pronunciationLabel: String,
        pronunciationHint: String,
        pronunciationNote: String?,
        badge: MainPill,
        problem: String?,
        replace: MainAction? = nil,
        kept: [String] = [],
        save: MainAction,
        cancel: MainAction,
        tryIt: MainAction? = nil,
        trial: DictionaryTrialLine? = nil
    ) {
        self.tryIt = tryIt
        self.trial = trial
        self.word = word
        self.pronunciation = pronunciation
        self.wordLabel = wordLabel
        self.pronunciationLabel = pronunciationLabel
        self.pronunciationHint = pronunciationHint
        self.pronunciationNote = pronunciationNote
        self.badge = badge
        self.problem = problem
        self.replace = replace
        self.kept = kept
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
    /// The chosen filter chip's identifier; empty or unknown lists every word.
    public let filter: String
    /// The chosen order's identifier; empty or unknown is ``DictionarySort/standard``.
    public let sort: String
    /// Dictionary corrections, newest first, from which today's are drawn as cards.
    public let corrections: [Correction]
    /// The clock the page is drawn against.
    public let now: Date
    /// The words the last recogniser prompt held, as Diagnostics lists them; `nil` before any was packed.
    public let packed: [String]?
    /// The spellings deleted words are refused under, newest first, as the store lists them.
    public let refused: [String]
    /// The try under way or last finished, and whose it is.
    public let trial: DictionaryTrial?

    /// Builds a snapshot; everything but the clock defaults to empty.
    public init(
        entries: [DictionaryEntry] = [], draft: DictionaryDraft? = nil, refusal: String? = nil,
        query: String = "", filter: String = "", sort: String = "", corrections: [Correction] = [],
        now: Date, packed: [String]? = nil, refused: [String] = [], trial: DictionaryTrial? = nil
    ) {
        self.trial = trial
        self.packed = packed
        self.refused = refused
        self.entries = entries
        self.draft = draft
        self.refusal = refusal
        self.query = query
        self.filter = filter
        self.sort = sort
        self.corrections = corrections
        self.now = now
    }
}

/// One spoken try of a word: whose it is and how far it got.
public struct DictionaryTrial: Sendable, Equatable {
    /// The word a try is of.
    public enum Subject: Sendable, Equatable {
        /// What is typed in the open editor.
        case draft
        /// A saved word.
        case word(UUID)
    }

    /// How far a try got.
    public enum Phase: Sendable, Equatable {
        /// Recording the word being said.
        case listening
        /// Decoding the clip.
        case checking
        /// The probe's one line, and the heard words a miss offers as "Say it like".
        case result(line: String, offer: String?)
        /// Why the try could not run, in words.
        case failed(String)
    }

    /// Whose try this is.
    public let subject: Subject
    /// How far it got.
    public let phase: Phase

    /// Builds a try from its parts.
    public init(subject: Subject, phase: Phase) {
        self.subject = subject
        self.phase = phase
    }
}

/// A try's result row: one line, whether it is still going, and the "Say it like" a miss offers.
public struct DictionaryTrialLine: Sendable, Equatable {
    /// What the row says.
    public let text: String
    /// Whether the try is still listening or checking.
    public let isBusy: Bool
    /// Fills "Say it like" with what was heard; present only on a miss.
    public let offer: MainAction?

    /// Builds the row from its parts.
    public init(text: String, isBusy: Bool, offer: MainAction?) {
        self.text = text
        self.isBusy = isBusy
        self.offer = offer
    }
}

/// What the dictionary page shows.
public struct DictionaryPresentation: Sendable, Equatable {
    /// The title, caption, search field and Add button across the top.
    public let chrome: MainPageChrome
    /// "Fixed today · 3 corrections", over today's cards; absent when nothing was fixed today.
    public let fixesLabel: String?
    /// Today's corrections still standing, newest first, at most three.
    public let fixes: [CorrectionRow]
    /// The filter chips over the table, empty while there are no words to filter.
    public let filters: [MainScopeOption]
    /// The words that match the query and the filter, in the chosen order.
    public let rows: [DictionaryRow]
    /// The open editor, above the rows. Present only while a word is being written.
    public let editor: DictionaryEditor?
    /// Absent while the editor is open, so the user is not told the dictionary is empty mid-entry.
    public let emptyState: MainEmptyState?
    /// What the origins mean, under the rows.
    public let footnote: String?
    /// The words Uttrflow will not learn, each with Allow again; absent when none is refused.
    public let notLearning: DictionaryNotLearning?

    /// Builds the page from its parts.
    public init(
        chrome: MainPageChrome,
        fixesLabel: String?,
        fixes: [CorrectionRow],
        filters: [MainScopeOption],
        rows: [DictionaryRow],
        editor: DictionaryEditor?,
        emptyState: MainEmptyState?,
        footnote: String?,
        notLearning: DictionaryNotLearning? = nil
    ) {
        self.chrome = chrome
        self.fixesLabel = fixesLabel
        self.fixes = fixes
        self.filters = filters
        self.rows = rows
        self.editor = editor
        self.emptyState = emptyState
        self.footnote = footnote
        self.notLearning = notLearning
    }
}

/// The disclosure under the table listing refused spellings, so a deleted word's absence is explained.
public struct DictionaryNotLearning: Sendable, Equatable {
    /// "Not learning · 3 words".
    public let title: String
    /// What the list is and how long it lasts.
    public let note: String
    /// One spelling and its Allow again, newest refusal first.
    public let rows: [DictionaryRefusedRow]

    /// Builds the disclosure from its parts.
    public init(title: String, note: String, rows: [DictionaryRefusedRow]) {
        self.title = title
        self.note = note
        self.rows = rows
    }
}

/// One refused spelling and the action that lifts the refusal.
public struct DictionaryRefusedRow: Sendable, Equatable, Identifiable {
    /// The spelling, which is also unique within the list.
    public var id: String { word }
    /// The spelling, in the user's own case.
    public let word: String
    /// Allow again.
    public let allow: MainAction

    /// Builds a row from its parts.
    public init(word: String, allow: MainAction) {
        self.word = word
        self.allow = allow
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
        let filter = self.filter(named: snapshot.filter)
        let sort = DictionarySort(named: snapshot.sort)
        let found = matches(snapshot.entries, query: snapshot.query, locale: locale)
            .filter { filter == nil || DictionarySource($0) == filter }
        let listed = sort.ordered(found, id: \.id, locale: locale)
        let standings = WorkingSet.explain(
            entries: snapshot.entries, now: snapshot.now, packed: snapshot.packed)
        let rivals = rivals(among: snapshot.entries)
        let rows = listed.map {
            row(
                for: $0, standing: standings[$0.id], rival: rivals[$0.id], now: snapshot.now,
                calendar: calendar, locale: locale, trial: snapshot.trial)
        }
        let editor = snapshot.draft.map { self.editor(for: $0, in: snapshot) }
        let today = fixedToday(in: snapshot, calendar: calendar)
        // The empty page is the title over the scene, whose own button is the one way to add.
        let isBare = snapshot.entries.isEmpty && editor == nil

        return DictionaryPresentation(
            chrome: MainPageChrome(
                title: "Dictionary",
                caption: isBare
                    ? nil
                    : caption(for: snapshot.entries.count(where: \.isTrustworthy))
                        + promptNote(
                            inPrompt: standings.values.count {
                                if case .inPrompt = $0 { true } else { false }
                            }),
                search: snapshot.entries.isEmpty
                    ? nil
                    : MainSearchField(placeholder: searchPlaceholder, query: snapshot.query),
                sort: snapshot.entries.isEmpty ? nil : sort.menu,
                addAction: isBare ? nil : MainAction(title: "Add Word", symbolName: "plus", intent: .addWord)),
            fixesLabel: today.isEmpty
                ? nil
                : "Fixed today · \(MainFormatting.count(today.count, "correction", "corrections"))",
            fixes: today.prefix(fixesShown).map { CorrectionsPresenter.row(for: $0, locale: locale) },
            filters: snapshot.entries.isEmpty ? [] : filters(selecting: filter),
            rows: rows,
            editor: editor,
            emptyState: rows.isEmpty && editor == nil ? emptyState(for: snapshot, filter: filter) : nil,
            footnote: rows.isEmpty ? nil : footnote(for: listed),
            notLearning: notLearning(snapshot.refused))
    }

    /// The refused spellings with Allow again on each, or nothing when no word is refused.
    static func notLearning(_ refused: [String]) -> DictionaryNotLearning? {
        guard !refused.isEmpty else { return nil }
        return DictionaryNotLearning(
            title: "Not learning · \(MainFormatting.count(refused.count, "word", "words"))",
            note: """
                Words you deleted. Uttrflow will not learn them again from what you say or see, \
                though you can still type one in. Only the latest \(PersonalDictionaryStore.maximumRefusedWords) \
                are kept; older ones are forgotten.
                """,
            rows: refused.map {
                DictionaryRefusedRow(
                    word: $0, allow: MainAction(title: "Allow again", intent: .allowWord($0)))
            })
    }

    /// How many of today's corrections are drawn as cards.
    static let fixesShown = 3

    /// "Names and terms Uttrflow would otherwise get wrong. · 24 words", the count once there is one.
    static func caption(for count: Int) -> String {
        let lede = "Names and terms Uttrflow would otherwise get wrong."
        return count == 0 ? lede : "\(lede) · \(MainFormatting.count(count, "word", "words"))"
    }

    /// " · 19 given to the recogniser", or nothing when no word is.
    static func promptNote(inPrompt: Int) -> String {
        inPrompt == 0 ? "" : " · \(inPrompt) given to the recogniser"
    }

    // MARK: - Today's fixes

    /// Corrections made today and not undone, newest first, matching the sidebar's count.
    static func fixedToday(in snapshot: DictionarySnapshot, calendar: Calendar) -> [Correction] {
        snapshot.corrections
            .filter { !$0.isUndone && calendar.isDate($0.when, inSameDayAs: snapshot.now) }
            .sorted { $0.when > $1.when }
    }

    // MARK: - Filtering

    /// The chips in order: every word, then each source a word can be listed under but shipped.
    static let filterSources: [DictionarySource] = [.added, .learned, .seen, .retired]

    /// The chip identifier that lists every word.
    public static let allFilter = "all"

    /// The source a chip identifier names, or `nil` for every word.
    static func filter(named id: String) -> DictionarySource? {
        DictionarySource(rawValue: id).flatMap { filterSources.contains($0) ? $0 : nil }
    }

    /// The chips, with the chosen one selected.
    static func filters(selecting chosen: DictionarySource?) -> [MainScopeOption] {
        [MainScopeOption(id: allFilter, title: "All", isSelected: chosen == nil)]
            + filterSources.map {
                MainScopeOption(id: $0.rawValue, title: $0.title, isSelected: $0 == chosen)
            }
    }

    /// What the four origins mean, and what a retired word is only when one is on screen.
    static func footnote(for entries: [DictionaryEntry]) -> String {
        let origins = """
            Learned means you said a word again over the spelling Uttrflow got wrong, and it \
            kept yours. Seen on screen means the title of what you were working in kept \
            saying it while you spoke. Added by you means you typed it in here. Shipped with \
            Uttrflow means it came with the app; delete it and it stays deleted. Every word \
            here stays on this Mac.
            """
        guard entries.contains(where: { !$0.isTrustworthy }) else { return origins }
        return """
            \(origins) A word you undo more often than you keep retires itself and stops being \
            applied. Restore to try again.
            """
    }

    // MARK: - Searching

    /// Matches the spelling and every pronunciation, ignoring case and accents.
    static func matches(
        _ entries: [DictionaryEntry], query: String, locale: Locale
    ) -> [DictionaryEntry] {
        SearchQuery.matches(entries, query: query, locale: locale) { [$0.word] + $0.pronunciations }
    }

    // MARK: - One word

    /// For each applied entry, another one filed under a sound it is filed under, a same-spelling one first.
    static func rivals(among entries: [DictionaryEntry]) -> [UUID: DictionaryEntry] {
        let applied = entries.filter(\.isTrustworthy)
        var bySound: [String: [DictionaryEntry]] = [:]
        for entry in applied {
            for key in PronunciationCoder.keys(for: entry.soundsLike) {
                bySound[key, default: []].append(entry)
            }
        }
        var rivals: [UUID: DictionaryEntry] = [:]
        for entry in applied {
            let sharing = PronunciationCoder.keys(for: entry.soundsLike)
                .flatMap { bySound[$0] ?? [] }.filter { $0.id != entry.id }
            rivals[entry.id] = sharing.first { $0.spellingKey == entry.spellingKey } ?? sharing.first
        }
        return rivals
    }

    /// One entry as a row, with Merge on a respelt duplicate, Restore on a retired word, and Edit and Delete on every one.
    static func row(
        for entry: DictionaryEntry, standing: WorkingSet.Standing?, rival: DictionaryEntry? = nil,
        now: Date, calendar: Calendar, locale: Locale, trial: DictionaryTrial? = nil
    ) -> DictionaryRow {
        let isRetired = !entry.isTrustworthy
        // Only a respelling is merged; two words that merely sound alike are the person's to keep.
        let merge = rival.flatMap { rival in
            rival.spellingKey == entry.spellingKey
                ? MainAction(
                    title: "Keep this spelling", intent: .mergeWords(keeping: entry.id, absorbing: rival.id))
                : nil
        }
        return DictionaryRow(
            id: entry.id,
            word: entry.word,
            pronunciation: entry.pronunciation ?? "—",
            origin: title(for: entry.origin),
            source: DictionarySource(entry),
            added: MainFormatting.date(entry.firstSeen, now: now, calendar: calendar, locale: locale),
            timesUsed: "\(entry.timesUsed)",
            timesUndone: "\(entry.timesReverted)",
            timesUsedSpoken: "Used \(MainFormatting.count(entry.timesUsed, "time", "times"))",
            timesUndoneSpoken: "Undone \(MainFormatting.count(entry.timesReverted, "time", "times"))",
            prompt: DictionaryPromptChip(standing),
            hasBeenUndone: entry.timesReverted > 0,
            undoneIsConcerning: entry.timesReverted > concerningUndos,
            isRetired: isRetired,
            soundsLike: rival.map { "Sounds like \u{2018}\($0.word)\u{2019}" },
            tryIt: MainAction(title: "Try it", symbolName: "waveform", intent: .tryWord(entry.id)),
            trial: trial.flatMap { $0.subject == .word(entry.id) ? line(for: $0) : nil },
            actions: (merge.map { [$0] } ?? [])
                + (isRetired ? [MainAction(title: "Restore", intent: .restoreWords([entry.id]))] : [])
                + [
                    MainAction(title: "Edit", symbolName: "pencil", intent: .editWord(entry.id)),
                    .delete(.forgetWords([entry.id])),
                ])
    }

    /// The user's words for where a word came from; "Seen on screen" rather than "observed".
    public static func title(for origin: WordOrigin) -> String {
        switch origin {
        case .learned: "Learned"
        case .added: "Added by you"
        case .observed: "Seen on screen"
        case .shipped: "Shipped with Uttrflow"
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
            pronunciationHint: pronunciationHint(for: draft),
            pronunciationNote: pronunciationNote(for: draft),
            badge: MainPill(text: draft.editing == nil ? "New" : "Editing"),
            problem: problem(with: draft, in: snapshot),
            replace: draft.editing != nil
                ? nil
                : duplicate(of: draft, in: snapshot).map {
                    MainAction(
                        title: "Replace",
                        intent: .replaceWord(
                            $0.id, word: draft.word,
                            pronunciation: keeping($0.pronunciations, adding: draft.pronunciation)))
                },
            kept: draft.editing != nil ? [] : duplicate(of: draft, in: snapshot)?.pronunciations ?? [],
            save: MainAction(
                title: "Save",
                intent: draft.editing.map {
                    .replaceWord($0, word: draft.word, pronunciation: draft.pronunciation)
                } ?? .saveWord(word: draft.word, pronunciation: draft.pronunciation)),
            cancel: MainAction(title: "Cancel", intent: .cancelWordEdit),
            tryIt: draft.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : MainAction(
                    title: "Try it", symbolName: "waveform",
                    intent: .tryDraft(word: draft.word, pronunciation: draft.pronunciation)),
            trial: snapshot.trial.flatMap { $0.subject == .draft ? line(for: $0) : nil })
    }

    // MARK: - Trying one

    /// The row a try draws under its word, with the "Say it like" offer a miss makes.
    static func line(for trial: DictionaryTrial) -> DictionaryTrialLine {
        switch trial.phase {
        case .listening:
            return DictionaryTrialLine(text: "Listening… say the word once", isBusy: true, offer: nil)
        case .checking:
            return DictionaryTrialLine(text: "Checking what was heard…", isBusy: true, offer: nil)
        case .failed(let reason):
            return DictionaryTrialLine(text: reason, isBusy: false, offer: nil)
        case .result(let text, let offer):
            let editing: UUID? =
                if case .word(let id) = trial.subject { id } else { nil }
            return DictionaryTrialLine(
                text: text, isBusy: false,
                offer: offer.map {
                    MainAction(
                        title: "Say it like \u{2018}\($0)\u{2019}", intent: .useSayItLike(editing, heard: $0))
                })
        }
    }

    /// The draft with `heard` added as a way of saying it, after any already typed.
    public static func offering(_ heard: String, to draft: DictionaryDraft) -> DictionaryDraft {
        DictionaryDraft(
            editing: draft.editing, word: draft.word,
            pronunciation: keeping(
                DictionaryEntry.pronunciations(inField: draft.pronunciation), adding: heard))
    }

    /// The field a Replace writes: the duplicate's pronunciations kept, then those typed, so a fix adds a way of saying it.
    public static func keeping(_ kept: [String], adding field: String) -> String {
        DictionaryEntry.pronunciationField(for: kept + DictionaryEntry.pronunciations(inField: field))
    }

    /// What the pronunciation field is for, and when it is the only thing that will make the word work.
    static func pronunciationHint(for draft: DictionaryDraft) -> String {
        let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
        // A spelling with no English letters is matched letter for letter, which is not how dictation arrives.
        guard !word.isEmpty, draft.pronunciation.isEmpty,
            DoubleMetaphone.code(for: word).isSilent
        else {
            return """
                Leave this blank unless the spelling misleads. \u{201C}Nikhil\u{201D} written, \
                \u{201C}Nikkel\u{201D} said. Separate several ways of saying it with commas.
                """
        }
        return """
            \u{201C}\(word)\u{201D} has no English letters to sound out, so write here how it is \
            said — otherwise it is only matched spelt exactly this way.
            """
    }

    /// What the pronunciation will do once saved, when that is not what a reader would assume; a refusal shows as the problem instead.
    static func pronunciationNote(for draft: DictionaryDraft) -> String? {
        readings(of: draft, word: draft.word).first { !$0.refusesSaving }?.note(for: draft.word)
    }

    /// How the index will read each pronunciation in the field, in the order typed.
    private static func readings(of draft: DictionaryDraft, word: String) -> [PronunciationReading] {
        DictionaryEntry.pronunciations(inField: draft.pronunciation).compactMap {
            PronunciationReading.of(pronunciation: $0, for: word)
        }
    }

    /// Why a draft cannot be saved; an existing word is refused, since re-adding resets its counters.
    static func problem(with draft: DictionaryDraft, in snapshot: DictionarySnapshot) -> String? {
        let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
        // The store's refusal wins: it is the more recent fact and about the attempt the user made.
        if let refusal = snapshot.refusal, !word.isEmpty { return refusal }
        // An editor that opens complaining is telling somebody off for doing nothing yet.
        if draft.isUntouched { return nil }
        if word.isEmpty { return "A word needs a spelling." }
        let sounds = DictionaryEntry.pronunciations(inField: draft.pronunciation)
        if let refusal = (sounds.isEmpty ? [nil] : sounds.map(Optional.some)).lazy
            .compactMap({ PhoneticIndex.refusal(word: word, pronunciation: $0) }).first
        {
            return refusal.userMessage
        }
        if let reading = readings(of: draft, word: word).first(where: \.refusesSaving) {
            return reading.note(for: word)
        }
        guard let existing = duplicate(of: draft, in: snapshot) else { return nil }
        return existing.word.compare(word, options: .caseInsensitive) == .orderedSame
            ? "\u{201C}\(word)\u{201D} is already in your dictionary."
            : "\u{2018}\(word)\u{2019} is already in your dictionary as \u{2018}\(existing.word)\u{2019}."
    }

    /// The entry a draft would write again, by the store's own spelling key, so "Open AI" finds "OpenAI".
    static func duplicate(of draft: DictionaryDraft, in snapshot: DictionarySnapshot) -> DictionaryEntry? {
        let word = draft.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return nil }
        let key = DictionaryEntry.spellingKey(for: word)
        return snapshot.entries.first { $0.id != draft.editing && $0.spellingKey == key }
    }

    // MARK: - Nothing to show

    /// No matches, nothing under the chosen chip, or no words at all.
    static func emptyState(for snapshot: DictionarySnapshot, filter: DictionarySource?) -> MainEmptyState {
        guard !snapshot.entries.isEmpty else {
            return MainEmptyState(
                symbolName: "character.book.closed",
                title: "Your dictionary is empty",
                message: "Add names and terms Uttrflow would otherwise get wrong.",
                action: MainAction(title: "Add Word", symbolName: "plus", intent: .addWord))
        }
        let query = SearchQuery.needle(in: snapshot.query)
        if !query.isEmpty {
            return .noMatches("No word in your dictionary looks or sounds like “\(query)”.")
        }
        if let filter, !snapshot.entries.isEmpty {
            return MainEmptyState(
                symbolName: "line.3.horizontal.decrease",
                title: "Nothing in this view",
                message: """
                    \(MainFormatting.count(snapshot.entries.count, "word", "words")), and none of \
                    them is listed as \(filter.title.lowercased()).
                    """)
        }
        return MainEmptyState(
            symbolName: "character.book.closed",
            title: "Your dictionary is empty",
            message: "Add names and terms Uttrflow would otherwise get wrong.",
            action: MainAction(title: "Add Word", symbolName: "plus", intent: .addWord))
    }
}
