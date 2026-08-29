public import Foundation
public import UttrflowHistory
public import UttrflowSettings

/// One change Uttrflow made, as the pages talk about it.
///
/// The stored change itself rather than a copy of its fields, for the reason
/// ``HistoryEntry`` gives about the record that holds it: there were two spellings of
/// this, and — more to the point — two lists of reasons a word might have been changed,
/// which did not agree. The page's list was written for the artboard before the
/// correction engine existed, and named things the engine could not establish. One type,
/// one set of reasons, one answer to why a word was rewritten.
///
/// Named again here, and only here, so that every page and every test can say
/// `Correction` without each one importing the store.
public typealias Correction = UttrflowHistory.Correction

/// See ``Correction``. These are the correction engine's own reasons, carried through
/// the pipeline and kept on the record; ``CorrectionReason/title`` is what a row shows.
public typealias CorrectionReason = UttrflowHistory.CorrectionReason

/// Which changes the page is listing. On the store as well as the page, because both
/// narrow the same list.
public typealias CorrectionsScope = UttrflowHistory.CorrectionsScope

/// One change, ready to draw.
public struct CorrectionRow: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let heard: String
    public let wrote: String
    /// Struck through, because the word on screen is the one that was heard. Drawing an
    /// undone change as though it still applied would make this page lie about the
    /// exact thing it exists to be honest about.
    public let isUndone: Bool
    public let reason: MainPill
    /// "4:12 PM".
    public let when: String
    public let application: HistoryApplication?
    /// Absent on a change that has already been put back — there is nothing left to undo.
    public let undo: MainAction?

    public init(
        id: UUID,
        heard: String,
        wrote: String,
        isUndone: Bool,
        reason: MainPill,
        when: String,
        application: HistoryApplication?,
        undo: MainAction?
    ) {
        self.id = id
        self.heard = heard
        self.wrote = wrote
        self.isUndone = isUndone
        self.reason = reason
        self.when = when
        self.application = application
        self.undo = undo
    }
}

/// Everything the corrections page is drawn from.
public struct CorrectionsSnapshot: Sendable, Equatable {
    /// Newest first.
    public let corrections: [Correction]
    /// Today's dictations, so the caption can say how many sentences the changes are
    /// spread across. A page reporting seven changes says nothing until you know
    /// whether that was over seven sentences or seventy.
    public let dictations: [HistoryEntry]
    public let query: String
    public let scope: CorrectionsScope
    public let settings: Settings
    public let now: Date

    public init(
        corrections: [Correction] = [],
        dictations: [HistoryEntry] = [],
        query: String = "",
        scope: CorrectionsScope = .all,
        settings: Settings = .default,
        now: Date
    ) {
        self.corrections = corrections
        self.dictations = dictations
        self.query = query
        self.scope = scope
        self.settings = settings
        self.now = now
    }
}

/// What the corrections page shows.
public struct CorrectionsPresentation: Sendable, Equatable {
    public let chrome: MainPageChrome
    /// Why this page exists at all, stated on the page rather than in a release note.
    public let callout: MainCallout
    /// "Today · 7 changes across 34 dictations".
    public let caption: String
    public let rows: [CorrectionRow]
    /// Set when — and only when — ``rows`` is empty.
    public let emptyState: MainEmptyState?
    public let footnote: String?

    public init(
        chrome: MainPageChrome,
        callout: MainCallout,
        caption: String,
        rows: [CorrectionRow],
        emptyState: MainEmptyState?,
        footnote: String?
    ) {
        self.chrome = chrome
        self.callout = callout
        self.caption = caption
        self.rows = rows
        self.emptyState = emptyState
        self.footnote = footnote
    }
}

/// Turns what Uttrflow changed into the page that admits it.
///
/// The most important of the new pages, and the one whose rules are least negotiable. A
/// product that quietly rewrites your words owes you a list of every rewrite, the reason
/// for each, and a way to put it back — so nothing here is summarised, sampled or
/// rounded, and a change with no nameable reason is a change that should never have been
/// made.
public enum CorrectionsPresenter {
    public static let searchPlaceholder = "Search"

    public static func page(
        for snapshot: CorrectionsSnapshot,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> CorrectionsPresentation {
        let today = madeToday(snapshot, calendar: calendar)
        let listed = matches(
            snapshot.scope.matching(today), query: snapshot.query, locale: locale)
        let rows = listed.map { row(for: $0, locale: locale) }

        return CorrectionsPresentation(
            chrome: chrome(for: snapshot, anyToday: !today.isEmpty),
            callout: MainCallout(
                symbolName: "arrow.left.arrow.right",
                message: """
                    Every word Uttrflow changed today, and why. A product that quietly rewrites \
                    what you said owes you this page — nothing here happened without a reason, \
                    and nothing here is permanent.
                    """),
            caption: caption(for: snapshot, changes: today.count, calendar: calendar),
            rows: rows,
            emptyState: rows.isEmpty
                ? emptyState(for: snapshot, madeToday: today.count, calendar: calendar) : nil,
            // Dropped when the pane is empty: the empty state carries its own closing
            // line, and two pieces of small print under one sentence is clutter.
            footnote: rows.isEmpty
                ? nil
                : """
                Undo teaches Uttrflow. Undo a word more often than you keep it and it stops \
                being applied — the word retires itself in your Dictionary.
                """)
    }

    // MARK: - Chrome

    /// The scope pop-up appears only once there is something to narrow. Offering three
    /// filters over an empty list is three ways to reach the same nothing.
    static func chrome(for snapshot: CorrectionsSnapshot, anyToday: Bool) -> MainPageChrome {
        MainPageChrome(
            title: "Corrections",
            caption: "What Uttrflow changed after it heard you.",
            scope: anyToday
                ? MainScope(
                    title: snapshot.scope.title,
                    options: CorrectionsScope.allCases.map {
                        MainScopeOption(
                            id: $0.rawValue, title: $0.title, isSelected: $0 == snapshot.scope)
                    })
                : nil,
            search: anyToday
                ? MainSearchField(placeholder: searchPlaceholder, query: snapshot.query) : nil)
    }

    /// "Today · 7 changes across 34 dictations".
    ///
    /// Both halves counted rather than one: the number of changes alone is unreadable
    /// without knowing how much was said.
    static func caption(
        for snapshot: CorrectionsSnapshot, changes: Int, calendar: Calendar
    ) -> String {
        let said = saidToday(in: snapshot, calendar: calendar)
        return """
            Today · \(MainFormatting.count(changes, "change", "changes")) across \
            \(MainFormatting.count(said, "dictation", "dictations"))
            """
    }

    /// How many dictations were made today.
    ///
    /// One function because there were two, and they disagreed: the caption filtered by
    /// day and the empty state's chip counted the whole retained history under the word
    /// "today". A page can survive saying nothing; it cannot survive saying "99
    /// dictations today" beside another page saying nothing was dictated today.
    static func saidToday(in snapshot: CorrectionsSnapshot, calendar: Calendar) -> Int {
        snapshot.dictations.filter { calendar.isDate($0.when, inSameDayAs: snapshot.now) }.count
    }

    // MARK: - Choosing rows

    /// Today only. Everything older belongs to the dictation it happened in, which is on
    /// History — this page is about the words that were changed while you were watching.
    static func madeToday(_ snapshot: CorrectionsSnapshot, calendar: Calendar) -> [Correction] {
        snapshot.corrections.filter { calendar.isDate($0.when, inSameDayAs: snapshot.now) }
    }

    /// Matches what was heard, what was written and the reason.
    ///
    /// The reason is searchable because "what has it been doing to my punctuation" is a
    /// real question, and the pill is the only place the answer is written down.
    static func matches(
        _ corrections: [Correction], query: String, locale: Locale
    ) -> [Correction] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return corrections }
        return corrections.filter { correction in
            [correction.heard, correction.wrote, correction.reason.title].contains {
                $0.range(
                    of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: nil,
                    locale: locale) != nil
            }
        }
    }

    // MARK: - Drawing one

    static func row(for correction: Correction, locale: Locale) -> CorrectionRow {
        CorrectionRow(
            id: correction.id,
            heard: correction.heard,
            wrote: correction.wrote,
            isUndone: correction.isUndone,
            reason: MainPill(text: correction.reason.title),
            when: MainFormatting.time(correction.when, locale: locale),
            application: correction.applicationName.flatMap {
                HistoryPresenter.application(named: $0)
            },
            undo: correction.isUndone
                ? nil
                : MainAction(
                    title: "Undo", symbolName: "arrow.uturn.backward",
                    intent: .undoCorrection(correction.id)))
    }

    // MARK: - Nothing to show

    /// Four different nothings. The difference between "it changed nothing" and "your
    /// filter hid everything" is the difference between reassurance and confusion.
    static func emptyState(
        for snapshot: CorrectionsSnapshot, madeToday: Int, calendar: Calendar
    ) -> MainEmptyState {
        let query = snapshot.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return MainEmptyState(
                symbolName: "magnifyingglass",
                title: "No matches",
                message: "Nothing Uttrflow changed today mentions “\(query)”.")
        }
        if madeToday > 0 {
            return MainEmptyState(
                symbolName: "line.3.horizontal.decrease",
                title: "Nothing in this view",
                message: """
                    \(MainFormatting.count(madeToday, "change", "changes")) today, and none of \
                    them is \(snapshot.scope.title.lowercased()).
                    """)
        }
        let said = saidToday(in: snapshot, calendar: calendar)
        return MainEmptyState(
            symbolName: "arrow.left.arrow.right",
            title: "Uttrflow changed nothing you said today",
            message: """
                It only changes a word when it has a reason it can name: a word in your \
                dictionary, a term it could see on your screen, a filler word, or punctuation. \
                When it does, the change is listed here with what it heard, what it wrote, and \
                an undo.
                """,
            chips: [
                MainStatistic(value: "\(said)", caption: said == 1 ? "dictation today" : "dictations today"),
                MainStatistic(value: "0", caption: "words changed"),
            ],
            footnote: "An empty page here is the good outcome, not a missing feature.")
    }
}
